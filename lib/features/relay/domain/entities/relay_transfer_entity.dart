class RelayTransferEntity {
  const RelayTransferEntity({
    required this.transferId,
    required this.senderAccountId,
    required this.senderLabel,
    required this.senderClientId,
    required this.targetCount,
    required this.fileName,
    this.mimeType,
    required this.fileSize,
    this.checksum,
    required this.checksumAlgorithm,
    required this.chunkSize,
    required this.storageMode,
    required this.status,
    this.retryOfTransferId,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.expiredAt,
    this.readyAt,
    this.completedAt,
    this.cancelledAt,
    this.failedAt,
    this.interruptedAt,
    this.failureCode,
    this.failureMessage,
    this.transport,
    required this.targets,
    required this.artifact,
  });

  final String transferId;
  final String senderAccountId;
  final String senderLabel;
  final String senderClientId;
  final int targetCount;
  final String fileName;
  final String? mimeType;
  final int fileSize;
  final String? checksum;
  final String checksumAlgorithm;
  final int chunkSize;
  final String storageMode;
  final RelayTransferStatus status;
  final String? retryOfTransferId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final DateTime? expiredAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? failedAt;
  final DateTime? interruptedAt;
  final String? failureCode;
  final String? failureMessage;
  final RelayTransportEntity? transport;
  final List<RelayTransferTargetEntity> targets;
  final RelayTransferArtifactEntity artifact;

  bool isSender(String clientId) => senderClientId == clientId;

  bool isReceiver(String clientId) =>
      targets.any((target) => target.receiverClientId == clientId);

  RelayTransferTargetEntity? targetForClient(String clientId) {
    for (final target in targets) {
      if (target.receiverClientId == clientId) {
        return target;
      }
    }
    return null;
  }

  String? counterpartClientIdFor(String currentClientId) {
    if (isSender(currentClientId)) {
      if (targets.isEmpty) {
        return null;
      }
      return targets.first.receiverClientId;
    }
    if (isReceiver(currentClientId)) {
      return senderClientId;
    }
    return null;
  }

  bool involvesPeer(String currentClientId, String peerClientId) {
    return counterpartClientIdFor(currentClientId) == peerClientId;
  }

  bool canCancelAs(String clientId) {
    return isSender(clientId) && !status.isTerminal;
  }

  bool canRetryAs(String clientId) {
    return isSender(clientId) && status.isTerminal;
  }

  bool canDownloadAs(String clientId) {
    if (!isReceiver(clientId)) {
      return false;
    }
    if (artifact.cleanupState == RelayArtifactCleanupState.deleted) {
      return false;
    }
    return (status == RelayTransferStatus.uploading &&
            artifact.receivedBytes > 0) ||
        status == RelayTransferStatus.ready ||
        status == RelayTransferStatus.downloading ||
        status == RelayTransferStatus.completed;
  }

  double get uploadProgress {
    if (fileSize <= 0) {
      return 0;
    }
    final ratio = artifact.receivedBytes / fileSize;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }

  RelayTransferEntity copyWith({
    String? transferId,
    String? senderAccountId,
    String? senderLabel,
    String? senderClientId,
    int? targetCount,
    String? fileName,
    Object? mimeType = _sentinel,
    int? fileSize,
    Object? checksum = _sentinel,
    String? checksumAlgorithm,
    int? chunkSize,
    String? storageMode,
    RelayTransferStatus? status,
    Object? retryOfTransferId = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    Object? expiredAt = _sentinel,
    Object? readyAt = _sentinel,
    Object? completedAt = _sentinel,
    Object? cancelledAt = _sentinel,
    Object? failedAt = _sentinel,
    Object? interruptedAt = _sentinel,
    Object? failureCode = _sentinel,
    Object? failureMessage = _sentinel,
    Object? transport = _sentinel,
    List<RelayTransferTargetEntity>? targets,
    RelayTransferArtifactEntity? artifact,
  }) {
    return RelayTransferEntity(
      transferId: transferId ?? this.transferId,
      senderAccountId: senderAccountId ?? this.senderAccountId,
      senderLabel: senderLabel ?? this.senderLabel,
      senderClientId: senderClientId ?? this.senderClientId,
      targetCount: targetCount ?? this.targetCount,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType == _sentinel ? this.mimeType : mimeType as String?,
      fileSize: fileSize ?? this.fileSize,
      checksum: checksum == _sentinel ? this.checksum : checksum as String?,
      checksumAlgorithm: checksumAlgorithm ?? this.checksumAlgorithm,
      chunkSize: chunkSize ?? this.chunkSize,
      storageMode: storageMode ?? this.storageMode,
      status: status ?? this.status,
      retryOfTransferId: retryOfTransferId == _sentinel
          ? this.retryOfTransferId
          : retryOfTransferId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      expiredAt: expiredAt == _sentinel
          ? this.expiredAt
          : expiredAt as DateTime?,
      readyAt: readyAt == _sentinel ? this.readyAt : readyAt as DateTime?,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as DateTime?,
      cancelledAt: cancelledAt == _sentinel
          ? this.cancelledAt
          : cancelledAt as DateTime?,
      failedAt: failedAt == _sentinel ? this.failedAt : failedAt as DateTime?,
      interruptedAt: interruptedAt == _sentinel
          ? this.interruptedAt
          : interruptedAt as DateTime?,
      failureCode: failureCode == _sentinel
          ? this.failureCode
          : failureCode as String?,
      failureMessage: failureMessage == _sentinel
          ? this.failureMessage
          : failureMessage as String?,
      transport: transport == _sentinel
          ? this.transport
          : transport as RelayTransportEntity?,
      targets: targets ?? this.targets,
      artifact: artifact ?? this.artifact,
    );
  }
}

