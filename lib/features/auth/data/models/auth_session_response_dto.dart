class AuthSessionResponseDto {
  const AuthSessionResponseDto({
    required this.accountId,
    required this.role,
    required this.sessionId,
    required this.accessToken,
    String? clientId,
    String? deviceId,
    this.expiresAt,
  }) : deviceId = deviceId ?? clientId;

  final String accountId;
  final String role;
  final String? deviceId;
  final String sessionId;
  final String accessToken;
  final String? expiresAt;
  String? get clientId => deviceId;

  DateTime? get expiresAtDateTime {
    final value = expiresAt;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  factory AuthSessionResponseDto.fromJson(Map<String, dynamic> json) {
    final resolvedDeviceId =
        json['deviceId'] as String? ?? json['clientId'] as String?;
    return AuthSessionResponseDto(
      accountId: json['accountId'] as String? ?? '',
      role: json['role'] as String? ?? 'client',
      clientId: resolvedDeviceId,
      deviceId: resolvedDeviceId,
      sessionId: json['sessionId'] as String? ?? '',
      accessToken: json['accessToken'] as String? ?? '',
      expiresAt: json['expiresAt'] as String?,
    );
  }
}
