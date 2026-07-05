import '../../domain/entities/relay_transfer_entity.dart';

class RelayUnreadTracker {
  final Map<String, Set<String>> _unreadTransferIdsByPeerId =
      <String, Set<String>>{};
  final Map<String, DateTime> _lastReadAtByPeerId = <String, DateTime>{};

  Map<String, int> get unreadCountByPeerId {
    return Map<String, int>.unmodifiable(
      _unreadTransferIdsByPeerId.map(
        (peerId, transferIds) => MapEntry(peerId, transferIds.length),
      ),
    );
  }

  int get totalUnread =>
      _unreadTransferIdsByPeerId.values.fold<int>(0, (sum, ids) => sum + ids.length);

  int unreadForPeer(String peerId) {
    return _unreadTransferIdsByPeerId[peerId]?.length ?? 0;
  }

  void seedLastReadAt(Map<String, DateTime> lastReadAtByPeerId) {
    _lastReadAtByPeerId
      ..clear()
      ..addAll(lastReadAtByPeerId);
  }

  DateTime? lastReadAtFor(String peerId) => _lastReadAtByPeerId[peerId];

  void onTransferEvent({
    required String eventType,
    required RelayTransferEntity transfer,
    required String myClientId,
    required String? activePeerClientId,
  }) {
    if (!_shouldTrackEvent(eventType)) {
      return;
    }
    if (!transfer.isReceiver(myClientId) || transfer.isSender(myClientId)) {
      return;
    }
    if (transfer.status.isTerminal) {
      _removeUnreadTransfer(transfer.senderClientId, transfer.transferId);
      return;
    }

    final peerId = transfer.senderClientId.trim();
    if (peerId.isEmpty || peerId == myClientId) {
      return;
    }
    if (activePeerClientId == peerId) {
      return;
    }

    final unreadIds = _unreadTransferIdsByPeerId.putIfAbsent(
      peerId,
      () => <String>{},
    );
    unreadIds.add(transfer.transferId);
  }

  void recomputeFromHistory({
    required List<RelayTransferEntity> transfers,
    required String myClientId,
  }) {
    final nextUnread = <String, Set<String>>{};
    for (final transfer in transfers) {
      if (!transfer.isReceiver(myClientId) || transfer.isSender(myClientId)) {
        continue;
      }
      if (transfer.status.isTerminal) {
        continue;
      }

      final peerId = transfer.senderClientId.trim();
      if (peerId.isEmpty || peerId == myClientId) {
        continue;
      }

      final lastReadAt = _lastReadAtByPeerId[peerId];
      if (lastReadAt != null && !transfer.updatedAt.isAfter(lastReadAt)) {
        continue;
      }

      nextUnread.putIfAbsent(peerId, () => <String>{}).add(transfer.transferId);
    }

    _unreadTransferIdsByPeerId
      ..clear()
      ..addAll(nextUnread);
  }

  DateTime markPeerRead(String peerId, {DateTime? readAt}) {
    final normalizedPeerId = peerId.trim();
    final effectiveReadAt = (readAt ?? DateTime.now()).toUtc();
    _unreadTransferIdsByPeerId.remove(normalizedPeerId);
    _lastReadAtByPeerId[normalizedPeerId] = effectiveReadAt;
    return effectiveReadAt;
  }

  void clear() {
    _unreadTransferIdsByPeerId.clear();
    _lastReadAtByPeerId.clear();
  }

  bool _shouldTrackEvent(String eventType) {
    return eventType == 'transfer.created' || eventType == 'transfer.ready';
  }

  void _removeUnreadTransfer(String peerId, String transferId) {
    final unreadIds = _unreadTransferIdsByPeerId[peerId];
    if (unreadIds == null) {
      return;
    }
    unreadIds.remove(transferId);
    if (unreadIds.isEmpty) {
      _unreadTransferIdsByPeerId.remove(peerId);
    }
  }
}
