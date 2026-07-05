/// 文件输入：无参数
/// 文件职责：定义仪表盘仓库抽象接口
/// 文件对外接口：DashboardRepository
/// 文件包含：DashboardRepository
import '../../../../core/result/app_result.dart';
import '../entities/dashboard_summary_entity.dart';
import '../entities/device_info_entity.dart';
import '../entities/storage_info_entity.dart';

abstract class DashboardRepository {
  Future<AppResult<DashboardSummaryEntity>> getDashboardSummary();
  Future<AppResult<DeviceInfoEntity>> getDeviceInfo();
  Future<AppResult<StorageInfoEntity>> getStorageInfo();
}
