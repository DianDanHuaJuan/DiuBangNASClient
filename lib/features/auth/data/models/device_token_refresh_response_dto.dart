class DeviceTokenRefreshResponseDto {
  const DeviceTokenRefreshResponseDto({
    required this.deviceId,
    required this.accessToken,
    required this.sessionId,
    this.expiresAt,
  });

  final String deviceId;
  final String accessToken;
  final String sessionId;
  final String? expiresAt;

  DateTime? get expiresAtDateTime {
    final value = expiresAt;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  factory DeviceTokenRefreshResponseDto.fromJson(Map<String, dynamic> json) {
    return DeviceTokenRefreshResponseDto(
      deviceId: json['deviceId'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      expiresAt: json['expiresAt'] as String?,
    );
  }
}
