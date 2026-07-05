import '../../../../core/result/app_result.dart';
import '../../domain/repositories/backup_repository.dart';

class CompleteBackupRunParams {
  const CompleteBackupRunParams({
    required this.runId,
    required this.status,
    required this.scannedCount,
    required this.queuedCount,
    required this.skippedCount,
    required this.failedCount,
    this.errorMessage,
  });

  final String runId;
  final String status;
  final int scannedCount;
  final int queuedCount;
  final int skippedCount;
  final int failedCount;
  final String? errorMessage;
}

class CompleteBackupRunUseCase {
  CompleteBackupRunUseCase({required BackupRepository repository})
    : _repository = repository;

  final BackupRepository _repository;

  Future<AppResult<void>> call(CompleteBackupRunParams params) {
    return _repository.completeRun(
      runId: params.runId,
      status: params.status,
      scannedCount: params.scannedCount,
      queuedCount: params.queuedCount,
      skippedCount: params.skippedCount,
      failedCount: params.failedCount,
      errorMessage: params.errorMessage,
    );
  }
}
