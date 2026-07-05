import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/client_route_ip_service.dart';

void main() {
  group('ClientRouteIpService', () {
    test(
      'uses the target host and default https port to resolve route ip',
      () async {
        String? capturedHost;
        int? capturedPort;
        final service = ClientRouteIpService(
          socketConnector:
              ({
                required String host,
                required int port,
                required Duration timeout,
              }) async {
                capturedHost = host;
                capturedPort = port;
                return _FakeRouteProbeSocket(
                  localAddress: '192.168.1.23',
                  remoteAddress: '192.168.1.10',
                );
              },
        );

        final routeIp = await service.resolveRouteIpForBaseUrl(
          'https://nas.local',
        );

        expect(routeIp, '192.168.1.23');
        expect(capturedHost, 'nas.local');
        expect(capturedPort, 443);
      },
    );

    test('normalizes ipv4-mapped ipv6 route addresses', () async {
      final service = ClientRouteIpService(
        socketConnector:
            ({
              required String host,
              required int port,
              required Duration timeout,
            }) async => _FakeRouteProbeSocket(
              localAddress: '::ffff:192.168.1.23',
              remoteAddress: '192.168.1.10',
            ),
      );

      final routeIp = await service.resolveRouteIpForBaseUrl(
        'http://192.168.1.10:8080',
      );

      expect(routeIp, '192.168.1.23');
    });

    test('returns null when probing fails', () async {
      final service = ClientRouteIpService(
        socketConnector:
            ({
              required String host,
              required int port,
              required Duration timeout,
            }) async {
              throw SocketException('connect failed');
            },
      );

      expect(
        await service.resolveRouteIpForBaseUrl('https://nas.local:9443'),
        isNull,
      );
    });

    test('rejects route ip equal to server host', () async {
      final service = ClientRouteIpService(
        socketConnector:
            ({
              required String host,
              required int port,
              required Duration timeout,
            }) async => _FakeRouteProbeSocket(
              localAddress: '192.168.1.10',
              remoteAddress: '192.168.1.10',
            ),
      );

      expect(
        await service.resolveRouteIpForBaseUrl('https://192.168.1.10:9443'),
        isNull,
      );
    });

    test('rejects route ip equal to remote address', () async {
      final service = ClientRouteIpService(
        socketConnector:
            ({
              required String host,
              required int port,
              required Duration timeout,
            }) async => _FakeRouteProbeSocket(
              localAddress: '192.168.1.10',
              remoteAddress: '192.168.1.10',
            ),
      );

      expect(
        await service.resolveRouteIp(Uri.parse('https://192.168.1.10:9443')),
        isNull,
      );
    });

    test('real socket probe returns local address not remote', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final port = server.port;
      server.listen((client) {
        client.destroy();
      });

      final service = ClientRouteIpService();
      final routeIp = await service.resolveRouteIp(
        Uri.parse('http://127.0.0.1:$port'),
      );

      expect(routeIp, isNull);
    });
  });
}

class _FakeRouteProbeSocket implements RouteProbeSocket {
  _FakeRouteProbeSocket({
    required String localAddress,
    required String remoteAddress,
  }) : _localAddress = InternetAddress.tryParse(localAddress)!,
       _remoteAddress = InternetAddress.tryParse(remoteAddress)!;

  final InternetAddress _localAddress;
  final InternetAddress _remoteAddress;

  @override
  InternetAddress get localAddress => _localAddress;

  @override
  InternetAddress get remoteAddress => _remoteAddress;

  @override
  void close() {}
}
