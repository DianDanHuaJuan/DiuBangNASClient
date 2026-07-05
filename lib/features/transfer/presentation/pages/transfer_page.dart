/// 文件输入：传输任务列表、任务操作回调
/// 文件职责：显示传输任务列表页面
/// 文件对外接口：TransferPage
/// 文件包含：TransferPage
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/service_locator.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_status.dart';
import '../cubit/transfer_cubit.dart';
import '../cubit/transfer_state.dart';

class TransferPage extends StatelessWidget {
  const TransferPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: serviceLocator.transferCubit..loadTasks(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('传输管理'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () {
                context.read<TransferCubit>().clearCompleted();
              },
              tooltip: '清除已完成',
            ),
          ],
        ),
        body: BlocBuilder<TransferCubit, TransferState>(
          builder: (context, state) {
            if (state is TransferLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is TransferError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('加载失败: ${state.message}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          context.read<TransferCubit>().loadTasks(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }

            if (state is TransferLoaded) {
              if (state.tasks.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('暂无传输任务', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  _TransferSummary(
                    activeCount: state.activeCount,
                    completedCount: state.completedCount,
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.tasks.length,
                      itemBuilder: (context, index) {
                        final task = state.tasks[index];
                        return _TransferTaskItem(task: task);
                      },
                    ),
                  ),
                ],
              );
            }

            return const Center(child: Text('请稍候...'));
          },
        ),
      ),
    );
  }
}

class _TransferSummary extends StatelessWidget {
  final int activeCount;
  final int completedCount;

  const _TransferSummary({
    required this.activeCount,
    required this.completedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryItem(
            icon: Icons.sync,
            label: '进行中',
            count: activeCount,
            color: Theme.of(context).colorScheme.primary,
          ),
          _SummaryItem(
            icon: Icons.check_circle_outline,
            label: '已完成',
            count: completedCount,
            color: Colors.green,
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          '$label: $count',
          style: TextStyle(color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _TransferTaskItem extends StatelessWidget {
  final TransferTaskEntity task;

  const _TransferTaskItem({required this.task});

  @override
  Widget build(BuildContext context) {
    final isUpload = task.direction == TransferDirection.upload;
    final isActive = task.status == TransferStatus.transferring;
    final isAwaitingConflict =
        task.status == TransferStatus.awaitingConflictResolution;
    final isCompleted = task.status == TransferStatus.completed;
    final isFailed = task.status == TransferStatus.failed;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUpload ? Icons.upload_rounded : Icons.download_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: task.status),
              ],
            ),
            const SizedBox(height: 12),
            if (isActive) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${task.formattedTransferred} / ${task.formattedSize}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${(task.progress * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (isFailed) ...[
              Text(
                task.errorMessage ?? '传输失败',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (isCompleted && task.localPath.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '保存位置: ${task.localPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (isAwaitingConflict) ...[
              Text(
                '检测到重名文件，等待你选择跳过、覆盖或同时保留。',
                style: TextStyle(color: Colors.orange[800], fontSize: 12),
              ),
            ],
            if (!isCompleted) const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final TransferStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case TransferStatus.pending:
        color = Colors.grey;
        label = '等待中';
      case TransferStatus.transferring:
        color = Colors.blue;
        label = '传输中';
      case TransferStatus.awaitingConflictResolution:
        color = Colors.orange;
        label = '等待处理';
      case TransferStatus.paused:
        color = Colors.orange;
        label = '已暂停';
      case TransferStatus.completed:
        color = Colors.green;
        label = '已完成';
      case TransferStatus.skipped:
        color = Colors.grey;
        label = '已跳过';
      case TransferStatus.failed:
        color = Colors.red;
        label = '失败';
      case TransferStatus.cancelled:
        color = Colors.grey;
        label = '已取消';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
