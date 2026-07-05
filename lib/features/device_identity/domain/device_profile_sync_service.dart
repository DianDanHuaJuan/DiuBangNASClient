import '../../../core/node/unified_node.dart';
import '../../../core/node/unified_node_store.dart';
import '../data/device_profile_remote_data_source.dart';

class DeviceProfileSyncService {
  DeviceProfileSyncService({
    required DeviceProfileRemoteDataSource remoteDataSource,
    required UnifiedNodeStore unifiedNodeStore,
  }) : _remoteDataSource = remoteDataSource,
       _unifiedNodeStore = unifiedNodeStore;

  final DeviceProfileRemoteDataSource _remoteDataSource;
  final UnifiedNodeStore _unifiedNodeStore;
  Future<void>? _inFlightSync;

  Future<void> syncPeers(Iterable<String> deviceIds) {
    final inFlightSync = _inFlightSync;
    if (inFlightSync != null) {
      return inFlightSync;
    }

    final sync = _syncPeersInternal(deviceIds);
    _inFlightSync = sync;
    return sync.whenComplete(() {
      if (identical(_inFlightSync, sync)) {
        _inFlightSync = null;
      }
    });
  }

  Future<void> syncKnownPeers() {
    final deviceIds = _unifiedNodeStore.peerClients
        .map((node) => node.identity.clientId)
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty);
    return syncPeers(deviceIds);
  }

  Future<void> _syncPeersInternal(Iterable<String> deviceIds) async {
    final profiles = await _remoteDataSource.fetchPeerProfiles(deviceIds);
    if (profiles.isEmpty) {
      return;
    }
    _unifiedNodeStore.applyPeerProfiles(profiles);
  }
}
