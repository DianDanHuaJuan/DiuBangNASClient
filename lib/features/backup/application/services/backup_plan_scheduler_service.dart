import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/device/client_identity_service.dart';
import '../../../../core/network/trusted_server_store.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../data/datasources/backup_local_data_source.dart';
import '../../domain/entities/backup_mode.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/entities/backup_plan_schedule_status.dart';
import '../../domain/entities/backup_schedule_entity.dart';
import 'backup_schedule_utils.dart';

class BackupPlanSchedulerService {
  static const String platformChannelName = 'com.nasclient/backup_scheduler';
  static const Duration activePollInterval = Duration(seconds: 2);
  static const Duration postActionPollBoostWindow = Duration(seconds: 20);

  BackupPlanSchedulerService({
    required BackupLocalDataSource localDataSource,
    required BackupPlanExecutionProfileResolver profileResolver,
    MethodChannel? channel,
  }) : _localDataSource = localDataSource,
       _profileResolver = profileResolver,
       _channel = channel ?? const MethodChannel(platformChannelName);

  final BackupLocalDataSource _localDataSource;
  final BackupPlanExecutionProfileResolver _profileResolver;
  final MethodChannel _channel;

  BackupWorkerRunSnapshot? _lastPersistedActiveRun;
  BackupWorkerPlanSnapshot? _lastPersistedPlanSnapshot;
  DateTime? _pollBoostUntil;

  /// After schedule/stop/toggle, poll frequently even before an active run appears.
  void boostPollWindow({Duration duration = postActionPollBoostWindow}) {
    _pollBoostUntil = DateTime.now().add(duration);
  }

