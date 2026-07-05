/// 文件输入：NasPath、视频地址、封面地址、缩略图数据、请求头、缓存 Key
/// 文件职责：表达视频预览页实际使用的视频与封面来源
/// 文件对外接口：PreviewVideoSource
/// 文件包含：PreviewVideoSource
import 'dart:typed_data';

import '../../../../core/path/nas_path.dart';
import 'preview_strategy.dart';

/// 输入：NasPath、视频地址、封面地址、缩略图数据、请求头、缓存 Key。
/// 职责：统一表达视频播放地址、封面占位图与请求头等媒体预览来源。
/// 对外接口：PreviewVideoSource 实体及其状态 getter。
class PreviewVideoSource {
  final NasPath nasPath;
  final String heroTag;
  final String videoUrl;
  final String videoCacheKey;
  final Map<String, String>? headers;
  final PreviewStrategy strategy;
  final String? posterUrl;
  final String? posterCacheKey;
  final Uint8List? thumbnailData;

  const PreviewVideoSource({
    required this.nasPath,
    required this.heroTag,
    required this.videoUrl,
    required this.videoCacheKey,
    required this.headers,
    required this.strategy,
    required this.posterUrl,
    required this.posterCacheKey,
    required this.thumbnailData,
  });

  bool get hasVideoUrl => videoUrl.trim().isNotEmpty;

  bool get hasPosterUrl => posterUrl != null && posterUrl!.trim().isNotEmpty;

  bool get hasThumbnailData => thumbnailData != null;
}
