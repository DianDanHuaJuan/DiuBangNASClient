import '../../domain/entities/relay_transfer_entity.dart';
import 'peer_conversation_history.dart';

class RelayState {
  const RelayState({
    this.isLoading = false,
    this.isSending = false,
    this.sendingPeerId,
    this.transfers = const <RelayTransferEntity>[],
    this.peerConversationHistories =
        const <String, PeerConversationHistory>{},
    this.busyTransferIds = const <String>{},
    this.downloadProgressByTransferId = const <String, double>{},
    this.unreadCountByPeerId = const <String, int>{},
    this.activePeerClientId,
    this.mediaCacheRevision = 0,
    this.message,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isSending;
  final String? sendingPeerId;
  final List<RelayTransferEntity> transfers;
  final Map<String, PeerConversationHistory> peerConversationHistories;
  final Set<String> busyTransferIds;
  final Map<String, double> downloadProgressByTransferId;
  final Map<String, int> unreadCountByPeerId;
  final String? activePeerClientId;
  final int mediaCacheRevision;
  final String? message;
  final String? errorMessage;

  bool get hasTransfers => transfers.isNotEmpty;

  int get totalUnread => unreadCountByPeerId.values.fold<int>(
    0,
    (sum, count) => sum + count,
  );

  int unreadForPeer(String peerId) => unreadCountByPeerId[peerId.trim()] ?? 0;

  bool get hasUnread => totalUnread > 0;

  List<RelayTransferEntity> transfersForPeer(
    String currentClientId,
    String peerClientId,
  ) {
    return transfers
        .where(
          (transfer) => transfer.involvesPeer(currentClientId, peerClientId),
        )
        .toList(growable: false);
  }

  PeerConversationHistory peerHistory(String peerClientId) {
    return peerConversationHistories[peerClientId.trim()] ??
        const PeerConversationHistory();
  }

  RelayState copyWith({
    bool? isLoading,
    bool? isSending,
    Object? sendingPeerId = _sentinel,
    List<RelayTransferEntity>? transfers,
    Map<String, PeerConversationHistory>? peerConversationHistories,
    Set<String>? busyTransferIds,
    Map<String, double>? downloadProgressByTransferId,
    Map<String, int>? unreadCountByPeerId,
    Object? activePeerClientId = _sentinel,
    int? mediaCacheRevision,
    Object? message = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return RelayState(
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      sendingPeerId: sendingPeerId == _sentinel
          ? this.sendingPeerId
          : sendingPeerId as String?,
      transfers: transfers ?? this.transfers,
      peerConversationHistories:
          peerConversationHistories ?? this.peerConversationHistories,
      busyTransferIds: busyTransferIds ?? this.busyTransferIds,
      downloadProgressByTransferId:
          downloadProgressByTransferId ?? this.downloadProgressByTransferId,
      unreadCountByPeerId: unreadCountByPeerId ?? this.unreadCountByPeerId,
      activePeerClientId: activePeerClientId == _sentinel
          ? this.activePeerClientId
          : activePeerClientId as String?,
      mediaCacheRevision: mediaCacheRevision ?? this.mediaCacheRevision,
      message: message == _sentinel ? this.message : message as String?,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const Object _sentinel = Object();
