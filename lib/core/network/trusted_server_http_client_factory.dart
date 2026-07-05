import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../error/app_exception.dart';
import 'trusted_server_store.dart';

class TrustedServerHttpClientFactory {
  TrustedServerHttpClientFactory({required TrustedServerStore trustedServerStore})
    : _trustedServerStore = trustedServerStore;

  final TrustedServerStore _trustedServerStore;

  HttpClient createHttpClient({
    required String baseUrl,
    int maxConnectionsPerHost = 8,
  }) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'wss') {
      throw const AppException(
        code: 'HTTPS_REQUIRED',
        message: '仅支持通过 HTTPS 连接 NAS 服务器。',
      );
    }
    final trustedServer = _trustedServerStore.findByServerUrl(baseUrl);
    if (trustedServer == null) {
      throw const AppException(
        code: 'SERVER_NOT_TRUSTED',
        message: '请先扫描服务端配对二维码完成 HTTPS 配对。',
      );
    }

    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(utf8.encode(trustedServer.rootCaPem));
    final client = HttpClient(context: context);
    client.maxConnectionsPerHost = maxConnectionsPerHost;
    final pinnedLeafSha256 = trustedServer.leafSha256?.trim();
    if (pinnedLeafSha256 != null && pinnedLeafSha256.isNotEmpty) {
      client.badCertificateCallback = (certificate, host, port) {
        final presentedLeafSha256 = _calculateCertificateSha256(certificate.pem);
        return presentedLeafSha256 == pinnedLeafSha256.toLowerCase();
      };
    }
    return client;
  }

  void configureDio(
    Dio dio, {
    required String baseUrl,
    int maxConnectionsPerHost = 8,
  }) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        return createHttpClient(
          baseUrl: baseUrl,
          maxConnectionsPerHost: maxConnectionsPerHost,
        );
      },
    );
  }

  String _calculateCertificateSha256(String pem) {
    final base64Body = pem
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.startsWith('-----BEGIN') &&
              !line.startsWith('-----END'),
        )
        .join();
    final derBytes = base64Decode(base64Body);
    return crypto.sha256.convert(derBytes).toString();
  }
}
