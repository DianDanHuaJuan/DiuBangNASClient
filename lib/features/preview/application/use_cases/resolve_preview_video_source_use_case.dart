/// 文件输入：服务端基地址、ResolvePreviewVideoSourceParams
/// 文件职责：将 preview/meta 和当前缩略图上下文解析为视频展示来源
/// 文件对外接口：ResolvePreviewVideoSourceUseCase
/// 文件包含：ResolvePreviewVideoSourceUseCase
import '../../../../core/image/image_cache_key_builder.dart';
import '../../../../core/path/nas_path.dart';
import '../../domain/entities/preview_item_entity.dart';
import '../../domain/entities/preview_video_source.dart';
import '../params/resolve_preview_video_source_params.dart';

/// 输入：服务端基地址、ResolvePreviewVideoSourceParams。
/// 职责：把视频播放地址、封面图与缩略图上下文解析为统一展示来源。
/// 对外接口：call()。
class ResolvePreviewVideoSourceUseCase {
  ResolvePreviewVideoSourceUseCase({required String baseUrl})
    : _baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

  final String _baseUrl;

  PreviewVideoSource call(ResolvePreviewVideoSourceParams params) {
    final nasPath = params.nasPath;
    final item = params.item;
    final posterUrl = _resolvePosterUrl(nasPath, item);

    return PreviewVideoSource(
      nasPath: nasPath,
      heroTag: ImageCacheKeyBuilder.heroTag(nasPath),
      videoUrl: item.url ?? '',
      videoCacheKey: ImageCacheKeyBuilder.videoKey(nasPath),
      headers: item.headers,
      strategy: item.strategy,
      posterUrl: posterUrl,
      posterCacheKey: posterUrl == null || posterUrl.trim().isEmpty
          ? null
          : ImageCacheKeyBuilder.previewKey(nasPath),
      thumbnailData: params.thumbnailData,
    );
  }

  String? _resolvePosterUrl(NasPath nasPath, PreviewItemEntity item) {
    final posterUrl = item.posterUrl;
    if (posterUrl != null && posterUrl.trim().isNotEmpty) {
      return posterUrl;
    }

    final thumbnailUrl = item.thumbnailUrl;
    if (thumbnailUrl != null && thumbnailUrl.trim().isNotEmpty) {
      return thumbnailUrl;
    }

    return _buildThumbnailUrl(nasPath, type: 'preview');
  }

  String _buildThumbnailUrl(NasPath nasPath, {required String type}) {
    final encodedPath = Uri.encodeQueryComponent(nasPath.toApiPath());
    return '$_baseUrl/api/v1/thumbnail?path=$encodedPath&type=$type';
  }
}
