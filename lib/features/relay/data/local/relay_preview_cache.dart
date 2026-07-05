import 'dart:convert';
import 'dart:io';

import '../../../../core/storage/key_value_store.dart';
import '../../domain/relay_media_kind.dart';

/// Local dual-track cache for relay media: bubble thumbnails vs original access.
class RelayPreviewCache {
  RelayPreviewCache({required KeyValueStore keyValueStore})
    : _keyValueStore = keyValueStore;

  static const _storageKey = 'relay_preview_map';

  final KeyValueStore _keyValueStore;
  Map<String, RelayMediaCacheEntry> _entries = const {};

  Set<String> get transferIds => _entries.keys.toSet();

  Future<void> load() async {
    final raw = _keyValueStore.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      _entries = const {};
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _entries = const {};
        return;
      }
      final next = <String, RelayMediaCacheEntry>{};
      for (final entry in decoded.entries) {
        final transferId = entry.key.toString().trim();
        if (transferId.isEmpty || entry.value is! Map) {
          continue;
        }
        final value = entry.value as Map;
        final parsed = _parseEntry(value);
        if (parsed != null) {
          next[transferId] = parsed;
        }
      }
      _entries = next;
    } catch (_) {
      _entries = const {};
    }
  }

  String? thumbnailPathFor(String transferId) {
    final path = _entries[transferId]?.thumbnailPath;
    if (path == null || path.isEmpty) {
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return path;
  }

  String? originalPathFor(String transferId) {
    final entry = _entries[transferId];
    if (entry == null) {
      return null;
    }
    final path = entry.originalPath;
    if (path == null || path.isEmpty) {
      return null;
    }
    if (entry.originalIsContentUri) {
      return path;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    return path;
  }

  bool originalIsContentUri(String transferId) {
    return _entries[transferId]?.originalIsContentUri ?? false;
  }

  bool hasDownloadedOriginal(String transferId) {
    return originalPathFor(transferId) != null &&
        (_entries[transferId]?.originalIsContentUri ?? false);
  }

  RelayMediaKind? kindFor(String transferId) {
    return _entries[transferId]?.kind;
  }

  Future<void> putThumbnail({
    required String transferId,
    required String thumbnailPath,
    required RelayMediaKind kind,
  }) async {
    if (transferId.trim().isEmpty || thumbnailPath.trim().isEmpty) {
      return;
    }
    final existing = _entries[transferId];
    _entries = {
      ..._entries,
      transferId: RelayMediaCacheEntry(
        kind: kind,
        thumbnailPath: thumbnailPath,
        originalPath: existing?.originalPath,
        originalIsContentUri: existing?.originalIsContentUri ?? false,
      ),
    };
    await _persist();
  }

  Future<void> putOriginal({
    required String transferId,
    required String originalPath,
    required RelayMediaKind kind,
    bool isContentUri = false,
  }) async {
    if (transferId.trim().isEmpty || originalPath.trim().isEmpty) {
      return;
    }
    final existing = _entries[transferId];
    _entries = {
      ..._entries,
      transferId: RelayMediaCacheEntry(
        kind: kind,
        thumbnailPath: existing?.thumbnailPath,
        originalPath: originalPath,
        originalIsContentUri: isContentUri,
      ),
    };
    await _persist();
  }

  Future<void> clearThumbnail(String transferId) async {
    final entry = _entries[transferId];
    if (entry == null || entry.thumbnailPath == null) {
      return;
    }
    final thumbFile = File(entry.thumbnailPath!);
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }
    if (entry.originalPath == null) {
      await remove(transferId);
      return;
    }
    _entries = {
      ..._entries,
      transferId: RelayMediaCacheEntry(
        kind: entry.kind,
        originalPath: entry.originalPath,
        originalIsContentUri: entry.originalIsContentUri,
      ),
    };
    await _persist();
  }

  Future<void> remove(String transferId) async {
    if (!_entries.containsKey(transferId)) {
      return;
    }
    final next = Map<String, RelayMediaCacheEntry>.from(_entries)
      ..remove(transferId);
    _entries = next;
    await _persist();
  }

  /// Drops index entries for transfers no longer in server history.
  /// Thumbnail files are retained locally until FIFO eviction in
  /// [RelayThumbnailCacheManager]; gallery originals are never deleted here.
  Future<void> pruneStale(Set<String> activeTransferIds) async {
    final staleIds = <String>[];
    for (final id in _entries.keys) {
      if (!activeTransferIds.contains(id)) {
        staleIds.add(id);
      }
    }
    if (staleIds.isEmpty) {
      return;
    }

    final next = Map<String, RelayMediaCacheEntry>.from(_entries);
    for (final id in staleIds) {
      next.remove(id);
    }
    _entries = next;
    await _persist();
  }

  Future<void> _persist() async {
    final payload = _entries.map(
      (transferId, entry) => MapEntry(transferId, entry.toJson()),
    );
    await _keyValueStore.setString(_storageKey, jsonEncode(payload));
  }

  RelayMediaCacheEntry? _parseEntry(Map value) {
    final kind = _parseKind(value['kind']?.toString());

    final thumbnailPath = value['thumbnailPath']?.toString().trim();
    final originalPath = value['originalPath']?.toString().trim();
    final originalIsContentUri = value['originalIsContentUri'] == true;

    if ((thumbnailPath == null || thumbnailPath.isEmpty) &&
        (originalPath == null || originalPath.isEmpty)) {
      return null;
    }

    return RelayMediaCacheEntry(
      kind: kind,
      thumbnailPath: thumbnailPath?.isNotEmpty == true ? thumbnailPath : null,
      originalPath: originalPath?.isNotEmpty == true ? originalPath : null,
      originalIsContentUri: originalIsContentUri,
    );
  }
}

RelayMediaKind _parseKind(String? raw) {
  return switch (raw) {
    'image' => RelayMediaKind.image,
    'video' => RelayMediaKind.video,
    _ => RelayMediaKind.other,
  };
}

class RelayMediaCacheEntry {
  const RelayMediaCacheEntry({
    required this.kind,
    this.thumbnailPath,
    this.originalPath,
    this.originalIsContentUri = false,
  });

  final RelayMediaKind kind;
  final String? thumbnailPath;
  final String? originalPath;
  final bool originalIsContentUri;

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
      if (originalPath != null) 'originalPath': originalPath,
      if (originalIsContentUri) 'originalIsContentUri': true,
    };
  }
}
