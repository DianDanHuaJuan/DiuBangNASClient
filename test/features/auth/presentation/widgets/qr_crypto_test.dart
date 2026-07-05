import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/auth/presentation/widgets/qr_crypto.dart';

void main() {
  const keyBytes = <int>[
    0x00,
    0x11,
    0x22,
    0x33,
    0x44,
    0x55,
    0x66,
    0x77,
    0x88,
    0x99,
    0xaa,
    0xbb,
    0xcc,
    0xdd,
    0xee,
    0xff,
  ];

  Future<String> buildToken(Map<String, dynamic> payload) async {
    final secretBox = await AesGcm.with128bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(keyBytes),
    );
    final combined = <int>[
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ];
    return 'ENC1|${base64UrlEncode(combined)}';
  }

  String buildPairingToken(Map<String, dynamic> payload) {
    return 'NASPAIR1|${base64UrlEncode(utf8.encode(jsonEncode(payload)))}';
  }

  String buildCompactPairingToken(Map<String, dynamic> payload) {
    return 'NASPAIR2|${base64UrlEncode(gzip.encode(utf8.encode(jsonEncode(payload))))}';
  }

  String buildPem(List<int> derBytes) {
    return '''
-----BEGIN CERTIFICATE-----
${base64Encode(derBytes)}
-----END CERTIFICATE-----
''';
  }

  test('identifies NAS credential QR tokens', () {
    expect(isCredentialQrToken(' ENC1|abc '), isTrue);
    expect(isCredentialQrToken('https://example.com'), isFalse);
  });

  test('decrypts a valid token and validates its payload', () async {
    final token = await buildToken({
      'username': 'client-01',
      'password': 'secret-pass',
      'exp': 1_900_000_000,
    });

    final payload = await decryptQrWithKeyBytes(
      token,
      Uint8List.fromList(keyBytes),
      now: DateTime.fromMillisecondsSinceEpoch(
        1_800_000_000 * 1000,
        isUtc: true,
      ),
    );

    expect(payload['username'], 'client-01');
    expect(payload['password'], 'secret-pass');
  });

  test('rejects expired tokens', () async {
    final token = await buildToken({
      'username': 'client-01',
      'password': 'secret-pass',
      'exp': 1_700_000_000,
    });

    await expectLater(
      decryptQrWithKeyBytes(
        token,
        Uint8List.fromList(keyBytes),
        now: DateTime.fromMillisecondsSinceEpoch(
          1_800_000_000 * 1000,
          isUtc: true,
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('parses a valid pairing token and validates its fingerprint', () async {
    final rootCaPem = buildPem(utf8.encode('dummy-root-ca-der'));
    final caSha256 = await calculatePemSha256(rootCaPem);
    final token = buildPairingToken({
      'serverId': 'server-01',
      'serverName': '家庭NAS',
      'baseUrl': 'https://192.168.1.10:9443',
      'caSha256': caSha256,
      'rootCaPem': rootCaPem,
      'hostLabel': 'nas-home',
      'host': '192.168.1.10',
      'port': 9443,
    });

    final payload = await parsePairingQrToken(token);

    expect(payload.serverId, 'server-01');
    expect(payload.serverName, '家庭NAS');
    expect(payload.hostLabel, 'nas-home');
    expect(payload.baseUrl, 'https://192.168.1.10:9443');
    expect(payload.caSha256, caSha256);
  });

  test('parses a compact pairing token and validates its fingerprint', () async {
    final rootCaPem = buildPem(utf8.encode('dummy-root-ca-der'));
    final rootCaDerBase64Url = base64UrlEncode(utf8.encode('dummy-root-ca-der'));
    final caSha256 = await calculatePemSha256(rootCaPem);
    final token = buildCompactPairingToken({
      'i': 'server-01',
      'n': '家庭NAS',
      'u': 'https://192.168.1.10:8080',
      'f': caSha256,
      'c': rootCaDerBase64Url,
      'l': 'feedface',
    });

    final payload = await parsePairingQrToken(token);

    expect(payload.serverId, 'server-01');
    expect(payload.serverName, '家庭NAS');
    expect(payload.hostLabel, isNull);
    expect(payload.baseUrl, 'https://192.168.1.10:8080');
    expect(payload.caSha256, caSha256);
    expect(payload.rootCaPem.trim(), rootCaPem.trim());
    expect(payload.leafSha256, 'feedface');
  });

  test('rejects pairing token when fingerprint does not match root ca', () async {
    final rootCaPem = buildPem(utf8.encode('dummy-root-ca-der'));
    final token = buildPairingToken({
      'serverId': 'server-01',
      'serverName': '家庭NAS',
      'baseUrl': 'https://192.168.1.10:9443',
      'caSha256': 'deadbeef',
      'rootCaPem': rootCaPem,
    });

    await expectLater(parsePairingQrToken(token), throwsA(isA<Exception>()));
  });
}
