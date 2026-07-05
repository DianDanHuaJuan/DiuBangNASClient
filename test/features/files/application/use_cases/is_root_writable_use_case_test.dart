/// 文件输入：IsRootWritableUseCase、CurrentSession
/// 文件职责：验证文件根目录写入能力判断逻辑
/// 文件对外接口：main
/// 文件包含：main
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/files/application/use_cases/is_root_writable_use_case.dart';

/// 输入：Flutter test runtime。
/// 职责：验证根目录写权限判断会优先使用当前会话中的根目录信息。
/// 对外接口：main。
void main() {
  final session = CurrentSession();

  setUp(() {
    session.clear();
    session.set(
      serverId: 'server-1',
      serverName: 'MiniNAS',
      serverVersion: '1.0.0',
      serverStatus: 'online',
      serverUrl: 'http://192.168.1.10:8080',
      username: 'admin',
      password: 'admin',
      protocol: 'webdav',
      rootId: 'fs',
      rootName: '共享',
      roots: const [
        RootInfo(
          id: 'fs',
          name: '共享',
          path: '/fs',
          type: 'local',
          writable: true,
        ),
        RootInfo(
          id: 'library',
          name: '原机',
          path: '/library',
          type: 'mediastore',
          writable: false,
        ),
      ],
    );
  });

  tearDown(session.clear);

  group('IsRootWritableUseCase', () {
    test('returns root writable flag from current session', () {
      final useCase = IsRootWritableUseCase(currentSession: session);

      expect(useCase.call('fs'), isTrue);
      expect(useCase.call('library'), isFalse);
    });

    test('keeps fs as writable fallback when root metadata is missing', () {
      final useCase = IsRootWritableUseCase(currentSession: session);

      expect(useCase.call('fs-missing'), isFalse);
      expect(useCase.call('fs'), isTrue);
    });
  });
}
