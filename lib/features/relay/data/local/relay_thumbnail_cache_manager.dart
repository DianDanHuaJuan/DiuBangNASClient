import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/relay_media_kind.dart';

/// Manages the relay thumbnail cache directory under app documents storage.
///
/// Enforces a configurable FIFO size limit. When storing a new thumbnail causes
/// the total cache size to exceed [maxSizeBytes], the oldest files (by
/// modification time) are deleted until the cache is back under the limit.
class RelayThumbnailCacheManager {
  RelayThumbnailCacheManager({
    this.maxSizeBytes = 100 * 1024 * 1024, // 100 MB
  });

  final int maxSizeBytes;

  String? _cacheDirPath;

  Future<String> get cacheDir async {
    if (_cacheDirPath != null) {
      return _cacheDirPath!;
    }
    final documentsDir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(documentsDir.path, 'relay_thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    _cacheDirPath = thumbDir.path;
    return _cacheDirPath!;
  }

  /// Returns the preferred save path for a NAS thumbnail download.
  Future<String> buildSavePath(
    String transferId, {
    RelayMediaKind kind = RelayMediaKind.image,
  }) async {
    final dir = await cacheDir;
    final extension = kind == RelayMediaKind.video ? 'jpg' : 'png';
    return p.join(dir, '${transferId}_thumb.$extension');
  }

  /// Returns the local generator output path for the given [mediaKind].
  Future<String> buildGeneratedPath(
    String transferId,
    RelayMediaKind mediaKind,
  ) async {
    final dir = await cacheDir;
    final extension = mediaKind == RelayMediaKind.image ? 'png' : 'jpg';
    return p.join(dir, '${transferId}_thumb.$extension');
  }

  /// Registers a newly saved thumbnail file and evicts old files if the cache
  /// exceeds [maxSizeBytes].
  ///
  /// Returns the set of transferIds that were evicted (so callers can update
  /// RelayPreviewCache accordingly).
  Future<Set<String>> registerFile({
    required String transferId,
    required String filePath,
    int? fileSize,
  }) async {
    final file = File(filePath);
    final size = fileSize ?? (await file.exists() ? await file.length() : 0);
    if (size <= 0) {
      return const {};
    }

    // Collect all cached files with their sizes and modification times.
    final dir = Directory(await cacheDir);
    if (!await dir.exists()) {
      return const {};
    }

    final entries = <_CacheEntry>[];
    var totalSize = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          final entrySize = stat.size;
          entries.add(
            _CacheEntry(
              path: entity.path,
              size: entrySize,
              modifiedAt: stat.modified,
            ),
          );
          totalSize += entrySize;
        } catch (_) {
          // Ignore files that can't be stat'd
        }
      }
    }

    // Sort oldest first (FIFO)
    entries.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));

    totalSize += size;

    final evictedIds = <String>{};
    while (totalSize > maxSizeBytes && entries.isNotEmpty) {
      final oldest = entries.removeAt(0);
      final oldestFile = File(oldest.path);
      try {
        if (await oldestFile.exists()) {
          await oldestFile.delete();
          totalSize -= oldest.size;
          // Extract transferId from filename: {transferId}_thumb.jpg
          final fileName = p.basenameWithoutExtension(oldest.path);
          final underscoreIndex = fileName.lastIndexOf('_thumb');
          if (underscoreIndex > 0) {
            evictedIds.add(fileName.substring(0, underscoreIndex));
          }
        }
      } catch (_) {
        // If deletion fails, skip and try next
      }
    }

    return evictedIds;
  }

  /// Returns the total size of the cache directory in bytes.
  Future<int> totalSize() async {
    final dir = Directory(await cacheDir);
    if (!await dir.exists()) {
      return 0;
    }
    var size = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          size += await entity.length();
        } catch (_) {}
      }
    }
    return size;
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.path,
    required this.size,
    required this.modifiedAt,
  });

  final String path;
  final int size;
  final DateTime modifiedAt;
}
