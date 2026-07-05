import '../../../../core/result/app_result.dart';
import '../../domain/entities/backup_run_record_entity.dart';
import '../../domain/repositories/backup_repository.dart';

class LoadRecentBackupRunsParams {
  const LoadRecentBackupRunsParams({
    this.planId,
    this.limit = 10,
    this.onlyAbnormal = false,
  });

  final String? planId;
  final int limit;
  final bool onlyAbnormal;
}

class LoadRecentBackupRunsUseCase {
  LoadRecentBackupRunsUseCase({required BackupRepository repository})
    : _repository = repository;

  final BackupRepository _repository;

  Future<AppResult<List<BackupRunRecordEntity>>> call(
    LoadRecentBackupRunsParams params,
  ) {
    return _repository.loadRecentRuns(
      planId: params.planId,
      limit: params.limit,
      onlyAbnormal: params.onlyAbnormal,
    );
  }
}
