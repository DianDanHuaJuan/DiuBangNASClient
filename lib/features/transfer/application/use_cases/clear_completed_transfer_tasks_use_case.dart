/// 文件输入：TransferRepository
/// 文件职责：清理已完成传输任务的持久化记录
/// 文件对外接口：ClearCompletedTransferTasksUseCase
/// 文件包含：ClearCompletedTransferTasksUseCase
import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/use_case/use_case.dart';
import '../../domain/repositories/transfer_repository.dart';

class ClearCompletedTransferTasksUseCase
    implements UseCase<AppResult<void>, NoParams> {
  final TransferRepository _repository;

  ClearCompletedTransferTasksUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(NoParams params) async {
    return await _repository.clearCompletedTasks();
  }
}