  bool get isPollBoostActive {
    final until = _pollBoostUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Duration? pollIntervalFor({
    required bool hasActiveScheduledRun,
    required bool pollingEnabled,
  }) {
    if (!pollingEnabled) {
      return null;
    }
    if (hasActiveScheduledRun || isPollBoostActive) {
      return activePollInterval;
    }
    return null;
  }

  /// Loads native worker snapshot for UI. Persists to SQLite only on schedule/run
  /// state transitions unless [forcePersist] is true.
  Future<BackupWorkerStateSnapshot> refreshWorkerSnapshotForUi({
    required String planId,
    bool forcePersist = false,
  }) async {
    final snapshot = await loadWorkerStateSnapshot(persistToLocal: false);
    final activeRun = snapshot.findActiveRun(planId);
    BackupWorkerPlanSnapshot? planSnapshot;
    for (final plan in snapshot.plans) {
      if (plan.planId == planId) {
        planSnapshot = plan;
        break;
      }
    }

    final shouldPersist =
        forcePersist ||
        shouldPersistWorkerSnapshot(
          previousActiveRun: _lastPersistedActiveRun,
          nextActiveRun: activeRun,
          previousPlan: _lastPersistedPlanSnapshot,
          nextPlan: planSnapshot,
        );

    if (shouldPersist) {
      await _persistWorkerSnapshot(snapshot);
      _updatePersistedTrackers(snapshot, planId);
    }

    return snapshot;
  }

  Future<void> _persistWorkerSnapshot(BackupWorkerStateSnapshot snapshot) async {
    if (snapshot.plans.isEmpty && snapshot.runs.isEmpty) {
      return;
    }
    await _localDataSource.applyNativeWorkerState(
      planStates: snapshot.plans.map(_planSnapshotToMap).toList(growable: false),
      runRecords: snapshot.runs.map(_runSnapshotToMap).toList(growable: false),
    );
  }

  Map<String, Object?> _planSnapshotToMap(BackupWorkerPlanSnapshot plan) {
    return <String, Object?>{
      'planId': plan.planId,
      'lastRunAtMillis': plan.lastRunAt?.millisecondsSinceEpoch,
      'scheduleStatus': plan.scheduleStatus,
      'scheduledRunAtMillis': plan.scheduledRunAt?.millisecondsSinceEpoch,
      'scheduleErrorMessage': plan.scheduleErrorMessage,
    };
  }

  Map<String, Object?> _runSnapshotToMap(BackupWorkerRunSnapshot run) {
    return <String, Object?>{
      'id': run.id,
      'planId': run.planId,
      'triggerType': run.triggerType,
      'status': run.status,
      'scannedCount': run.scannedCount,
      'queuedCount': run.queuedCount,
      'skippedCount': run.skippedCount,
      'failedCount': run.failedCount,
      'processedCount': run.processedCount,
      'totalCount': run.totalCount,
      'startedAtMillis': run.startedAt.millisecondsSinceEpoch,
      'finishedAtMillis': run.finishedAt?.millisecondsSinceEpoch,
      'errorMessage': run.errorMessage,
    };
  }

  Future<void> syncPlans() async {
    await _syncNativeWorkerState();
    final plans = await _localDataSource.loadPlans();
    var hasScheduledPlan = false;
    for (final dto in plans) {
      final plan = dto.toEntity();
      if (!plan.enabled || plan.schedule == null) {
        await cancelPlan(plan.id);
        continue;
      }
      if (hasScheduledPlan) {
        await cancelPlan(plan.id);
        continue;
      }
      hasScheduledPlan = true;
      if (await _localDataSource.hasActiveRun(plan.id)) {
        continue;
      }
      if (await _localDataSource.hasRecentUserStoppedRun(plan.id)) {
        continue;
      }
      final shouldReschedule = await _shouldReschedulePlanOnSync(plan);
      if (!shouldReschedule) {
        continue;
      }
      await schedulePlan(plan);
    }
  }

  Future<BackupWorkerStateSnapshot> loadWorkerStateSnapshot({
    bool persistToLocal = true,
  }) async {
    try {
      final rawSnapshot = await _channel.invokeMapMethod<String, Object?>(
        'getWorkerStateSnapshot',
      );
      if (rawSnapshot == null) {
        return const BackupWorkerStateSnapshot();
      }
      final planStates = _normalizeWorkerStateList(rawSnapshot['plans']);
      final runRecords = _normalizeWorkerStateList(rawSnapshot['runs']);
      if (persistToLocal && (planStates.isNotEmpty || runRecords.isNotEmpty)) {
        await _localDataSource.applyNativeWorkerState(
          planStates: planStates,
          runRecords: runRecords,
        );
      }
      return BackupWorkerStateSnapshot(
        plans: planStates
            .map(BackupWorkerPlanSnapshot.fromMap)
            .toList(growable: false),
        runs: runRecords
            .map(BackupWorkerRunSnapshot.fromMap)
            .toList(growable: false),
      );
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'Failed to load native backup worker state snapshot',
        name: 'backup.scheduler',
        error: error,
        stackTrace: stackTrace,
      );
      return const BackupWorkerStateSnapshot();
    }
  }

  Future<AppResult<void>> stopCurrentRun(String planId) async {
    try {
      await _channel.invokeMethod<void>('stopCurrentRun', <String, Object?>{
        'planId': planId,
      });
      boostPollWindow();
      await _syncNativeWorkerState(planId: planId);
      return const Success(null);
    } on PlatformException catch (error) {
      return Failure(
        AppFailure(code: error.code, message: error.message ?? '停止当前备份失败'),
      );
    }
  }

  Future<ScheduledBackupNotificationState> loadNotificationState() async {
    try {
      final rawState = await _channel.invokeMapMethod<String, Object?>(
        'getScheduledBackupNotificationState',
      );
      return ScheduledBackupNotificationState.fromMap(rawState);
    } on PlatformException catch (error, stackTrace) {
      developer.log(
        'Failed to load scheduled backup notification state',
        name: 'backup.scheduler',
        error: error,
        stackTrace: stackTrace,
      );
      return const ScheduledBackupNotificationState(
        runtimePermissionGranted: false,
        appNotificationsEnabled: false,
        channelEnabled: false,
        message: '无法确认系统通知状态，请先在系统设置中开启铥棒文件通知。',
      );
    }
  }

