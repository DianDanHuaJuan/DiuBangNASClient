import 'device_alias_constraints.dart';

/// Single source for human-facing device names. Does not participate in identity.
abstract final class DeviceDisplayResolver {
  static String? sanitizeAlias(String? rawValue) {
    final trimmed = rawValue?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (_looksLikeTechnicalClientAlias(trimmed)) {
      return null;
    }
    return trimmed;
  }

  static String publicDisplayName({
    String? alias,
    String? hardwareName,
    String? brand,
    String? model,
    String? platform,
    required String fallback,
  }) {
    final sanitizedAlias = sanitizeAlias(alias);
    if (sanitizedAlias != null) {
      return sanitizedAlias;
    }
    final parts = <String>[
      if (brand != null && brand.trim().isNotEmpty) brand.trim(),
      if (model != null && model.trim().isNotEmpty) model.trim(),
    ];
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
    final platformFallback = _platformDeviceName(platform);
    if (platformFallback != null) {
      return platformFallback;
    }
    final sanitizedHardware = _sanitizePlainName(hardwareName);
    if (sanitizedHardware != null) {
      return sanitizedHardware;
    }
    final sanitizedFallback = _sanitizePlainName(fallback);
    if (sanitizedFallback != null) {
      return sanitizedFallback;
    }
    return '伙伴设备';
  }

  static String? disambiguationSubtitle({
    String? hardwareName,
    String? deviceId,
    String? reportedRouteIp,
  }) {
    final ip = reportedRouteIp?.trim();
    if (ip != null && ip.isNotEmpty) {
      return 'IP: $ip';
    }
    final hardware = _sanitizePlainName(hardwareName);
    if (hardware != null) {
      return hardware;
    }
    final id = deviceId?.trim() ?? '';
    if (id.length <= 8) {
      return id.isEmpty ? null : 'ID: $id';
    }
    return 'ID: ${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  static String localPublicDisplayName({
    String? alias,
    String? hardwareName,
    String fallback = '本机',
  }) {
    final sanitizedAlias = sanitizeAlias(alias);
    if (sanitizedAlias != null) {
      return sanitizedAlias;
    }
    final hardware = _sanitizePlainName(hardwareName);
    if (hardware != null) {
      return hardware;
    }
    return fallback;
  }

  static String? _sanitizePlainName(String? rawValue) {
    final trimmed = rawValue?.trim() ?? '';
    if (trimmed.isEmpty) {
      return null;
    }
    if (_looksLikeTechnicalClientAlias(trimmed)) {
      return null;
    }
    return trimmed;
  }

  static bool _looksLikeTechnicalClientAlias(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.startsWith('扫码接入')) {
      return true;
    }
    return RegExp(
      r'^(android|ios|windows|macos|linux|unknown|web)[_-].+',
    ).hasMatch(normalized);
  }

  static String? _platformDeviceName(String? platform) {
    switch (_normalizedPlatform(platform)) {
      case 'android':
        return '安卓设备';
      case 'ios':
        return 'iOS设备';
      case 'windows':
        return 'Windows设备';
      case 'macos':
        return 'macOS设备';
      case 'linux':
        return 'Linux设备';
      default:
        return null;
    }
  }

  static String _normalizedPlatform(String? platform) {
    final normalized = platform?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.contains('android')) {
      return 'android';
    }
    if (normalized == 'ios' ||
        normalized.contains('iphone') ||
        normalized.contains('ipad')) {
      return 'ios';
    }
    if (normalized.contains('windows') || normalized == 'win32') {
      return 'windows';
    }
    if (normalized.contains('mac') || normalized == 'darwin') {
      return 'macos';
    }
    if (normalized.contains('linux')) {
      return 'linux';
    }
    return normalized;
  }
}
