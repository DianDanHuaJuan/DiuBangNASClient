import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_avatar_processor.dart';
import '../storage/key_value_store.dart';

class DeviceIdentityStore {
  DeviceIdentityStore({required KeyValueStore keyValueStore})
    : _keyValueStore = keyValueStore;

  static const _avatarPathKey = 'local_avatar_path';
  static const _displayAliasKey = 'device_display_alias';
  static const _avatarUpdatedAtKey = 'local_avatar_updated_at';

  final KeyValueStore _keyValueStore;

  String? get avatarPath {
    final path = _keyValueStore.getString(_avatarPathKey)?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    if (!File(path).existsSync()) {
      return null;
    }
    return path;
  }

  String? get displayAlias {
    final alias = _keyValueStore.getString(_displayAliasKey)?.trim();
    if (alias == null || alias.isEmpty) {
      return null;
    }
    return alias;
  }

  DateTime? get avatarUpdatedAt {
    final raw = _keyValueStore.getString(_avatarUpdatedAtKey)?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<String?> saveAvatarFromPath(String sourcePath) async {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final bytes = await DeviceAvatarProcessor.prepareFromFile(trimmed);
    return saveAvatarBytes(bytes);
  }

  Future<String?> saveAvatarBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory(p.join(documentsDir.path, 'profile'));
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }

    final previousPath = _keyValueStore.getString(_avatarPathKey)?.trim();
    if (previousPath != null && previousPath.isNotEmpty) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) {
        await previousFile.delete();
      }
    }

    final updatedAt = DateTime.now().toUtc();
    final destinationPath = p.join(
      profileDir.path,
      'avatar_${updatedAt.millisecondsSinceEpoch}.jpg',
    );
    await File(destinationPath).writeAsBytes(bytes, flush: true);
    await _keyValueStore.setString(_avatarPathKey, destinationPath);
    await _keyValueStore.setString(
      _avatarUpdatedAtKey,
      updatedAt.toIso8601String(),
    );
    return destinationPath;
  }

  Future<void> clearAvatar() async {
    final existing = _keyValueStore.getString(_avatarPathKey);
    if (existing != null && existing.trim().isNotEmpty) {
      final file = File(existing);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _keyValueStore.remove(_avatarPathKey);
    await _keyValueStore.remove(_avatarUpdatedAtKey);
  }

  Future<void> saveDisplayAlias(String alias) async {
    final normalized = alias.trim();
    if (normalized.isEmpty) {
      await clearDisplayAlias();
      return;
    }
    await _keyValueStore.setString(_displayAliasKey, normalized);
  }

  Future<void> clearDisplayAlias() async {
    await _keyValueStore.remove(_displayAliasKey);
  }

  Future<void> markAvatarSynced(DateTime updatedAt) async {
    await _keyValueStore.setString(
      _avatarUpdatedAtKey,
      updatedAt.toUtc().toIso8601String(),
    );
  }

  Future<void> applyRemoteProfile({
    String? label,
    DateTime? avatarUpdatedAt,
  }) async {
    if (label != null) {
      await saveDisplayAlias(label);
    }
    if (avatarUpdatedAt != null) {
      await markAvatarSynced(avatarUpdatedAt);
    }
  }
}

/// Backward-compatible alias for existing wiring.
typedef UserProfileStore = DeviceIdentityStore;
