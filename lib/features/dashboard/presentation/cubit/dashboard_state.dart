import '../../../../core/realtime/realtime_connection_state.dart';
import '../../../../core/session/server_availability_controller.dart';

/// 文件输入：仪表盘状态类型、实体数据、错误消息
/// 文件职责：表达仪表盘页状态
/// 文件对外接口：DashboardState
/// 文件包含：DashboardState
abstract class DashboardState {
  const DashboardState();
}

class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  final String serverName;
  final String serverStatus;
  final String deviceName;
  final String deviceModel;
  final String deviceBrand;
  final int storageTotal;
  final int storageUsed;
  final int storageAvailable;
  final int batteryLevel;
  final double batteryPercent;
  final bool isCharging;
  final String localIp;
  final RealtimeConnectionStatus realtimeConnectionStatus;
  final ServerAvailabilityStatus serverAvailabilityStatus;

  const DashboardLoaded({
    required this.serverName,
    required this.serverStatus,
    required this.deviceName,
    required this.deviceModel,
    required this.deviceBrand,
    required this.storageTotal,
    required this.storageUsed,
    required this.storageAvailable,
    required this.batteryLevel,
    required this.batteryPercent,
    required this.isCharging,
    required this.localIp,
    this.realtimeConnectionStatus = RealtimeConnectionStatus.idle,
    this.serverAvailabilityStatus = ServerAvailabilityStatus.offline,
  });

  double get storageUsagePercent =>
      storageTotal > 0 ? storageUsed / storageTotal : 0;

  String get batteryStatusText {
    if (isCharging) return '充电中';
    switch (batteryLevel) {
      case 1:
        return '未知';
      case 2:
        return '充电中';
      case 3:
        return '使用中';
      case 4:
        return '未充电';
      case 5:
        return '已充满';
      default:
        return '未知';
    }
  }

  bool get canManualReconnect => realtimeConnectionStatus.allowsManualReconnect;

  bool get isConnecting =>
      realtimeConnectionStatus == RealtimeConnectionStatus.connecting ||
      realtimeConnectionStatus == RealtimeConnectionStatus.reconnecting;

  DashboardLoaded copyWith({
    String? serverName,
    String? serverStatus,
    String? deviceName,
    String? deviceModel,
    String? deviceBrand,
    int? storageTotal,
    int? storageUsed,
    int? storageAvailable,
    int? batteryLevel,
    double? batteryPercent,
    bool? isCharging,
    String? localIp,
    RealtimeConnectionStatus? realtimeConnectionStatus,
    ServerAvailabilityStatus? serverAvailabilityStatus,
  }) {
    return DashboardLoaded(
      serverName: serverName ?? this.serverName,
      serverStatus: serverStatus ?? this.serverStatus,
      deviceName: deviceName ?? this.deviceName,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceBrand: deviceBrand ?? this.deviceBrand,
      storageTotal: storageTotal ?? this.storageTotal,
      storageUsed: storageUsed ?? this.storageUsed,
      storageAvailable: storageAvailable ?? this.storageAvailable,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      localIp: localIp ?? this.localIp,
      realtimeConnectionStatus:
          realtimeConnectionStatus ?? this.realtimeConnectionStatus,
      serverAvailabilityStatus:
          serverAvailabilityStatus ?? this.serverAvailabilityStatus,
    );
  }
}

class DashboardError extends DashboardState {
  final String message;

  const DashboardError(this.message);
}
