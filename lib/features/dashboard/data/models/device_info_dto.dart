/// 文件输入：设备信息 JSON
/// 文件职责：解析设备信息 DTO
/// 文件对外接口：DeviceInfoDto
/// 文件包含：DeviceInfoDto
class DeviceInfoDto {
  final String deviceId;
  final String model;
  final String brand;
  final String systemVersion;
  final int batteryLevel;
  final double batteryPercent;
  final bool isCharging;

  const DeviceInfoDto({
    required this.deviceId,
    required this.model,
    required this.brand,
    required this.systemVersion,
    required this.batteryLevel,
    required this.batteryPercent,
    required this.isCharging,
  });

  factory DeviceInfoDto.fromJson(Map<String, dynamic> json) {
    return DeviceInfoDto(
      deviceId: json['deviceId'] as String? ?? '',
      model: json['model'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      systemVersion: json['systemVersion'] as String? ?? '',
      batteryLevel: json['batteryLevel'] as int? ?? 1,
      batteryPercent: (json['batteryPercent'] as num?)?.toDouble() ?? 0.0,
      isCharging: json['isCharging'] as bool? ?? false,
    );
  }
}
