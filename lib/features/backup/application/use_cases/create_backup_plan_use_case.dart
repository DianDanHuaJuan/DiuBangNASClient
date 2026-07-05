import '../../../../core/result/app_result.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/repositories/backup_repository.dart';
import '../params/create_backup_plan_params.dart';

class CreateBackupPlanUseCase {
  final BackupRepository _repository;

  CreateBackupPlanUseCase({required BackupRepository repository})
    : _repository = repository;

  Future<AppResult<BackupPlanEntity>> call(CreateBackupPlanParams params) {
    return _repository.createPlan(params.toEntity());
  }
}
