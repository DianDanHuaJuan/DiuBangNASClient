import '../../domain/entities/relay_transfer_entity.dart';

/// Whether an incoming transfer row should respond to taps.
bool relayIncomingTransferIsTappable({required bool isOutgoing}) {
  return !isOutgoing;
}

/// Whether an outgoing transfer row should respond to taps (local preview only).
bool relayOutgoingTransferIsTappable({
  required String? thumbnailPath,
  required String? originalPath,
}) {
  return (thumbnailPath != null && thumbnailPath.isNotEmpty) ||
      (originalPath != null && originalPath.isNotEmpty);
}

bool relayTransferIsTappable({
  required bool isOutgoing,
  required String? thumbnailPath,
  required String? originalPath,
}) {
  if (isOutgoing) {
    return relayOutgoingTransferIsTappable(
      thumbnailPath: thumbnailPath,
      originalPath: originalPath,
    );
  }
  return relayIncomingTransferIsTappable(isOutgoing: isOutgoing);
}

bool relayCanDownloadIncoming({
  required bool isOutgoing,
  required RelayTransferEntity transfer,
  required String selfClientId,
}) {
  if (isOutgoing || !transfer.isReceiver(selfClientId)) {
    return false;
  }
  if (transfer.artifact.cleanupState == RelayArtifactCleanupState.deleted) {
    return false;
  }
  return transfer.status == RelayTransferStatus.ready;
}
