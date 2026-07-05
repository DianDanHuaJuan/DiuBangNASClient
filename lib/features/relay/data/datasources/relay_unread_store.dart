import '../../../../core/storage/key_value_store.dart';

class RelayUnreadStore {
  RelayUnreadStore({required KeyValueStore keyValueStore})
    : _keyValueStore = keyValueStore;

  final KeyValueStore _keyValueStore;

  String _storageKey({
    required String serverId,
    required String clientId,
    required String peerId,
  }) {
    return 'relay.last_read_at.$serverId.$clientId.$peerId';
  }

  DateTime? readLastReadAt({
    required String serverId,
    required String clientId,
    required String peerId,
  }) {
    final raw = _keyValueStore.getString(
      _storageKey(serverId: serverId, clientId: clientId, peerId: peerId),
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return DateTime.parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeLastReadAt({
    required String serverId,
    required String clientId,
    required String peerId,
    required DateTime readAt,
  }) async {
    await _keyValueStore.setString(
      _storageKey(serverId: serverId, clientId: clientId, peerId: peerId),
      readAt.toUtc().toIso8601String(),
    );
  }
}
