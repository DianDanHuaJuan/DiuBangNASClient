/// 文件输入：NasPath、缩略图类型
/// 文件职责：统一生成图片相关的稳定缓存 Key 和 Hero Tag
/// 文件对外接口：ImageCacheKeyBuilder
/// 文件包含：ImageCacheKeyBuilder
import 'dart:convert';
import '../path/nas_path.dart';

/// 输入：NasPath、缩略图类型。
/// 职责：为缩略图、预览图、原图和 Hero 动画生成稳定标识。
/// 对外接口：previewKey()、thumbnailKey()、originalKey()、heroTag()。
class ImageCacheKeyBuilder {
  const ImageCacheKeyBuilder._();

  static String _sanitizePath(NasPath path) {
    // Treat root path as empty to avoid leading slashes in keys.
    final raw = path.path == '/' ? '' : path.path;
    final normalized = raw.startsWith('/') ? raw.substring(1) : raw;
    // Encode to base64-url to produce a filesystem-safe and reversible token.
    return base64Url.encode(utf8.encode(normalized));
  }

  static String previewKey(NasPath path) {
    final sp = _sanitizePath(path);
    return 'preview:${path.rootId}:$sp';
  }

  static String thumbnailKey(NasPath path, {required String type}) {
    final sp = _sanitizePath(path);
    return 'thumbnail:$type:${path.rootId}:$sp';
  }

  static String originalKey(NasPath path) {
    final sp = _sanitizePath(path);
    return 'original:${path.rootId}:$sp';
  }

  static String videoKey(NasPath path) {
    final sp = _sanitizePath(path);
    return 'video:${path.rootId}:$sp';
  }

  static String heroTag(NasPath path) {
    final sp = _sanitizePath(path);
    return 'hero:${path.rootId}:$sp';
  }
}
