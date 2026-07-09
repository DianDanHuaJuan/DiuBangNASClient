import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/error/app_exception.dart';
import 'package:nasclient/core/network/trusted_server_store.dart';
import 'package:nasclient/core/storage/secure_store.dart';
import 'package:nasclient/features/auth/data/pairing_client.dart';

void main() {
  group('PairingClient.completeCredentialEnrollment', () {
    final testCertPem = '''
-----BEGIN CERTIFICATE-----
${base64Encode(List<int>.generate(96, (index) => index % 251))}
-----END CERTIFICATE-----''';

    late _FakeSecureStore secureStore;
    late TrustedServerStore trustedServerStore;
    late PairingClient pairingClient;

    setUp(() {
      secureStore = _FakeSecureStore();
      trustedServerStore = TrustedServerStore(secureStore: secureStore);
      pairingClient = PairingClient(
        trustedServerStore: trustedServerStore,
        deviceIdProvider: () async => 'device-test-001',
        deviceNameProvider: () async => 'Test Device',
      );
    });

    test('registers device via credential enroll endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/api/v1/pairing/ca-cert') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'cert': testCertPem}));
          await request.response.close();
          return;
        }

        if (path == '/api/v1/auth/credential-device-enroll') {
          final auth = request.headers.value(HttpHeaders.authorizationHeader);
          expect(auth, startsWith('Basic '));
          final decoded = utf8.decode(base64Decode(auth!.substring(6)));
          expect(decoded, 'admin:admin');

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'serverId': 'srv-cred-001',
                'serverName': 'Credential NAS',
                'baseUrl': 'http://127.0.0.1:${server.port}',
                'rootCaPem': testCertPem,
                'caSha256': '',
                'deviceId': 'device-enrolled-001',
                'accessToken': 'access-token',
                'refreshToken': 'refresh-token',
                'sessionId': 'sess_test',
                'accessExpiresAt': '2030-01-01T00:00:00.000Z',
              }),
            );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final result = await pairingClient.completeCredentialEnrollment(
        serverUrl: 'http://127.0.0.1:${server.port}',
        username: 'admin',
        password: 'admin',
      );

      expect(result.serverId, 'srv-cred-001');
      expect(result.deviceId, 'device-enrolled-001');
      expect(result.accessToken, 'access-token');
      expect(result.refreshToken, 'refresh-token');

      final trusted = await trustedServerStore.findByServerId('srv-cred-001');
      expect(trusted, isNotNull);
      expect(trusted!.rootCaPem, testCertPem);
    });

    test('rejects enroll when server returns auth error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      server.listen((request) async {
        final path = request.uri.path;
        if (path == '/api/v1/pairing/ca-cert') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'cert': testCertPem}));
          await request.response.close();
          return;
        }

        if (path == '/api/v1/auth/credential-device-enroll') {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'code': 'AUTH_INVALID',
                'message': 'Invalid username or password',
              }),
            );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      expect(
        pairingClient.completeCredentialEnrollment(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'admin',
          password: 'wrong',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'message',
            contains('Invalid username or password'),
          ),
        ),
      );
    });
  });
}

class _FakeSecureStore extends SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