  Future<AppResult<void>> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>(
        'openScheduledBackupNotificationSettings',
      );
      return const Success(null);
    } on PlatformException catch (error) {
      return Failure(
        AppFailure(code: error.code, message: error.message ?? '无法打开系统通知设置'),
      );
    }
  }

  Future<AppResult<BackupPlanScheduleRegistration>> schedulePlan(
    BackupPlanEntity plan,
  ) async {
    final schedule = plan.schedule;
    if (schedule == null || !plan.enabled) {
      return cancelPlan(plan.id);
    }

    final nextRunAt = BackupScheduleUtils.nextRunAt(schedule);
    if (schedule.type == BackupScheduleType.once &&
        !nextRunAt.isAfter(DateTime.now())) {
      return _markScheduleFailure(
        plan.id,
        failure: AppFailure(
          code: 'BACKUP_PLAN_EXPIRED',
          message: '定时备份时间已过，请重新设置执行时间',
        ),
      );
    }

    final configResult = await _profileResolver.build(plan);
    if (configResult is Failure<BackupNativePlanConfig>) {
      return _markScheduleFailure(plan.id, failure: configResult.failure);
    }
    final config = (configResult as Success<BackupNativePlanConfig>).data;

    try {
      final rawResult = await _channel.invokeMapMethod<String, Object?>(
        'schedulePlan',
        config.toMap(),
      );
      final registration = BackupPlanScheduleRegistration.fromMap(rawResult);
      await _persistRegistration(plan.id, registration);
      boostPollWindow();
      if (registration.status == BackupPlanScheduleStatus.failed) {
        return Failure(
          AppFailure(
            code: 'BACKUP_SCHEDULE_FAILED',
            message: registration.errorMessage ?? '系统未能注册定时备份任务',
          ),
        );
      }
      return Success(registration);
    } on PlatformException catch (error) {
      return _markScheduleFailure(
        plan.id,
        failure: AppFailure(
          code: error.code,
          message: error.message ?? '系统未能注册定时备份任务',
        ),
      );
    }
  }

  Future<AppResult<BackupPlanScheduleRegistration>> cancelPlan(
    String planId,
  ) async {
    try {
      final rawResult = await _channel.invokeMapMethod<String, Object?>(
        'cancelPlan',
        <String, Object?>{'planId': planId},
      );
      final registration = BackupPlanScheduleRegistration.fromMap(rawResult);
      await _persistRegistration(planId, registration);
      boostPollWindow();
      return Success(registration);
    } on PlatformException catch (error) {
      final registration = const BackupPlanScheduleRegistration(
        status: BackupPlanScheduleStatus.unscheduled,
      );
      await _persistRegistration(planId, registration);
      return Failure(
        AppFailure(code: error.code, message: error.message ?? '系统未能取消定时备份任务'),
      );
    }
  }

  Future<Failure<BackupPlanScheduleRegistration>> _markScheduleFailure(
    String planId, {
    required AppFailure failure,
  }) async {
    try {
      await _channel.invokeMethod<void>('cancelPlan', <String, Object?>{
        'planId': planId,
      });
    } on PlatformException {
      // Preserve the original scheduling failure below.
    }
    await _persistRegistration(
      planId,
      BackupPlanScheduleRegistration.failed(failure.message),
    );
    return Failure(failure);
  }

  Future<void> _persistRegistration(
    String planId,
    BackupPlanScheduleRegistration registration,
  ) {
    return _localDataSource.updatePlanScheduleState(
      planId,
      status: registration.status,
      scheduleErrorMessage: registration.errorMessage,
      scheduledRunAt: registration.scheduledRunAt,
    );
  }

  Future<bool> _shouldReschedulePlanOnSync(BackupPlanEntity plan) async {
    final scheduledRunAt = plan.scheduledRunAt;
    if (plan.scheduleStatus != BackupPlanScheduleStatus.scheduled ||
        scheduledRunAt == null) {
      return true;
    }
    if (scheduledRunAt.isAfter(DateTime.now())) {
      return false;
    }
    return await _recordMissedRunIfNeeded(plan);
  }

  Future<bool> _recordMissedRunIfNeeded(BackupPlanEntity plan) async {
    final scheduledRunAt = plan.scheduledRunAt;
    if (plan.scheduleStatus != BackupPlanScheduleStatus.scheduled ||
        scheduledRunAt == null ||
        !BackupScheduleUtils.shouldTreatRunAsMissed(
          plan.schedule!,
          scheduledRunAt,
          now: DateTime.now(),
        )) {
      return false;
    }
    if (plan.lastRunAt != null && !plan.lastRunAt!.isBefore(scheduledRunAt)) {
      return false;
    }
    if (await _localDataSource.hasActiveRun(plan.id)) {
      return false;
    }
    if (await _localDataSource.hasRecordedRunForPlanSince(
      plan.id,
      scheduledRunAt,
    )) {
      return false;
    }

    final now = DateTime.now();
    final runId =
        'scheduled-missed-${plan.id}-${scheduledRunAt.millisecondsSinceEpoch}';
    await _localDataSource.insertRun(
      runId: runId,
      planId: plan.id,
      triggerType: 'scheduled',
      status: 'missed',
      startedAt: scheduledRunAt,
    );
    await _localDataSource.completeRun(
      runId: runId,
      status: 'missed',
      scannedCount: 0,
      queuedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      finishedAt: now,
      errorMessage: '计划时间已到，但执行约束未满足，本次定时备份已跳过',
    );
    return true;
  }

  Future<void> _syncNativeWorkerState({String? planId}) async {
    final snapshot = await loadWorkerStateSnapshot(persistToLocal: true);
    if (planId != null) {
      _updatePersistedTrackers(snapshot, planId);
    } else {
      _lastPersistedActiveRun = null;
      _lastPersistedPlanSnapshot = null;
    }
  }

  void _updatePersistedTrackers(
    BackupWorkerStateSnapshot snapshot,
    String planId,
  ) {
    _lastPersistedActiveRun = snapshot.findActiveRun(planId);
    _lastPersistedPlanSnapshot = null;
    for (final plan in snapshot.plans) {
      if (plan.planId == planId) {
        _lastPersistedPlanSnapshot = plan;
        break;
      }
    }
  }

  List<Map<String, Object?>> _normalizeWorkerStateList(Object? rawList) {
    if (rawList is! List) {
      return const <Map<String, Object?>>[];
    }
    final result = <Map<String, Object?>>[];
    for (final entry in rawList) {
      if (entry is! Map) {
        continue;
      }
      result.add(entry.map((key, value) => MapEntry('$key', value)));
    }
    return result;
  }
}

