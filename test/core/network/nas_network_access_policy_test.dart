import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/error/app_exception.dart';
import 'package:nasclient/core/network/nas_network_access_policy.dart';

void main() {
  group('NasNetworkAccessPolicy', () {
    test('normalizes bare private server host to https origin', () {
      final result = NasNetworkAccessPolicy.normalizeServerUrl(
        '192.168.1.10:8080',
      );

      expect(result, 'https://192.168.1.10:8080');
    });

    test('rejects local cleartext http url', () {
      expect(
        () => NasNetworkAccessPolicy.normalizeServerUrl(
          'http://mininas.local:8080',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'HTTP_ADDRESS_NOT_ALLOWED',
          ),
        ),
      );
    });

    test('rejects public http server url', () {
      expect(
        () => NasNetworkAccessPolicy.normalizeServerUrl(
          'http://example.com:8080',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'HTTP_ADDRESS_NOT_ALLOWED',
          ),
        ),
      );
    });

    test('allows public https server url', () {
      final result = NasNetworkAccessPolicy.normalizeServerUrl(
        'https://nas.example.com:8443',
      );

      expect(result, 'https://nas.example.com:8443');
    });

    test('normalizes remote media url and preserves path and query', () {
      final result = NasNetworkAccessPolicy.normalizeAbsoluteUrl(
        'https://192.168.1.10:8080/dav/fs/demo.mp4?download=0',
      );

      expect(result, 'https://192.168.1.10:8080/dav/fs/demo.mp4?download=0');
    });
  });
}
