/// 文件输入：远程数据源
/// 文件职责：实现缩略图仓库，包含 LRU 内存缓存、并发控制、请求去重、失败负缓存和自动重试
/// 文件对外接口：ThumbnailRepositoryImpl
/// 文件包含：ThumbnailRepositoryImpl
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/thumbnail_item_entity.dart';
import '../../domain/repositories/thumbnail_repository.dart';
import '../datasources/thumbnail_remote_data_source.dart';
import '../models/thumbnail_batch_response.dart';

class ThumbnailRepositoryImpl implements ThumbnailRepository {
  ThumbnailRepositoryImpl({required ThumbnailRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  final ThumbnailRemoteDataSource _remoteDataSource;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Set<String> _pendingPaths = {};
  final Map<String, DateTime> _failedUntil = <String, DateTime>{};
  final StreamController<String> _thumbnailUpdatesController =
      StreamController<String>.broadcast();

  static const int _maxCacheSize = 200;
  static const int _maxBatchSize = 5;
  static const int _maxConcurrentRequests = 4;
  static const int _maxRetryAttempts = 3;
  static const Duration _retryDelay = Duration(milliseconds: 500);
  static const Duration _failedPathTtl = Duration(seconds: 60);

  @override
  Stream<String> get thumbnailUpdates => _thumbnailUpdatesController.stream;

  @override
  bool shouldSkipThumbnail(String path) {
    _purgeExpiredFailures();
    if (_cache.containsKey(path)) {
      return true;
    }
    final failedUntil = _failedUntil[path];
    if (failedUntil == null) {
      return false;
    }
    return DateTime.now().isBefore(failedUntil);
  }

  @override
  void clearFailedPaths() {
    _failedUntil.clear();
  }

  @override
  Future<AppResult<List<ThumbnailItemEntity>>> loadBatchThumbnails({
    required List<String> paths,
    String type = 'grid',
  }) async {
    final uncachedPaths = paths
        .where((path) => !shouldSkipThumbnail(path) && !_pendingPaths.contains(path))
        .toList();

    if (uncachedPaths.isEmpty) {
      return Success(_getCachedThumbnails(paths));
    }

    _pendingPaths.addAll(uncachedPaths);

    try {
      final batches = _splitIntoBatches(uncachedPaths, _maxBatchSize);
      final allResults = <ThumbnailItemEntity>[];
      final semaphore = _Semaphore(_maxConcurrentRequests);

      final futures = batches.map((batch) async {
        await semaphore.acquire();
        try {
          return await _fetchWithRetry(batch: batch, type: type);
        } finally {
          semaphore.release();
        }
      });

      final batchResults = await Future.wait(futures);

      for (final response in batchResults) {
        _applyBatchResponse(response);
        allResults.addAll(response.items);
      }
    } finally {
      _pendingPaths.removeAll(uncachedPaths);
    }

    return Success(_getCachedThumbnails(paths));
  }

  void _putCache(String key, Uint8List data) {
    _failedUntil.remove(key);
    _cache.remove(key);
    _cache[key] = data;
    _thumbnailUpdatesController.add(key);

    while (_cache.length > _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  void _markFailedPaths(Iterable<String> paths) {
    final expiresAt = DateTime.now().add(_failedPathTtl);
    for (final path in paths) {
      _failedUntil[path] = expiresAt;
    }
  }

  void _applyBatchResponse(ThumbnailBatchResponse response) {
    for (final item in response.items) {
      _putCache(item.path, item.data);
    }
    if (response.failedPaths.isNotEmpty) {
      _markFailedPaths(response.failedPaths);
    }
  }

  Future<ThumbnailBatchResponse> _fetchWithRetry({
    required List<String> batch,
    required String type,
  }) async {
    var attempt = 0;

    while (attempt < _maxRetryAttempts) {
      try {
        return await _remoteDataSource.fetchBatchThumbnails(
          paths: batch,
          type: type,
        );
      } catch (_) {
        attempt++;
        if (attempt >= _maxRetryAttempts) {
          _markFailedPaths(batch);
          return ThumbnailBatchResponse(items: const [], failedPaths: batch);
        }
        await Future.delayed(_retryDelay * attempt);
      }
    }

    _markFailedPaths(batch);
    return ThumbnailBatchResponse(items: const [], failedPaths: batch);
  }

  List<List<String>> _splitIntoBatches(List<String> items, int batchSize) {
    final batches = <List<String>>[];
    for (var i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, items.length);
      batches.add(items.sublist(i, end));
    }
    return batches;
  }

  List<ThumbnailItemEntity> _getCachedThumbnails(List<String> paths) {
    return paths
        .where((path) => _cache.containsKey(path))
        .map(
          (path) => ThumbnailItemEntity(
            path: path,
            data: _cache[path]!,
            contentType: 'image/jpeg',
            size: _cache[path]!.length,
          ),
        )
        .toList();
  }

  @override
  Uint8List? getCachedThumbnail(String path) {
    final data = _cache[path];
    if (data != null) {
      _cache.remove(path);
      _cache[path] = data;
    }
    return data;
  }

  @override
  bool hasCachedThumbnail(String path) {
    return _cache.containsKey(path);
  }

  @override
  void clearCache() {
    _cache.clear();
    _pendingPaths.clear();
    _failedUntil.clear();
  }

  @override
  void evictThumbnail(String path) {
    _cache.remove(path);
    _pendingPaths.remove(path);
    _failedUntil.remove(path);
  }

  @override
  Stream<List<ThumbnailItemEntity>> loadThumbnailsProgressively({
    required List<String> paths,
    String type = 'grid',
  }) async* {
    final uncachedPaths = paths
        .where((path) => !shouldSkipThumbnail(path) && !_pendingPaths.contains(path))
        .toList();

    if (uncachedPaths.isEmpty) {
      return;
    }

    _pendingPaths.addAll(uncachedPaths);

    try {
      final batches = _splitIntoBatches(uncachedPaths, _maxBatchSize);
      final controller = StreamController<List<ThumbnailItemEntity>>();
      var activeFutures = 0;
      var nextIdx = 0;

      void launchNext() {
        while (nextIdx < batches.length &&
            activeFutures < _maxConcurrentRequests) {
          final batch = batches[nextIdx++];
          activeFutures++;
          _fetchWithRetry(batch: batch, type: type)
              .then((response) {
                _applyBatchResponse(response);
                controller.add(response.items);
                activeFutures--;
                launchNext();
                if (activeFutures == 0 && nextIdx >= batches.length) {
                  controller.close();
                }
              })
              .catchError((_) {
                _markFailedPaths(batch);
                controller.add(const <ThumbnailItemEntity>[]);
                activeFutures--;
                launchNext();
                if (activeFutures == 0 && nextIdx >= batches.length) {
                  controller.close();
                }
              });
        }
        if (activeFutures == 0 && nextIdx >= batches.length) {
          controller.close();
        }
      }

      launchNext();
      yield* controller.stream;
    } finally {
      _pendingPaths.removeAll(uncachedPaths);
    }
  }

  void _purgeExpiredFailures() {
    if (_failedUntil.isEmpty) {
      return;
    }
    final now = DateTime.now();
    _failedUntil.removeWhere((_, expiresAt) => !now.isBefore(expiresAt));
  }
}

class _Semaphore {
  _Semaphore(this._permits);

  int _permits;
  final List<Completer<void>> _waitQueue = [];

  Future<void> acquire() async {
    if (_permits > 0) {
      _permits--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _permits++;
    }
  }
}
