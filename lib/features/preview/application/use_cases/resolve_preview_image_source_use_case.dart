/// 文件输入：服务端基地址、ResolvePreviewImageSourceParams
/// 文件职责：将 preview/meta 和当前缩略图上下文解析为图片展示来源
/// 文件对外接口：ResolvePreviewImageSourceUseCase
/// 文件包含：ResolvePreviewImageSourceUseCase
import '../../../../core/image/image_cache_key_builder.dart';
import '../../../../core/path/nas_path.dart';
import '../../domain/entities/preview_image_source.dart';
import '../params/resolve_preview_image_source_params.dart';

/// 输入：服务端基地址、ResolvePreviewImageSourceParams。
/// 职责：优先使用服务端主预览地址作为图片预览来源，并保留缩略图与原图回退链路。
/// 对外接口：call()。
class ResolvePreviewImageSourceUseCase {
  ResolvePreviewImageSourceUseCase({required String baseUrl})
    : _baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

  final String _baseUrl;

  PreviewImageSource call(ResolvePreviewImageSourceParams params) {
    final nasPath = params.nasPath;
    final item = params.item;

    return PreviewImageSource(
      nasPath: nasPath,
      heroTag: ImageCacheKeyBuilder.heroTag(nasPath),
      previewUrl: item.url ?? _buildThumbnailUrl(nasPath, type: 'preview'),
      headers: item.headers,
      previewCacheKey: ImageCacheKeyBuilder.previewKey(nasPath),
      thumbnailUrl:
          item.thumbnailUrl ?? _buildThumbnailUrl(nasPath, type: 'grid'),
      thumbnailCacheKey: ImageCacheKeyBuilder.thumbnailKey(
        nasPath,
        type: 'grid',
      ),
      thumbnailData: params.thumbnailData,
      originalUrl: item.url,
      originalCacheKey: ImageCacheKeyBuilder.originalKey(nasPath),
    );
  }

  String _buildThumbnailUrl(NasPath nasPath, {required String type}) {
    final encodedPath = Uri.encodeQueryComponent(nasPath.toApiPath());
    return '$_baseUrl/api/v1/thumbnail?path=$encodedPath&type=$type';
  }
}
