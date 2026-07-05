/// 文件输入：ResolvePreviewVideoSourceUseCase、ResolvePreviewVideoSourceParams
/// 文件职责：验证视频来源解析会稳定生成播放地址、封面图和缩略图占位来源
/// 文件对外接口：main
/// 文件包含：main
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/image/image_cache_key_builder.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/features/preview/application/params/resolve_preview_video_source_params.dart';
import 'package:nasclient/features/preview/application/use_cases/resolve_preview_video_source_use_case.dart';
import 'package:nasclient/features/preview/domain/entities/preview_item_entity.dart';
import 'package:nasclient/features/preview/domain/entities/preview_kind.dart';
import 'package:nasclient/features/preview/domain/entities/preview_strategy.dart';

void main() {
  group('ResolvePreviewVideoSourceUseCase', () {
    test('builds video url and preview poster fallback for videos', () {
      final useCase = ResolvePreviewVideoSourceUseCase(
        baseUrl: 'http://nas.local:8080/',
      );
      final nasPath = const NasPath(rootId: 'fs', path: '/movies/demo 1.mp4');
      final thumbnailData = Uint8List.fromList(const [4, 3, 2, 1]);
      const headers = {'Authorization': 'Basic abc'};
      const item = PreviewItemEntity(
        kind: PreviewKind.video,
        strategy: PreviewStrategy.progressive,
        url: 'http://nas.local:8080/dav/fs/movies/demo%201.mp4',
        headers: headers,
      );

      final result = useCase(
        ResolvePreviewVideoSourceParams(
          nasPath: nasPath,
          item: item,
          thumbnailData: thumbnailData,
        ),
      );

      final encodedPath = Uri.encodeQueryComponent(nasPath.toApiPath());

      expect(result.videoUrl, item.url);
      expect(
        result.posterUrl,
        'http://nas.local:8080/api/v1/thumbnail?path=$encodedPath&type=preview',
      );
      expect(result.posterCacheKey, ImageCacheKeyBuilder.previewKey(nasPath));
      expect(result.heroTag, ImageCacheKeyBuilder.heroTag(nasPath));
      expect(result.headers, headers);
      expect(result.strategy, PreviewStrategy.progressive);
      expect(result.thumbnailData, same(thumbnailData));
      expect(result.hasVideoUrl, isTrue);
      expect(result.hasPosterUrl, isTrue);
      expect(result.hasThumbnailData, isTrue);
    });

    test('prefers explicit poster url from preview metadata', () {
      final useCase = ResolvePreviewVideoSourceUseCase(
        baseUrl: 'http://nas.local:8080',
      );
      const nasPath = NasPath(rootId: 'library', path: '/clips/a.mp4');
      const item = PreviewItemEntity(
        kind: PreviewKind.video,
        strategy: PreviewStrategy.native,
        url: 'http://nas.local:8080/dav/library/clips/a.mp4',
        posterUrl: 'http://cdn.example.com/posters/a.jpg',
        thumbnailUrl: 'http://cdn.example.com/thumbs/a.jpg',
      );

      final result = useCase(
        const ResolvePreviewVideoSourceParams(
          nasPath: nasPath,
          item: item,
          thumbnailData: null,
        ),
      );

      expect(result.posterUrl, 'http://cdn.example.com/posters/a.jpg');
      expect(result.hasPosterUrl, isTrue);
      expect(result.hasThumbnailData, isFalse);
    });
  });
}
