/// 文件输入：TrustedServerStore
/// 文件职责：处理配对流程，包括二维码解析、证书下载、凭据获取
/// 文件对外接口：PairingClient
/// 文件包含：PairingClient, PairingResult, PairingQrData
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../../core/device/device_id_normalizer.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/network/trusted_server_store.dart';

class PairingQrData {
  final String serverId;
  final String serverUrl;
  final String caFingerprint;
  final Uint8List serverPublicKey;

  const PairingQrData({
    required this.serverId,
    required this.serverUrl,
    required this.caFingerprint,
    required this.serverPublicKey,
  });

  factory PairingQrData.fromJson(Map<String, dynamic> json) {
    return PairingQrData(
      serverId: json['i'] as String? ?? '',
      serverUrl: json['u'] as String? ?? '',
      caFingerprint: json['f'] as String? ?? '',
      serverPublicKey: Uint8List.fromList(
        base64Url.decode(base64Url.normalize(json['p'] as String? ?? '')),
      ),
    );
  }
}

class PairingResult {
  final String serverId;
  final String baseUrl;
  final String certificate;
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final String? sessionId;
  final DateTime? accessExpiresAt;

  const PairingResult({
    required this.serverId,
    required this.baseUrl,
    required this.certificate,
    required this.deviceId,
    required this.accessToken,
    required this.refreshToken,
    this.sessionId,
    this.accessExpiresAt,
  });
}

class PairingClient {
  PairingClient({
    required TrustedServerStore trustedServerStore,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() deviceNameProvider,
    Future<String?> Function()? devicePlatformProvider,
    Future<String?> Function()? deviceBrandProvider,
    Future<String?> Function()? deviceModelProvider,
  }) : _trustedServerStore = trustedServerStore,
       _deviceIdProvider = deviceIdProvider,
       _deviceNameProvider = deviceNameProvider,
       _devicePlatformProvider = devicePlatformProvider,
       _deviceBrandProvider = deviceBrandProvider,
       _deviceModelProvider = deviceModelProvider;

  final TrustedServerStore _trustedServerStore;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _deviceNameProvider;
  final Future<String?> Function()? _devicePlatformProvider;
  final Future<String?> Function()? _deviceBrandProvider;
  final Future<String?> Function()? _deviceModelProvider;

  /// 解析配对二维码
  /// 支持格式: `NASPAIR3|base64url(gzip(json))`
  Future<PairingQrData> parsePairingQrToken(String token) async {
    final normalizedToken = token.trim();

    if (!normalizedToken.startsWith('NASPAIR3|')) {
      throw const AppException(
        code: 'INVALID_QR_FORMAT',
        message: '不支持的二维码格式，请扫描服务端连接二维码',
      );
    }

    final encoded = normalizedToken.substring('NASPAIR3|'.length);

    try {
      final compressed = base64Url.decode(base64Url.normalize(encoded));
      final jsonBytes = gzip.decode(compressed);
      final payload =
          jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;

      return PairingQrData.fromJson(payload);
    } catch (e) {
      throw AppException(code: 'QR_PARSE_ERROR', message: '二维码解析失败: $e');
    }
  }

  /// 完整的配对流程
  Future<PairingResult> completePairing(String qrToken) async {
    // 1. 解析二维码
    final qrData = await parsePairingQrToken(qrToken);

    if (qrData.serverId.isEmpty) {
      throw const AppException(
        code: 'MISSING_SERVER_ID',
        message: '二维码缺少服务器标识',
      );
    }

    if (qrData.serverUrl.isEmpty) {
      throw const AppException(
        code: 'MISSING_SERVER_URL',
        message: '二维码缺少服务器地址',
      );
    }

    // 2. 下载并验证证书
    final certificate = await _downloadAndVerifyCertificate(
      serverUrl: qrData.serverUrl,
      expectedFingerprint: qrData.caFingerprint,
    );

    // 3. 保存信任的服务器
    await _trustedServerStore.trustServer(
      serverId: qrData.serverId,
      baseUrl: qrData.serverUrl,
      rootCaPem: certificate,
      caSha256: qrData.caFingerprint,
    );

    // 4. 请求设备注册令牌
    final enrollment = await _requestDeviceEnrollment(
      serverUrl: qrData.serverUrl,
      serverId: qrData.serverId,
      serverPublicKey: qrData.serverPublicKey,
      certificate: certificate,
    );

    return PairingResult(
      serverId: qrData.serverId,
      baseUrl: qrData.serverUrl,
      certificate: certificate,
      deviceId: enrollment.deviceId,
      accessToken: enrollment.accessToken,
      refreshToken: enrollment.refreshToken,
      sessionId: enrollment.sessionId,
      accessExpiresAt: enrollment.accessExpiresAt,
    );
  }

