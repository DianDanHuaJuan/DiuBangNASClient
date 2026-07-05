/// 文件输入：传输任务列表、状态类型、错误消息
/// 文件职责：表达传输页面的各种状态
/// 文件对外接口：TransferState
/// 文件包含：TransferState
import '../../domain/entities/transfer_task_entity.dart';

abstract class TransferState {
  const TransferState();
}

class TransferInitial extends TransferState {
  const TransferInitial();
}

class TransferLoading extends TransferState {
  const TransferLoading();
}

class TransferLoaded extends TransferState {
  final List<TransferTaskEntity> tasks;
  final int activeCount;
  final int completedCount;

  const TransferLoaded({
    required this.tasks,
    required this.activeCount,
    required this.completedCount,
  });
}

class TransferError extends TransferState {
  final String message;

  const TransferError(this.message);
}
