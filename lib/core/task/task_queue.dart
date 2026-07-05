/// 文件输入：待执行任务、并发限制、任务状态变更回调
/// 文件职责：统一管理上传、下载、备份、互传等任务排队与执行
/// 文件对外接口：TaskQueue
/// 文件包含：TaskQueue, TransferTask
import 'dart:async';

enum TransferTaskStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

class TransferTask {
  final String id;
  final String direction;
  final String sourcePath;
  final String targetPath;
  final String fileName;
  final int fileSize;
  final DateTime createdAt;
  TransferTaskStatus status;
  double progress;
  String? errorMessage;

  TransferTask({
    required this.id,
    required this.direction,
    required this.sourcePath,
    required this.targetPath,
    required this.fileName,
    required this.fileSize,
    required this.createdAt,
    this.status = TransferTaskStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
  });
}

class TaskQueue {
  final int maxConcurrent;
  final void Function(TransferTask task)? onTaskStart;
  final void Function(TransferTask task)? onTaskComplete;
  final void Function(TransferTask task, double progress)? onProgress;
  final void Function(TransferTask task, String error)? onError;

  final List<TransferTask> _queue = [];
  final List<TransferTask> _running = [];
  int _runningCount = 0;

  TaskQueue({
    this.maxConcurrent = 3,
    this.onTaskStart,
    this.onTaskComplete,
    this.onProgress,
    this.onError,
  });

  List<TransferTask> get queue => List.unmodifiable(_queue);
  List<TransferTask> get running => List.unmodifiable(_running);

  Future<void> enqueue(TransferTask task) async {
    _queue.add(task);
    _processQueue();
  }

  void _processQueue() {
    while (_runningCount < maxConcurrent && _queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _running.add(task);
      _runningCount++;
      _executeTask(task);
    }
  }

  Future<void> _executeTask(TransferTask task) async {
    task.status = TransferTaskStatus.running;
    onTaskStart?.call(task);

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      task.progress = 1.0;
      task.status = TransferTaskStatus.completed;
      onTaskComplete?.call(task);
    } catch (e) {
      task.status = TransferTaskStatus.failed;
      task.errorMessage = e.toString();
      onError?.call(task, e.toString());
    } finally {
      _running.remove(task);
      _runningCount--;
      _processQueue();
    }
  }

  Future<void> pause(String taskId) async {
    final task = [..._queue, ..._running].firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw Exception('Task not found'),
    );
    if (task.status == TransferTaskStatus.running) {
      task.status = TransferTaskStatus.paused;
    }
  }

  Future<void> resume(String taskId) async {
    final task = _running.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw Exception('Task not found'),
    );
    if (task.status == TransferTaskStatus.paused) {
      task.status = TransferTaskStatus.pending;
      _executeTask(task);
    }
  }

  Future<void> cancel(String taskId) async {
    TransferTask? task;
    task = _queue.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw Exception('Task not found'),
    );
    _queue.remove(task);
    task.status = TransferTaskStatus.cancelled;
  }

  Future<void> clearCompleted() async {
    _queue.removeWhere((t) => t.status == TransferTaskStatus.completed);
    _running.removeWhere((t) => t.status == TransferTaskStatus.completed);
  }
}
