/// 文件输入：无参数
/// 文件职责：恢复已保存的会话
/// 文件对外接口：RestoreSessionUseCase
/// 文件包含：RestoreSessionUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/auth_session_entity.dart';
import '../../domain/repositories/auth_repository.dart';

class RestoreSessionUseCase
    implements UseCase<AppResult<AuthSessionEntity>, NoParams> {
  final AuthRepository _repository;

  RestoreSessionUseCase({required AuthRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<AuthSessionEntity>> call(NoParams params) async {
    return await _repository.restoreSession();
  }
}
