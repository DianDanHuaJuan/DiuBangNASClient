import '../../../../core/result/app_result.dart';
import '../../domain/repositories/backup_repository.dart';

class ToggleBackupPlanUseCase {
  final BackupRepository _repository;

  ToggleBackupPlanUseCase({required BackupRepository repository})
    : _repository = repository;

  Future<AppResult<void>> call({
    required String planId,
    required bool enabled,
  }) {
    return _repository.togglePlan(planId, enabled);
  }
}