class BackupPlanScheduleRegistration {
  const BackupPlanScheduleRegistration({
    required this.status,
    this.scheduledRunAt,
    this.errorMessage,
  });

  const BackupPlanScheduleRegistration.failed(this.errorMessage)
    : status = BackupPlanScheduleStatus.failed,
      scheduledRunAt = null;

  factory BackupPlanScheduleRegistration.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const BackupPlanScheduleRegistration(
        status: BackupPlanScheduleStatus.scheduled,
      );
    }
    final nextRunAtMillis = switch (map['nextRunAtMillis']) {
      int value => value,
      num value => value.toInt(),
      _ => null,
    };
    return BackupPlanScheduleRegistration(
      status: BackupPlanScheduleStatus.fromWireValue(map['status'] as String?),
      scheduledRunAt: nextRunAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextRunAtMillis),
      errorMessage: map['errorMessage'] as String?,
    );
  }

  final BackupPlanScheduleStatus status;
  final DateTime? scheduledRunAt;
  final String? errorMessage;
}

class BackupWorkerStateSnapshot {
  const BackupWorkerStateSnapshot({
    this.plans = const <BackupWorkerPlanSnapshot>[],
    this.runs = const <BackupWorkerRunSnapshot>[],
  });

  final List<BackupWorkerPlanSnapshot> plans;
  final List<BackupWorkerRunSnapshot> runs;

  BackupWorkerRunSnapshot? findActiveRun(String planId) {
    for (final run in runs) {
      if (run.planId == planId && run.isActive) {
        return run;
      }
    }
    return null;
  }
}

class BackupWorkerPlanSnapshot {
  const BackupWorkerPlanSnapshot({
    required this.planId,
    required this.enabled,
    required this.scheduleStatus,
    this.lastRunAt,
    this.scheduledRunAt,
    this.scheduleErrorMessage,
  });

