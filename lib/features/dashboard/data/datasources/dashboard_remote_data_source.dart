/// 文件输入：API 客户端、/api/v1/dashboard 接口
/// 文件职责：获取仪表盘数据
/// 文件对外接口：DashboardRemoteDataSource
/// 文件包含：DashboardRemoteDataSource
import '../../../../core/network/nas_api_client.dart';
import '../models/dashboard_summary_dto.dart';
import '../models/device_info_dto.dart';
import '../models/storage_info_dto.dart';

class DashboardRemoteDataSource {
  final NasApiClient _apiClient;

  DashboardRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient;

  Future<DashboardSummaryDto> getDashboardSummary() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/dashboard',
      parser: (json) => json as Map<String, dynamic>,
    );
    return DashboardSummaryDto.fromJson(response);
  }

  Future<DeviceInfoDto> getDeviceInfo() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/dashboard/device',
      parser: (json) => json as Map<String, dynamic>,
    );
    return DeviceInfoDto.fromJson(response);
  }

  Future<StorageInfoDto> getStorageInfo() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/dashboard/storage',
      parser: (json) => json as Map<String, dynamic>,
    );
    return StorageInfoDto.fromJson(response);
  }
}