const Object _sentinel = Object();

class RelayTransportEntity {
  const RelayTransportEntity({
    required this.protocol,
    required this.upload,
    required this.download,
    this.thumbnailUpload,
    this.thumbnailDownload,
  });

  final String protocol;
  final RelayTransportEndpointEntity upload;
  final RelayTransportEndpointEntity download;
  final RelayTransportEndpointEntity? thumbnailUpload;
  final RelayTransportEndpointEntity? thumbnailDownload;
}

class RelayTransportEndpointEntity {
  const RelayTransportEndpointEntity({
    required this.method,
    required this.path,
    this.supportsRange = false,
  });

  final String method;
  final String path;
  final bool supportsRange;
}

class RelayTransferTargetEntity {
  const RelayTransferTargetEntity({
    required this.transferId,
    required this.receiverClientId,
    required this.deliveryState,
    required this.updatedAt,
    this.deliveredAt,
    this.downloadStartedAt,
    this.downloadCompletedAt,
  });

  final String transferId;
  final String receiverClientId;
  final RelayTransferTargetState deliveryState;
  final DateTime updatedAt;
  final DateTime? deliveredAt;
  final DateTime? downloadStartedAt;
  final DateTime? downloadCompletedAt;
}

class RelayTransferArtifactEntity {
  const RelayTransferArtifactEntity({
    required this.transferId,
    required this.tempPath,
    this.sealedPath,
    required this.chunkCount,
    required this.receivedBytes,
    required this.isSealed,
    required this.cleanupState,
    required this.updatedAt,
  });

  final String transferId;
  final String tempPath;
  final String? sealedPath;
  final int chunkCount;
  final int receivedBytes;
  final bool isSealed;
  final RelayArtifactCleanupState cleanupState;
  final DateTime updatedAt;
}

class RelayDownloadResult {
  const RelayDownloadResult({
    required this.fileName,
    required this.publicUri,
    this.localPath,
  });

  final String fileName;
  final String publicUri;
  final String? localPath;
}

enum RelayTransferStatus {
  created,
  uploading,
  ready,
  downloading,
  completed,
  cancelled,
  expired,
  failed,
  interrupted,
}

extension RelayTransferStatusX on RelayTransferStatus {
  bool get isTerminal => switch (this) {
    RelayTransferStatus.completed ||
    RelayTransferStatus.cancelled ||
    RelayTransferStatus.expired ||
    RelayTransferStatus.failed ||
    RelayTransferStatus.interrupted => true,
    RelayTransferStatus.created ||
    RelayTransferStatus.uploading ||
    RelayTransferStatus.ready ||
    RelayTransferStatus.downloading => false,
  };
}

enum RelayTransferTargetState {
  pending,
  ready,
  downloading,
  completed,
  cancelled,
  expired,
  failed,
  interrupted,
}

enum RelayArtifactCleanupState { pending, sealed, deleted }
