/// 文件输入：CurrentSession、rootId
/// 文件职责：判断指定根目录当前是否支持写入
/// 文件对外接口：IsRootWritableUseCase
/// 文件包含：IsRootWritableUseCase
import '../../../../core/session/current_session.dart';

/// 输入：CurrentSession、rootId。
/// 职责：为文件浏览 UI 提供当前根目录的写入能力判断。
/// 对外接口：call(rootId) -> bool。
class IsRootWritableUseCase {
  final CurrentSession _currentSession;

  IsRootWritableUseCase({required CurrentSession currentSession})
    : _currentSession = currentSession;

  bool call(String rootId) {
    return _currentSession.getRootById(rootId)?.writable ?? (rootId == 'fs');
  }
}
