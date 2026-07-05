/// 与服务端 DeviceStore._normalizeDeviceId 保持一致。
class DeviceIdNormalizer {
  DeviceIdNormalizer._();

  static final RegExp _whitespace = RegExp(r'\s+');

  static String? normalize(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().replaceAll(_whitespace, '-');
    return normalized.isEmpty ? null : normalized;
  }

  static String normalizeRequired(String value) {
    return normalize(value) ?? '';
  }
}
