import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/relay/domain/entities/relay_transfer_entity.dart';
import 'package:nasclient/features/relay/presentation/cubit/relay_unread_tracker.dart';

void main() {
  group('RelayUnreadTracker', () {
    test('counts incoming transfer.created for receiver only', () {
      final tracker = RelayUnreadTracker();
      final transfer = _transfer(
        transferId: 'relay-1',
        senderClientId: 'phone-01',
        receiverClientId: 'tablet-01',
      );

      tracker.onTransferEvent(
        eventType: 'transfer.created',
        transfer: transfer,
        myClientId: 'tablet-01',
        activePeerClientId: null,
      );

      expect(tracker.unreadForPeer('phone-01'), 1);
      expect(tracker.totalUnread, 1);
    });

    test('does not count outgoing transfers for sender', () {
      final tracker = RelayUnreadTracker();
      final transfer = _transfer(
        transferId: 'relay-1',
        senderClientId: 'tablet-01',
        receiverClientId: 'phone-01',
      );

      tracker.onTransferEvent(
        eventType: 'transfer.ready',
        transfer: transfer,
        myClientId: 'tablet-01',
        activePeerClientId: null,
      );

      expect(tracker.totalUnread, 0);
    });

    test('deduplicates created and ready for same transfer', () {
      final tracker = RelayUnreadTracker();
      final transfer = _transfer(
        transferId: 'relay-1',
        senderClientId: 'phone-01',
        receiverClientId: 'tablet-01',
      );

      tracker
        ..onTransferEvent(
          eventType: 'transfer.created',
          transfer: transfer,
          myClientId: 'tablet-01',
          activePeerClientId: null,
        )
        ..onTransferEvent(
          eventType: 'transfer.ready',
          transfer: transfer,
          myClientId: 'tablet-01',
          activePeerClientId: null,
        );

      expect(tracker.unreadForPeer('phone-01'), 1);
    });

    test('skips unread while active peer chat is open', () {
      final tracker = RelayUnreadTracker();
      final transfer = _transfer(
        transferId: 'relay-1',
        senderClientId: 'phone-01',
        receiverClientId: 'tablet-01',
      );

      tracker.onTransferEvent(
        eventType: 'transfer.ready',
        transfer: transfer,
        myClientId: 'tablet-01',
        activePeerClientId: 'phone-01',
      );

      expect(tracker.totalUnread, 0);
    });

    test('markPeerRead clears peer unread count', () {
      final tracker = RelayUnreadTracker();
      final transfer = _transfer(
        transferId: 'relay-1',
        senderClientId: 'phone-01',
        receiverClientId: 'tablet-01',
      );

      tracker.onTransferEvent(
        eventType: 'transfer.ready',
        transfer: transfer,
        myClientId: 'tablet-01',
        activePeerClientId: null,
      );
      tracker.markPeerRead('phone-01');

      expect(tracker.unreadForPeer('phone-01'), 0);
      expect(tracker.lastReadAtFor('phone-01'), isNotNull);
    });

    test('recomputeFromHistory respects lastReadAt', () {
      final tracker = RelayUnreadTracker()
        ..seedLastReadAt(<String, DateTime>{
          'phone-01': DateTime.utc(2026, 6, 5, 12),
        });

      tracker.recomputeFromHistory(
        transfers: <RelayTransferEntity>[
          _transfer(
            transferId: 'old',
            senderClientId: 'phone-01',
            receiverClientId: 'tablet-01',
            updatedAt: DateTime.utc(2026, 6, 5, 11),
          ),
          _transfer(
            transferId: 'new',
            senderClientId: 'phone-01',
            receiverClientId: 'tablet-01',
            updatedAt: DateTime.utc(2026, 6, 5, 13),
          ),
        ],
        myClientId: 'tablet-01',
      );

      expect(tracker.unreadForPeer('phone-01'), 1);
    });
  });
}

RelayTransferEntity _transfer({
  required String transferId,
  required String senderClientId,
  required String receiverClientId,
  DateTime? updatedAt,
}) {
  final effectiveUpdatedAt = updatedAt ?? DateTime.utc(2026, 6, 5, 12);
  return RelayTransferEntity(
    transferId: transferId,
    senderAccountId: 'acct-1',
    senderLabel: senderClientId,
    senderClientId: senderClientId,
    targetCount: 1,
    fileName: 'demo.txt',
    fileSize: 128,
    checksumAlgorithm: 'sha256',
    chunkSize: 1048576,
    storageMode: 'store_on_nas',
    status: RelayTransferStatus.ready,
    createdAt: effectiveUpdatedAt,
    updatedAt: effectiveUpdatedAt,
    expiresAt: DateTime.utc(2026, 6, 8, 12),
    targets: <RelayTransferTargetEntity>[
      RelayTransferTargetEntity(
        transferId: transferId,
        receiverClientId: receiverClientId,
        deliveryState: RelayTransferTargetState.ready,
        updatedAt: effectiveUpdatedAt,
      ),
    ],
    artifact: RelayTransferArtifactEntity(
      transferId: transferId,
      tempPath: 'D:\\relay\\$transferId.part',
      chunkCount: 1,
      receivedBytes: 128,
      isSealed: true,
      cleanupState: RelayArtifactCleanupState.sealed,
      updatedAt: effectiveUpdatedAt,
    ),
  );
}
