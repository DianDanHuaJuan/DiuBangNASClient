/// 文件输入：上传冲突处理参数
/// 文件职责：将用户选择的冲突处理动作交给传输仓库执行
/// 文件对外接口：ResolveUploadConflictUseCase
/// 文件包含：ResolveUploadConflictUseCase
import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/use_case.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../params/resolve_upload_conflict_params.dart';

class ResolveUploadConflictUseCase
    implements UseCase<AppResult<void>, ResolveUploadConflictParams> {
  final TransferRepository _repository;

  ResolveUploadConflictUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(ResolveUploadConflictParams params) async {
    return _repository.resolveUploadConflict(
      taskId: params.taskId,
      resolution: params.resolution,
    );
  }
}
