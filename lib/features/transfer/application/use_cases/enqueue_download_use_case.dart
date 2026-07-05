/// 文件输入：下载参数
/// 文件职责：创建下载任务
/// 文件对外接口：EnqueueDownloadUseCase
/// 文件包含：EnqueueDownloadUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../params/enqueue_download_params.dart';

class EnqueueDownloadUseCase
    implements UseCase<AppResult<TransferTaskEntity>, EnqueueDownloadParams> {
  final TransferRepository _repository;

  EnqueueDownloadUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<TransferTaskEntity>> call(
    EnqueueDownloadParams params,
  ) async {
    return await _repository.enqueueDownload(
      remotePath: params.remotePath,
      localPath: params.localPath,
      rootId: params.rootId,
    );
  }
}
