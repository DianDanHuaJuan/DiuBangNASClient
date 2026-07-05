/// 文件输入：远程数据源、当前时间提供器
/// 文件职责：实现预览仓库，包含具备过期感知的内存缓存
/// 文件对外接口：PreviewRepositoryImpl
/// 文件包含：PreviewRepositoryImpl、_CachedPreviewItem
import '../../../../core/result/app_result.dart';
import '../../../../core/path/nas_path.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/network/nas_network_access_policy.dart';
import '../../domain/entities/preview_item_entity.dart';
import '../../domain/repositories/preview_repository.dart';
import '../datasources/preview_remote_data_source.dart';
import '../../../../core/image/image_cache_key_builder.dart';

class PreviewRepositoryImpl implements PreviewRepository {
  final PreviewRemoteDataSource _remoteDataSource;
  final DateTime Function() _nowProvider;
  final Map<String, _CachedPreviewItem> _cache = {};
  static const Duration _expirySafetyWindow = Duration(seconds: 30);

  PreviewRepositoryImpl({
    required PreviewRemoteDataSource remoteDataSource,
    DateTime Function()? nowProvider,
  }) : _remoteDataSource = remoteDataSource,
       _nowProvider = nowProvider ?? DateTime.now;

  String _cacheKey(NasPath path) => ImageCacheKeyBuilder.previewKey(path);

  @override
  Future<AppResult<PreviewItemEntity>> loadPreview(NasPath path) async {
    final key = _cacheKey(path);
    var cached = _cache[key];

    if (cached != null && !_shouldRefresh(cached)) {
      return Success(cached.item);
    }

    try {
      final dto = await _remoteDataSource.loadPreview(path);
      final item = PreviewItemEntity(
        kind: dto.kindEnum,
        strategy: dto.strategyEnum,
        url: _normalizeRemoteUrl(dto.url),
        headers: dto.headers,
        contentType: dto.contentType,
        size: dto.size,
        thumbnailUrl: _normalizeRemoteUrl(dto.thumbnailUrl),
        posterUrl: _normalizeRemoteUrl(dto.posterUrl),
        expiresAt: dto.expiresAt,
      );

      _cache[key] = _CachedPreviewItem(
        item: item,
        expiresAt: _parseExpiresAt(item.expiresAt),
        hasExplicitExpiry:
            item.expiresAt != null && item.expiresAt!.trim().isNotEmpty,
      );
      return Success(item);
    } on AppException catch (e) {
      return Failure(AppFailure(code: e.code, message: e.message));
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'PREVIEW_ERROR',
          message: 'Failed to load preview: ${e.toString()}',
        ),
      );
    }
  }

  void clearCache() {
    _cache.clear();
  }

  bool _shouldRefresh(_CachedPreviewItem cachedItem) {
    if (!cachedItem.hasExplicitExpiry) {
      return false;
    }

    final expiresAt = cachedItem.expiresAt;
    if (expiresAt == null) {
      return true;
    }

    final refreshAt = _nowProvider().toUtc().add(_expirySafetyWindow);
    return !expiresAt.isAfter(refreshAt);
  }

  DateTime? _parseExpiresAt(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(rawValue)?.toUtc();
  }

  String? _normalizeRemoteUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return rawUrl;
    }
    return NasNetworkAccessPolicy.normalizeAbsoluteUrl(rawUrl);
  }
}

class _CachedPreviewItem {
  final PreviewItemEntity item;
  final DateTime? expiresAt;
  final bool hasExplicitExpiry;

  const _CachedPreviewItem({
    required this.item,
    required this.expiresAt,
    required this.hasExplicitExpiry,
  });
}
