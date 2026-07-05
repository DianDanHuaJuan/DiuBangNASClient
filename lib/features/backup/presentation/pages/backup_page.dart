/// 文件输入：BackupCubit、TransferCubit、本地图库/文件/目录选择结果
/// 文件职责：展示文件备份页面，提供精简的图库备份入口
/// 文件对外接口：BackupPage
/// 文件包含：BackupPage
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/auth/root_info.dart';
import '../../../../core/device/local_media_picker.dart';
import '../../../../core/realtime/realtime_session_service.dart';
import '../../../../core/widgets/offline_resource_gate.dart';
import '../../../transfer/domain/entities/upload_conflict_resolution.dart';
import '../../application/params/create_backup_plan_params.dart';
import '../../application/services/backup_plan_scheduler_service.dart';
import '../../application/services/backup_schedule_utils.dart';
import '../../application/services/scheduled_backup_poll_controller.dart';
import '../../application/use_cases/load_recent_backup_runs_use_case.dart';
import '../../domain/entities/backup_mode.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/entities/backup_plan_schedule_status.dart';
import '../../domain/entities/backup_preparation_progress.dart';
import '../../domain/entities/backup_run_record_entity.dart';
import '../../domain/entities/backup_schedule_entity.dart';
import '../../domain/entities/backup_upload_request.dart';
import '../../../transfer/domain/entities/transfer_status.dart';
import '../../../transfer/domain/entities/transfer_task_entity.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';
import '../../../transfer/presentation/cubit/transfer_state.dart';
import '../../domain/entities/backup_source_item.dart';
import '../../domain/entities/backup_source_type.dart';
import '../cubit/backup_cubit.dart';
import '../cubit/backup_state.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

enum _BackupGalleryAction { now, scheduled, cancel }

class _BackupPageState extends State<BackupPage> {
  static const _dailyPlanId = 'daily-full-gallery-plan';
  static const _localMediaPicker = LocalMediaPicker();
  static const _backupSchedulerChannel = MethodChannel(
    'com.nasclient/backup_scheduler',
  );
  String? _activeConflictTaskId;
  bool _isLoadingPlans = true;
  bool _isSavingPlan = false;
  List<BackupPlanEntity> _plans = const <BackupPlanEntity>[];
  List<BackupRunRecordEntity> _recentBackupRuns =
      const <BackupRunRecordEntity>[];
  List<BackupRunRecordEntity> _recentScheduledIssues =
      const <BackupRunRecordEntity>[];
  Timer? _floatingStatusDismissTimer;
  late final ScheduledBackupPollController _scheduledPollController;
  BackupWorkerRunSnapshot? _activeScheduledRun;
  bool _isStoppingScheduledRun = false;

  @override
  void initState() {
    super.initState();
    _scheduledPollController = ScheduledBackupPollController(
      scheduler: serviceLocator.backupPlanScheduler,
      planId: _dailyPlanId,
      onUpdated: _onScheduledPollUpdated,
    );
    unawaited(_loadPlans());
    _scheduledPollController.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final transferState = context.read<TransferCubit>().state;
    _syncTransferState(transferState);
    _handleTransferState(transferState);
    _handleBackupState(context.read<BackupCubit>().state);
  }

  @override
  void dispose() {
    _floatingStatusDismissTimer?.cancel();
    _scheduledPollController.stop();
    super.dispose();
  }

  void _onScheduledPollUpdated(
    BackupWorkerStateSnapshot snapshot,
    BackupWorkerRunSnapshot? activeRun,
    bool runTransitioned,
  ) {
    if (!mounted) {
      return;
    }
    final previousRunId = _activeScheduledRun?.id;
    final nextRunId = activeRun?.id;
    if (previousRunId == nextRunId &&
        _activeScheduledRun?.status == activeRun?.status &&
        _activeScheduledRun?.progressMessage == activeRun?.progressMessage) {
      return;
    }
    setState(() {
      _activeScheduledRun = activeRun;
    });
    if (runTransitioned) {
      unawaited(_loadPlans());
    }
  }

  void _syncTransferState(TransferState state) {
    if (state is TransferLoaded) {
      context.read<BackupCubit>().syncTrackedTasks(state.tasks);
    }
  }

  void _handleTransferState(TransferState state) {
    if (state is! TransferLoaded) {
      return;
    }

    final trackedTaskIds = context
        .read<BackupCubit>()
        .state
        .trackedTaskIds
        .toSet();
    if (trackedTaskIds.isEmpty) {
      return;
    }

    for (final task in state.tasks) {
      if (task.status != TransferStatus.awaitingConflictResolution) {
        continue;
      }
      if (!trackedTaskIds.contains(task.id)) {
        continue;
      }
      unawaited(_autoResolveTrackedUploadConflict(task));
      break;
    }
  }

