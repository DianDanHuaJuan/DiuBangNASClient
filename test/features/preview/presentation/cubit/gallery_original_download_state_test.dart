import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/preview/presentation/cubit/gallery_original_download_state.dart';

void main() {
  group('GalleryOriginalDownloadState', () {
    test('localPath with active download is not original ready', () {
      const state = GalleryOriginalDownloadState(
        localPath: '/cache/original.jpg',
        isDownloading: true,
        progress: 0.4,
      );

      expect(state.hasLocalPath, isTrue);
      expect(state.isOriginalReady, isFalse);
      expect(state.isCached, isFalse);
      expect(state.canViewOriginal, isFalse);
      expect(state.canSaveToPublic, isFalse);
    });

    test('completed download without failure is original ready', () {
      const state = GalleryOriginalDownloadState(
        localPath: '/cache/original.jpg',
        progress: 1,
      );

      expect(state.isOriginalReady, isTrue);
      expect(state.isCached, isTrue);
      expect(state.canViewOriginal, isTrue);
      expect(state.canSaveToPublic, isTrue);
    });

    test('failed download is not original ready and can retry', () {
      const state = GalleryOriginalDownloadState(
        localPath: '/cache/original.jpg',
        errorMessage: '原图下载失败，请重试。',
      );

      expect(state.isOriginalReady, isFalse);
      expect(state.isCached, isFalse);
      expect(state.needsDownloadRetry, isTrue);
      expect(state.canSaveToPublic, isFalse);
    });

    test('saved original is cached but cannot save again', () {
      const state = GalleryOriginalDownloadState(
        localPath: '/cache/original.jpg',
        publicUri: 'content://media/external/images/1',
        progress: 1,
      );

      expect(state.isOriginalReady, isTrue);
      expect(state.isSaved, isTrue);
      expect(state.canSaveToPublic, isFalse);
    });
  });
}
