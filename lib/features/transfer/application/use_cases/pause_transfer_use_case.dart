/// 文件输入：任务 ID
/// 文件职责：暂停传输任务
/// 文件对外接口：PauseTransferUseCase
/// 文件包含：PauseTransferUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/repositories/transfer_repository.dart';

class PauseTransferUseCase implements UseCase<AppResult<void>, String> {
  final TransferRepository _repository;

  PauseTransferUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(String taskId) async {
    return await _repository.pauseTask(taskId);
  }
}
