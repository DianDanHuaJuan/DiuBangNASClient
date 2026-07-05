import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/files/data/datasources/thumbnail_remote_data_source.dart';
import 'package:nasclient/features/files/data/models/thumbnail_batch_response.dart';
import 'package:nasclient/features/files/data/repositories/thumbnail_repository_impl.dart';
import 'package:nasclient/features/files/domain/entities/thumbnail_item_entity.dart';

void main() {
  group('ThumbnailRepositoryImpl negative cache', () {
    test('marks failed batch paths and skips them until cleared', () async {
      final remote = _StubThumbnailRemoteDataSource(
        responses: <ThumbnailBatchResponse>[
          const ThumbnailBatchResponse(
            items: <ThumbnailItemEntity>[],
            failedPaths: <String>['/fs/photos/a.jpg'],
          ),
        ],
      );
      final repository = ThumbnailRepositoryImpl(remoteDataSource: remote);

      expect(repository.shouldSkipThumbnail('/fs/photos/a.jpg'), isFalse);

      final firstResult = await repository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg'],
      );

      expect(firstResult.isSuccess, isTrue);
      expect(firstResult.dataOrNull, isEmpty);
      expect(repository.shouldSkipThumbnail('/fs/photos/a.jpg'), isTrue);
      expect(remote.callCount, 1);

      final secondResult = await repository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg'],
      );

      expect(secondResult.isSuccess, isTrue);
      expect(remote.callCount, 1);

      repository.clearFailedPaths();

      expect(repository.shouldSkipThumbnail('/fs/photos/a.jpg'), isFalse);
    });

    test('caches successful thumbnails and clears failures on success', () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final remote = _StubThumbnailRemoteDataSource(
        responses: <ThumbnailBatchResponse>[
          ThumbnailBatchResponse(
            items: <ThumbnailItemEntity>[
              ThumbnailItemEntity(
                path: '/fs/photos/a.jpg',
                data: bytes,
                contentType: 'image/jpeg',
                size: bytes.length,
              ),
            ],
            failedPaths: const <String>[],
          ),
        ],
      );
      final repository = ThumbnailRepositoryImpl(remoteDataSource: remote);

      final result = await repository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg'],
      );

      expect(result.isSuccess, isTrue);
      expect(repository.hasCachedThumbnail('/fs/photos/a.jpg'), isTrue);
      expect(
        repository.getCachedThumbnail('/fs/photos/a.jpg'),
        equals(bytes),
      );
      expect(repository.shouldSkipThumbnail('/fs/photos/a.jpg'), isTrue);
    });

    test('evictThumbnail removes only the targeted cache entry', () async {
      final bytesA = Uint8List.fromList(<int>[1, 2, 3]);
      final bytesB = Uint8List.fromList(<int>[4, 5, 6]);
      final remote = _StubThumbnailRemoteDataSource(
        responses: <ThumbnailBatchResponse>[
          ThumbnailBatchResponse(
            items: <ThumbnailItemEntity>[
              ThumbnailItemEntity(
                path: '/fs/photos/a.jpg',
                data: bytesA,
                contentType: 'image/jpeg',
                size: bytesA.length,
              ),
              ThumbnailItemEntity(
                path: '/fs/photos/b.jpg',
                data: bytesB,
                contentType: 'image/jpeg',
                size: bytesB.length,
              ),
            ],
            failedPaths: const <String>[],
          ),
        ],
      );
      final repository = ThumbnailRepositoryImpl(remoteDataSource: remote);

      await repository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg', '/fs/photos/b.jpg'],
      );
      expect(repository.hasCachedThumbnail('/fs/photos/a.jpg'), isTrue);
      expect(repository.hasCachedThumbnail('/fs/photos/b.jpg'), isTrue);

      repository.evictThumbnail('/fs/photos/a.jpg');

      expect(repository.hasCachedThumbnail('/fs/photos/a.jpg'), isFalse);
      expect(repository.hasCachedThumbnail('/fs/photos/b.jpg'), isTrue);
    });

    test('clearCache removes cached thumbnails and failed paths', () async {
      final remote = _StubThumbnailRemoteDataSource(
        responses: <ThumbnailBatchResponse>[
          const ThumbnailBatchResponse(
            items: <ThumbnailItemEntity>[],
            failedPaths: <String>['/fs/photos/a.jpg'],
          ),
        ],
      );
      final repository = ThumbnailRepositoryImpl(remoteDataSource: remote);

      await repository.loadBatchThumbnails(paths: <String>['/fs/photos/a.jpg']);
      expect(repository.shouldSkipThumbnail('/fs/photos/a.jpg'), isTrue);

      repository.clearCache();

      expect(repository.shouldSkipThumbnail('/fs/photos/a.jpg'), isFalse);
      expect(repository.hasCachedThumbnail('/fs/photos/a.jpg'), isFalse);
    });
  });
}

class _StubThumbnailRemoteDataSource extends ThumbnailRemoteDataSource {
  _StubThumbnailRemoteDataSource({required this.responses})
    : super(apiClient: _UnusedNasApiClient());

  final List<ThumbnailBatchResponse> responses;
  var callCount = 0;

  @override
  Future<ThumbnailBatchResponse> fetchBatchThumbnails({
    required List<String> paths,
    String type = 'grid',
  }) async {
    callCount++;
    final index = (callCount - 1).clamp(0, responses.length - 1);
    return responses[index];
  }
}

class _UnusedNasApiClient extends NasApiClient {
  _UnusedNasApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        session: CurrentSession(),
        dio: Dio(),
      );
}
