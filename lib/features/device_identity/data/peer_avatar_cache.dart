import 'dart:io';

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
    final cachedRevision = _cachedRevisionByDeviceId[normalized];
    if (await localFile.exists() &&
        remoteUpdatedAt != null &&
        cachedRevision != null &&
        !remoteUpdatedAt.isAfter(cachedRevision)) {
      return localPath;
    }

    final bytes = await _remoteDataSource.downloadPeerAvatar(normalized);
    if (bytes == null || bytes.isEmpty) {
      _cachedRevisionByDeviceId[normalized] = remoteUpdatedAt;
      if (await localFile.exists()) {
        await localFile.delete();
      }
      return null;
    }

    final directory = Directory(p.dirname(localPath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await localFile.writeAsBytes(bytes, flush: true);
    _cachedRevisionByDeviceId[normalized] =
        remoteUpdatedAt ?? DateTime.now().toUtc();
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
