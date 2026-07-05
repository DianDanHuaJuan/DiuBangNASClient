/// 文件输入：任务 ID
/// 文件职责：恢复传输任务
/// 文件对外接口：ResumeTransferUseCase
/// 文件包含：ResumeTransferUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/repositories/transfer_repository.dart';

class ResumeTransferUseCase implements UseCase<AppResult<void>, String> {
  final TransferRepository _repository;

  ResumeTransferUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(String taskId) async {
    return await _repository.resumeTask(taskId);
  }
}
