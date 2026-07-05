/// 文件输入：本地存储的会话 JSON
/// 文件职责：解析会话 DTO
/// 文件对外接口：AuthSessionDto
/// 文件包含：AuthSessionDto
class AuthSessionDto {
  final String serverUrl;
  final String serverId;
  final String serverName;
  final String? username;
  final String? accountId;
  final String role;
  final String? deviceId;
  final String sessionId;
  final String accessToken;
  final String? refreshToken;
  final String? expiresAt;
  final String protocol;
  final String rootId;
  final String rootName;
  String? get clientId => deviceId;

  const AuthSessionDto({
    required this.serverUrl,
    required this.serverId,
    required this.serverName,
    this.username,
    this.accountId,
    required this.role,
    required this.sessionId,
    required this.accessToken,
    required this.protocol,
    required this.rootId,
    required this.rootName,
    String? clientId,
    String? deviceId,
    this.refreshToken,
    this.expiresAt,
  }) : deviceId = deviceId ?? clientId;

  factory AuthSessionDto.fromJson(Map<String, dynamic> json) {
    final resolvedDeviceId =
        json['deviceId'] as String? ?? json['clientId'] as String?;
    return AuthSessionDto(
      serverUrl: json['serverUrl'] as String? ?? '',
      serverId: json['serverId'] as String? ?? '',
      serverName: json['serverName'] as String? ?? '',
      username: json['username'] as String?,
      accountId: json['accountId'] as String?,
      role: json['role'] as String? ?? 'device',
      clientId: resolvedDeviceId,
      deviceId: resolvedDeviceId,
      sessionId: json['sessionId'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      expiresAt: json['expiresAt'] as String?,
      protocol: json['protocol'] as String? ?? 'webdav',
      rootId: json['rootId'] as String? ?? '',
      rootName: json['rootName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'serverId': serverId,
      'serverName': serverName,
      'username': username,
      'accountId': accountId,
      'role': role,
      'clientId': deviceId,
      'deviceId': deviceId,
      'sessionId': sessionId,
      'accessToken': accessToken,
      if (refreshToken != null) 'refreshToken': refreshToken,
      'expiresAt': expiresAt,
      'protocol': protocol,
      'rootId': rootId,
      'rootName': rootName,
    };
  }
}
