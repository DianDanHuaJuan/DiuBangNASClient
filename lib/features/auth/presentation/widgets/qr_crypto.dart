import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../../core/crypto/encryption_key_loader.dart';

class PairingQrPayload {
  const PairingQrPayload({
    required this.serverId,
    required this.baseUrl,
    required this.caSha256,
    required this.rootCaPem,
    this.serverName,
    this.leafSha256,
    this.hostLabel,
    this.host,
    this.port,
  });

  final String serverId;
  final String baseUrl;
  final String caSha256;
  final String rootCaPem;
  final String? serverName;
  final String? leafSha256;
  final String? hostLabel;
  final String? host;
  final int? port;
}

bool isCredentialQrToken(String token) {
  return token.trim().startsWith('ENC1|');
}

bool isPairingQrToken(String token) {
  final normalized = token.trim();
  return normalized.startsWith('NASPAIR1|') ||
      normalized.startsWith('NASPAIR2|') ||
      normalized.startsWith('NASPAIR3|');
}

bool isPairingV3QrToken(String token) {
  return token.trim().startsWith('NASPAIR3|');
}

bool isSupportedQrToken(String token) {
  return isCredentialQrToken(token) || isPairingQrToken(token);
}

/// Decrypts a token produced by server using format:
///  `ENC1|base64url(iv || ciphertext || tag)`
/// Returns the decoded JSON map (e.g. {"username": "u", "password": "p", "exp": 123456})
Future<Map<String, dynamic>> decryptQr(String token, {DateTime? now}) async {
  final keyBytes = await loadEncryptionKey();
  return decryptQrWithKeyBytes(token, keyBytes, now: now);
}

Future<Map<String, dynamic>> decryptQrWithKeyBytes(
  String token,
  Uint8List keyBytes, {
  DateTime? now,
}) async {
  final normalizedToken = token.trim();
  if (!isCredentialQrToken(normalizedToken)) {
    throw Exception('请扫描 NAS 客户端凭据二维码');
  }

  token = normalizedToken.substring('ENC1|'.length);
  late final List<int> bytes;
  try {
    bytes = base64Url.decode(token);
  } catch (e) {
    throw Exception('Token is not valid base64url: $e');
  }
  if (bytes.length < 12 + 16) throw Exception('Token too short');
  final nonce = bytes.sublist(0, 12);
  final cipherAndTag = bytes.sublist(12);
  if (cipherAndTag.length < 16) throw Exception('Ciphertext too short');

  final cipherText = cipherAndTag.sublist(0, cipherAndTag.length - 16);
  final tag = cipherAndTag.sublist(cipherText.length);

  final algorithm = AesGcm.with128bits();
  final secretKey = SecretKey(keyBytes);

  try {
    final secretBox = SecretBox(
      Uint8List.fromList(cipherText),
      nonce: Uint8List.fromList(nonce),
      mac: Mac(Uint8List.fromList(tag)),
    );
    final clear = await algorithm.decrypt(secretBox, secretKey: secretKey);
    final jsonStr = utf8.decode(clear);
    final decoded = json.decode(jsonStr);
    if (decoded is Map<String, dynamic>) {
      return _validateCredentialPayload(decoded, now: now);
    }
    if (decoded is Map) {
      return _validateCredentialPayload(
        Map<String, dynamic>.from(decoded),
        now: now,
      );
    }
    throw Exception('Decrypted payload is not a JSON object');
  } catch (e) {
    throw Exception('Decryption failed: $e');
  }
}

Future<PairingQrPayload> parsePairingQrToken(String token) async {
  final normalizedToken = token.trim();
  if (!isPairingQrToken(normalizedToken)) {
    throw Exception('请扫描 NAS 服务端连接二维码');
  }
  if (isPairingV3QrToken(normalizedToken)) {
    throw Exception('NASPAIR3 格式需要走一次扫码配对流程');
  }

  final payloadMap = _decodePairingPayloadMap(normalizedToken);
  return _validatePairingPayload(payloadMap);
}