  void _handleBackupState(BackupState state) {
    if (state.isBatchFinished &&
        state.activeRunId == null &&
        state.hasTrackedBatch) {
      unawaited(_loadBackupHistory());
    }

    if (!state.showFloatingStatusBar || !state.hasTrackedBatch) {
      _floatingStatusDismissTimer?.cancel();
      _floatingStatusDismissTimer = null;
      return;
    }
    if (state.isBatchRunning) {
      _floatingStatusDismissTimer?.cancel();
      _floatingStatusDismissTimer = null;
      return;
    }
    if (_floatingStatusDismissTimer != null) {
      return;
    }
    _floatingStatusDismissTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      context.read<BackupCubit>().dismissFloatingStatusBar();
      _floatingStatusDismissTimer = null;
    });
  }

  BackupPlanEntity? get _dailyPlan {
    for (final plan in _plans) {
      if (plan.id == _dailyPlanId) {
        return plan;
      }
    }
    return null;
  }

  Future<void> _autoResolveTrackedUploadConflict(
    TransferTaskEntity task,
  ) async {
    if (!mounted) {
      return;
    }
    if (_activeConflictTaskId != null) {
      return;
    }

    _activeConflictTaskId = task.id;
    try {
      await context.read<TransferCubit>().resolveUploadConflict(
        taskId: task.id,
        resolution: UploadConflictResolution.autoRename,
      );
      if (!mounted) {
        return;
      }
      _showSnackBar('检测到重名冲突，已自动保留副本继续备份');
    } finally {
      _activeConflictTaskId = null;
    }
  }

  RootInfo? _resolveBackupRoot() {
    final session = serviceLocator.currentSession;
    final fsRoot = session.getRootById('fs');
    if (fsRoot != null && fsRoot.writable) {
      return fsRoot;
    }
    final writableRoots = session.writableRoots;
    if (writableRoots.isEmpty) {
      return null;
    }
    return writableRoots.first;
  }

  bool get _hasWritableTarget => _resolveBackupRoot() != null;

  Future<void> _loadPlans() async {
    setState(() {
      _isLoadingPlans = true;
    });
    final planResult = await serviceLocator.loadBackupPlansUseCase.call();
    final runResult = await serviceLocator.loadRecentBackupRunsUseCase.call(
      const LoadRecentBackupRunsParams(
        planId: _dailyPlanId,
        limit: 3,
        onlyAbnormal: true,
      ),
    );
    final historyResult = await serviceLocator.loadRecentBackupRunsUseCase.call(
      const LoadRecentBackupRunsParams(limit: 10),
    );
    if (!mounted) {
      return;
    }
    planResult.when(
      success: (plans) {
        setState(() {
          _plans = plans;
          _isLoadingPlans = false;
        });
      },
      failure: (failure) {
        setState(() {
          _isLoadingPlans = false;
        });
        _showSnackBar(failure.message);
      },
    );
    if (!mounted) {
      return;
    }
    runResult.when(
      success: (runs) {
        setState(() {
          _recentScheduledIssues = runs;
        });
      },
      failure: (_) {},
    );
    historyResult.when(
      success: (runs) {
        setState(() {
          _recentBackupRuns = runs;
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _refreshBackupPlanSnapshot({bool forcePersist = false}) async {
    await _scheduledPollController.refreshOnce(forcePersist: forcePersist);
  }

  Future<void> _stopScheduledBackup() async {
    if (_isStoppingScheduledRun) {
      return;
    }
    setState(() {
      _isStoppingScheduledRun = true;
    });
    try {
      final result = await serviceLocator.backupPlanScheduler.stopCurrentRun(
        _dailyPlanId,
      );
      if (!mounted) {
        return;
      }
      result.when(
        success: (_) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('正在停止当前本次备份')));
        },
        failure: (failure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(failure.message)));
        },
      );
      _scheduledPollController.boostPollWindow();
      await _refreshBackupPlanSnapshot(forcePersist: true);
      await _loadPlans();
    } finally {
      if (mounted) {
        setState(() {
          _isStoppingScheduledRun = false;
        });
      }
    }
  }

  Future<bool> _confirmStopBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('停止备份？'),
          content: const Text('备份尚未完成。停止后本次进度将放弃，你可以稍后重新开始。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('继续备份'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC53030),
              ),
              child: const Text('停止备份'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _handleBackPress() async {
    final backupState = context.read<BackupCubit>().state;
    if (!backupState.shouldConfirmBackNavigation) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    final shouldStop = await _confirmStopBackup();
    if (!shouldStop || !mounted) {
      return;
    }
    await context.read<BackupCubit>().stopCurrentBackup();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openBackupPlanPage() async {
    _scheduledPollController.pause();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BackupPlanDetailPage(
          planId: _dailyPlanId,
          pollController: _scheduledPollController,
          onConfigurePlan: () async {
            await _configureScheduledBackup();
          },
          onTogglePlan: (enabled) async {
            await _toggleScheduledPlan(enabled);
          },
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _scheduledPollController.setListener(_onScheduledPollUpdated);
    _scheduledPollController.resume();
    await _loadPlans();
  }

  Future<void> _loadBackupHistory() async {
    final historyResult = await serviceLocator.loadRecentBackupRunsUseCase.call(
      const LoadRecentBackupRunsParams(limit: 10),
    );
    if (!mounted) {
      return;
    }
    historyResult.when(
      success: (runs) {
        setState(() {
          _recentBackupRuns = runs;
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _configureScheduledBackup() async {
    final backupRoot = _resolveBackupRoot();
    if (backupRoot == null) {
      _showSnackBar('当前会话没有可写入的服务端根目录');
      return;
    }
    final hasNotificationPermission =
        await _ensureScheduledBackupNotificationPermission();
    if (!hasNotificationPermission || !mounted) {
      return;
    }
    final hasMediaAccess = await _ensureFullGalleryMediaAccess(
      includeImages: true,
      includeVideos: true,
    );
    if (!hasMediaAccess || !mounted) {
      return;
    }

    final existingPlan = _dailyPlan;
    final draft = await showDialog<_ScheduledPlanDraft>(
      context: context,
      builder: (dialogContext) => _ScheduledPlanDialog(plan: existingPlan),
    );
    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isSavingPlan = true;
    });
    try {
      final currentServer = serviceLocator.unifiedNodeStore.currentServer;
      final serverId =
          currentServer?.identity.serverId ??
          currentServer?.network.connectBaseUrl;
      final result = await serviceLocator.createBackupPlanUseCase.call(
        CreateBackupPlanParams(
          id: _dailyPlanId,
          name: '定时图库自动备份',
          mode: BackupMode.fullGallery,
          sourcePath: 'gallery://all',
          targetPath: '/',
          serverId: serverId,
          rootId: backupRoot.id,
          schedule: BackupScheduleEntity(
            type: draft.type,
            hour: draft.time.hour,
            minute: draft.time.minute,
            weekday: draft.weekday,
            dayOfMonth: draft.dayOfMonth,
            onceAt: draft.scheduledAt,
            requiresWifi: draft.requiresWifi,
            requiresCharging: draft.requiresCharging,
          ),
          includeImages: draft.includeImages,
          includeVideos: draft.includeVideos,
        ),
      );
      if (!mounted) {
        return;
      }
      if (result.isFailure) {
        _showSnackBar(result.failureOrNull!.message);
        return;
      }

      final plan = result.dataOrNull!;
      final scheduleResult = await serviceLocator.backupPlanScheduler
          .schedulePlan(plan);
      await _loadPlans();
      if (!mounted) {
        return;
      }
      if (scheduleResult.isFailure) {
        _showSnackBar(
          '计划已保存，但系统调度未注册：${scheduleResult.failureOrNull!.message}',
        );
        return;
      }
      final registration = scheduleResult.dataOrNull!;
      _showSnackBar(
        registration.scheduledRunAt == null
            ? '已设置定时自动备份：${BackupScheduleUtils.formatTime(plan.schedule!)}'
            : '已设置定时自动备份，下次执行：${_formatDateTime(registration.scheduledRunAt!)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPlan = false;
        });
      } else {
        _isSavingPlan = false;
      }
    }
  }

  Future<void> _toggleScheduledPlan(bool enabled) async {
    final plan = _dailyPlan;
    if (plan == null) {
      return;
    }
    if (enabled) {
      final hasNotificationPermission =
          await _ensureScheduledBackupNotificationPermission();
      if (!hasNotificationPermission || !mounted) {
        return;
      }
      final hasMediaAccess = await _ensureFullGalleryMediaAccess(
        includeImages: plan.includeImages,
        includeVideos: plan.includeVideos,
      );
      if (!hasMediaAccess || !mounted) {
        return;
      }
    }
    setState(() {
      _isSavingPlan = true;
    });
    try {
      final result = await serviceLocator.toggleBackupPlanUseCase.call(
        planId: plan.id,
        enabled: enabled,
      );
      if (!mounted) {
        return;
      }
      if (result.isFailure) {
        _showSnackBar(result.failureOrNull!.message);
        return;
      }

      if (enabled) {
        final scheduleResult = await serviceLocator.backupPlanScheduler
            .schedulePlan(
              BackupPlanEntity(
                id: plan.id,
                name: plan.name,
                mode: plan.mode,
                sourcePath: plan.sourcePath,
                targetPath: plan.targetPath,
                serverId: plan.serverId,
                rootId: plan.rootId,
                schedule: plan.schedule,
                enabled: true,
                includeImages: plan.includeImages,
                includeVideos: plan.includeVideos,
                lastRunAt: plan.lastRunAt,
                scheduleStatus: plan.scheduleStatus,
                scheduleErrorMessage: plan.scheduleErrorMessage,
                scheduledRunAt: plan.scheduledRunAt,
                createdAt: plan.createdAt,
                updatedAt: plan.updatedAt,
              ),
            );
        await _loadPlans();
        if (!mounted) {
          return;
        }
        if (scheduleResult.isFailure) {
          _showSnackBar(
            '计划已启用，但系统调度未注册：${scheduleResult.failureOrNull!.message}',
          );
          return;
        }
        final registration = scheduleResult.dataOrNull!;
        _showSnackBar(
          registration.scheduledRunAt == null
              ? '已启用定时自动备份'
              : '已启用定时自动备份，下次执行：${_formatDateTime(registration.scheduledRunAt!)}',
        );
      } else {
        final cancelResult = await serviceLocator.backupPlanScheduler
            .cancelPlan(plan.id);
        await _loadPlans();
        if (!mounted) {
          return;
        }
        if (cancelResult.isFailure) {
          _showSnackBar(cancelResult.failureOrNull!.message);
          return;
        }
        _showSnackBar('已暂停定时自动备份');
      }
      _scheduledPollController.boostPollWindow();
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPlan = false;
        });
      } else {
        _isSavingPlan = false;
      }
    }
  }

  Future<void> _runBackupNow() async {
    final selectedItems = List<BackupSourceItem>.from(
      context.read<BackupCubit>().state.selectedItems,
    );
    if (selectedItems.isEmpty) {
      _showSnackBar('请先选择要备份的资源');
      return;
    }

    final requests = selectedItems
        .map((item) => BackupUploadRequest.fromSource(item))
        .toList(growable: false);
    await _runBackupRequests(
      requests,
      scannedCount: selectedItems.length,
      unavailableCount: 0,
    );
  }

  Future<void> _showBackupGalleryDialog() async {
    final result = await showDialog<_BackupGalleryAction>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '即将备份图库中的全部图片和视频',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              Center(
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_BackupGalleryAction.now),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D8A5A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('立即备份', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_BackupGalleryAction.scheduled),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D8A5A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('定时备份', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_BackupGalleryAction.cancel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF3F4F6),
                    foregroundColor: const Color(0xFF374151),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || result == null || result == _BackupGalleryAction.cancel) {
      return;
    }
    if (result == _BackupGalleryAction.now) {
      await _backupEntireGalleryNow();
    } else {
      await _configureScheduledBackup();
    }
  }

  Future<void> _backupEntireGalleryNow() async {
    final backupCubit = context.read<BackupCubit>();
    if (backupCubit.state.isBusyPreparing) {
      return;
    }
    final hasMediaAccess = await _ensureFullGalleryMediaAccess(
      includeImages: true,
      includeVideos: true,
    );
    if (!hasMediaAccess || !mounted) {
      return;
    }
    final cancellation = backupCubit.beginBackupOperation();
    backupCubit.updatePreparationProgress(
      const BackupPreparationProgress(
        phase: BackupPreparationPhase.scanningGallery,
        processedCount: 0,
        totalCount: 0,
        detail: '正在读取整机图库',
      ),
    );

    try {
      final result = await _localMediaPicker.loadAllMedia(
        shouldCancel: () => cancellation.isCancelled,
        onProgress: (progress) {
          if (!mounted || cancellation.isCancelled) {
            return;
          }
          context.read<BackupCubit>().updatePreparationProgress(
            BackupPreparationProgress(
              phase: BackupPreparationPhase.scanningGallery,
              processedCount: progress.scannedAssets,
              totalCount: progress.totalAssets,
              detail:
                  '已扫描 ${progress.scannedAssets} / ${progress.totalAssets} 项，发现 ${progress.discoveredItems} 个可备份文件',
            ),
          );
        },
      );
      if (!mounted || cancellation.isCancelled) {
        return;
      }
      if (result.items.isEmpty) {
        backupCubit.clearPreparationProgress();
        _showSnackBar('图库中没有可备份的图片或视频');
        return;
      }

      final requests = result.items
          .map(
            (item) => BackupUploadRequest.fromSource(
              BackupSourceItem(
                id: 'media:${item.id}',
                sourceType: BackupSourceType.media,
                localPath: item.localPath,
                displayName: item.displayName,
                size: item.size,
                mimeType: item.mimeType,
                sourceLabel: '来自整机图库',
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt,
                durationSeconds: item.durationSeconds,
              ),
            ),
          )
          .toList(growable: false);

      await _runBackupRequests(
        requests,
        scannedCount: result.items.length,
        unavailableCount: result.unavailableCount,
      );
    } finally {
      backupCubit.endBackupOperation();
      if (mounted &&
          !context.read<BackupCubit>().state.isSubmitting &&
          !cancellation.isCancelled) {
        context.read<BackupCubit>().clearPreparationProgress();
      }
    }
  }

  Future<void> _runBackupRequests(
    List<BackupUploadRequest> requests, {
    required int scannedCount,
    required int unavailableCount,
  }) async {
    final backupRoot = _resolveBackupRoot();
    if (backupRoot == null) {
      _showSnackBar('当前会话没有可写入的服务端根目录');
      return;
    }

    context.read<BackupCubit>().updatePreparationProgress(
      const BackupPreparationProgress(
        phase: BackupPreparationPhase.inspectingFiles,
        processedCount: 0,
        totalCount: 0,
        detail: '正在准备备份任务',
      ),
    );
    final result = await context.read<BackupCubit>().runBackupNow(
      requests: requests,
    );
    if (!mounted) {
      return;
    }

    result.when(
      success: (runResult) {
        _handleTransferState(context.read<TransferCubit>().state);
        final parts = <String>[
          '已扫描 ${runResult.scannedCount} 项',
          if (unavailableCount > 0) '$unavailableCount 项无法读取',
          if (runResult.skippedCount > 0)
            '自动跳过 ${runResult.skippedCount} 个已备份/重复文件',
          runResult.queuedCount == 1
              ? '已创建 1 个备份任务'
              : '已创建 ${runResult.queuedCount} 个备份任务',
          if (runResult.failedCount > 0) '${runResult.failedCount} 个未加入队列',
          '目标位置：${runResult.rootName}',
        ];
        _showSnackBar(parts.join('，'));
      },
      failure: (failure) {
        unawaited(_loadBackupHistory());
        final prefix = unavailableCount > 0 ? '$unavailableCount 项无法读取，' : '';
        _showSnackBar('$prefix${failure.message}');
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureFullGalleryMediaAccess({
    required bool includeImages,
    required bool includeVideos,
  }) async {
    var accessState = await _loadGalleryMediaAccessState(
      includeImages: includeImages,
      includeVideos: includeVideos,
    );
    if (accessState.isFullAccess) {
      return true;
    }

    await PhotoManager.requestPermissionExtend();
    accessState = await _loadGalleryMediaAccessState(
      includeImages: includeImages,
      includeVideos: includeVideos,
    );
    if (accessState.isFullAccess) {
      return true;
    }

    if (mounted) {
      _showSnackBar(accessState.message);
    }
    return false;
  }

  Future<bool> _ensureScheduledBackupNotificationPermission() async {
    var notificationState = await serviceLocator.backupPlanScheduler
        .loadNotificationState();
    if (notificationState.isVisibleInDrawer) {
      return true;
    }
    if (!notificationState.runtimePermissionGranted) {
      final granted = await serviceLocator.permissionService
          .requestNotificationPermission();
      if (granted) {
        notificationState = await serviceLocator.backupPlanScheduler
            .loadNotificationState();
        if (notificationState.isVisibleInDrawer) {
          return true;
        }
      }
    }
    if (mounted) {
      _showSnackBar(notificationState.message);
    }
    return false;
  }

  Future<_GalleryMediaAccessState> _loadGalleryMediaAccessState({
    required bool includeImages,
    required bool includeVideos,
  }) async {
    try {
      final raw = await _backupSchedulerChannel
          .invokeMethod<Map<Object?, Object?>>(
            'getMediaAccessScope',
            <String, Object?>{
              'includeImages': includeImages,
              'includeVideos': includeVideos,
            },
          );
      final data = <String, Object?>{};
      raw?.forEach((key, value) {
        if (key != null) {
          data[key.toString()] = value;
        }
      });
      return _GalleryMediaAccessState.fromMap(data);
    } on PlatformException {
      return const _GalleryMediaAccessState(
        scope: 'unknown',
        message: '无法确认系统照片权限，请先在系统设置中允许铥棒文件访问全部照片和视频。',
      );
    }
  }

  bool _looksLikeVideo(BackupSourceItem item) {
    final mimeType = item.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('video/')) {
      return true;
    }
    final ext = p.extension(item.displayName).toLowerCase();
    return const {
      '.mp4',
      '.mov',
      '.mkv',
      '.avi',
      '.webm',
      '.3gp',
      '.m4v',
    }.contains(ext);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<TransferCubit, TransferState>(
          listener: (context, state) => _handleTransferState(state),
        ),
        BlocListener<BackupCubit, BackupState>(
          listener: (context, state) => _handleBackupState(state),
        ),
      ],
      child: BlocBuilder<BackupCubit, BackupState>(
        builder: (context, state) {
          final canStartBackup =
              _hasWritableTarget &&
              state.hasSelection &&
              !state.isBusyPreparing &&
              !state.isSubmitting &&
              !state.isBatchRunning;

          return PopScope(
            canPop: !state.shouldConfirmBackNavigation,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop || !state.shouldConfirmBackNavigation) {
                return;
              }
              final shouldStop = await _confirmStopBackup();
              if (shouldStop && context.mounted) {
                await context.read<BackupCubit>().stopCurrentBackup();
              }
            },
            child: Scaffold(
              appBar: AppBar(
                leadingWidth: 150,
                leading: Tooltip(
                  message: '返回设置页',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _handleBackPress,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 24,
                            color: Color(0xFF6D6C6A),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '返回设置页',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF6D6C6A),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              body: Stack(
                children: [
                  SafeArea(
                    child: IgnorePointer(
                      ignoring: state.isBusyPreparing,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 112),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SourceActionCard(
                              icon: Icons.photo_library_outlined,
                              title: '备份图库',
                              accentColor: const Color(0xFF3D8A5A),
                              enabled:
                                  !state.isSubmitting &&
                                  !state.isBatchRunning &&
                                  !state.isPreparing,
                              onTap: _showBackupGalleryDialog,
                            ),
                            const SizedBox(height: 12),
                            _BackupPlanEntryCard(
                              plan: _dailyPlan,
                              activeRun: _activeScheduledRun,
                              enabled: !state.isBusyPreparing,
                              onTap: _openBackupPlanPage,
                            ),
                            if (_activeScheduledRun?.isActive == true) ...[
                              const SizedBox(height: 12),
                              _ScheduledBackupStopBanner(
                                run: _activeScheduledRun!,
                                planName:
                                    _dailyPlan?.name ?? '定时图库自动备份',
                                isStopping: _isStoppingScheduledRun,
                                onStop: _stopScheduledBackup,
                              ),
                            ],
                            const SizedBox(height: 12),
                            const _BatteryOptimizationHint(),
                            const SizedBox(height: 24),
                            if (state.hasSelection) ...[
                              _SelectionSummaryCard(
                                itemCount: state.selectedItems.length,
                                totalSizeLabel: _formatSize(
                                  state.selectedTotalBytes,
                                ),
                                duplicateNameCount: state.duplicateNameCount,
                                onClear:
                                    !state.isSubmitting && !state.isPreparing
                                    ? () => context
                                          .read<BackupCubit>()
                                          .clearSelection()
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              _SelectionList(
                                items: state.selectedItems,
                                formatSize: _formatSize,
                                isVideo: _looksLikeVideo,
                                onRemove:
                                    state.isSubmitting ||
                                        state.isBatchRunning ||
                                        state.isPreparing
                                    ? null
                                    : (item) => context
                                          .read<BackupCubit>()
                                          .removeSelectedItem(item.id),
                              ),
                              const SizedBox(height: 24),
                            ],
                            if (state.hasTrackedBatch && state.isBatchRunning)
                              _BatchProgressCard(
                                state: state,
                                formatSize: _formatSize,
                                onStop: state.isBackupStoppable
                                    ? () => context
                                          .read<BackupCubit>()
                                          .stopCurrentBackup()
                                    : null,
                              ),
                            const SizedBox(height: 16),
                            _BackupHistoryCard(
                              runs: _recentBackupRuns,
                              formatDateTime: _formatDateTime,
                            ),
                            if (!_hasWritableTarget) ...[
                              const SizedBox(height: 16),
                              const _WarningCard(
                                message: '当前会话没有可写入的服务端根目录，暂时无法创建备份任务。',
                              ),
                            ],
                            if (state.hasSelection ||
                                state.isBusyPreparing ||
                                state.isSubmitting ||
                                state.isBatchRunning) ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: canStartBackup
                                      ? _runBackupNow
                                      : null,
                                  icon: state.isBusyPreparing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.backup_outlined),
                                  label: Text(
                                    state.isPreparing
                                        ? '${state.preparationPhase?.title ?? '正在准备备份'}...'
                                        : state.isSubmitting
                                        ? '正在创建备份任务...'
                                        : state.isBatchRunning
                                        ? '当前批次执行中'
                                        : '开始备份 (${state.selectedItems.length} 项)',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  OfflineResourceGate(
                    controller: serviceLocator.serverAvailabilityController,
                    onReconnect: () =>
                        context.read<RealtimeSessionService>().reconnectNow(),
                  ),
                  if (state.isBusyPreparing)
                    _PreparationOverlay(
                      state: state,
                      onStop: state.isBackupStoppable
                          ? () => context
                                .read<BackupCubit>()
                                .stopCurrentBackup()
                          : null,
                    ),
                  if (!state.isBusyPreparing &&
                      state.hasTrackedBatch &&
                      state.showFloatingStatusBar)
                    _FloatingBatchStatusBar(
                      state: state,
                      formatSize: _formatSize,
                      onStop: state.isBackupStoppable
                          ? () => context
                                .read<BackupCubit>()
                                .stopCurrentBackup()
                          : null,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreparationOverlay extends StatelessWidget {
  const _PreparationOverlay({required this.state, this.onStop});

  final BackupState state;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final phaseTitle = state.preparationPhase?.title ?? '正在准备备份';
    final hasProgress = state.preparationTotalCount > 0;
    final subtitle =
        state.preparationDetail ??
        (state.isSubmitting ? '正在分析本地文件并创建上传任务' : '正在准备备份');

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.28),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F1FB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.sync_rounded,
                          color: Color(0xFF2B6CB0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          phaseTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6D6C6A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: hasProgress
                        ? state.preparationProgress.clamp(0, 1)
                        : null,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  if (hasProgress) ...[
                    const SizedBox(height: 10),
                    Text(
                      '${state.preparationProcessedCount} / ${state.preparationTotalCount}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6D6C6A),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    '准备完成后会立即开始上传，你可以随后离开此页，传输任务会继续执行。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6D6C6A),
                    ),
                  ),
                  if (onStop != null) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: state.isStopping ? null : onStop,
                        icon: state.isStopping
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.stop_circle_outlined),
                        label: Text(state.isStopping ? '正在停止…' : '停止备份'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC53030),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingBatchStatusBar extends StatelessWidget {
  const _FloatingBatchStatusBar({
    required this.state,
    required this.formatSize,
    this.onStop,
  });

  final BackupState state;
  final String Function(int bytes) formatSize;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final waitingToStart =
        state.isBatchRunning &&
        state.activeTaskCount == 0 &&
        state.totalBytes == 0 &&
        state.pendingTaskCount > 0;
    final title = switch ((waitingToStart, state.isBatchRunning)) {
      (true, _) => '备份任务已创建',
      (false, true) => '正在上传备份',
      _ => '本次备份已完成',
    };
    final subtitle = switch ((waitingToStart, state.isBatchRunning)) {
      (true, _) => '已入队 ${state.queuedTaskCount} 项，正在接管上传队列，请稍候',
      (false, true) =>
        '完成 ${state.completedTaskCount} · 上传中 ${state.activeTaskCount} · 等待 ${state.pendingTaskCount}',
      _ =>
        '完成 ${state.completedTaskCount} · 跳过 ${state.skippedTaskCount} · 失败 ${state.failedTaskCount}',
    };
    final progressText = waitingToStart
        ? '系统正在准备真正开始上传'
        : state.totalBytes > 0
        ? '${formatSize(state.transferredBytes)} / ${formatSize(state.totalBytes)}'
        : '已入队 ${state.queuedTaskCount} 项';

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 10,
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE6E2DC)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1FB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.backup_rounded,
                        size: 20,
                        color: Color(0xFF2B6CB0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF6D6C6A)),
                          ),
                        ],
                      ),
                    ),
                    if (onStop != null && state.isBatchRunning)
                      IconButton(
                        tooltip: '停止备份',
                        onPressed: state.isStopping ? null : onStop,
                        icon: state.isStopping
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.stop_circle_outlined,
                                color: Color(0xFFC53030),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: waitingToStart
                      ? null
                      : state.batchProgress.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 8),
                Text(
                  progressText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D6C6A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduledBackupStopBanner extends StatelessWidget {
  const _ScheduledBackupStopBanner({
    required this.run,
    required this.planName,
    required this.isStopping,
    required this.onStop,
  });

  final BackupWorkerRunSnapshot run;
  final String planName;
  final bool isStopping;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5C6C6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '定时备份执行中',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            planName,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
          ),
          const SizedBox(height: 8),
          Text(run.detailMessage),
          if (run.hasProgress) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: (run.processedCount! / run.totalCount!).clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isStopping || run.status == 'stopping' ? null : onStop,
              icon: isStopping || run.status == 'stopping'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: Text(
                isStopping || run.status == 'stopping'
                    ? '正在停止本次备份'
                    : '停止本次备份',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC53030),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final Color accentColor;

  const _SourceActionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.accentColor = const Color(0xFF2D3748),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6E2DC)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((subtitle?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6D6C6A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled
                    ? const Color(0xFF6D6C6A)
                    : const Color(0xFFBDB7AE),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupPlanEntryCard extends StatelessWidget {
  const _BackupPlanEntryCard({
    required this.plan,
    required this.activeRun,
    required this.enabled,
    required this.onTap,
  });

  final BackupPlanEntity? plan;
  final BackupWorkerRunSnapshot? activeRun;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final schedule = plan?.schedule;
    final nextRunAt = plan?.scheduledRunAt;
    final subtitle = switch (plan) {
      null => '查看定时备份计划和当前执行状态',
      _ when schedule == null => '当前计划缺少执行时间，请重新配置',
      _ =>
        '${BackupScheduleUtils.formatTime(schedule)}'
            '${nextRunAt == null ? '' : ' · 下次执行 ${_formatBackupDateTime(nextRunAt)}'}',
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE6E2DC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F1FB),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFF2B6CB0),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '备份计划',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF6D6C6A)),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: enabled
                        ? const Color(0xFF6D6C6A)
                        : const Color(0xFFBDB7AE),
                  ),
                ],
              ),
              if (activeRun != null) ...[
                const SizedBox(height: 12),
                Text(
                  '当前有正在执行的备份计划',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF2B6CB0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupPlanDetailPage extends StatefulWidget {
  const _BackupPlanDetailPage({
    required this.planId,
    required this.pollController,
    required this.onConfigurePlan,
    required this.onTogglePlan,
  });

  final String planId;
  final ScheduledBackupPollController pollController;
  final Future<void> Function() onConfigurePlan;
  final Future<void> Function(bool enabled) onTogglePlan;

  @override
  State<_BackupPlanDetailPage> createState() => _BackupPlanDetailPageState();
}

class _BackupPlanDetailPageState extends State<_BackupPlanDetailPage> {
  BackupPlanEntity? _plan;
  BackupWorkerRunSnapshot? _activeRun;
  ScheduledBackupNotificationState? _notificationState;
  bool _isLoading = true;
  bool _isMutatingPlan = false;
  bool _isStoppingRun = false;

  @override
  void initState() {
    super.initState();
    widget.pollController.setListener(_onScheduledPollUpdated);
    unawaited(_refresh(forcePersist: true));
    widget.pollController.resume();
  }

  @override
  void dispose() {
    widget.pollController.pause();
    super.dispose();
  }

  void _onScheduledPollUpdated(
    BackupWorkerStateSnapshot snapshot,
    BackupWorkerRunSnapshot? activeRun,
    bool runTransitioned,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeRun = activeRun;
    });
    if (runTransitioned) {
      unawaited(_loadPlanFromDatabase());
    }
  }

  Future<void> _loadPlanFromDatabase() async {
    final planResult = await serviceLocator.loadBackupPlansUseCase.call();
    if (!mounted) {
      return;
    }
    planResult.when(
      success: (plans) {
        BackupPlanEntity? plan;
        for (final entry in plans) {
          if (entry.id == widget.planId) {
            plan = entry;
            break;
          }
        }
        setState(() {
          _plan = plan;
        });
      },
      failure: (_) {},
    );
  }

  Future<void> _refresh({bool forcePersist = false}) async {
    final planResult = await serviceLocator.loadBackupPlansUseCase.call();
    final notificationState = await serviceLocator.backupPlanScheduler
        .loadNotificationState();
    await widget.pollController.refreshOnce(forcePersist: forcePersist);
    if (!mounted) {
      return;
    }

    planResult.when(
      success: (plans) {
        BackupPlanEntity? plan;
        for (final entry in plans) {
          if (entry.id == widget.planId) {
            plan = entry;
            break;
          }
        }
        setState(() {
          _plan = plan;
          _notificationState = notificationState;
          _isLoading = false;
        });
      },
      failure: (failure) {
        setState(() {
          _notificationState = notificationState;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      },
    );
  }

  Future<void> _configurePlan() async {
    setState(() {
      _isMutatingPlan = true;
    });
    try {
      await widget.onConfigurePlan();
      if (!mounted) {
        return;
      }
      widget.pollController.boostPollWindow();
      await _refresh(forcePersist: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingPlan = false;
        });
      }
    }
  }

  Future<void> _togglePlan(bool enabled) async {
    setState(() {
      _isMutatingPlan = true;
    });
    try {
      await widget.onTogglePlan(enabled);
      if (!mounted) {
        return;
      }
      widget.pollController.boostPollWindow();
      await _refresh(forcePersist: true);
    } finally {
      if (mounted) {
        setState(() {
          _isMutatingPlan = false;
        });
      }
    }
  }

  Future<void> _openNotificationSettings() async {
    final result = await serviceLocator.backupPlanScheduler
        .openNotificationSettings();
    if (!mounted) {
      return;
    }
    result.when(
      success: (_) {},
      failure: (failure) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
      },
    );
  }

  Future<void> _stopCurrentRun() async {
    final planId = _activeRun?.planId ?? _plan?.id ?? widget.planId;
    setState(() {
      _isStoppingRun = true;
    });
    try {
      final result = await serviceLocator.backupPlanScheduler.stopCurrentRun(
        planId,
      );
      if (!mounted) {
        return;
      }
      result.when(
        success: (_) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('正在停止当前本次备份')));
        },
        failure: (failure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(failure.message)));
        },
      );
      widget.pollController.boostPollWindow();
      await _refresh(forcePersist: true);
    } finally {
      if (mounted) {
        setState(() {
          _isStoppingRun = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showEmptyState = !_isLoading && _plan == null && _activeRun == null;

    return Scaffold(
      appBar: AppBar(title: const Text('备份计划')),
      body: SafeArea(
        child: _isLoading && _plan == null && _activeRun == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showEmptyState)
                      Text(
                        '当前无备份计划',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6D6C6A),
                        ),
                      ),
                    if (_plan != null) ...[
                      _ScheduledBackupCard(
                        plan: _plan,
                        recentIssues: const <BackupRunRecordEntity>[],
                        isBusy: _isLoading || _isMutatingPlan || _isStoppingRun,
                        enabled: !_isStoppingRun,
                        onConfigure: _configurePlan,
                        onToggle: _togglePlan,
                      ),
                      if (_activeRun != null) const SizedBox(height: 16),
                    ],
                    if (_activeRun != null)
                      _RunningBackupPlanCard(
                        run: _activeRun!,
                        planName: _plan?.name ?? '定时图库自动备份',
                        isStopping: _isStoppingRun,
                        notificationWarningMessage:
                            _notificationState != null &&
                                !_notificationState!.isVisibleInDrawer
                            ? _notificationState!.message
                            : null,
                        onOpenNotificationSettings: _openNotificationSettings,
                        onStop: _stopCurrentRun,
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RunningBackupPlanCard extends StatelessWidget {
  const _RunningBackupPlanCard({
    required this.run,
    required this.planName,
    required this.isStopping,
    required this.onOpenNotificationSettings,
    required this.onStop,
    this.notificationWarningMessage,
  });

  final BackupWorkerRunSnapshot run;
  final String planName;
  final bool isStopping;
  final String? notificationWarningMessage;
  final VoidCallback onOpenNotificationSettings;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (run.status) {
      'retrying' => const Color(0xFFB54708),
      'stopping' => const Color(0xFF2B6CB0),
      _ => const Color(0xFF3D8A5A),
    };
    final statusLabel = switch (run.status) {
      'retrying' => '重试中',
      'stopping' => '停止中',
      _ => '执行中',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E2DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.autorenew_rounded, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前正在执行的备份计划',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      planName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6D6C6A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            run.detailMessage,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (run.hasProgress) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (run.processedCount! / run.totalCount!).clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '开始时间：${_formatBackupDateTime(run.startedAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
          ),
          if (run.updatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              '最近更新：${_formatBackupDateTime(run.updatedAt!)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (run.hasProgress)
                _PlanTag(
                  label: '已处理 ${run.processedCount} / ${run.totalCount}',
                ),
              _PlanTag(label: '已上传 ${run.queuedCount}'),
              _PlanTag(label: '已跳过 ${run.skippedCount}'),
              _PlanTag(label: '失败 ${run.failedCount}'),
            ],
          ),
          if (notificationWarningMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF3D19C)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_off_outlined,
                        size: 18,
                        color: Color(0xFFB54708),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          notificationWarningMessage!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF8A5A00)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onOpenNotificationSettings,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('去打开通知设置'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isStopping || run.status == 'stopping' ? null : onStop,
              icon: isStopping || run.status == 'stopping'
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: Text(
                isStopping || run.status == 'stopping'
                    ? '正在停止本次备份'
                    : '停止当前本次备份',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledBackupCard extends StatelessWidget {
  const _ScheduledBackupCard({
    required this.plan,
    required this.recentIssues,
    required this.isBusy,
    required this.enabled,
    required this.onConfigure,
    required this.onToggle,
  });

  final BackupPlanEntity? plan;
  final List<BackupRunRecordEntity> recentIssues;
  final bool isBusy;
  final bool enabled;
  final VoidCallback onConfigure;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final schedule = plan?.schedule;
    final actualNextRunAt = plan?.scheduledRunAt;
    final scheduleRule = schedule == null
        ? null
        : BackupScheduleUtils.describeRule(schedule);
    final scheduleStatus =
        plan?.scheduleStatus ?? BackupPlanScheduleStatus.unscheduled;
    final statusSummary = switch (scheduleStatus) {
      BackupPlanScheduleStatus.scheduled =>
        actualNextRunAt == null
            ? '系统调度已注册'
            : '系统调度已注册，下次执行 ${_formatDateTime(actualNextRunAt)}',
      BackupPlanScheduleStatus.failed => '系统调度失败，需要重新处理',
      BackupPlanScheduleStatus.unscheduled when plan?.enabled == true =>
        '计划已保存，等待完成系统调度',
      _ => null,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E2DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Color(0xFF2B6CB0),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '定时自动备份',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan == null
                          ? '可按每日、每周、每月或仅一次执行整机图库增量备份'
                          : statusSummary == null
                          ? '已设置 ${BackupScheduleUtils.formatTime(schedule!)}'
                          : '${BackupScheduleUtils.formatTime(schedule!)} · $statusSummary',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6D6C6A),
                      ),
                    ),
                  ],
                ),
              ),
              if (plan != null)
                Switch(
                  value: plan!.enabled,
                  onChanged: enabled && !isBusy && onToggle != null
                      ? onToggle
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (plan == null)
            Text(
              '还没有配置定时计划。建议至少开启 Wi‑Fi 条件，避免蜂窝网络下自动触发大批量上传。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PlanTag(
                  label: plan!.includeImages && plan!.includeVideos
                      ? '图片 + 视频'
                      : plan!.includeImages
                      ? '仅图片'
                      : '仅视频',
                ),
                if (schedule!.requiresWifi) const _PlanTag(label: '仅 Wi-Fi'),
                if (schedule.requiresCharging) const _PlanTag(label: '仅充电'),
                if (scheduleStatus == BackupPlanScheduleStatus.scheduled)
                  const _PlanTag(label: '系统已注册'),
                if (scheduleStatus == BackupPlanScheduleStatus.failed)
                  const _PlanTag(label: '系统调度失败'),
                if (scheduleStatus == BackupPlanScheduleStatus.unscheduled &&
                    plan!.enabled)
                  const _PlanTag(label: '尚未注册到系统'),
                if (actualNextRunAt != null)
                  _PlanTag(label: '下次执行 ${_formatDateTime(actualNextRunAt)}'),
                if (scheduleRule?.isNotEmpty ?? false)
                  _PlanTag(label: scheduleRule!),
              ],
            ),
            if ((plan!.scheduleErrorMessage?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 10),
              Text(
                '调度状态：${plan!.scheduleErrorMessage!}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFFB42318)),
              ),
            ],
            if (plan!.lastRunAt != null) ...[
              const SizedBox(height: 10),
              Text(
                '最近一次执行：${_formatDateTime(plan!.lastRunAt!)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
              ),
            ],
            if (recentIssues.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                '最近异常记录',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final run in recentIssues) ...[
                _BackupRunIssueTile(run: run),
                if (run != recentIssues.last) const SizedBox(height: 8),
              ],
            ],
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: enabled && !isBusy ? onConfigure : null,
              icon: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      plan == null
                          ? Icons.add_alarm_rounded
                          : Icons.edit_rounded,
                    ),
              label: Text(plan == null ? '配置定时自动备份' : '修改定时计划'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    return _formatBackupDateTime(value);
  }
}

