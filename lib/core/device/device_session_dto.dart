/// 文件输入：设备配对返回的令牌 JSON
/// 文件职责：解析与序列化按 serverId 持久化的设备会话
/// 文件对外接口：DeviceSessionDto
/// 文件包含：DeviceSessionDto
class DeviceSessionDto {
  const DeviceSessionDto({
    required this.deviceId,
    required this.accessToken,
    required this.refreshToken,
    this.sessionId,
    this.expiresAt,
  });

  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final String? sessionId;
  final String? expiresAt;

  DateTime? get expiresAtDateTime {
    final value = expiresAt;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  factory DeviceSessionDto.fromJson(Map<String, dynamic> json) {
    return DeviceSessionDto(
      deviceId: json['deviceId'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      expiresAt: json['expiresAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      if (sessionId != null) 'sessionId': sessionId,
      if (expiresAt != null) 'expiresAt': expiresAt,
    };
  }
}
