/// 文件输入：聚合后的仪表盘 JSON
/// 文件职责：解析仪表盘聚合 DTO
/// 文件对外接口：DashboardSummaryDto
/// 文件包含：DashboardSummaryDto
import 'device_info_dto.dart';
import 'storage_info_dto.dart';

class DashboardSummaryDto {
  final DeviceInfoDto device;
  final StorageInfoDto storage;
  final int uptime;
  final String serverStatus;
  final String localIp;
  final int port;

  const DashboardSummaryDto({
    required this.device,
    required this.storage,
    required this.uptime,
    required this.serverStatus,
    required this.localIp,
    required this.port,
  });

  factory DashboardSummaryDto.fromJson(Map<String, dynamic> json) {
    final deviceJson = json['device'] as Map<String, dynamic>? ?? {};
    final systemJson = json['system'] as Map<String, dynamic>? ?? {};
    final storageJson = systemJson['storage'] as Map<String, dynamic>? ?? {};
    final networkJson = json['network'] as Map<String, dynamic>? ?? {};
    final serverJson = json['server'] as Map<String, dynamic>? ?? {};

    return DashboardSummaryDto(
      device: DeviceInfoDto.fromJson(deviceJson),
      storage: StorageInfoDto.fromJson(storageJson),
      uptime: systemJson['uptime'] as int? ?? 0,
      serverStatus: serverJson['status'] as String? ?? 'unknown',
      localIp: networkJson['localIp'] as String? ?? '',
      port: networkJson['port'] as int? ?? 8080,
    );
  }
}
