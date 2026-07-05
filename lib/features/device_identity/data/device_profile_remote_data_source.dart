import 'package:dio/dio.dart';

import '../../../core/network/nas_api_client.dart';
import '../../../core/node/unified_node.dart';

class DeviceProfileRemoteDataSource {
  DeviceProfileRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient;

  final NasApiClient _apiClient;

  Future<DeviceProfileDto> fetchMyProfile() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/me/device-profile',
    );
    return DeviceProfileDto.fromJson(response);
  }

  Future<DeviceProfileDto> updateLabel(String label) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '/api/v1/me/device-profile',
      data: <String, dynamic>{'label': label},
    );
    return DeviceProfileDto.fromJson(response);
  }

  Future<DateTime?> uploadAvatar(List<int> bytes) async {
    final response = await _apiClient.putBytes<Map<String, dynamic>>(
      '/api/v1/me/device-profile/avatar',
      data: bytes,
    );
    final raw = response['avatarUpdatedAt'];
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> deleteAvatar() async {
    await _apiClient.delete<void>('/api/v1/me/device-profile/avatar');
  }

  Future<List<PeerProfileSnapshot>> fetchPeerProfiles(
    Iterable<String> deviceIds,
  ) async {
    final normalizedIds = deviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <PeerProfileSnapshot>[];
    }

    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/devices/profiles',
      queryParameters: <String, dynamic>{'ids': normalizedIds.join(',')},
    );
    final rawProfiles = response['profiles'];
    if (rawProfiles is! List) {
      return const <PeerProfileSnapshot>[];
    }

    final profiles = <PeerProfileSnapshot>[];
    for (final item in rawProfiles) {
      if (item is! Map) {
        continue;
      }
      final map = item.map((key, value) => MapEntry('$key', value));
      final deviceId = '${map['deviceId']}'.trim();
      if (deviceId.isEmpty) {
        continue;
      }
      profiles.add(
        PeerProfileSnapshot(
          deviceId: deviceId,
          label: (map['label'] as String?)?.trim(),
          deviceName: (map['deviceName'] as String?)?.trim(),
          avatarUpdatedAt: _parseDateTime(map['avatarUpdatedAt']),
        ),
      );
    }
    return List<PeerProfileSnapshot>.unmodifiable(profiles);
  }

  Future<List<int>?> downloadPeerAvatar(String deviceId) async {
    try {
      final bytes = await _apiClient.getBytes(
        '/api/v1/devices/$deviceId/avatar',
      );
      if (bytes.isEmpty) {
        return null;
      }
      return bytes;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}

class DeviceProfileDto {
  const DeviceProfileDto({
    required this.deviceId,
    required this.deviceName,
    this.physicalDeviceId,
    this.label,
    this.avatarUpdatedAt,
  });

  final String deviceId;
  final String? physicalDeviceId;
  final String deviceName;
  final String? label;
  final DateTime? avatarUpdatedAt;

  factory DeviceProfileDto.fromJson(Map<String, dynamic> json) {
    return DeviceProfileDto(
      deviceId: '${json['deviceId']}',
      physicalDeviceId: json['physicalDeviceId'] as String?,
      deviceName: '${json['deviceName']}',
      label: (json['label'] as String?)?.trim(),
      avatarUpdatedAt: _parseDateTime(json['avatarUpdatedAt']),
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}