String _formatBackupDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _BackupRunIssueTile extends StatelessWidget {
  const _BackupRunIssueTile({required this.run});

  final BackupRunRecordEntity run;

  @override
  Widget build(BuildContext context) {
    final color = switch (run.status) {
      'missed' || 'skipped' || 'stopped' => const Color(0xFFB54708),
      _ => const Color(0xFFB42318),
    };
    final title = switch (run.status) {
      'missed' => '已错过本次定时备份',
      'skipped' => '本次定时备份已跳过',
      'stopped' => '本次定时备份已停止',
      'partial_failed' => '本次定时备份部分失败',
      'failed' => '本次定时备份失败',
      _ => '本次定时备份异常',
    };
    final timeText = _formatBackupDateTime(run.finishedAt ?? run.startedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5D0C8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$timeText · 备份 ${run.queuedCount} 个，跳过 ${run.skippedCount} 个，失败 ${run.failedCount} 个',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
          ),
        ],
      ),
    );
  }
}

class _PlanTag extends StatelessWidget {
  const _PlanTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xFF4A5568)),
      ),
    );
  }
}

class _ScheduledPlanDraft {
  const _ScheduledPlanDraft({
    required this.type,
    required this.time,
    required this.weekday,
    required this.dayOfMonth,
    required this.scheduledAt,
    required this.includeImages,
    required this.includeVideos,
    required this.requiresWifi,
    required this.requiresCharging,
  });