  factory BackupWorkerPlanSnapshot.fromMap(Map<String, Object?> map) {
    return BackupWorkerPlanSnapshot(
      planId: map['planId']?.toString() ?? '',
      enabled: map['enabled'] as bool? ?? true,
      scheduleStatus: map['scheduleStatus']?.toString() ?? 'unscheduled',
      lastRunAt: _millisToDateTime(map['lastRunAtMillis']),
      scheduledRunAt: _millisToDateTime(map['scheduledRunAtMillis']),
      scheduleErrorMessage: map['scheduleErrorMessage'] as String?,
    );
  }

  final String planId;
  final bool enabled;
  final String scheduleStatus;
  final DateTime? lastRunAt;
  final DateTime? scheduledRunAt;
  final String? scheduleErrorMessage;
}

class ScheduledBackupNotificationState {
  const ScheduledBackupNotificationState({
    required this.runtimePermissionGranted,
    required this.appNotificationsEnabled,
    required this.channelEnabled,
    required this.message,
    this.channelImportance,
  });

  factory ScheduledBackupNotificationState.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const ScheduledBackupNotificationState(
        runtimePermissionGranted: false,
        appNotificationsEnabled: false,
        channelEnabled: false,
        message: '无法确认系统通知状态，请先在系统设置中开启铥棒文件通知。',
      );
    }
    return ScheduledBackupNotificationState(
      runtimePermissionGranted:
          map['runtimePermissionGranted'] as bool? ?? false,
      appNotificationsEnabled: map['appNotificationsEnabled'] as bool? ?? false,
      channelEnabled: map['channelEnabled'] as bool? ?? false,
      channelImportance: _nullableInt(map['channelImportance']),
      message: map['message']?.toString() ?? '无法确认系统通知状态，请检查系统设置。',
    );
  }

  final bool runtimePermissionGranted;
  final bool appNotificationsEnabled;
  final bool channelEnabled;
  final int? channelImportance;
  final String message;

  bool get isVisibleInDrawer =>
      runtimePermissionGranted && appNotificationsEnabled && channelEnabled;
}

class BackupWorkerRunSnapshot {
  const BackupWorkerRunSnapshot({
    required this.id,
    required this.triggerType,
    required this.status,
    required this.scannedCount,
    required this.queuedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.startedAt,
    this.processedCount,
    this.totalCount,
    this.planId,
    this.finishedAt,
    this.errorMessage,
    this.progressMessage,
    this.updatedAt,
  });

  factory BackupWorkerRunSnapshot.fromMap(Map<String, Object?> map) {
    return BackupWorkerRunSnapshot(
      id: map['id']?.toString() ?? '',
      planId: map['planId']?.toString(),
      triggerType: map['triggerType']?.toString() ?? 'scheduled',
      status: map['status']?.toString() ?? 'failed',
      scannedCount: _asInt(map['scannedCount']),
      queuedCount: _asInt(map['queuedCount']),
      skippedCount: _asInt(map['skippedCount']),
      failedCount: _asInt(map['failedCount']),
      processedCount: _nullableInt(map['processedCount']),
      totalCount: _nullableInt(map['totalCount']),
      startedAt: _millisToDateTime(map['startedAtMillis']) ?? DateTime.now(),
      finishedAt: _millisToDateTime(map['finishedAtMillis']),
      errorMessage: map['errorMessage'] as String?,
      progressMessage: map['progressMessage'] as String?,
      updatedAt: _millisToDateTime(map['updatedAtMillis']),
    );
  }

  final String id;
  final String? planId;
  final String triggerType;
  final String status;
  final int scannedCount;
  final int queuedCount;
  final int skippedCount;
  final int failedCount;
  final int? processedCount;
  final int? totalCount;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? errorMessage;
  final String? progressMessage;
  final DateTime? updatedAt;

  bool get isActive => switch (status) {
    'running' || 'retrying' || 'stopping' => true,
    _ => false,
  };

  bool get hasProgress =>
      processedCount != null && totalCount != null && totalCount! > 0;

