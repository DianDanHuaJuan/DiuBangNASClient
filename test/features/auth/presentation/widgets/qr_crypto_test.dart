import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/auth/presentation/widgets/qr_crypto.dart';

void main() {
  String buildPem(List<int> derBytes) {
    return '''
-----BEGIN CERTIFICATE-----
${base64Encode(derBytes)}
-----END CERTIFICATE-----
''';
  }

  test('identifies NASPAIR3 pairing tokens', () {
    expect(isPairingV3QrToken(' NASPAIR3|abc '), isTrue);
    expect(isSupportedQrToken('NASPAIR3|abc'), isTrue);
    expect(isPairingV3QrToken('NASPAIR1|abc'), isFalse);
    expect(isPairingV3QrToken('NASPAIR2|abc'), isFalse);
    expect(isPairingV3QrToken('ENC1|abc'), isFalse);
    expect(isPairingV3QrToken('https://example.com'), isFalse);
  });

  test('calculates PEM SHA256 fingerprint', () async {
    final rootCaPem = buildPem(utf8.encode('dummy-root-ca-der'));
    final caSha256 = await calculatePemSha256(rootCaPem);

    expect(caSha256, isNotEmpty);
    expect(normalizeSha256Fingerprint(caSha256), caSha256);
  });

  test('normalizes SHA256 fingerprint formatting', () {
    expect(
      normalizeSha256Fingerprint('AB:CD:EF 12'),
      'abcdef12',
    );
  });
}
