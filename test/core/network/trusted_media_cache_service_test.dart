import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/trusted_media_cache_service.dart';

void main() {
  group('TrustedMediaCacheService.buildFileNameForTesting', () {
    test('builds fixed-length cache filenames for very long keys', () {
      final longCacheKey =
          'preview:fs:${List.filled(1200, 'very-long-segment').join('/')}';

      final fileName = TrustedMediaCacheService.buildFileNameForTesting(
        url: 'https://example.com/cover.jpg',
        cacheKey: longCacheKey,
      );

      expect(fileName, startsWith('preview_'));
      expect(fileName, endsWith('.jpg'));
      expect(fileName.length, lessThan(90));
    });

    test('uses distinct filenames for different cache keys', () {
      final first = TrustedMediaCacheService.buildFileNameForTesting(
        url: 'https://example.com/cover.jpg',
        cacheKey: 'preview:fs:/albums/a/cover.jpg',
      );
      final second = TrustedMediaCacheService.buildFileNameForTesting(
        url: 'https://example.com/cover.jpg',
        cacheKey: 'original:fs:/albums/a/cover.jpg',
      );

      expect(first, isNot(second));
    });
  });
}
