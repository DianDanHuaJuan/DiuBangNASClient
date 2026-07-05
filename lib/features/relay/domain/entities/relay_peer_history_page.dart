import 'relay_transfer_entity.dart';

class RelayPeerHistoryPage {
  const RelayPeerHistoryPage({
    required this.transfers,
    required this.hasMore,
  });

  final List<RelayTransferEntity> transfers;
  final bool hasMore;
}