  /// 使用服务端 owner 账密注册为设备（账密不持久化）
  Future<PairingResult> completeCredentialEnrollment({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final normalizedServerUrl = serverUrl.trim();
    if (normalizedServerUrl.isEmpty) {
      throw const AppException(
        code: 'MISSING_SERVER_URL',
        message: '请输入服务器地址',
      );
    }

    final trimmedUsername = username.trim();
    final trimmedPassword = password;
    if (trimmedUsername.isEmpty || trimmedPassword.isEmpty) {
      throw const AppException(
        code: 'MISSING_CREDENTIALS',
        message: '请输入用户名和密码',
      );
    }

    final certificate = await _downloadCertificate(normalizedServerUrl);
    final certificateFingerprint = await _calculateFingerprint(certificate);

    final deviceId = DeviceIdNormalizer.normalizeRequired(
      await _deviceIdProvider(),
    );
    final physicalDeviceId = deviceId;
    final deviceName = await _deviceNameProvider();
    final devicePlatform = await _devicePlatformProvider?.call();
    final deviceBrand = await _deviceBrandProvider?.call();
    final deviceModel = await _deviceModelProvider?.call();

    final dio = Dio();
    final useTlsPinning = Uri.parse(normalizedServerUrl).scheme == 'https';
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        if (!useTlsPinning) {
          return HttpClient();
        }
        final context = SecurityContext(withTrustedRoots: false);
        context.setTrustedCertificatesBytes(utf8.encode(certificate));
        return HttpClient(context: context);
      },
    );

    try {
      final response = await dio.post(
        '$normalizedServerUrl/api/v1/auth/credential-device-enroll',
        options: Options(
          headers: {
            'Authorization': _encodeBasicAuth(trimmedUsername, trimmedPassword),
          },
        ),
        data: {
          'device_id': deviceId,
          'physical_device_id': physicalDeviceId,
          'device_name': deviceName,
          if ((devicePlatform?.trim().isNotEmpty ?? false))
            'device_platform': devicePlatform!.trim(),
          if ((deviceBrand?.trim().isNotEmpty ?? false))
            'device_brand': deviceBrand!.trim(),
          if ((deviceModel?.trim().isNotEmpty ?? false))
            'device_model': deviceModel!.trim(),
        },
      );

      final payload = response.data;
      if (payload is! Map) {
        throw const AppException(
          code: 'INVALID_ENROLLMENT_RESPONSE',
          message: '服务器返回的设备注册数据无效',
        );
      }

      final serverId = payload['serverId'] as String? ?? '';
      final baseUrl = payload['baseUrl'] as String? ?? normalizedServerUrl;
      final rootCaPem = payload['rootCaPem'] as String? ?? certificate;
      final caSha256 = payload['caSha256'] as String? ?? '';
      final enrolledDeviceId = payload['deviceId'] as String? ?? deviceId;
      final accessToken = payload['accessToken'] as String? ?? '';
      final refreshToken = payload['refreshToken'] as String? ?? '';

      if (serverId.trim().isEmpty ||
          enrolledDeviceId.trim().isEmpty ||
          accessToken.trim().isEmpty ||
          refreshToken.trim().isEmpty) {
        throw const AppException(
          code: 'INVALID_ENROLLMENT_RESPONSE',
          message: '服务器返回的设备令牌无效',
        );
      }

      final normalizedCaSha256 = _normalizeFingerprint(caSha256);
      final normalizedCertFingerprint = _normalizeFingerprint(
        certificateFingerprint,
      );
      if (normalizedCaSha256.isNotEmpty &&
          normalizedCertFingerprint != normalizedCaSha256) {
        throw const AppException(
          code: 'FINGERPRINT_MISMATCH',
          message: '服务器证书指纹不匹配，请检查网络环境',
        );
      }

      await _trustedServerStore.trustServer(
        serverId: serverId.trim(),
        baseUrl: baseUrl.trim(),
        rootCaPem: rootCaPem,
        caSha256: caSha256.isNotEmpty ? caSha256 : certificateFingerprint,
      );

      return PairingResult(
        serverId: serverId.trim(),
        baseUrl: baseUrl.trim(),
        certificate: rootCaPem,
        deviceId: enrolledDeviceId.trim(),
        accessToken: accessToken.trim(),
        refreshToken: refreshToken.trim(),
        sessionId: payload['sessionId'] as String?,
        accessExpiresAt: _parseExpiresAt(payload['accessExpiresAt']),
      );
    } on DioException catch (e) {
      throw _mapDioException(
        e,
        defaultCode: 'CREDENTIAL_ENROLL_ERROR',
        defaultMessage: '账密设备注册失败',
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException(
        code: 'CREDENTIAL_ENROLL_ERROR',
        message: '账密设备注册失败: $e',
      );
    } finally {
      dio.close();
    }
  }

