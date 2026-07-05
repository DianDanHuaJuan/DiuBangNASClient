import '../../domain/entities/relay_transfer_entity.dart';

class PeerConversationHistory {
  const PeerConversationHistory({
    this.transfers = const <RelayTransferEntity>[],
    this.hasMore = true,
    this.isLoadingInitial = false,
    this.isLoadingMore = false,
  });

  final List<RelayTransferEntity> transfers;
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;

  DateTime? get oldestCursor =>
      transfers.isEmpty ? null : transfers.first.createdAt;

  PeerConversationHistory copyWith({
    List<RelayTransferEntity>? transfers,
    bool? hasMore,
    bool? isLoadingInitial,
    bool? isLoadingMore,
  }) {
    return PeerConversationHistory(
      transfers: transfers ?? this.transfers,
      hasMore: hasMore ?? this.hasMore,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}
