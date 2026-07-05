/// 文件输入：NasPath、预览地址、原图地址、缩略图数据、缓存 Key
/// 文件职责：表达图片预览页实际使用的多级图片来源
/// 文件对外接口：PreviewImageSource
/// 文件包含：PreviewImageSource
import 'dart:typed_data';

import '../../../../core/path/nas_path.dart';

/// 输入：NasPath、预览地址、原图地址、缩略图数据、缓存 Key。
/// 职责：统一表达网格缩略图、预览图和原图在客户端的图片来源。
/// 对外接口：PreviewImageSource 实体及其状态 getter。
class PreviewImageSource {
  final NasPath nasPath;
  final String heroTag;
  final String previewUrl;
  final Map<String, String>? headers;
  final String previewCacheKey;
  final String? thumbnailUrl;
  final String? thumbnailCacheKey;
  final Uint8List? thumbnailData;
  final String? originalUrl;
  final String originalCacheKey;

  const PreviewImageSource({
    required this.nasPath,
    required this.heroTag,
    required this.previewUrl,
    required this.headers,
    required this.previewCacheKey,
    required this.thumbnailUrl,
    required this.thumbnailCacheKey,
    required this.thumbnailData,
    required this.originalUrl,
    required this.originalCacheKey,
  });

  bool get hasThumbnailData => thumbnailData != null;

  bool get hasThumbnailUrl =>
      thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty;

  bool get hasOriginalUrl =>
      originalUrl != null && originalUrl!.trim().isNotEmpty;
}
