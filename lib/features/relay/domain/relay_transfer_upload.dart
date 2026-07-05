import 'entities/relay_transfer_entity.dart';

RelayTransferEntity relayTransferWithUploadBytes(
  RelayTransferEntity transfer,
  int sentBytes,
) {
  final artifact = transfer.artifact;
  return transfer.copyWith(
    status: RelayTransferStatus.uploading,
    artifact: RelayTransferArtifactEntity(
      transferId: artifact.transferId,
      tempPath: artifact.tempPath,
      sealedPath: artifact.sealedPath,
      chunkCount: artifact.chunkCount,
      receivedBytes: sentBytes,
      isSealed: artifact.isSealed,
      cleanupState: artifact.cleanupState,
      updatedAt: DateTime.now().toUtc(),
    ),
  );
}
