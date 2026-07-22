import 'package:dio/dio.dart';

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
  Future<void>? _inFlightPeerSync;
  Future<void>? _inFlightRosterSync;

  Future<void> syncPeers(Iterable<String> deviceIds) {
    final inFlightSync = _inFlightPeerSync;
    if (inFlightSync != null) {
      return inFlightSync;
    }

    final sync = _syncPeersInternal(deviceIds);
    _inFlightPeerSync = sync;
    return sync.whenComplete(() {
      if (identical(_inFlightPeerSync, sync)) {
        _inFlightPeerSync = null;
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

  /// Pull authoritative device roster from the server and replace the local copy.
  Future<void> syncServerRoster() {
    final inFlightSync = _inFlightRosterSync;
    if (inFlightSync != null) {
      return inFlightSync;
    }

    final sync = _syncServerRosterInternal();
    _inFlightRosterSync = sync;
    return sync.whenComplete(() {
      if (identical(_inFlightRosterSync, sync)) {
        _inFlightRosterSync = null;
      }
    });
  }

  Future<void> _syncPeersInternal(Iterable<String> deviceIds) async {
    final requestedIds = deviceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (requestedIds.isEmpty) {
      return;
    }

    final profiles = await _remoteDataSource.fetchPeerProfiles(requestedIds);
    if (profiles.isNotEmpty) {
      _unifiedNodeStore.applyPeerProfiles(profiles);
    }
    // Do not prune from partial profile responses; roster sync owns membership.
  }

  Future<void> _syncServerRosterInternal() async {
    try {
      final roster = await _remoteDataSource.fetchRoster();
      _unifiedNodeStore.applyServerRoster(roster);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 404 || statusCode == 405) {
        await _syncRosterFallbackFromEnrolledIds();
        return;
      }
      // Keep the existing local copy on transient failures.
    } catch (_) {
      // Keep the existing local copy on unexpected failures.
    }
  }

  Future<void> _syncRosterFallbackFromEnrolledIds() async {
    final enrolled = _unifiedNodeStore.enrolledDeviceIds;
    if (enrolled == null || enrolled.isEmpty) {
      return;
    }
    final profiles = await _remoteDataSource.fetchPeerProfiles(enrolled);
    _unifiedNodeStore.applyServerRoster(profiles);
  }
}
