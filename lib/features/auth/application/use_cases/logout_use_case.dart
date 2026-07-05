/// 文件输入：无参数
/// 文件职责：执行退出登录，清除本地会话
/// 文件对外接口：LogoutUseCase
/// 文件包含：LogoutUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/repositories/auth_repository.dart';

class LogoutUseCase implements UseCase<AppResult<void>, NoParams> {
  final AuthRepository _repository;

  LogoutUseCase({required AuthRepository repository})
    : _repository = repository;

  @override
  Future<AppResult<void>> call(NoParams params) async {
    return await _repository.logout();
  }
}
