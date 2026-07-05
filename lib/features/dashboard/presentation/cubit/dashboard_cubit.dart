/// 文件输入：仪表盘上下文、UseCase
/// 文件职责：管理仪表盘数据加载逻辑
/// 文件对外接口：DashboardCubit
/// 文件包含：DashboardCubit
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/node/unified_node_store.dart';
import '../../../../core/realtime/realtime_connection_state.dart';
import '../../../../core/session/server_availability_controller.dart';
import '../../../../core/use_case/no_params.dart';
import '../../application/use_cases/load_dashboard_use_case.dart';
import '../../data/models/dashboard_summary_dto.dart';
import '../../domain/entities/dashboard_summary_entity.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  static const _transientRetryLimit = 2;
  static const _transientRetryDelay = Duration(milliseconds: 500);

  final LoadDashboardUseCase _loadDashboardUseCase;
  final UnifiedNodeStore _unifiedNodeStore;
  RealtimeConnectionStatus _realtimeConnectionStatus =
      RealtimeConnectionStatus.idle;
  ServerAvailabilityStatus _serverAvailabilityStatus =
      ServerAvailabilityStatus.offline;

  DashboardCubit({
    required LoadDashboardUseCase loadDashboardUseCase,
    required UnifiedNodeStore unifiedNodeStore,
  }) : _unifiedNodeStore = unifiedNodeStore,
       _loadDashboardUseCase = loadDashboardUseCase,
       super(const DashboardInitial());

  bool get hasLoadedDashboard => state is DashboardLoaded;

  Future<void> loadDashboard({bool force = false}) async {
    if (!force && hasLoadedDashboard) {
      return;
    }

    final previousLoadedState = state is DashboardLoaded
        ? state as DashboardLoaded
        : null;
    if (previousLoadedState == null) {
      emit(const DashboardLoading());
    }

    AppFailure? lastFailure;
    for (var attempt = 0; attempt <= _transientRetryLimit; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_transientRetryDelay);
      }

      final result = await _loadDashboardUseCase.call(const NoParams());
      final failure = result.failureOrNull;
      if (failure == null) {
        _applyDashboardEntity(result.dataOrNull!);
        emit(_buildStateFromCurrentServer());
        return;
      }

      lastFailure = failure;
      if (!_isTransientFailure(failure) || attempt == _transientRetryLimit) {
        break;
      }
    }

    if (previousLoadedState != null) {
      emit(
        previousLoadedState.copyWith(
          serverAvailabilityStatus: _serverAvailabilityStatus,
        ),
      );
      return;
    }

    if (_shouldDeferInitialError()) {
      return;
    }

    emit(DashboardError(lastFailure?.message ?? 'Failed to load dashboard'));
  }

  void applyRealtimeDashboardPayload(Map<String, dynamic> payload) {
    final dto = DashboardSummaryDto.fromJson(payload);
    _applyDashboardDto(dto);
    emit(_buildStateFromCurrentServer());
  }

  void applyRealtimeConnectionStatus(RealtimeConnectionStatus status) {
    _realtimeConnectionStatus = status;
    final currentState = state;
    if (currentState is! DashboardLoaded ||
        currentState.realtimeConnectionStatus == status) {
      return;
    }

    emit(currentState.copyWith(realtimeConnectionStatus: status));
  }

  void applyServerAvailabilityStatus(ServerAvailabilityStatus status) {
    _serverAvailabilityStatus = status;
    final currentState = state;
    if (currentState is! DashboardLoaded ||
        currentState.serverAvailabilityStatus == status) {
      return;
    }

    emit(currentState.copyWith(serverAvailabilityStatus: status));
  }

  bool _shouldDeferInitialError() {
    return _realtimeConnectionStatus == RealtimeConnectionStatus.connecting ||
        _realtimeConnectionStatus == RealtimeConnectionStatus.reconnecting;
  }

  bool _isTransientFailure(AppFailure failure) {
    const transientCodes = {'TIMEOUT', 'CONNECTION_ERROR', 'DASHBOARD_ERROR'};
    if (transientCodes.contains(failure.code)) {
      return true;
    }

    final message = failure.message.toLowerCase();
    return message.contains('timeout') || message.contains('cannot connect');
  }

  void _applyDashboardEntity(DashboardSummaryEntity data) {
    _unifiedNodeStore.applyCurrentServerRuntime(
      serverLanIp: data.localIp,
      serverStatus: data.deviceInfo.status,
      brand: data.deviceInfo.brand,
      model: data.deviceInfo.model,
      storageTotal: data.storageInfo.totalBytes,
      storageUsed: data.storageInfo.usedBytes,
      storageAvailable: data.storageInfo.availableBytes,
      batteryLevel: data.deviceInfo.batteryLevel,
      batteryPercent: data.deviceInfo.batteryPercent,
      isCharging: data.deviceInfo.isCharging,
    );
  }

  void _applyDashboardDto(DashboardSummaryDto dto) {
    _unifiedNodeStore.applyCurrentServerRuntime(
      serverLanIp: dto.localIp,
      serverStatus: dto.serverStatus,
      brand: dto.device.brand,
      model: dto.device.model,
      storageTotal: dto.storage.totalBytes,
      storageUsed: dto.storage.usedBytes,
      storageAvailable: dto.storage.freeBytes,
      batteryLevel: dto.device.batteryLevel,
      batteryPercent: dto.device.batteryPercent,
      isCharging: dto.device.isCharging,
    );
  }

  DashboardLoaded _buildStateFromCurrentServer() {
    final serverNode = _unifiedNodeStore.currentServer;
    final runtime = serverNode?.runtime;
    final identity = serverNode?.identity;
    final network = serverNode?.network;
    return DashboardLoaded(
      serverName: identity?.displayName ?? '当前服务器',
      serverStatus: runtime?.status ?? 'unknown',
      deviceName: identity?.displayName ?? '当前服务器',
      deviceModel: identity?.model ?? '',
      deviceBrand: identity?.brand ?? '',
      storageTotal: runtime?.storageTotal ?? 0,
      storageUsed: runtime?.storageUsed ?? 0,
      storageAvailable: runtime?.storageAvailable ?? 0,
      batteryLevel: runtime?.batteryLevel ?? 1,
      batteryPercent: runtime?.batteryPercent ?? 0,
      isCharging: runtime?.isCharging ?? false,
      localIp: network?.serverLanIp ?? '',
      realtimeConnectionStatus: _realtimeConnectionStatus,
      serverAvailabilityStatus: _serverAvailabilityStatus,
    );
  }
}
