/// 文件输入：TransferRepository
/// 文件职责：暴露传输任务实时流，供上层统一订阅任务变化
/// 文件对外接口：ObserveTransferTasksUseCase
/// 文件包含：ObserveTransferTasksUseCase
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/repositories/transfer_repository.dart';

/// 输入：TransferRepository。
/// 职责：为 presentation 层提供统一的传输任务事件订阅入口。
/// 对外接口：`call() -> Stream<TransferTaskEntity>`。
class ObserveTransferTasksUseCase {
  final TransferRepository _repository;

  ObserveTransferTasksUseCase({required TransferRepository repository})
    : _repository = repository;

  Stream<TransferTaskEntity> call() {
    return _repository.taskStream;
  }
}
