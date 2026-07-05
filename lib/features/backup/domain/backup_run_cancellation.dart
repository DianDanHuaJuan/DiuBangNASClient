/// 文件输入：无
/// 文件职责：为立即备份提供轻量协作式取消信号
/// 文件对外接口：BackupRunCancellation、BackupRunCancelledException
/// 文件包含：BackupRunCancellation、BackupRunCancelledException
class BackupRunCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class BackupRunCancelledException implements Exception {
  const BackupRunCancelledException([this.message = '用户已停止本次备份']);

  final String message;

  @override
  String toString() => message;
}
