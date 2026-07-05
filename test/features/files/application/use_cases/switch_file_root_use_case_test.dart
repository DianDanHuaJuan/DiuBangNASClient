/// 文件输入：SwitchFileRootUseCase、CurrentSession
/// 文件职责：验证当前文件根目录切换逻辑
/// 文件对外接口：main
/// 文件包含：main
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/files/application/use_cases/switch_file_root_use_case.dart';

/// 输入：Flutter test runtime。
/// 职责：验证文件根目录切换在成功和失败分支下都会返回稳定结果。
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

  group('SwitchFileRootUseCase', () {
    test('switches current root when target root exists', () async {
      final useCase = SwitchFileRootUseCase(currentSession: session);

      final result = await useCase.call('library');

      expect(result.isSuccess, isTrue);
      expect(session.rootId, 'library');
      expect(session.rootName, '原机');
    });

    test('returns failure when target root does not exist', () async {
      final useCase = SwitchFileRootUseCase(currentSession: session);

      final result = await useCase.call('missing-root');

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.code, 'ROOT_NOT_FOUND');
      expect(session.rootId, 'fs');
    });
  });
}
