import 'entities/relay_transfer_entity.dart';

RelayTransferEntity mergeRelayTransferTransport(
  RelayTransferEntity previous,
  RelayTransferEntity incoming,
) {
  final previousTransport = previous.transport;
  final incomingTransport = incoming.transport;
  if (previousTransport == null) {
    return incoming;
  }
  if (incomingTransport == null) {
    return incoming.copyWith(transport: previousTransport);
  }

  return incoming.copyWith(
    transport: RelayTransportEntity(
      protocol: incomingTransport.protocol,
      upload: incomingTransport.upload,
      download: incomingTransport.download,
      thumbnailUpload:
          incomingTransport.thumbnailUpload ?? previousTransport.thumbnailUpload,
      thumbnailDownload:
          incomingTransport.thumbnailDownload ??
          previousTransport.thumbnailDownload,
    ),
  );
}

RelayTransferArtifactEntity mergeRelayTransferArtifact(
  RelayTransferArtifactEntity previous,
  RelayTransferArtifactEntity incoming,
) {
  final incomingTempPath = incoming.tempPath.trim();
  final incomingSealed = incoming.sealedPath?.trim();
  return RelayTransferArtifactEntity(
    transferId: incoming.transferId,
    tempPath: incomingTempPath.isNotEmpty ? incomingTempPath : previous.tempPath,
    sealedPath: (incomingSealed != null && incomingSealed.isNotEmpty)
        ? incomingSealed
        : previous.sealedPath,
    chunkCount: incoming.chunkCount,
    receivedBytes: incoming.receivedBytes >= previous.receivedBytes
        ? incoming.receivedBytes
        : previous.receivedBytes,
    isSealed: incoming.isSealed,
    cleanupState: incoming.cleanupState,
    updatedAt: incoming.updatedAt,
  );
}

RelayTransferEntity mergeRelayTransferEntity(
  RelayTransferEntity previous,
  RelayTransferEntity incoming,
) {
  final mergedTransport = mergeRelayTransferTransport(previous, incoming);
  return mergedTransport.copyWith(
    artifact: mergeRelayTransferArtifact(
      previous.artifact,
      incoming.artifact,
    ),
  );
}

bool relayTransferCanFetchRemoteThumbnail(RelayTransferEntity transfer) {
  if (transfer.artifact.cleanupState == RelayArtifactCleanupState.deleted) {
    return false;
  }
  return switch (transfer.status) {
    RelayTransferStatus.created ||
    RelayTransferStatus.uploading ||
    RelayTransferStatus.ready ||
    RelayTransferStatus.downloading ||
    RelayTransferStatus.completed => true,
    _ => false,
  };
}