  /// 下载服务器 CA 证书（首次连接，不校验指纹）
  Future<String> _downloadCertificate(String serverUrl) async {
    final tempDio = Dio();
    tempDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );

    try {
      final response = await tempDio.get('$serverUrl/api/v1/pairing/ca-cert');
      final certPem = response.data['cert'] as String? ?? '';
      if (certPem.isEmpty) {
        throw const AppException(
          code: 'EMPTY_CERTIFICATE',
          message: '服务器返回的证书为空',
        );
      }
      return certPem;
    } on DioException catch (e) {
      throw _mapDioException(
        e,
        defaultCode: 'CERT_DOWNLOAD_ERROR',
        defaultMessage: '下载证书失败',
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException(code: 'CERT_DOWNLOAD_ERROR', message: '下载证书失败: $e');
    } finally {
      tempDio.close();
    }
  }

  /// 下载并验证证书
  Future<String> _downloadAndVerifyCertificate({
    required String serverUrl,
    required String expectedFingerprint,
  }) async {
    // 创建临时的 Dio 实例，忽略证书验证
    final tempDio = Dio();
    tempDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );

    try {
      // 下载证书
      final response = await tempDio.get('$serverUrl/api/v1/pairing/ca-cert');
      final certPem = response.data['cert'] as String? ?? '';

      if (certPem.isEmpty) {
        throw const AppException(
          code: 'EMPTY_CERTIFICATE',
          message: '服务器返回的证书为空',
        );
      }

      // 验证指纹
      final actualFingerprint = await _calculateFingerprint(certPem);
      final normalizedExpected = _normalizeFingerprint(expectedFingerprint);
      final normalizedActual = _normalizeFingerprint(actualFingerprint);

      if (normalizedActual != normalizedExpected) {
        throw AppException(
          code: 'FINGERPRINT_MISMATCH',
          message:
              '证书指纹不匹配！\n'
              '预期: $expectedFingerprint\n'
              '实际: $actualFingerprint\n'
              '可能存在中间人攻击，请检查网络环境。',
        );
      }

      return certPem;
    } on DioException catch (e) {
      throw _mapDioException(
        e,
        defaultCode: 'CERT_DOWNLOAD_ERROR',
        defaultMessage: '下载证书失败',
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException(code: 'CERT_VERIFY_ERROR', message: '证书验证失败: $e');
    } finally {
      tempDio.close();
    }
  }

