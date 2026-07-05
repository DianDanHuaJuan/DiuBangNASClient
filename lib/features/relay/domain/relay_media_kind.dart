import '../../../core/device/local_media_picker.dart';
import 'entities/relay_transfer_entity.dart';

enum RelayMediaKind { image, video, other }

RelayMediaKind relayMediaKindFromMime(String? mimeType) {
  final mime = mimeType?.trim().toLowerCase();
  if (mime == null || mime.isEmpty) {
    return RelayMediaKind.other;
  }
  if (mime.startsWith('image/')) {
    return RelayMediaKind.image;
  }
  if (mime.startsWith('video/')) {
    return RelayMediaKind.video;
  }
  return RelayMediaKind.other;
}

RelayMediaKind relayMediaKindFromTransfer(RelayTransferEntity transfer) {
  final mime = transfer.mimeType ?? guessMimeTypeFromFileName(transfer.fileName);
  return relayMediaKindFromMime(mime);
}

String? relayMimeTypeForTransfer(RelayTransferEntity transfer) {
  return transfer.mimeType ?? guessMimeTypeFromFileName(transfer.fileName);
}

bool relayTransferIsMedia(RelayTransferEntity transfer) {
  return relayMediaKindFromTransfer(transfer) != RelayMediaKind.other;
}
