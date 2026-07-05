import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/relay/domain/entities/relay_transfer_entity.dart';
import 'package:nasclient/features/relay/domain/relay_media_kind.dart';
import 'package:nasclient/features/relay/presentation/utils/relay_transfer_progress.dart';
import 'package:nasclient/features/relay/presentation/utils/relay_transfer_tap.dart';
import 'package:nasclient/features/relay/presentation/utils/relay_transfer_tap_handler.dart';
import 'package:nasclient/features/relay/presentation/widgets/partner_message_content.dart';

void main() {
  group('DeviceChat message content', () {
    test('uses thumbnail preview when cache thumb path exists', () {
      final transfer = _imageTransfer();

      final content = _buildContentForTest(
        transfer: transfer,
        mediaKind: relayMediaKindFromTransfer(transfer),
        thumbnailPath: '/tmp/photo_thumb.jpg',
      );

      expect(content.kind, PartnerMessageContentKind.mediaPreview);
      expect(content.thumbnailPath, '/tmp/photo_thumb.jpg');
    });

    test('uses placeholder when image transfer has no thumbnail path', () {
      final transfer = _videoTransfer();

      final content = _buildContentForTest(
        transfer: transfer,
        mediaKind: relayMediaKindFromTransfer(transfer),
        thumbnailPath: null,
      );

      expect(content.kind, PartnerMessageContentKind.mediaPlaceholder);
      expect(content.placeholderLabel, 'clip.mp4');
    });
  });

  group('relay transfer tap eligibility', () {
    const selfClientId = 'tablet-01';
    const peerClientId = 'phone-01';

    test('incoming file with ready status is tappable', () {
      final transfer = _incomingTransfer(
        senderClientId: peerClientId,
        receiverClientId: selfClientId,
        fileName: 'report.pdf',
        mimeType: 'application/pdf',
        status: RelayTransferStatus.ready,
      );
      final mediaKind = relayMediaKindFromTransfer(transfer);

      expect(mediaKind, RelayMediaKind.other);
      expect(
        relayTransferIsTappable(
          isOutgoing: false,
          thumbnailPath: null,
          originalPath: null,
        ),
        isTrue,
      );
      expect(
        relayCanDownloadIncoming(
          isOutgoing: false,
          transfer: transfer,
          selfClientId: selfClientId,
        ),
        isTrue,
      );
    });

    test('incoming image without thumbnail and ready status is tappable', () {
      final transfer = _incomingTransfer(
        senderClientId: peerClientId,
        receiverClientId: selfClientId,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        status: RelayTransferStatus.ready,
      );

      expect(
        relayTransferIsTappable(
          isOutgoing: false,
          thumbnailPath: null,
          originalPath: null,
        ),
        isTrue,
      );
      expect(
        relayCanDownloadIncoming(
          isOutgoing: false,
          transfer: transfer,
          selfClientId: selfClientId,
        ),
        isTrue,
      );
    });

    test('incoming transfer with created status is tappable but not downloadable', () {
      final transfer = _incomingTransfer(
        senderClientId: peerClientId,
        receiverClientId: selfClientId,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        status: RelayTransferStatus.created,
      );

      expect(
        relayTransferIsTappable(
          isOutgoing: false,
          thumbnailPath: null,
          originalPath: null,
        ),
        isTrue,
      );
      expect(
        relayCanDownloadIncoming(
          isOutgoing: false,
          transfer: transfer,
          selfClientId: selfClientId,
        ),
        isFalse,
      );
    });

    test('incoming transfer uploading with partial bytes is not downloadable', () {
      final transfer = _incomingTransfer(
        senderClientId: peerClientId,
        receiverClientId: selfClientId,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        status: RelayTransferStatus.uploading,
        receivedBytes: 512,
      );

      expect(
        relayCanDownloadIncoming(
          isOutgoing: false,
          transfer: transfer,
          selfClientId: selfClientId,
        ),
        isFalse,
      );
    });

    test('outgoing file without local cache is not tappable', () {
      final transfer = _incomingTransfer(
        senderClientId: selfClientId,
        receiverClientId: peerClientId,
        fileName: 'report.pdf',
        mimeType: 'application/pdf',
        status: RelayTransferStatus.ready,
      );

      expect(
        relayTransferIsTappable(
          isOutgoing: transfer.isSender(selfClientId),
          thumbnailPath: null,
          originalPath: null,
        ),
        isFalse,
      );
    });

    test('outgoing media with local thumbnail is tappable', () {
      expect(
        relayTransferIsTappable(
          isOutgoing: true,
          thumbnailPath: '/tmp/thumb.jpg',
          originalPath: null,
        ),
        isTrue,
      );
    });
  });

  group('relay transfer progress display', () {
    test('shows upload progress for outgoing uploading transfer', () {
      final transfer = _incomingTransfer(
        senderClientId: 'tablet-01',
        receiverClientId: 'phone-01',
        fileName: 'report.pdf',
        mimeType: 'application/pdf',
        status: RelayTransferStatus.uploading,
        receivedBytes: 512,
      );

      expect(
        relayProgressForDisplay(
          transfer: transfer,
          isOutgoing: true,
          downloadProgress: null,
        ),
        0.5,
      );
      expect(
        relayProgressLabelForDisplay(
          transfer: transfer,
          isOutgoing: true,
          downloadProgress: null,
        ),
        '上传中 50%',
      );
    });

    test('shows sender progress for incoming uploading transfer', () {
      final transfer = _incomingTransfer(
        senderClientId: 'phone-01',
        receiverClientId: 'tablet-01',
        fileName: 'report.pdf',
        mimeType: 'application/pdf',
        status: RelayTransferStatus.uploading,
        receivedBytes: 256,
      );

      expect(
        relayProgressForDisplay(
          transfer: transfer,
          isOutgoing: false,
          downloadProgress: null,
        ),
        closeTo(0.25, 0.001),
      );
      expect(
        relayProgressLabelForDisplay(
          transfer: transfer,
          isOutgoing: false,
          downloadProgress: null,
        ),
        '对方发送中 25%',
      );
    });
  });

  group('handleRelayTransferTap', () {
    testWidgets('shows preparing snackbar when incoming transfer is not ready', (
      tester,
    ) async {
      const selfClientId = 'tablet-01';
      final transfer = _incomingTransfer(
        senderClientId: 'phone-01',
        receiverClientId: selfClientId,
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        status: RelayTransferStatus.created,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => handleRelayTransferTap(
                    context: context,
                    transfer: transfer,
                    mediaKind: RelayMediaKind.image,
                    isOutgoing: false,
                    originalPath: null,
                    originalIsContentUri: false,
                    thumbnailPath: null,
                    selfClientId: selfClientId,
                    downloadTransfer: (_) async => null,
                  ),
                  child: const Text('tap'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('tap'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('对方发送中，请稍后再试'), findsOneWidget);
    });
  });
}

RelayTransferEntity _imageTransfer() {
  return RelayTransferEntity(
    transferId: 'relay-1',
    senderAccountId: 'acc',
    senderLabel: 'Phone',
    senderClientId: 'phone-01',
    targetCount: 1,
    fileName: 'photo.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1024,
    checksumAlgorithm: 'sha256',
    chunkSize: 1048576,
    storageMode: 'store_on_nas',
    status: RelayTransferStatus.ready,
    createdAt: DateTime.utc(2026, 6, 6, 12),
    updatedAt: DateTime.utc(2026, 6, 6, 12),
    expiresAt: DateTime.utc(2026, 6, 7, 12),
    targets: const [],
    artifact: RelayTransferArtifactEntity(
      transferId: 'relay-1',
      tempPath: '/tmp/relay-1.part',
      chunkCount: 1,
      receivedBytes: 1024,
      isSealed: true,
      cleanupState: RelayArtifactCleanupState.sealed,
      updatedAt: DateTime.utc(2026, 6, 6, 12),
    ),
  );
}

RelayTransferEntity _videoTransfer() {
  return RelayTransferEntity(
    transferId: 'relay-2',
    senderAccountId: 'acc',
    senderLabel: 'Phone',
    senderClientId: 'phone-01',
    targetCount: 1,
    fileName: 'clip.mp4',
    mimeType: 'video/mp4',
    fileSize: 2048,
    checksumAlgorithm: 'sha256',
    chunkSize: 1048576,
    storageMode: 'store_on_nas',
    status: RelayTransferStatus.ready,
    createdAt: DateTime.utc(2026, 6, 6, 12),
    updatedAt: DateTime.utc(2026, 6, 6, 12),
    expiresAt: DateTime.utc(2026, 6, 7, 12),
    targets: const [],
    artifact: RelayTransferArtifactEntity(
      transferId: 'relay-2',
      tempPath: '/tmp/relay-2.part',
      chunkCount: 1,
      receivedBytes: 2048,
      isSealed: true,
      cleanupState: RelayArtifactCleanupState.sealed,
      updatedAt: DateTime.utc(2026, 6, 6, 12),
    ),
  );
}

RelayTransferEntity _incomingTransfer({
  required String senderClientId,
  required String receiverClientId,
  required String fileName,
  required String mimeType,
  required RelayTransferStatus status,
  int receivedBytes = 1024,
}) {
  final updatedAt = DateTime.utc(2026, 6, 6, 12);
  return RelayTransferEntity(
    transferId: 'relay-incoming',
    senderAccountId: 'acc',
    senderLabel: 'Phone',
    senderClientId: senderClientId,
    targetCount: 1,
    fileName: fileName,
    mimeType: mimeType,
    fileSize: 1024,
    checksumAlgorithm: 'sha256',
    chunkSize: 1048576,
    storageMode: 'store_on_nas',
    status: status,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    expiresAt: DateTime.utc(2026, 6, 7, 12),
    targets: <RelayTransferTargetEntity>[
      RelayTransferTargetEntity(
        transferId: 'relay-incoming',
        receiverClientId: receiverClientId,
        deliveryState: RelayTransferTargetState.ready,
        updatedAt: updatedAt,
      ),
    ],
    artifact: RelayTransferArtifactEntity(
      transferId: 'relay-incoming',
      tempPath: '/tmp/relay-incoming.part',
      chunkCount: 1,
      receivedBytes: status == RelayTransferStatus.created ? 0 : receivedBytes,
      isSealed: status != RelayTransferStatus.created,
      cleanupState: RelayArtifactCleanupState.sealed,
      updatedAt: updatedAt,
    ),
  );
}

PartnerMessageContent _buildContentForTest({
  required RelayTransferEntity transfer,
  required RelayMediaKind mediaKind,
  required String? thumbnailPath,
}) {
  if (mediaKind == RelayMediaKind.other) {
    return PartnerMessageContent.file(title: transfer.fileName);
  }
  if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
    return PartnerMessageContent.mediaPreview(
      mediaKind: mediaKind,
      thumbnailPath: thumbnailPath,
    );
  }
  return PartnerMessageContent.mediaPlaceholder(
    mediaKind: mediaKind,
    placeholderLabel: transfer.fileName,
  );
}
