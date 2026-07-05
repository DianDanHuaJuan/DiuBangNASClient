/// 文件输入：ThumbnailRepository
/// 文件职责：同步获取已缓存的缩略图数据，供 UI 渲染时调用
/// 文件对外接口：GetCachedThumbnailUseCase
/// 文件包含：GetCachedThumbnailUseCase
import 'dart:typed_data';
import 'dart:async';
import '../../domain/repositories/thumbnail_repository.dart';

/// 输入：缩略图完整路径
/// 职责：同步从缓存读取缩略图二进制数据
/// 对外接口：call() 返回 Uint8List?，未缓存返回 null
class GetCachedThumbnailUseCase {
  final ThumbnailRepository _repository;

  GetCachedThumbnailUseCase({required ThumbnailRepository repository})
    : _repository = repository;

  Uint8List? call(String path) {
    return _repository.getCachedThumbnail(path);
  }

  Stream<String> get thumbnailUpdates => _repository.thumbnailUpdates;

  bool hasCached(String path) {
    return _repository.hasCachedThumbnail(path);
  }

  bool shouldSkip(String path) {
    return _repository.shouldSkipThumbnail(path);
  }

  void clearCache() {
    _repository.clearCache();
  }

  void clearFailedPaths() {
    _repository.clearFailedPaths();
  }

  void evictThumbnail(String path) {
    _repository.evictThumbnail(path);
  }
}
