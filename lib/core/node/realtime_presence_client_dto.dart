class RealtimePresenceClientDto {
  const RealtimePresenceClientDto({
    required this.deviceId,
    required this.status,
    this.accountId,
    this.label,
    this.role,
    this.deviceName,
    this.platform,
    this.brand,
    this.model,
    this.reportedRouteIp,
    this.observedRemoteIp,
    this.appVersion,
    this.connectionId,
    this.sessionId,
    this.connectedAt,
    this.lastSeenAt,
    this.avatarUpdatedAt,
  });

  final String deviceId;
  String get clientId => deviceId;
  final String status;
  final String? accountId;
  final String? label;
  final String? role;
  final String? deviceName;
  final String? platform;
  final String? brand;
  final String? model;
  final String? reportedRouteIp;
  final String? observedRemoteIp;
  final String? appVersion;
  final String? connectionId;
  final String? sessionId;
  final DateTime? connectedAt;
  final DateTime? lastSeenAt;
  final DateTime? avatarUpdatedAt;

  factory RealtimePresenceClientDto.fromJson(Map<String, dynamic> json) {
    final deviceId = _requireString(
      json['deviceId'] ?? json['clientId'],
      field: 'deviceId',
    );
    return RealtimePresenceClientDto(
      deviceId: deviceId,
      status: _optionalString(json['status']) ?? 'online',
      accountId: _optionalString(json['accountId']),
      label: _optionalString(json['label']),
      role: _optionalString(json['role']),
      deviceName: _optionalString(json['deviceName']),
      platform: _optionalString(json['platform']),
      brand: _optionalString(json['brand']),
      model: _optionalString(json['model']),
      reportedRouteIp: _optionalString(json['reportedRouteIp']),
      observedRemoteIp: _optionalString(json['observedRemoteIp']),
      appVersion: _optionalString(json['appVersion']),
      connectionId: _optionalString(json['connectionId']),
      sessionId: _optionalString(json['sessionId']),
      connectedAt: _optionalDateTime(json['connectedAt']),
      lastSeenAt: _optionalDateTime(json['lastSeenAt']),
      avatarUpdatedAt: _optionalDateTime(json['avatarUpdatedAt']),
    );
  }
}

String _requireString(Object? value, {required String field}) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _optionalDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}