  final BackupScheduleType type;
  final TimeOfDay time;
  final int? weekday;
  final int? dayOfMonth;
  final DateTime? scheduledAt;
  final bool includeImages;
  final bool includeVideos;
  final bool requiresWifi;
  final bool requiresCharging;
}

class _ScheduledPlanDialog extends StatefulWidget {
  const _ScheduledPlanDialog({required this.plan});

  final BackupPlanEntity? plan;

  @override
  State<_ScheduledPlanDialog> createState() => _ScheduledPlanDialogState();
}

class _ScheduledPlanDialogState extends State<_ScheduledPlanDialog> {
  late BackupScheduleType _type;
  late TimeOfDay _time;
  late int _weekday;
  late int _dayOfMonth;
  late DateTime _scheduledDate;
  late bool _requiresCharging;

  @override
  void initState() {
    super.initState();
    final schedule = widget.plan?.schedule;
    final now = DateTime.now();
    _type = schedule?.type ?? BackupScheduleType.daily;
    _time = TimeOfDay(hour: schedule?.hour ?? 2, minute: schedule?.minute ?? 0);
    _weekday = schedule?.weekday ?? now.weekday;
    _dayOfMonth = schedule?.dayOfMonth ?? now.day;
    _scheduledDate =
        schedule?.onceAt ??
        DateTime(now.year, now.month, now.day + 1, _time.hour, _time.minute);
    _requiresCharging = schedule?.requiresCharging ?? false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledDate.isBefore(now) ? now : _scheduledDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    setState(() {
      _scheduledDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _time.hour,
        _time.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final result = await showModalBottomSheet<_WheelTimeResult>(
      context: context,
      builder: (context) => _WheelTimePicker(
        initialHour: _time.hour,
        initialMinute: _time.minute,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _time = TimeOfDay(hour: result.hour, minute: result.minute);
      if (_type == BackupScheduleType.once) {
        _scheduledDate = DateTime(
          _scheduledDate.year,
          _scheduledDate.month,
          _scheduledDate.day,
          result.hour,
          result.minute,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '将在设定的时间自动开始备份整个图库，仅能在 Wi‑Fi 条件下执行',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<BackupScheduleType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: '执行周期',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: BackupScheduleType.daily,
                  child: Text('每日'),
                ),
                DropdownMenuItem(
                  value: BackupScheduleType.weekly,
                  child: Text('每周'),
                ),
                DropdownMenuItem(
                  value: BackupScheduleType.monthly,
                  child: Text('每月'),
                ),
                DropdownMenuItem(
                  value: BackupScheduleType.once,
                  child: Text('仅一次'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _type = value;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_type == BackupScheduleType.weekly)
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(
                  labelText: '每周执行日',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: DateTime.monday, child: Text('周一')),
                  DropdownMenuItem(value: DateTime.tuesday, child: Text('周二')),
                  DropdownMenuItem(
                    value: DateTime.wednesday,
                    child: Text('周三'),
                  ),
                  DropdownMenuItem(value: DateTime.thursday, child: Text('周四')),
                  DropdownMenuItem(value: DateTime.friday, child: Text('周五')),
                  DropdownMenuItem(value: DateTime.saturday, child: Text('周六')),
                  DropdownMenuItem(value: DateTime.sunday, child: Text('周日')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _weekday = value;
                  });
                },
              ),
            if (_type == BackupScheduleType.weekly) const SizedBox(height: 16),
            if (_type == BackupScheduleType.monthly)
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth < 1
                    ? 1
                    : _dayOfMonth > 31
                    ? 31
                    : _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: '每月执行日',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  31,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1} 日'),
                  ),
                ),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _dayOfMonth = value;
                  });
                },
              ),
            if (_type == BackupScheduleType.monthly) const SizedBox(height: 16),
            if (_type == BackupScheduleType.monthly)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '若当月没有所选日期，则会在该月最后一天执行。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D6C6A),
                  ),
                ),
              ),
            if (_type == BackupScheduleType.once)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: const Text('执行日期'),
                subtitle: Text(
                  '${_scheduledDate.year}-${_scheduledDate.month.toString().padLeft(2, '0')}-${_scheduledDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: TextButton(
                  onPressed: _pickDate,
                  child: const Text('修改'),
                ),
              ),
            if (_type == BackupScheduleType.once) const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time_rounded),
              title: const Text('执行时间'),
              subtitle: Text(
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
              ),
              trailing: TextButton(
                onPressed: _pickTime,
                child: const Text('修改'),
              ),
            ),
            if (_type == BackupScheduleType.once)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '仅一次计划使用完整日期和时间；错过后会记录为异常，不会自动改到下一天。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D6C6A),
                  ),
                ),
              ),
            SwitchListTile(
              value: _requiresCharging,
              onChanged: (value) {
                setState(() {
                  _requiresCharging = value;
                });
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('仅在充电时执行'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  _ScheduledPlanDraft(
                    type: _type,
                    time: _time,
                    weekday: _type == BackupScheduleType.weekly
                        ? _weekday
                        : null,
                    dayOfMonth: _type == BackupScheduleType.monthly
                        ? _dayOfMonth
                        : null,
                    scheduledAt: _type == BackupScheduleType.once
                        ? DateTime(
                            _scheduledDate.year,
                            _scheduledDate.month,
                            _scheduledDate.day,
                            _time.hour,
                            _time.minute,
                          )
                        : null,
                    includeImages: true,
                    includeVideos: true,
                    requiresWifi: true,
                    requiresCharging: _requiresCharging,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D8A5A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('保存'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF374151),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
      actions: const <Widget>[],
    );
  }
}

class _WheelDateResult {
  final int month;
  final int day;
  const _WheelDateResult({required this.month, required this.day});
}

class _WheelDatePicker extends StatefulWidget {
  final int year;
  final int initialMonth;
  final int initialDay;
  const _WheelDatePicker({
    required this.year,
    required this.initialMonth,
    required this.initialDay,
  });

  @override
  State<_WheelDatePicker> createState() => _WheelDatePickerState();
}

class _WheelDatePickerState extends State<_WheelDatePicker> {
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;
  int _selectedMonth = 1;
  int _selectedDay = 1;

  int _daysInMonth(int month) {
    return DateTime(widget.year, month + 1, 0).day;
  }

  int _maxSelectableDay() {
    return _daysInMonth(_selectedMonth);
  }

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth;
    _selectedDay = widget.initialDay;
    _monthController = FixedExtentScrollController(
      initialItem: widget.initialMonth - 1,
    );
    _dayController = FixedExtentScrollController(
      initialItem: widget.initialDay - 1,
    );
  }

  @override
  void dispose() {
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const Text(
            '选择日期',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _monthController,
                    itemExtent: 44,
                    backgroundColor: Colors.white,
                    diameterRatio: 100,
                    onSelectedItemChanged: (index) {
                      final newMonth = index + 1;
                      if (newMonth != _selectedMonth) {
                        final maxDay = _daysInMonth(newMonth);
                        setState(() {
                          _selectedMonth = newMonth;
                          if (_selectedDay > maxDay) {
                            _selectedDay = maxDay;
                            _dayController.jumpToItem(maxDay - 1);
                          }
                        });
                      }
                    },
                    children: List.generate(12, (index) {
                      final month = index + 1;
                      final isMonthAvailable = month >= widget.initialMonth;
                      return Center(
                        child: Text(
                          month.toString(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: isMonthAvailable
                                ? const Color(0xFF111827)
                                : const Color(0xFFD1D5DB),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _dayController,
                    itemExtent: 44,
                    backgroundColor: Colors.white,
                    diameterRatio: 100,
                    onSelectedItemChanged: (index) {
                      final newDay = index + 1;
                      final maxDay = _maxSelectableDay();
                      if (newDay <= maxDay) {
                        setState(() {
                          _selectedDay = newDay;
                        });
                      }
                    },
                    children: List.generate(31, (index) {
                      final day = index + 1;
                      final maxDay = _maxSelectableDay();
                      final isDayAvailable =
                          day <= maxDay &&
                          !(_selectedMonth == widget.initialMonth &&
                              day < widget.initialDay);
                      return Center(
                        child: Text(
                          day.toString(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: isDayAvailable
                                ? const Color(0xFF111827)
                                : const Color(0xFFD1D5DB),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _WheelDateResult(
                          month: _selectedMonth,
                          day: _selectedDay,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D8A5A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF374151),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _WheelTimeResult {
  final int hour;
  final int minute;
  const _WheelTimeResult({required this.hour, required this.minute});
}

class _WheelTimePicker extends StatefulWidget {
  final int initialHour;
  final int initialMinute;
  const _WheelTimePicker({
    required this.initialHour,
    required this.initialMinute,
  });

  @override
  State<_WheelTimePicker> createState() => _WheelTimePickerState();
}

class _WheelTimePickerState extends State<_WheelTimePicker> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  int _selectedHour = 0;
  int _selectedMinute = 0;

  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialHour;
    _selectedMinute = widget.initialMinute;
    _hourController = FixedExtentScrollController(
      initialItem: widget.initialHour,
    );
    _minuteController = FixedExtentScrollController(
      initialItem: widget.initialMinute,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const Text(
            '选择时间',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 132,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _hourController,
                    itemExtent: 44,
                    backgroundColor: Colors.white,
                    diameterRatio: 100,
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedHour = index;
                      });
                    },
                    children: List.generate(24, (index) {
                      return Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111827),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _minuteController,
                    itemExtent: 44,
                    backgroundColor: Colors.white,
                    diameterRatio: 100,
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedMinute = index;
                      });
                    },
                    children: List.generate(60, (index) {
                      return Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111827),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _WheelTimeResult(
                          hour: _selectedHour,
                          minute: _selectedMinute,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D8A5A),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF374151),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GalleryMediaAccessState {
  const _GalleryMediaAccessState({required this.scope, required this.message});

  factory _GalleryMediaAccessState.fromMap(Map<String, Object?> map) {
    final scope = map['scope']?.toString().trim();
    final message = map['message']?.toString().trim();
    return _GalleryMediaAccessState(
      scope: (scope == null || scope.isEmpty) ? 'unknown' : scope,
      message: (message == null || message.isEmpty)
          ? '整机图库备份需要“允许全部”照片和视频权限，请到系统设置中调整后重试。'
          : message,
    );
  }

  final String scope;
  final String message;

  bool get isFullAccess => scope == 'full';
}

class _BatteryOptimizationHint extends StatefulWidget {
  const _BatteryOptimizationHint();

  @override
  State<_BatteryOptimizationHint> createState() =>
      _BatteryOptimizationHintState();
}

class _BatteryOptimizationHintState extends State<_BatteryOptimizationHint> {
  static const _channel = MethodChannel('com.nasclient/backup_scheduler');
  static bool _dismissedForProcess = false;

  Future<void> _openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('openBatteryOptimizationSettings');
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(error.message ?? '无法打开电池优化设置页面')),
        );
    }
  }

  Future<void> _openAutoStartSettings() async {
    try {
      await _channel.invokeMethod('openAutoStartSettings');
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(error.message ?? '无法打开自启动设置页面')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedForProcess) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(
          children: [
            TextSpan(
              text: '定时备份需要开启本软件的',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF9C9B99)),
            ),
            TextSpan(
              text: '自启动权限',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFD4A017),
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  unawaited(_openAutoStartSettings());
                },
            ),
            TextSpan(
              text: '，并关闭',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF9C9B99)),
            ),
            TextSpan(
              text: '电池优化选项',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFD4A017),
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  unawaited(_openBatteryOptimizationSettings());
                },
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _dismissedForProcess = true;
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 14, color: Color(0xFF9C9B99)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSummaryCard extends StatelessWidget {
  final int itemCount;
  final String totalSizeLabel;
  final int duplicateNameCount;
  final VoidCallback? onClear;

  const _SelectionSummaryCard({
    required this.itemCount,
    required this.totalSizeLabel,
    required this.duplicateNameCount,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E2DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '待备份资源',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (onClear != null)
                TextButton(onPressed: onClear, child: const Text('清空'))
              else
                Text(
                  '共 $itemCount 项',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D6C6A),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            itemCount == 0 ? '还没有选择任何资源' : '已选 $itemCount 项，合计 $totalSizeLabel',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (itemCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              duplicateNameCount > 0
                  ? '开始备份前会先刷新目标目录并检测重名；当前列表中已有 $duplicateNameCount 个本地重名文件，发现同名项后可统一处理或逐个选择。'
                  : '开始备份前会先刷新目标目录并检测重名；如发现同名项，可统一选择跳过、覆盖、同时保留，或改为逐个选择。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB64848),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionList extends StatelessWidget {
  final List<BackupSourceItem> items;
  final String Function(int bytes) formatSize;
  final bool Function(BackupSourceItem item) isVideo;
  final ValueChanged<BackupSourceItem>? onRemove;

  const _SelectionList({
    required this.items,
    required this.formatSize,
    required this.isVideo,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final previewItems = items.take(6).toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E2DC)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < previewItems.length; i++) ...[
            _SelectionTile(
              item: previewItems[i],
              isVideo: isVideo(previewItems[i]),
              sizeLabel: formatSize(previewItems[i].size),
              onRemove: onRemove == null
                  ? null
                  : () => onRemove!(previewItems[i]),
            ),
            if (i != previewItems.length - 1)
              const Divider(height: 1, color: Color(0xFFF0ECE6)),
          ],
          if (items.length > previewItems.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '还有 ${items.length - previewItems.length} 项未展开显示',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6D6C6A),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final BackupSourceItem item;
  final bool isVideo;
  final String sizeLabel;
  final VoidCallback? onRemove;

  const _SelectionTile({
    required this.item,
    required this.isVideo,
    required this.sizeLabel,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.sourceType) {
      BackupSourceType.media =>
        isVideo ? Icons.video_library_outlined : Icons.photo_outlined,
      BackupSourceType.file => Icons.insert_drive_file_outlined,
      BackupSourceType.directoryExpandedFile => Icons.folder_copy_outlined,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFF5F4F1),
        foregroundColor: const Color(0xFF5A4F45),
        child: Icon(icon, size: 20),
      ),
      title: Text(
        item.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.sourceLabel ?? item.sourceType.label} · $sizeLabel',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: '移除',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
    );
  }
}

class _BatchProgressCard extends StatelessWidget {
  final BackupState state;
  final String Function(int bytes) formatSize;
  final VoidCallback? onStop;

  const _BatchProgressCard({
    required this.state,
    required this.formatSize,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final progressPercent = (state.batchProgress * 100).clamp(0, 100).round();
    final title = state.isBatchRunning ? '当前备份批次' : '最近一次备份';
    final summary = [
      '已入队 ${state.queuedTaskCount} 项',
      if (state.completedTaskCount > 0) '完成 ${state.completedTaskCount}',
      if (state.skippedTaskCount > 0) '跳过 ${state.skippedTaskCount}',
      if (state.failedTaskCount > 0) '失败 ${state.failedTaskCount}',
      if (state.failedToQueueCount > 0) '未入队 ${state.failedToQueueCount}',
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4F1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (onStop != null && state.isBatchRunning)
                TextButton.icon(
                  onPressed: state.isStopping ? null : onStop,
                  icon: state.isStopping
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.stop_circle_outlined,
                          color: Color(0xFFC53030),
                        ),
                  label: Text(
                    state.isStopping ? '停止中' : '停止',
                    style: const TextStyle(color: Color(0xFFC53030)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(summary, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: state.batchProgress.clamp(0, 1).toDouble(),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${formatSize(state.transferredBytes)} / ${formatSize(state.totalBytes)} · $progressPercent%',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
          ),
          if (state.activeFileName != null &&
              state.activeFileName!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              state.isBatchRunning
                  ? '当前处理：${state.activeFileName}'
                  : '最后处理：${state.activeFileName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackupHistoryCard extends StatelessWidget {
  const _BackupHistoryCard({required this.runs, required this.formatDateTime});

  final List<BackupRunRecordEntity> runs;
  final String Function(DateTime value) formatDateTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E2DC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '备份记录',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '展示立即备份与定时备份的最近结果，包括成功、失败、跳过数量。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
          ),
          const SizedBox(height: 14),
          if (runs.isEmpty)
            Text(
              '还没有可展示的备份记录。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
            )
          else
            for (final run in runs) ...[
              _BackupHistoryTile(run: run, formatDateTime: formatDateTime),
              if (run != runs.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _BackupHistoryTile extends StatelessWidget {
  const _BackupHistoryTile({required this.run, required this.formatDateTime});

  final BackupRunRecordEntity run;
  final String Function(DateTime value) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final labelColor = switch (run.status) {
      'completed' => const Color(0xFF027A48),
      'running' || 'retrying' => const Color(0xFF175CD3),
      'missed' || 'skipped' => const Color(0xFFB54708),
      _ => const Color(0xFFB42318),
    };
    final statusLabel = switch (run.status) {
      'completed' => '成功',
      'partial_failed' => '部分失败',
      'failed' => '失败',
      'running' => '进行中',
      'retrying' => '重试中',
      'missed' => '已错过',
      'skipped' => '已跳过',
      _ => run.status,
    };
    final triggerLabel = run.triggerType == 'scheduled' ? '定时备份' : '立即备份';
    final occurredAt = formatDateTime(run.finishedAt ?? run.startedAt);
    final summary = [
      '备份 ${run.queuedCount} 个文件',
      '跳过 ${run.skippedCount} 个',
      '失败 ${run.failedCount} 个',
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$triggerLabel · $occurredAt',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: labelColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(summary, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String message;

  const _WarningCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB64848)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8C3A3A),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
