import 'server_display_name_policy.dart';

/// 从 bootstrap / mDNS serviceName / QR 等权威通道解析服务器显示名。
abstract final class ServerDisplayNameResolver {
  static const String fallbackDisplayName = 'NAS 服务器';

  /// 优先级：bootstrap > mDNS serviceName > QR `n`。
  static String resolve({
    String? bootstrapName,
    String? mdnsServiceName,
    String? qrName,
  }) {
    for (final candidate in [bootstrapName, mdnsServiceName, qrName]) {
      final name = candidate?.trim();
      if (name != null &&
          name.isNotEmpty &&
          ServerDisplayNamePolicy.isUsableDisplayName(name)) {
        return name;
      }
    }
    return fallbackDisplayName;
  }
}
