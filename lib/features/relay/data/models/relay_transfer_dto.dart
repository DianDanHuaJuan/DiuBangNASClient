import '../../domain/entities/relay_peer_history_page.dart';
import '../../domain/entities/relay_transfer_entity.dart';
import '../../debug/relay_diagnostic_log.dart';

class RelayTransferDto {
  static RelayTransferEntity fromJson(Map<String, dynamic> json) {
    final transferId = _requireString(json['transferId'], field: 'transferId');
    final targetsJson = json['targets'];
    if (targetsJson is! List) {
      throw const FormatException('targets must be a list');
    }
    final artifactJson = _requireMap(json['artifact'], field: 'artifact');

    try {
      return _buildEntity(json, transferId, targetsJson, artifactJson);
    } on FormatException catch (error) {
      relayDiag(
        'dto_parse_fail',
        fields: <String, Object?>{
          'transferId': transferId,
          'status': json['status'],
          'error': error.message,
          'tempPath': artifactJson['tempPath'],
          'sealedPath': artifactJson['sealedPath'],
          'cleanupState': artifactJson['cleanupState'],
        },
      );
      rethrow;
    }
  }

  static RelayTransferEntity _buildEntity(
    Map<String, dynamic> json,
    String transferId,
    List<dynamic> targetsJson,
    Map<String, dynamic> artifactJson,
  ) {
    return RelayTransferEntity(
      transferId: transferId,
      senderAccountId: _requireString(
        json['senderAccountId'],
        field: 'senderAccountId',
      ),
      senderLabel: _requireString(json['senderLabel'], field: 'senderLabel'),
      senderClientId: _requireString(
        json['senderClientId'],
        field: 'senderClientId',
      ),
      targetCount: _requireInt(json['targetCount'], field: 'targetCount'),
      fileName: _requireString(json['fileName'], field: 'fileName'),
      mimeType: _optionalString(json['mimeType']),
      fileSize: _requireInt(json['fileSize'], field: 'fileSize'),
      checksum: _optionalString(json['checksum']),
      checksumAlgorithm: _optionalString(json['checksumAlgorithm']) ?? 'sha256',
      chunkSize: _requireInt(json['chunkSize'], field: 'chunkSize'),
      storageMode: _requireString(json['storageMode'], field: 'storageMode'),
      status: _parseTransferStatus(json['status']),
      retryOfTransferId: _optionalString(json['retryOfTransferId']),
      createdAt: _requireDateTime(json['createdAt'], field: 'createdAt'),
      updatedAt: _requireDateTime(json['updatedAt'], field: 'updatedAt'),
      expiresAt: _requireDateTime(json['expiresAt'], field: 'expiresAt'),
      expiredAt: _optionalDateTime(json['expiredAt']),
      readyAt: _optionalDateTime(json['readyAt']),
      completedAt: _optionalDateTime(json['completedAt']),
      cancelledAt: _optionalDateTime(json['cancelledAt']),
      failedAt: _optionalDateTime(json['failedAt']),
      interruptedAt: _optionalDateTime(json['interruptedAt']),
      failureCode: _optionalString(json['failureCode']),
      failureMessage: _optionalString(json['failureMessage']),
      transport: _optionalTransport(json['transport']),
      targets: targetsJson
          .map(
            (item) => RelayTransferTargetEntity(
              transferId: transferId,
              receiverClientId: _requireString(
                _requireMap(item, field: 'targets entry')['receiverClientId'],
                field: 'receiverClientId',
              ),
              deliveryState: _parseTargetState(
                _requireMap(item, field: 'targets entry')['deliveryState'],
              ),
              deliveredAt: _optionalDateTime(
                _requireMap(item, field: 'targets entry')['deliveredAt'],
              ),
              downloadStartedAt: _optionalDateTime(
                _requireMap(item, field: 'targets entry')['downloadStartedAt'],
              ),
              downloadCompletedAt: _optionalDateTime(
                _requireMap(
                  item,
                  field: 'targets entry',
                )['downloadCompletedAt'],
              ),
              updatedAt: _requireDateTime(
                _requireMap(item, field: 'targets entry')['updatedAt'],
                field: 'updatedAt',
              ),
            ),
          )
          .toList(growable: false),
      artifact: RelayTransferArtifactEntity(
        transferId: transferId,
        tempPath: _parseArtifactTempPath(artifactJson, transferId),
        sealedPath: _optionalString(artifactJson['sealedPath']),
        chunkCount: _requireInt(
          artifactJson['chunkCount'],
          field: 'chunkCount',
        ),
        receivedBytes: _requireInt(
          artifactJson['receivedBytes'],
          field: 'receivedBytes',
        ),
        isSealed: _requireBool(artifactJson['isSealed'], field: 'isSealed'),
        cleanupState: _parseCleanupState(artifactJson['cleanupState']),
        updatedAt: _requireDateTime(
          artifactJson['updatedAt'],
          field: 'artifact.updatedAt',
        ),
      ),
    );
  }

  static Map<String, dynamic> requireEnvelopeTransfer(dynamic json) {
    final body = _requireMap(json, field: 'response');
    return _requireMap(body['transfer'], field: 'transfer');
  }

  static List<Map<String, dynamic>> requireEnvelopeTransfers(dynamic json) {
    final body = _requireMap(json, field: 'response');
    final transfers = body['transfers'];
    if (transfers is! List) {
      throw const FormatException('transfers must be a list');
    }
    return transfers
        .map((item) => _requireMap(item, field: 'transfers entry'))
        .toList(growable: false);
  }

