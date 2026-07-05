/// 文件输入：传输状态枚举
/// 文件职责：定义传输任务状态
/// 文件对外接口：TransferStatus
/// 文件包含：TransferStatus
enum TransferStatus {
  pending,
  paused,
  transferring,
  awaitingConflictResolution,
  completed,
  skipped,
  failed,
  cancelled,
}
