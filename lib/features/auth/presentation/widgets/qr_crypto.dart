import 'dart:convert';

import 'package:cryptography/cryptography.dart';

bool isPairingV3QrToken(String token) {
  return token.trim().startsWith('NASPAIR3|');
}

bool isSupportedQrToken(String token) {
  return isPairingV3QrToken(token);
}

Future<String> calculatePemSha256(String pem) async {
  final derBytes = _extractPemDerBytes(pem);
  final digest = await Sha256().hash(derBytes);
  final buffer = StringBuffer();
  for (final byte in digest.bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String normalizeSha256Fingerprint(String value) {
  return value.trim().replaceAll(':', '').replaceAll(' ', '').toLowerCase();
}

List<int> _extractPemDerBytes(String pem) {
  final base64Body = pem
      .split('\n')
      .map((line) => line.trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !line.startsWith('-----BEGIN') &&
            !line.startsWith('-----END'),
      )
      .join();
  if (base64Body.isEmpty) {
    throw Exception('PEM 证书内容为空');
  }
  try {
    return base64Decode(base64Body);
  } catch (e) {
    throw Exception('PEM 证书内容损坏: $e');
  }
}
