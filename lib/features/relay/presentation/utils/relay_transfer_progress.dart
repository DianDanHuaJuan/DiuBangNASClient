import '../../domain/entities/relay_transfer_entity.dart';

double? relayProgressForDisplay({
  required RelayTransferEntity transfer,
  required bool isOutgoing,
  required double? downloadProgress,
}) {
  if (isOutgoing &&
      (transfer.status == RelayTransferStatus.created ||
          transfer.status == RelayTransferStatus.uploading)) {
    return transfer.uploadProgress;
  }

  if (!isOutgoing &&
      (transfer.status == RelayTransferStatus.created ||
          transfer.status == RelayTransferStatus.uploading)) {
    return transfer.uploadProgress;
  }

  if (!isOutgoing &&
      (transfer.status == RelayTransferStatus.downloading ||
          downloadProgress != null)) {
    return downloadProgress ?? 0;
  }

  return null;
}

String? relayProgressLabelForDisplay({
  required RelayTransferEntity transfer,
  required bool isOutgoing,
  required double? downloadProgress,
}) {
  final progress = relayProgressForDisplay(
    transfer: transfer,
    isOutgoing: isOutgoing,
    downloadProgress: downloadProgress,
  );
  if (progress == null) {
    return null;
  }

  final percent = (progress * 100).clamp(0, 100).round();
  if (isOutgoing &&
      (transfer.status == RelayTransferStatus.created ||
          transfer.status == RelayTransferStatus.uploading)) {
    return '上传中 $percent%';
  }
  if (!isOutgoing &&
      (transfer.status == RelayTransferStatus.created ||
          transfer.status == RelayTransferStatus.uploading)) {
    return '对方发送中 $percent%';
  }
  if (!isOutgoing &&
      (transfer.status == RelayTransferStatus.downloading ||
          downloadProgress != null)) {
    return '下载中 $percent%';
  }
  return null;
}
