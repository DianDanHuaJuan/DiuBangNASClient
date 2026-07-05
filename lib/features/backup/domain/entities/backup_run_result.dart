/// 文件输入：目标根目录、成功入队任务、失败资源与失败消息
/// 文件职责：表达一次立即备份编排结果，供页面展示批量入队反馈
/// 文件对外接口：BackupRunResult
/// 文件包含：BackupRunResult
import 'backup_source_item.dart';

class BackupRunResult {
  final String runId;
  final String rootId;
  final String rootName;
  final int scannedCount;
  final int skippedCount;
  final List<String> queuedTaskIds;
  final List<BackupSourceItem> failedItems;
  final List<String> failureMessages;

  const BackupRunResult({
    required this.runId,
    required this.rootId,
    required this.rootName,
    required this.scannedCount,
    required this.skippedCount,
    required this.queuedTaskIds,
    required this.failedItems,
    required this.failureMessages,
  });

  int get queuedCount => queuedTaskIds.length;

  int get failedCount => failedItems.length;

  bool get hasQueuedTasks => queuedTaskIds.isNotEmpty;
}
