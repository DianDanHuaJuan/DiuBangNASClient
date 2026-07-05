/// 文件输入：立即备份参数
/// 文件职责：触发一次立即备份，将待备份资源转换为传输任务
/// 文件对外接口：RunBackupNowUseCase
/// 文件包含：RunBackupNowUseCase
import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/use_case.dart';
import '../../domain/entities/backup_run_result.dart';
import '../../domain/repositories/backup_repository.dart';
import '../params/run_backup_now_params.dart';

class RunBackupNowUseCase
    implements UseCase<AppResult<BackupRunResult>, RunBackupNowParams> {
  final BackupRepository _repository;

  RunBackupNowUseCase({required BackupRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<BackupRunResult>> call(RunBackupNowParams params) async {
    return _repository.runBackupNow(
      params.requests,
      onProgress: params.onProgress,
      cancellation: params.cancellation,
    );
  }
}