  String get detailMessage {
    final progress = progressMessage?.trim();
    if (progress != null && progress.isNotEmpty) {
      return progress;
    }
    final error = errorMessage?.trim();
    if (error != null && error.isNotEmpty) {
      return error;
    }
    return switch (status) {
      'running' => '正在执行定时备份',
      'retrying' => '正在等待下一次重试',
      'stopping' => '正在停止本次备份',
      'stopped' => '本次备份已停止',
      'completed' => '本次备份已完成',
      _ => '当前备份状态已更新',
    };
  }
}

class BackupPlanExecutionProfileResolver {
  BackupPlanExecutionProfileResolver({
    required AuthLocalDataSource authLocalDataSource,
    required ClientIdentityService clientIdentityService,
    required TrustedServerStore trustedServerStore,
  }) : _authLocalDataSource = authLocalDataSource,
       _clientIdentityService = clientIdentityService,
       _trustedServerStore = trustedServerStore;

  final AuthLocalDataSource _authLocalDataSource;
  final ClientIdentityService _clientIdentityService;
  final TrustedServerStore _trustedServerStore;

  Future<AppResult<BackupNativePlanConfig>> build(BackupPlanEntity plan) async {
    final schedule = plan.schedule;
    if (schedule == null || !plan.enabled) {
      return Failure(
        AppFailure(code: 'BACKUP_PLAN_DISABLED', message: '请先启用定时备份计划'),
      );
    }
    if (plan.mode != BackupMode.fullGallery ||
        plan.sourcePath != 'gallery://all') {
      return Failure(
        AppFailure(
          code: 'BACKUP_PLAN_UNSUPPORTED_SOURCE',
          message: '当前只有整机图库备份支持后台定时执行',
        ),
      );
    }

    final savedSession = await _authLocalDataSource.loadSession();
    if (savedSession == null) {
      return Failure(
        AppFailure(
          code: 'BACKUP_PLAN_NO_SESSION',
          message: '请先登录服务器并保存会话后再启用定时备份',
        ),
      );
    }

    final planServerId = plan.serverId?.trim();
    final sessionServerId = savedSession.serverId.trim();
    if (planServerId != null &&
        planServerId.isNotEmpty &&
        sessionServerId.isNotEmpty &&
        planServerId != sessionServerId) {
      return Failure(
        AppFailure(
          code: 'BACKUP_PLAN_SERVER_MISMATCH',
          message: '计划绑定的服务器与当前已保存会话不一致，请重新连接对应服务器',
        ),
      );
    }

    final serverUrl = savedSession.serverUrl.trim();
    if (serverUrl.isEmpty) {
      return Failure(
        AppFailure(
          code: 'BACKUP_PLAN_NO_SERVER_URL',
          message: '当前已保存会话缺少服务器地址，无法注册定时备份',
        ),
      );
    }

    final deviceSession = await _authLocalDataSource.loadDeviceSession(
      serverId: sessionServerId,
    );
    if (deviceSession == null ||
        deviceSession.accessToken.trim().isEmpty ||
        deviceSession.refreshToken.trim().isEmpty) {
      return Failure(
        AppFailure(
          code: 'BACKUP_PLAN_NO_DEVICE_SESSION',
          message: '定时备份需要已保存的设备会话，请重新扫描服务端连接二维码',
        ),
      );
    }

    final trustedServer =
        _trustedServerStore.findByServerId(sessionServerId) ??
        _trustedServerStore.findByServerUrl(serverUrl);
    if (trustedServer == null || trustedServer.rootCaPem.trim().isEmpty) {
      return Failure(
        AppFailure(
          code: 'BACKUP_PLAN_UNTRUSTED_SERVER',
          message: '请先信任当前服务器证书后再启用定时备份',
        ),
      );
    }

    final deviceId = deviceSession.deviceId;
    final deviceName = await _clientIdentityService.getDeviceName();

    return Success(
      BackupNativePlanConfig(
        planId: plan.id,
        planName: plan.name,
        serverId: sessionServerId,
        serverUrl: serverUrl,
        rootId: plan.rootId,
        accessToken: deviceSession.accessToken,
        refreshToken: deviceSession.refreshToken,
        deviceId: deviceSession.deviceId,
        deviceName: deviceName,
        includeImages: plan.includeImages,
        includeVideos: plan.includeVideos,
        scheduleType: schedule.type.name,
        hour: schedule.hour,
        minute: schedule.minute,
        weekday: schedule.weekday,
        dayOfMonth: schedule.dayOfMonth,
        onceAtMillis: schedule.onceAt?.millisecondsSinceEpoch,
        requiresWifi: schedule.requiresWifi,
        requiresCharging: schedule.requiresCharging,
        rootCaPem: trustedServer.rootCaPem,
        leafSha256: trustedServer.leafSha256,
      ),
    );
  }
}

