/// 文件输入：BootstrapResponseDto
/// 文件职责：验证 bootstrap 响应解析会正确提取 roots 与默认根目录
/// 文件对外接口：main
/// 文件包含：main
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/auth/data/models/bootstrap_response_dto.dart';

/// 输入：Flutter test runtime。
/// 职责：验证客户端会从当前服务端 bootstrap 结构中解析根目录与基础能力字段。
/// 对外接口：main。
void main() {
  group('BootstrapResponseDto', () {
    test('parses nested bootstrap response and derives roots', () {
      final dto = BootstrapResponseDto.fromJson({
        'server': {
          'id': 'server-1',
          'name': 'MiniNAS',
          'version': '1.0.0',
          'status': 'online',
        },
        'fileAccess': {
          'protocol': 'webdav',
          'roots': [
            {
              'id': 'fs',
              'name': '共享',
              'path': '/fs',
              'type': 'local',
              'writable': true,
            },
            {
              'id': 'library',
              'name': '媒体库',
              'path': '/library',
              'type': 'mediastore',
              'writable': false,
            },
          ],
        },
        'capabilities': {
          'preview': {'image': true},
        },
      });

      expect(dto.serverId, 'server-1');
      expect(dto.serverName, 'MiniNAS');
      expect(dto.serverVersion, '1.0.0');
      expect(dto.serverStatus, 'online');
      expect(dto.protocol, 'webdav');
      expect(dto.rootId, 'fs');
      expect(dto.rootName, '共享');
      expect(dto.roots, hasLength(2));
      expect(dto.roots[1].id, 'library');
      expect(dto.capabilities?['preview']?['image'], isTrue);
    });
  });
}
