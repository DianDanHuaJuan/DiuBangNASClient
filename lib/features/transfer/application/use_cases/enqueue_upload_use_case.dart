/// 文件输入：上传参数
/// 文件职责：创建上传任务
/// 文件对外接口：EnqueueUploadUseCase
/// 文件包含：EnqueueUploadUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../params/enqueue_upload_params.dart';

class EnqueueUploadUseCase
    implements UseCase<AppResult<TransferTaskEntity>, EnqueueUploadParams> {
  final TransferRepository _repository;

  EnqueueUploadUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<TransferTaskEntity>> call(EnqueueUploadParams params) async {
    return await _repository.enqueueUpload(
      localPath: params.localPath,
      remotePath: params.remotePath,
      rootId: params.rootId,
      conflictPolicy: params.conflictPolicy,
      requiresConflictResolution: params.requiresConflictResolution,
      uploadHeaders: params.uploadHeaders,
    );
  }
}
