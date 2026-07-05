/// 文件输入：路径列表、缩略图类型
/// 文件职责：定义缩略图仓库抽象接口，支持异步加载、逐批渐进加载和同步缓存访问
/// 文件对外接口：ThumbnailRepository
/// 文件包含：ThumbnailRepository
import 'dart:typed_data';
import 'dart:async';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/thumbnail_item_entity.dart';

abstract class ThumbnailRepository {
  Stream<String> get thumbnailUpdates;

  /// 输入：路径列表、缩略图类型
  /// 职责：异步批量加载缩略图，优先从缓存获取，未命中则从网络请求
  /// 对外接口：返回缩略图实体列表
  Future<AppResult<List<ThumbnailItemEntity>>> loadBatchThumbnails({
    required List<String> paths,
    String type = 'grid',
  });

  /// 输入：路径列表、缩略图类型
  /// 职责：逐批渐进加载缩略图，每完成一个小批次（3个）就通过 Stream 通知调用方
  /// 对外接口：返回 Stream，每个事件为一个小批次加载完成的缩略图列表
  Stream<List<ThumbnailItemEntity>> loadThumbnailsProgressively({
    required List<String> paths,
    String type = 'grid',
  });

  /// 输入：缩略图路径
  /// 职责：同步获取已缓存的缩略图数据
  /// 对外接口：返回缩略图二进制数据，未缓存返回 null
  Uint8List? getCachedThumbnail(String path);

  /// 输入：无
  /// 职责：检查指定路径的缩略图是否已缓存
  /// 对外接口：返回是否已缓存
  bool hasCachedThumbnail(String path);

  /// 输入：无
  /// 职责：清空所有缓存的缩略图
  /// 对外接口：无返回值
  void clearCache();

  /// 输入：缩略图路径
  /// 职责：判断路径是否应跳过请求（已缓存或处于失败冷却期）
  bool shouldSkipThumbnail(String path);

  /// 输入：无
  /// 职责：清除失败冷却记录，供下拉刷新后重试
  void clearFailedPaths();

  /// 输入：缩略图完整路径
  /// 职责：从缓存中移除单条缩略图（不触发全量失效）
  void evictThumbnail(String path);
}