  static List<RelayTransferEntity> parseTransferList(
    Iterable<Map<String, dynamic>> rawTransfers, {
    required String context,
  }) {
    final parsed = <RelayTransferEntity>[];
    var index = 0;
    for (final raw in rawTransfers) {
      relayDiag(
        'parse_attempt',
        fields: <String, Object?>{
          'context': context,
          'index': index,
          'transferId': raw['transferId'],
          'status': raw['status'],
        },
      );
      final artifact = raw['artifact'];
      if (artifact is Map) {
        relayDiagArtifactJson(
          '$context#$index',
          artifact.cast<String, dynamic>(),
        );
      }
      try {
        parsed.add(RelayTransferDto.fromJson(raw));
      } on FormatException catch (error) {
        relayDiag(
          'batch_parse_skip',
          fields: <String, Object?>{
            'context': context,
            'index': index,
            'parsedSoFar': parsed.length,
            'transferId': raw['transferId'],
            'error': error.message,
          },
        );
      }
      index += 1;
    }
    relayDiag(
      'parse_ok',
      fields: <String, Object?>{
        'context': context,
        'count': parsed.length,
      },
    );
    return parsed;
  }

  static RelayTransferEntity parseEnvelopeTransfer(
    dynamic json, {
    required String context,
  }) {
    final raw = requireEnvelopeTransfer(json);
    relayDiag(
      'parse_envelope_transfer',
      fields: <String, Object?>{
        'context': context,
        'transferId': raw['transferId'],
        'status': raw['status'],
      },
    );
    final artifact = raw['artifact'];
    if (artifact is Map) {
      relayDiagArtifactJson(context, artifact.cast<String, dynamic>());
    }
    return RelayTransferDto.fromJson(raw);
  }

  static RelayPeerHistoryPage requirePeerHistoryPage(dynamic json) {
    final body = _requireMap(json, field: 'response');
    final transfers = body['transfers'];
    if (transfers is! List) {
      throw const FormatException('transfers must be a list');
    }
    final hasMore = body['hasMore'] == true;
    final rawMaps = transfers
        .map((item) => _requireMap(item, field: 'transfers entry'))
        .toList(growable: false);
    return RelayPeerHistoryPage(
      transfers: parseTransferList(rawMaps, context: 'peerHistory'),
      hasMore: hasMore,
    );
  }
}

RelayTransportEntity? _optionalTransport(Object? value) {
  final transportJson = _optionalMap(value);
  if (transportJson == null) {
    return null;
  }
  final uploadJson = _requireMap(transportJson['upload'], field: 'upload');
  final downloadJson = _requireMap(
    transportJson['download'],
    field: 'download',
  );
  return RelayTransportEntity(
    protocol: _requireString(transportJson['protocol'], field: 'protocol'),
    upload: RelayTransportEndpointEntity(
      method: _requireString(uploadJson['method'], field: 'upload.method'),
      path: _requireString(uploadJson['path'], field: 'upload.path'),
      supportsRange: _optionalBool(uploadJson['supportsRange']) ?? false,
    ),
    download: RelayTransportEndpointEntity(
      method: _requireString(downloadJson['method'], field: 'download.method'),
      path: _requireString(downloadJson['path'], field: 'download.path'),
      supportsRange: _optionalBool(downloadJson['supportsRange']) ?? false,
    ),
    thumbnailUpload: _optionalEndpoint(transportJson['thumbnailUpload']),
    thumbnailDownload: _optionalEndpoint(transportJson['thumbnailDownload']),
  );
}

RelayTransportEndpointEntity? _optionalEndpoint(Object? value) {
  final json = _optionalMap(value);
  if (json == null) {
    return null;
  }
  return RelayTransportEndpointEntity(
    method: _requireString(json['method'], field: 'endpoint.method'),
    path: _requireString(json['path'], field: 'endpoint.path'),
    supportsRange: _optionalBool(json['supportsRange']) ?? false,
  );
}

Map<String, dynamic> _requireMap(Object? value, {required String field}) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  throw FormatException('$field must be a JSON object');
}

Map<String, dynamic>? _optionalMap(Object? value) {
  if (value == null) {
    return null;
  }
  return _requireMap(value, field: 'map');
}

String _requireString(Object? value, {required String field}) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}

int _requireInt(Object? value, {required String field}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('$field must be an integer');
}

bool _requireBool(Object? value, {required String field}) {
  if (value is bool) {
    return value;
  }
  throw FormatException('$field must be a boolean');
}

bool? _optionalBool(Object? value) {
  if (value is bool) {
    return value;
  }
  return null;
}

DateTime _requireDateTime(Object? value, {required String field}) {
  final parsed = _optionalDateTime(value);
  if (parsed == null) {
    throw FormatException('$field must be an ISO8601 string');
  }
  return parsed;
}

DateTime? _optionalDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toLocal();
}

RelayTransferStatus _parseTransferStatus(Object? value) {
  final raw = _requireString(value, field: 'status');
  return RelayTransferStatus.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => throw FormatException('Unknown relay transfer status: $raw'),
  );
}

RelayTransferTargetState _parseTargetState(Object? value) {
  final raw = _requireString(value, field: 'deliveryState');
  return RelayTransferTargetState.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => throw FormatException('Unknown relay target state: $raw'),
  );
}

RelayArtifactCleanupState _parseCleanupState(Object? value) {
  final raw = _requireString(value, field: 'cleanupState');
  return RelayArtifactCleanupState.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => throw FormatException('Unknown relay cleanup state: $raw'),
  );
}

String _parseArtifactTempPath(
  Map<String, dynamic> artifactJson,
  String transferId,
) {
  final cleanupState = _parseCleanupState(artifactJson['cleanupState']);
  final raw = artifactJson['tempPath'];
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.trim();
  }
  if (cleanupState == RelayArtifactCleanupState.deleted) {
    return '/purged/$transferId';
  }
  throw const FormatException('tempPath must be a non-empty string');
}
