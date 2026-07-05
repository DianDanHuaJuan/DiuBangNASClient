/// 文件输入：远程数据源
/// 文件职责：实现仪表盘仓库
/// 文件对外接口：DashboardRepositoryImpl
/// 文件包含：DashboardRepositoryImpl
import '../../../../core/error/app_exception.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/error/app_failure.dart';
import '../../domain/entities/dashboard_summary_entity.dart';
import '../../domain/entities/device_info_entity.dart';
import '../../domain/entities/storage_info_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_data_source.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource _remoteDataSource;

  DashboardRepositoryImpl({required DashboardRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  @override
  Future<AppResult<DashboardSummaryEntity>> getDashboardSummary() async {
    try {
      final dto = await _remoteDataSource.getDashboardSummary();
      return Success(
        DashboardSummaryEntity(
          deviceInfo: DeviceInfoEntity(
            deviceName: dto.device.deviceId,
            model: dto.device.model,
            brand: dto.device.brand,
            status: dto.serverStatus,
            uptime: dto.uptime,
            batteryLevel: dto.device.batteryLevel,
            batteryPercent: dto.device.batteryPercent,
            isCharging: dto.device.isCharging,
          ),
          storageInfo: StorageInfoEntity(
            totalBytes: dto.storage.totalBytes,
            usedBytes: dto.storage.usedBytes,
            availableBytes: dto.storage.freeBytes,
          ),
          localIp: dto.localIp,
        ),
      );
    } on AppException catch (e) {
      return Failure(AppFailure(code: e.code, message: e.message));
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'DASHBOARD_ERROR',
          message: 'Failed to load dashboard: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<DeviceInfoEntity>> getDeviceInfo() async {
    try {
      final dto = await _remoteDataSource.getDeviceInfo();
      return Success(
        DeviceInfoEntity(
          deviceName: dto.deviceId,
          model: dto.model,
          brand: dto.brand,
          status: '',
          uptime: 0,
          batteryLevel: dto.batteryLevel,
          batteryPercent: dto.batteryPercent,
          isCharging: dto.isCharging,
        ),
      );
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'DEVICE_INFO_ERROR',
          message: 'Failed to load device info: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<StorageInfoEntity>> getStorageInfo() async {
    try {
      final dto = await _remoteDataSource.getStorageInfo();
      return Success(
        StorageInfoEntity(
          totalBytes: dto.totalBytes,
          usedBytes: dto.usedBytes,
          availableBytes: dto.freeBytes,
        ),
      );
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'STORAGE_INFO_ERROR',
          message: 'Failed to load storage info: ${e.toString()}',
        ),
      );
    }
  }
}
