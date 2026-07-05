/// 文件输入：服务器基地址或媒体绝对地址
/// 文件职责：统一规范 NAS 访问策略，仅允许 HTTPS 地址
/// 文件对外接口：NasNetworkAccessPolicy
/// 文件包含：NasNetworkAccessPolicy
import 'dart:io';

import '../error/app_exception.dart';

class NasNetworkAccessPolicy {
  static const String _httpScheme = 'http';
  static const String _httpsScheme = 'https';

  static String normalizeServerUrl(String rawUrl) {
    final uri = _parseServerUri(rawUrl);
    _ensureAllowedUri(uri);
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static String normalizeAbsoluteUrl(String rawUrl) {
    final uri = _parseAbsoluteUri(
      rawUrl,
      invalidCode: 'REMOTE_URL_INVALID',
      invalidMessage: '服务器返回的地址格式无效',
    );
    _ensureAllowedUri(uri);
    return uri.toString();
  }

  static bool isPrivateOrLocalHost(String host) {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty) {
      return false;
    }
    if (normalizedHost == 'localhost' ||
        normalizedHost.endsWith('.local') ||
        normalizedHost.endsWith('.lan') ||
        normalizedHost.endsWith('.home.arpa')) {
      return true;
    }

    final strippedHost = _stripIpv6ZoneId(normalizedHost);
    final address = InternetAddress.tryParse(strippedHost);
    if (address == null) {
      return false;
    }

    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      return _isPrivateOrLocalIpv4(bytes);
    }
    if (bytes.length == 16) {
      return _isPrivateOrLocalIpv6(bytes);
    }
    return false;
  }

  static Uri _parseServerUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const AppException(code: 'SERVER_URL_EMPTY', message: '请输入服务器地址');
    }

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return _parseAbsoluteUri(
      candidate,
      invalidCode: 'SERVER_URL_INVALID',
      invalidMessage: '服务器地址格式无效',
    );
  }

  static Uri _parseAbsoluteUri(
    String rawUrl, {
    required String invalidCode,
    required String invalidMessage,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.trim().isEmpty) {
      throw AppException(code: invalidCode, message: invalidMessage);
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != _httpScheme && scheme != _httpsScheme) {
      throw AppException(code: invalidCode, message: '仅支持 HTTPS 地址');
    }

    return uri;
  }

  static void _ensureAllowedUri(Uri uri) {
    if (uri.scheme.toLowerCase() == _httpsScheme) {
      return;
    }
    throw const AppException(
      code: 'HTTP_ADDRESS_NOT_ALLOWED',
      message: '当前版本仅允许通过 HTTPS 连接服务器。',
    );
  }

  static String _stripIpv6ZoneId(String host) {
    final separatorIndex = host.indexOf('%');
    if (separatorIndex == -1) {
      return host;
    }
    return host.substring(0, separatorIndex);
  }

  static bool _isPrivateOrLocalIpv4(List<int> bytes) {
    final first = bytes[0];
    final second = bytes[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 169 && second == 254) ||
        first == 127;
  }

  static bool _isPrivateOrLocalIpv6(List<int> bytes) {
    final first = bytes[0];
    final second = bytes[1];
    final isLoopback =
        bytes.sublist(0, 15).every((value) => value == 0) && bytes[15] == 1;
    final isUniqueLocal = (first & 0xfe) == 0xfc;
    final isLinkLocal = first == 0xfe && (second & 0xc0) == 0x80;
    return isLoopback || isUniqueLocal || isLinkLocal;
  }
}
