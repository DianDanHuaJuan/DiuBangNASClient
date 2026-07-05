import 'package:flutter/material.dart';

import '../../domain/entities/relay_transfer_entity.dart';
import '../../domain/relay_media_kind.dart';
import '../pages/relay_local_media_preview_page.dart';
import 'relay_transfer_tap.dart';

/// Handles tap on a relay transfer message (incoming download / preview).
Future<void> handleRelayTransferTap({
  required BuildContext context,
  required RelayTransferEntity transfer,
  required RelayMediaKind mediaKind,
  required bool isOutgoing,
  required String? originalPath,
  required bool originalIsContentUri,
  required String? thumbnailPath,
  required String selfClientId,
  required Future<String?> Function(RelayTransferEntity transfer) downloadTransfer,
}) async {
  if (originalPath != null && originalPath.isNotEmpty) {
    if (mediaKind == RelayMediaKind.other) {
      _showSnackBar(context, '文件已保存到本地');
      return;
    }
    openRelayLocalMediaPreview(
      context,
      fileName: transfer.fileName,
      localPath: originalPath,
      mediaKind: mediaKind,
      fileSize: transfer.fileSize,
      isContentUri: originalIsContentUri,
    );
    return;
  }

  if (!isOutgoing &&
      transfer.artifact.cleanupState == RelayArtifactCleanupState.deleted) {
    _showSnackBar(context, 'NAS 已释放该文件');
    return;
  }

  final canDownloadIncoming = relayCanDownloadIncoming(
    isOutgoing: isOutgoing,
    transfer: transfer,
    selfClientId: selfClientId,
  );

  if (!isOutgoing && canDownloadIncoming) {
    final downloadedPath = await downloadTransfer(transfer);
    if (!context.mounted) {
      return;
    }
    if (downloadedPath != null &&
        downloadedPath.isNotEmpty &&
        mediaKind != RelayMediaKind.other) {
      openRelayLocalMediaPreview(
        context,
        fileName: transfer.fileName,
        localPath: downloadedPath,
        mediaKind: mediaKind,
        fileSize: transfer.fileSize,
        isContentUri: true,
      );
    }
    return;
  }

  if (!isOutgoing) {
    _showSnackBar(context, '对方发送中，请稍后再试');
    return;
  }

  if (isOutgoing && thumbnailPath != null) {
    _showSnackBar(context, '原文件已删除');
  }
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
