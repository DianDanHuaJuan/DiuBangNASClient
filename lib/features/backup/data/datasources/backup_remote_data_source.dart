import '../../../../core/network/nas_api_client.dart';

class BackupRemoteDataSource {
  BackupRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient;

  final NasApiClient _apiClient;

  Future<List<BackupPreflightDecisionDto>> preflight({
    required String rootId,
    required List<BackupPreflightItemDto> items,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/backup/preflight',
      data: {
        'rootId': rootId,
        'items': items.map((item) => item.toJson()).toList(growable: false),
      },
      parser: (json) => Map<String, dynamic>.from(json as Map),
    );

    final rawItems = response['items'];
    if (rawItems is! List) {
      return const <BackupPreflightDecisionDto>[];
    }

    return rawItems
        .whereType<Map>()
        .map(
          (item) => BackupPreflightDecisionDto.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
  }
}

enum BackupPreflightAction { upload, skip, needHash }

class BackupPreflightItemDto {
  final String id;
  final String sourceFingerprint;
  final String? contentHash;
  final String extension;
  final int sizeBytes;
  final int modifiedMs;
  final String? mimeType;

  const BackupPreflightItemDto({
    required this.id,
    required this.sourceFingerprint,
    this.contentHash,
    required this.extension,
    required this.sizeBytes,
    required this.modifiedMs,
    this.mimeType,
  });

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'sourceFingerprint': sourceFingerprint,
      if (contentHash != null && contentHash!.trim().isNotEmpty)
        'contentHash': contentHash,
      'extension': extension,
      'sizeBytes': sizeBytes,
      'modifiedMs': modifiedMs,
      'mimeType': mimeType,
    };
  }
}

class BackupPreflightDecisionDto {
  final String id;
  final BackupPreflightAction action;
  final String relativePath;
  final String reason;

  const BackupPreflightDecisionDto({
    required this.id,
    required this.action,
    required this.relativePath,
    required this.reason,
  });

  factory BackupPreflightDecisionDto.fromJson(Map<String, dynamic> json) {
    final action = switch (json['action'] as String?) {
      'skip' => BackupPreflightAction.skip,
      'need_hash' => BackupPreflightAction.needHash,
      _ => BackupPreflightAction.upload,
    };
    return BackupPreflightDecisionDto(
      id: json['id'] as String,
      action: action,
      relativePath: json['relativePath'] as String? ?? '/',
      reason: json['reason'] as String? ?? '',
    );
  }
}
