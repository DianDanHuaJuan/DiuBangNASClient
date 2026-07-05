/// 文件输入：立即备份资源列表
/// 文件职责：封装立即备份用例的输入参数
/// 文件对外接口：RunBackupNowParams
/// 文件包含：RunBackupNowParams
import '../../domain/entities/backup_upload_request.dart';
import '../../domain/entities/backup_preparation_progress.dart';
import '../../domain/backup_run_cancellation.dart';

class RunBackupNowParams {
  final List<BackupUploadRequest> requests;
  final void Function(BackupPreparationProgress progress)? onProgress;
  final BackupRunCancellation? cancellation;

  const RunBackupNowParams({
    required this.requests,
    this.onProgress,
    this.cancellation,
  });
}
