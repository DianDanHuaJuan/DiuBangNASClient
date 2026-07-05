import '../../../../core/protocol/upload_contract.dart';

/// 文件输入：本地路径、远程路径、根目录 ID
/// 文件职责：封装上传任务参数
/// 文件对外接口：EnqueueUploadParams
/// 文件包含：EnqueueUploadParams
class EnqueueUploadParams {
  final String localPath;
  final String remotePath;
  final String? rootId;
  final UploadConflictPolicy conflictPolicy;
  final bool requiresConflictResolution;
  final Map<String, String>? uploadHeaders;

  const EnqueueUploadParams({
    required this.localPath,
    required this.remotePath,
    this.rootId,
    this.conflictPolicy = UploadConflictPolicy.fail,
    this.requiresConflictResolution = false,
    this.uploadHeaders,
  });
}
