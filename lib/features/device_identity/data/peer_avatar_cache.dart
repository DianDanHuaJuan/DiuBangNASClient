import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_profile_remote_data_source.dart';

class PeerAvatarCache {
  PeerAvatarCache({required DeviceProfileRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  final DeviceProfileRemoteDataSource _remoteDataSource;
  final Map<String, DateTime?> _cachedRevisionByDeviceId =
      <String, DateTime?>{};
  String? _cacheRoot;

  Future<String?> pathFor(String deviceId) async {
    final normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final localPath = await _localPath(normalized);
    if (!File(localPath).existsSync()) {
      return null;
    }
    return localPath;
  }

  Future<String?> ensureCached({
    required String deviceId,
    DateTime? remoteUpdatedAt,
  }) async {
    final normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final localPath = await _localPath(normalized);
    final localFile = File(localPath);
    final exists = await localFile.exists();
    final cachedRevision = _cachedRevisionByDeviceId[normalized];
    final remote = remoteUpdatedAt?.toUtc();

    if (exists && remote != null) {
      // Memory revision from a prior successful sync.
      if (cachedRevision != null && !remote.isAfter(cachedRevision)) {
        return localPath;
      }
      // App restarted: memory map empty — compare against on-disk mtime.
      if (cachedRevision == null) {
        final localMtime = (await localFile.lastModified()).toUtc();
        if (!remote.isAfter(localMtime)) {
          _cachedRevisionByDeviceId[normalized] = remote;
          return localPath;
        }
      }
    }

    // remote == null: never treat local bytes as authoritative forever.
    // Re-download so a later presence push with avatarUpdatedAt can compare.
    final bytes = await _remoteDataSource.downloadPeerAvatar(
      normalized,
      cacheBuster: remote,
    );
    if (bytes == null || bytes.isEmpty) {
      _cachedRevisionByDeviceId[normalized] = remote;
      if (await localFile.exists()) {
        PaintingBinding.instance.imageCache.evict(FileImage(localFile));
        await localFile.delete();
      }
      return null;
    }

    final directory = Directory(p.dirname(localPath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await localFile.writeAsBytes(bytes, flush: true);
    // FileImage cache keys by path only; overwrite would otherwise keep old bitmap.
    PaintingBinding.instance.imageCache.evict(FileImage(localFile));
    // Do NOT stamp DateTime.now() — that made later real mtimes look "older"
    // and permanently skipped refreshes.
    _cachedRevisionByDeviceId[normalized] = remote;
    return localPath;
  }

  Future<String> _localPath(String deviceId) async {
    final root = _cacheRoot ??= p.join(
      (await getApplicationDocumentsDirectory()).path,
      'peer_avatars',
    );
    return p.join(root, '$deviceId.jpg');
  }
}