/// Returns true when native worker snapshot should be merged into SQLite
/// (run/schedule state changed), not for progress-only UI updates.
bool shouldPersistWorkerSnapshot({
  required BackupWorkerRunSnapshot? previousActiveRun,
  required BackupWorkerRunSnapshot? nextActiveRun,
  required BackupWorkerPlanSnapshot? previousPlan,
  required BackupWorkerPlanSnapshot? nextPlan,
}) {
  if (previousActiveRun?.id != nextActiveRun?.id) {
    return true;
  }
  if (previousActiveRun?.status != nextActiveRun?.status) {
    return true;
  }
  if (previousActiveRun?.finishedAt != nextActiveRun?.finishedAt) {
    return true;
  }

  if (previousPlan?.scheduleStatus != nextPlan?.scheduleStatus) {
    return true;
  }
  if (previousPlan?.scheduledRunAt != nextPlan?.scheduledRunAt) {
    return true;
  }
  if (previousPlan?.lastRunAt != nextPlan?.lastRunAt) {
    return true;
  }
  if (previousPlan?.scheduleErrorMessage != nextPlan?.scheduleErrorMessage) {
    return true;
  }

  return false;
}

DateTime? _millisToDateTime(Object? rawMillis) {
  final millis = switch (rawMillis) {
    int value => value,
    num value => value.toInt(),
    _ => null,
  };
  return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
}

int _asInt(Object? value) {
  return switch (value) {
    int intValue => intValue,
    num numValue => numValue.toInt(),
    _ => 0,
  };
}

int? _nullableInt(Object? value) {
  return switch (value) {
    int intValue => intValue,
    num numValue => numValue.toInt(),
    _ => null,
  };
}

class BackupNativePlanConfig {
  const BackupNativePlanConfig({
    required this.planId,
    required this.planName,
    required this.serverId,
    required this.serverUrl,
    required this.rootId,
    required this.accessToken,
    required this.refreshToken,
    required this.deviceId,
    required this.deviceName,
    required this.includeImages,
    required this.includeVideos,
    required this.scheduleType,
    required this.hour,
    required this.minute,
    this.weekday,
    this.dayOfMonth,
    this.onceAtMillis,
    required this.requiresWifi,
    required this.requiresCharging,
    required this.rootCaPem,
    this.leafSha256,
  });

  final String planId;
  final String planName;
  final String serverId;
  final String serverUrl;
  final String rootId;
  final String accessToken;
  final String refreshToken;
  final String deviceId;
  final String deviceName;
  final bool includeImages;
  final bool includeVideos;
  final String scheduleType;
  final int hour;
  final int minute;
  final int? weekday;
  final int? dayOfMonth;
  final int? onceAtMillis;
  final bool requiresWifi;
  final bool requiresCharging;
  final String rootCaPem;
  final String? leafSha256;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'planId': planId,
      'planName': planName,
      'serverId': serverId,
      'serverUrl': serverUrl,
      'rootId': rootId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'includeImages': includeImages,
      'includeVideos': includeVideos,
      'scheduleType': scheduleType,
      'hour': hour,
      'minute': minute,
      'weekday': weekday,
      'dayOfMonth': dayOfMonth,
      'onceAtMillis': onceAtMillis,
      'requiresWifi': requiresWifi,
      'requiresCharging': requiresCharging,
      'rootCaPem': rootCaPem,
      'leafSha256': leafSha256,
    };
  }
}
