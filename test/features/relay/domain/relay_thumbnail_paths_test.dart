import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/relay/domain/entities/relay_transfer_entity.dart';
import 'package:nasclient/features/relay/domain/relay_thumbnail_paths.dart';

void main() {
  group('mergeRelayTransferArtifact', () {
    test('keeps higher receivedBytes when incoming regresses', () {
      const transferId = 'relay-1';
      final updatedAt = DateTime(2026, 4, 12, 10, 1);
      final previous = RelayTransferArtifactEntity(
        transferId: transferId,
        tempPath: 'D:\\relay\\$transferId.part',
        chunkCount: 1,
        receivedBytes: 900,
        isSealed: false,
        cleanupState: RelayArtifactCleanupState.pending,
        updatedAt: updatedAt,
      );
      final incoming = RelayTransferArtifactEntity(
        transferId: transferId,
        tempPath: 'D:\\relay\\$transferId.part',
        chunkCount: 1,
        receivedBytes: 800,
        isSealed: false,
        cleanupState: RelayArtifactCleanupState.pending,
        updatedAt: updatedAt,
      );

      final merged = mergeRelayTransferArtifact(previous, incoming);

      expect(merged.receivedBytes, 900);
    });

    test('accepts higher incoming receivedBytes', () {
      const transferId = 'relay-1';
      final updatedAt = DateTime(2026, 4, 12, 10, 1);
      final previous = RelayTransferArtifactEntity(
        transferId: transferId,
        tempPath: 'D:\\relay\\$transferId.part',
        chunkCount: 1,
        receivedBytes: 800,
        isSealed: false,
        cleanupState: RelayArtifactCleanupState.pending,
        updatedAt: updatedAt,
      );
      final incoming = RelayTransferArtifactEntity(
        transferId: transferId,
        tempPath: 'D:\\relay\\$transferId.part',
        chunkCount: 1,
        receivedBytes: 900,
        isSealed: false,
        cleanupState: RelayArtifactCleanupState.pending,
        updatedAt: updatedAt,
      );

      final merged = mergeRelayTransferArtifact(previous, incoming);

      expect(merged.receivedBytes, 900);
    });
  });

  group('mergeRelayTransferEntity', () {
    test('preserves monotonic upload progress across merges', () {
      const transferId = 'relay-1';
      final createdAt = DateTime(2026, 4, 12, 10);
      final previous = _transfer(
        transferId: transferId,
        receivedBytes: 900,
        createdAt: createdAt,
      );
      final incoming = _transfer(
        transferId: transferId,
        receivedBytes: 800,
        createdAt: createdAt,
      );

      final merged = mergeRelayTransferEntity(previous, incoming);

      expect(merged.uploadProgress, closeTo(900 / 1000, 0.0001));
    });
  });
}

RelayTransferEntity _transfer({
  required String transferId,
  required int receivedBytes,
  required DateTime createdAt,
}) {
  return RelayTransferEntity(
    transferId: transferId,
    senderAccountId: 'acct-1',
    senderLabel: 'Phone 01',
    senderClientId: 'phone-01',
    targetCount: 1,
    fileName: 'demo.bin',
    fileSize: 1000,
    checksumAlgorithm: 'sha256',
    chunkSize: 1048576,
    storageMode: 'store_on_nas',
    status: RelayTransferStatus.uploading,
    createdAt: createdAt,
    updatedAt: createdAt.add(const Duration(minutes: 1)),
    expiresAt: createdAt.add(const Duration(days: 3)),
    targets: <RelayTransferTargetEntity>[
      RelayTransferTargetEntity(
        transferId: transferId,
        receiverClientId: 'tablet-01',
        deliveryState: RelayTransferTargetState.pending,
        updatedAt: createdAt,
      ),
    ],
    artifact: RelayTransferArtifactEntity(
      transferId: transferId,
      tempPath: 'D:\\relay\\$transferId.part',
      chunkCount: 1,
      receivedBytes: receivedBytes,
      isSealed: false,
      cleanupState: RelayArtifactCleanupState.pending,
      updatedAt: createdAt,
    ),
  );
}
