/// 文件输入：任务 ID、冲突处理动作
/// 文件职责：封装上传冲突处理参数
/// 文件对外接口：ResolveUploadConflictParams
/// 文件包含：ResolveUploadConflictParams
import '../../domain/entities/upload_conflict_resolution.dart';

class ResolveUploadConflictParams {
  final String taskId;
  final UploadConflictResolution resolution;

  const ResolveUploadConflictParams({
    required this.taskId,
    required this.resolution,
  });
}
