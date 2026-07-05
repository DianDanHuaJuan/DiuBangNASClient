/// 判定字符串是否可作为 NAS 服务器 **显示名**（title）。
///
/// OS 主机名（如 DESKTOP-xxx）允许；IP 与空占位符拒绝。
abstract final class ServerDisplayNamePolicy {
  static const _placeholders = {'当前服务器', '已保存服务器', 'NAS 服务器'};

  static bool isRejectedAsDisplayName(String? raw) {
    final normalized = raw?.trim() ?? '';
    if (normalized.isEmpty) {
      return true;
    }
    if (_placeholders.contains(normalized)) {
      return true;
    }
    return _looksLikeIpAddress(normalized);
  }

  static bool isUsableDisplayName(String? raw) {
    return !isRejectedAsDisplayName(raw);
  }

  static bool _looksLikeIpAddress(String value) {
    final hostPort = value.split(':');
    final host = hostPort.first.trim();
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      return true;
    }
    if (host.startsWith('[') && host.endsWith(']')) {
      return true;
    }
    return false;
  }
}
