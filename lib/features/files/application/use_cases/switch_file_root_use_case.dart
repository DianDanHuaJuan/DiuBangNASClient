/// 文件输入：CurrentSession、rootId
/// 文件职责：切换当前文件浏览使用的根目录
/// 文件对外接口：SwitchFileRootUseCase
/// 文件包含：SwitchFileRootUseCase
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/session/current_session.dart';
import '../../../../core/use_case/use_case.dart';

/// 输入：CurrentSession、rootId。
/// 职责：校验并切换当前会话使用的文件根目录。
/// 对外接口：`call(rootId) -> Future<AppResult<void>>`。
class SwitchFileRootUseCase implements UseCase<AppResult<void>, String> {
  final CurrentSession _currentSession;

  SwitchFileRootUseCase({required CurrentSession currentSession})
    : _currentSession = currentSession;

  @override
  Future<AppResult<void>> call(String rootId) async {
    final root = _currentSession.getRootById(rootId);
    if (root == null) {
      return Failure(
        AppFailure.fromException(
          code: 'ROOT_NOT_FOUND',
          message: 'Root not found: $rootId',
        ),
      );
    }

    _currentSession.switchRoot(rootId);
    return const Success(null);
  }
}
