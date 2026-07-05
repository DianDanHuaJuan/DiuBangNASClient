/// 文件输入：待备份资源、上传冲突策略
/// 文件职责：描述一次立即备份中单个资源的实际上传请求
/// 文件对外接口：BackupUploadRequest
/// 文件包含：BackupUploadRequest
import '../../../../core/protocol/upload_contract.dart';
import 'backup_source_item.dart';

class BackupUploadRequest {
  final BackupSourceItem item;
  final UploadConflictPolicy conflictPolicy;
  final bool requiresConflictResolution;

  const BackupUploadRequest({
    required this.item,
    this.conflictPolicy = UploadConflictPolicy.autoRename,
    this.requiresConflictResolution = false,
  });

  factory BackupUploadRequest.fromSource(
    BackupSourceItem item, {
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.autoRename,
    bool requiresConflictResolution = false,
  }) {
    return BackupUploadRequest(
      item: item,
      conflictPolicy: conflictPolicy,
      requiresConflictResolution: requiresConflictResolution,
    );
  }
}