  /// 请求设备注册加密令牌
  Future<_DeviceEnrollment> _requestDeviceEnrollment({
    required String serverUrl,
    required String serverId,
    required Uint8List serverPublicKey,
    required String certificate,
  }) async {
    // 生成客户端临时 X25519 密钥对
    final clientKeyPair = await _generateX25519KeyPair();
    final deviceId = DeviceIdNormalizer.normalizeRequired(
      await _deviceIdProvider(),
    );
    final physicalDeviceId = deviceId;
    final deviceName = await _deviceNameProvider();
    final devicePlatform = await _devicePlatformProvider?.call();
    final deviceBrand = await _deviceBrandProvider?.call();
    final deviceModel = await _deviceModelProvider?.call();

    // 创建带证书验证的 Dio
    final dio = Dio();
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final context = SecurityContext(withTrustedRoots: false);
        context.setTrustedCertificatesBytes(utf8.encode(certificate));
        return HttpClient(context: context);
      },
    );

    try {
      // 发送设备注册请求
      final response = await dio.post(
        '$serverUrl/api/v1/pairing/device-enroll',
        data: {
          'client_pub': base64UrlEncode(clientKeyPair.publicKey),
          'server_id': serverId,
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'device_id': deviceId,
          'physical_device_id': physicalDeviceId,
          'device_name': deviceName,
          if ((devicePlatform?.trim().isNotEmpty ?? false))
            'device_platform': devicePlatform!.trim(),
          if ((deviceBrand?.trim().isNotEmpty ?? false))
            'device_brand': deviceBrand!.trim(),
          if ((deviceModel?.trim().isNotEmpty ?? false))
            'device_model': deviceModel!.trim(),
        },
      );

      // 解密设备令牌
      final encryptedCredential = base64Url.decode(
        base64Url.normalize(
          response.data['encrypted_enrollment'] as String? ??
              response.data['encrypted_credential'] as String? ??
              '',
        ),
      );
      final responseServerPub = base64Url.decode(
        base64Url.normalize(response.data['server_pub'] as String? ?? ''),
      );

      if (encryptedCredential.isEmpty || responseServerPub.isEmpty) {
        throw const AppException(
          code: 'INVALID_CREDENTIAL_RESPONSE',
          message: '服务器返回的凭据数据无效',
        );
      }
      if (!_bytesEqual(responseServerPub, serverPublicKey)) {
        throw const AppException(
          code: 'PAIRING_SESSION_MISMATCH',
          message: '配对会话已变化，请重新扫描服务端连接二维码',
        );
      }

      // ECDH 计算共享密钥
      final sharedSecret = await _computeSharedSecret(
        privateKey: clientKeyPair.privateKey,
        publicKey: responseServerPub,
      );

      // 派生 AES 密钥
      final aesKey = await _deriveAesKey(
        sharedSecret: sharedSecret,
        serverId: serverId,
        info: 'pairing-device-enrollment-v1',
      );

      // 解密
      final enrollmentJson = await _decryptPayload(
        encrypted: encryptedCredential,
        key: aesKey,
      );

      final enrolledDeviceId =
          enrollmentJson['deviceId'] as String? ?? deviceId;
      final accessToken = enrollmentJson['accessToken'] as String? ?? '';
      final refreshToken = enrollmentJson['refreshToken'] as String? ?? '';
      if (enrolledDeviceId.trim().isEmpty ||
          accessToken.trim().isEmpty ||
          refreshToken.trim().isEmpty) {
        throw const AppException(
          code: 'INVALID_ENROLLMENT_RESPONSE',
          message: '服务器返回的设备令牌无效',
        );
      }

      final accessExpiresAt = _parseExpiresAt(
        enrollmentJson['accessExpiresAt'] ?? enrollmentJson['expiresAt'],
      );

      return _DeviceEnrollment(
        deviceId: enrolledDeviceId.trim(),
        accessToken: accessToken.trim(),
        refreshToken: refreshToken.trim(),
        sessionId: enrollmentJson['sessionId'] as String?,
        accessExpiresAt: accessExpiresAt,
      );
    } on DioException catch (e) {
      throw _mapDioException(
        e,
        defaultCode: 'CREDENTIAL_REQUEST_ERROR',
        defaultMessage: '请求凭据失败',
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException(
        code: 'CREDENTIAL_DECRYPT_ERROR',
        message: '解密凭据失败: $e',
      );
    } finally {
      dio.close();
    }
  }

  // === 私有方法 ===

  Future<String> _calculateFingerprint(String pem) async {
    final derBytes = _pemToDer(pem);
    final hash = await Sha256().hash(derBytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _normalizeFingerprint(String fingerprint) {
    return fingerprint
        .toLowerCase()
        .replaceAll(':', '')
        .replaceAll(' ', '')
        .trim();
  }

  String _encodeBasicAuth(String username, String password) {
    final credentials = utf8.encode('$username:$password');
    return 'Basic ${base64Encode(credentials)}';
  }

  Uint8List _pemToDer(String pem) {
    final lines = pem
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return base64Decode(lines);
  }

  Future<_X25519KeyPair> _generateX25519KeyPair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final publicKey = await keyPair.extractPublicKey();

    return _X25519KeyPair(
      privateKey: Uint8List.fromList(keyPairData.bytes),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  Future<Uint8List> _computeSharedSecret({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKey);

    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );

    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  Future<Uint8List> _deriveAesKey({
    required Uint8List sharedSecret,
    required String serverId,
    String info = 'pairing-device-enrollment-v1',
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    final secretKey = await hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: utf8.encode(serverId),
      info: utf8.encode(info),
    );

    return Uint8List.fromList(await secretKey.extractBytes());
  }

  Future<Map<String, dynamic>> _decryptPayload({
    required Uint8List encrypted,
    required Uint8List key,
  }) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(key);

    // 解析: nonce(12) + ciphertext + mac(16)
    if (encrypted.length < 28) {
      throw const AppException(
        code: 'INVALID_ENCRYPTED_DATA',
        message: '加密数据长度不足',
      );
    }

    final nonce = encrypted.sublist(0, 12);
    final cipherText = encrypted.sublist(12, encrypted.length - 16);
    final mac = encrypted.sublist(encrypted.length - 16);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));

    final plaintext = await algorithm.decrypt(secretBox, secretKey: secretKey);
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  DateTime? _parseExpiresAt(Object? rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return DateTime.tryParse(rawValue)?.toUtc();
    }
    if (rawValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(rawValue * 1000, isUtc: true);
    }
    if (rawValue is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        rawValue.toInt() * 1000,
        isUtc: true,
      );
    }
    return null;
  }

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  AppException _mapDioException(
    DioException error, {
    required String defaultCode,
    required String defaultMessage,
  }) {
    final responseData = error.response?.data;
    if (responseData is Map) {
      final mapped = Map<String, dynamic>.from(responseData);
      final serverMessage = mapped['message']?.toString().trim() ?? '';
      final serverCode = mapped['code']?.toString().trim() ?? '';
      if (serverMessage.isNotEmpty) {
        return AppException(
          code: serverCode.isEmpty ? defaultCode : serverCode,
          message: serverMessage,
          originalError: error,
          stackTrace: error.stackTrace,
        );
      }
    }

    if (responseData is String && responseData.trim().isNotEmpty) {
      return AppException(
        code: defaultCode,
        message: responseData.trim(),
        originalError: error,
        stackTrace: error.stackTrace,
      );
    }

    final dioMessage = error.message?.trim() ?? '';
    return AppException(
      code: defaultCode,
      message: dioMessage.isEmpty
          ? defaultMessage
          : '$defaultMessage: $dioMessage',
      originalError: error,
      stackTrace: error.stackTrace,
    );
  }
}

class _X25519KeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;

  _X25519KeyPair({required this.privateKey, required this.publicKey});
}

class _DeviceEnrollment {
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final String? sessionId;
  final DateTime? accessExpiresAt;

  _DeviceEnrollment({
    required this.deviceId,
    required this.accessToken,
    required this.refreshToken,
    this.sessionId,
    this.accessExpiresAt,
  });
}
