/// 文件输入：ResolvePreviewImageSourceUseCase、ResolvePreviewImageSourceParams
/// 文件职责：验证图片来源解析会优先使用服务端主预览地址，并保留缩略图与原图来源
/// 文件对外接口：main
/// 文件包含：main
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/image/image_cache_key_builder.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/features/preview/application/params/resolve_preview_image_source_params.dart';
import 'package:nasclient/features/preview/application/use_cases/resolve_preview_image_source_use_case.dart';
import 'package:nasclient/features/preview/domain/entities/preview_item_entity.dart';
import 'package:nasclient/features/preview/domain/entities/preview_kind.dart';
import 'package:nasclient/features/preview/domain/entities/preview_strategy.dart';

void main() {
  group('ResolvePreviewImageSourceUseCase', () {
    test('prefers the server main url for image previews', () {
      final useCase = ResolvePreviewImageSourceUseCase(
        baseUrl: 'http://nas.local:8080/',
      );
      final nasPath = const NasPath(
        rootId: 'library',
        path: '/albums/2026/a 1.jpg',
      );
      final thumbnailData = Uint8List.fromList(const [1, 2, 3, 4]);
      const headers = {'Authorization': 'Basic abc'};
      const item = PreviewItemEntity(
        kind: PreviewKind.image,
        strategy: PreviewStrategy.native,
        url: 'http://nas.local:8080/dav/library/albums/2026/a%201.jpg',
        headers: headers,
      );

      final result = useCase(
        ResolvePreviewImageSourceParams(
          nasPath: nasPath,
          item: item,
          thumbnailData: thumbnailData,
        ),
      );

      final encodedPath = Uri.encodeQueryComponent(nasPath.toApiPath());

      expect(
        result.previewUrl,
        'http://nas.local:8080/dav/library/albums/2026/a%201.jpg',
      );
      expect(
        result.thumbnailUrl,
        'http://nas.local:8080/api/v1/thumbnail?path=$encodedPath&type=grid',
      );
      expect(result.previewCacheKey, ImageCacheKeyBuilder.previewKey(nasPath));
      expect(
        result.thumbnailCacheKey,
        ImageCacheKeyBuilder.thumbnailKey(nasPath, type: 'grid'),
      );
      expect(
        result.originalCacheKey,
        ImageCacheKeyBuilder.originalKey(nasPath),
      );
      expect(result.heroTag, ImageCacheKeyBuilder.heroTag(nasPath));
      expect(result.originalUrl, item.url);
      expect(result.headers, headers);
      expect(result.thumbnailData, same(thumbnailData));
      expect(result.hasThumbnailData, isTrue);
      expect(result.hasThumbnailUrl, isTrue);
      expect(result.hasOriginalUrl, isTrue);
    });

    test(
      'falls back to preview thumbnails when image metadata url is missing',
      () {
        final useCase = ResolvePreviewImageSourceUseCase(
          baseUrl: 'http://nas.local:8080/',
        );
        const nasPath = NasPath(rootId: 'fs', path: '/camera/c.jpg');
        const item = PreviewItemEntity(
          kind: PreviewKind.image,
          strategy: PreviewStrategy.native,
          url: null,
        );

        final result = useCase(
          const ResolvePreviewImageSourceParams(
            nasPath: nasPath,
            item: item,
            thumbnailData: null,
          ),
        );

        final encodedPath = Uri.encodeQueryComponent(nasPath.toApiPath());
        expect(
          result.previewUrl,
          'http://nas.local:8080/api/v1/thumbnail?path=$encodedPath&type=preview',
        );
      },
    );

    test(
      'keeps server thumbnail url when preview metadata already provides one',
      () {
        final useCase = ResolvePreviewImageSourceUseCase(
          baseUrl: 'http://nas.local:8080',
        );
        const nasPath = NasPath(rootId: 'fs', path: '/camera/b.jpg');
        const item = PreviewItemEntity(
          kind: PreviewKind.image,
          strategy: PreviewStrategy.native,
          url: 'http://nas.local:8080/dav/fs/camera/b.jpg',
          thumbnailUrl: 'http://cdn.example.com/thumb/b.jpg',
        );

        final result = useCase(
          const ResolvePreviewImageSourceParams(
            nasPath: nasPath,
            item: item,
            thumbnailData: null,
          ),
        );

        expect(result.thumbnailUrl, 'http://cdn.example.com/thumb/b.jpg');
        expect(result.hasThumbnailData, isFalse);
        expect(result.hasThumbnailUrl, isTrue);
      },
    );
  });
}
