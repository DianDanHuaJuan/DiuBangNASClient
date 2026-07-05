/// 文件输入：无参数
/// 文件职责：加载传输任务列表
/// 文件对外接口：LoadTransferTasksUseCase
/// 文件包含：LoadTransferTasksUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/repositories/transfer_repository.dart';

class LoadTransferTasksUseCase
    implements UseCase<AppResult<List<TransferTaskEntity>>, NoParams> {
  final TransferRepository _repository;

  LoadTransferTasksUseCase({required TransferRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<List<TransferTaskEntity>>> call(NoParams params) async {
    return await _repository.loadTasks();
  }
}
