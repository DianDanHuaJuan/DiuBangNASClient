/// 文件输入：设备信息、存储信息、网络信息
/// 文件职责：表达仪表盘聚合实体
/// 文件对外接口：DashboardSummaryEntity
/// 文件包含：DashboardSummaryEntity
import 'device_info_entity.dart';
import 'storage_info_entity.dart';

class DashboardSummaryEntity {
  final DeviceInfoEntity deviceInfo;
  final StorageInfoEntity storageInfo;
  final String localIp;

  const DashboardSummaryEntity({
    required this.deviceInfo,
    required this.storageInfo,
    required this.localIp,
  });
}
