/// 文件输入：设备名称、型号、品牌、状态、运行时间、电量信息
/// 文件职责：表达设备信息实体
/// 文件对外接口：DeviceInfoEntity
/// 文件包含：DeviceInfoEntity
class DeviceInfoEntity {
  final String deviceName;
  final String model;
  final String brand;
  final String status;
  final int uptime;
  final int batteryLevel;
  final double batteryPercent;
  final bool isCharging;

  const DeviceInfoEntity({
    required this.deviceName,
    required this.model,
    required this.brand,
    required this.status,
    required this.uptime,
    required this.batteryLevel,
    required this.batteryPercent,
    required this.isCharging,
  });

  String get formattedUptime {
    final days = uptime ~/ 86400;
    final hours = (uptime % 86400) ~/ 3600;
    final minutes = (uptime % 3600) ~/ 60;
    return '${days}d ${hours}h ${minutes}m';
  }

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
}
