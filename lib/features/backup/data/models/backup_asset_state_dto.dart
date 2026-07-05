class BackupAssetStateDto {
  final String serverId;
  final String rootId;
  final String sourceFingerprint;
  final String sourceId;
  final String displayName;
  final String localPath;
  final int sizeBytes;
  final int modifiedMs;
  final String? mimeType;
  final String contentHash;
  final String remotePath;
  final DateTime updatedAt;

  const BackupAssetStateDto({
    required this.serverId,
    required this.rootId,
    required this.sourceFingerprint,
    required this.sourceId,
    required this.displayName,
    required this.localPath,
    required this.sizeBytes,
    required this.modifiedMs,
    this.mimeType,
    required this.contentHash,
    required this.remotePath,
    required this.updatedAt,
  });

  factory BackupAssetStateDto.fromMap(Map<String, Object?> map) {
    return BackupAssetStateDto(
      serverId: map['server_id'] as String,
      rootId: map['root_id'] as String,
      sourceFingerprint: map['source_fingerprint'] as String,
      sourceId: map['source_id'] as String,
      displayName: map['display_name'] as String,
      localPath: map['local_path'] as String,
      sizeBytes: map['size_bytes'] as int,
      modifiedMs: map['modified_ms'] as int,
      mimeType: map['mime_type'] as String?,
      contentHash: map['content_hash'] as String,
      remotePath: map['remote_path'] as String,
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'server_id': serverId,
      'root_id': rootId,
      'source_fingerprint': sourceFingerprint,
      'source_id': sourceId,
      'display_name': displayName,
      'local_path': localPath,
      'size_bytes': sizeBytes,
      'modified_ms': modifiedMs,
      'mime_type': mimeType,
      'content_hash': contentHash,
      'remote_path': remotePath,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
