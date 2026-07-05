import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/server_display_name_policy.dart';
import 'package:nasclient/core/node/server_display_name_resolver.dart';

void main() {
  group('ServerDisplayNamePolicy', () {
    test('accepts OS hostnames such as DESKTOP-ABC123', () {
      expect(
        ServerDisplayNamePolicy.isUsableDisplayName('DESKTOP-ABC123'),
        isTrue,
      );
    });

    test('rejects IPv4 addresses', () {
      expect(
        ServerDisplayNamePolicy.isRejectedAsDisplayName('192.168.1.10'),
        isTrue,
      );
      expect(
        ServerDisplayNamePolicy.isRejectedAsDisplayName('192.168.1.10:9443'),
        isTrue,
      );
    });

    test('rejects UI placeholders', () {
      expect(
        ServerDisplayNamePolicy.isRejectedAsDisplayName('当前服务器'),
        isTrue,
      );
    });
  });

  group('ServerDisplayNameResolver', () {
    test('prefers bootstrap over mDNS serviceName', () {
      expect(
        ServerDisplayNameResolver.resolve(
          bootstrapName: '客厅 NAS',
          mdnsServiceName: 'DESKTOP-ABC123',
        ),
        '客厅 NAS',
      );
    });

    test('uses mDNS serviceName when bootstrap is empty', () {
      expect(
        ServerDisplayNameResolver.resolve(mdnsServiceName: 'DESKTOP-ABC123'),
        'DESKTOP-ABC123',
      );
    });

    test('does not fall back to IP-like values', () {
      expect(
        ServerDisplayNameResolver.resolve(mdnsServiceName: '192.168.1.10'),
        ServerDisplayNameResolver.fallbackDisplayName,
      );
    });
  });
}