Map<String, dynamic> _decodePairingPayloadMap(String token) {
  if (token.startsWith('NASPAIR2|')) {
    final encodedPayload = token.substring('NASPAIR2|'.length);
    late final List<int> compressedBytes;
    try {
      compressedBytes = base64Url.decode(base64Url.normalize(encodedPayload));
    } catch (e) {
      throw Exception('二维码内容不是有效的 base64url: $e');
    }

    late final List<int> payloadBytes;
    try {
      payloadBytes = gzip.decode(compressedBytes);
    } catch (e) {
      throw Exception('二维码压缩内容无效: $e');
    }

    late final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(payloadBytes));
    } catch (e) {
      throw Exception('二维码内容不是有效的 JSON: $e');
    }

    if (decoded is! Map) {
      throw Exception('二维码内容格式无效');
    }

    final compactPayload = Map<String, dynamic>.from(decoded);
    return {
      'serverId': compactPayload['i'],
      'serverName': compactPayload['n'],
      'baseUrl': compactPayload['u'],
      'caSha256': compactPayload['f'],
      'rootCaPem': _derBase64UrlToPem(compactPayload['c']?.toString() ?? ''),
      'leafSha256': compactPayload['l'],
    };
  }

  final encodedPayload = token.substring('NASPAIR1|'.length);
  late final List<int> bytes;
  try {
    bytes = base64Url.decode(base64Url.normalize(encodedPayload));
  } catch (e) {
    throw Exception('二维码内容不是有效的 base64url: $e');
  }

  late final dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (e) {
    throw Exception('二维码内容不是有效的 JSON: $e');
  }

  if (decoded is! Map) {
    throw Exception('二维码内容格式无效');
  }

  return Map<String, dynamic>.from(decoded);
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

Map<String, dynamic> _validateCredentialPayload(
  Map<String, dynamic> payload, {
  DateTime? now,
}) {
  final username = payload['username'];
  final password = payload['password'];
  if (username == null ||
      password == null ||
      username.toString().trim().isEmpty ||
      password.toString().isEmpty) {
    throw Exception('二维码不包含用户名或密码');
  }

  final expSeconds = _parseExpirySeconds(payload['exp']);
  if (expSeconds == null) {
    throw Exception('二维码缺少有效期信息');
  }

  final currentSeconds =
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
  if (currentSeconds >= expSeconds) {
    throw Exception('二维码已过期，请在服务端重新生成');
  }

  return payload;
}

int? _parseExpirySeconds(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

Future<PairingQrPayload> _validatePairingPayload(
  Map<String, dynamic> payload,
) async {
  final serverId = payload['serverId']?.toString().trim() ?? '';
  final baseUrl = payload['baseUrl']?.toString().trim() ?? '';
  final caSha256 = normalizeSha256Fingerprint(
    payload['caSha256']?.toString() ?? '',
  );
  final rootCaPem = payload['rootCaPem']?.toString().trim() ?? '';
  final leafSha256 = normalizeSha256Fingerprint(
    payload['leafSha256']?.toString() ?? '',
  );
  final hostLabel = payload['hostLabel']?.toString().trim();
  final serverName = payload['serverName']?.toString().trim();
  final host = payload['host']?.toString().trim();
  final port = _parseExpirySeconds(payload['port']);

  if (serverId.isEmpty) {
    throw Exception('二维码缺少服务器标识信息');
  }
  if (baseUrl.isEmpty || Uri.tryParse(baseUrl)?.scheme != 'https') {
    throw Exception('二维码中的服务器地址不是有效的 HTTPS 地址');
  }
  if (rootCaPem.isEmpty || !rootCaPem.contains('BEGIN CERTIFICATE')) {
    throw Exception('二维码缺少有效的 Root CA 证书');
  }
  if (caSha256.isEmpty) {
    throw Exception('二维码缺少 CA 指纹');
  }

  final calculatedFingerprint = await calculatePemSha256(rootCaPem);
  if (normalizeSha256Fingerprint(calculatedFingerprint) != caSha256) {
    throw Exception('二维码中的 CA 指纹与证书内容不匹配');
  }

  return PairingQrPayload(
    serverId: serverId,
    baseUrl: baseUrl,
    caSha256: caSha256,
    rootCaPem: rootCaPem,
    serverName: serverName == null || serverName.isEmpty ? null : serverName,
    leafSha256: leafSha256.isEmpty ? null : leafSha256,
    hostLabel: hostLabel == null || hostLabel.isEmpty ? null : hostLabel,
    host: host == null || host.isEmpty ? null : host,
    port: port,
  );
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

String _derBase64UrlToPem(String encodedDer) {
  if (encodedDer.trim().isEmpty) {
    throw Exception('二维码缺少有效的 Root CA 证书');
  }
  late final List<int> derBytes;
  try {
    derBytes = base64Url.decode(base64Url.normalize(encodedDer.trim()));
  } catch (e) {
    throw Exception('二维码中的 Root CA 证书内容损坏: $e');
  }

  final base64Body = base64Encode(derBytes);
  final buffer = StringBuffer('-----BEGIN CERTIFICATE-----\n');
  for (var offset = 0; offset < base64Body.length; offset += 64) {
    final end = (offset + 64 < base64Body.length)
        ? offset + 64
        : base64Body.length;
    buffer.writeln(base64Body.substring(offset, end));
  }
  buffer.write('-----END CERTIFICATE-----\n');
  return buffer.toString();
}
