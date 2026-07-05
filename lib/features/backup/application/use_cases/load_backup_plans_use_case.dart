import '../../../../core/result/app_result.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/repositories/backup_repository.dart';

class LoadBackupPlansUseCase {
  final BackupRepository _repository;

  LoadBackupPlansUseCase({required BackupRepository repository})
    : _repository = repository;

  Future<AppResult<List<BackupPlanEntity>>> call() {
    return _repository.loadPlans();
  }
}
