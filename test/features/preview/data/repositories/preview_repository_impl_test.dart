/// 文件输入：PreviewRepositoryImpl、预览 DTO、NAS 路径
/// 文件职责：验证预览仓库的内存缓存与 expiresAt 过期刷新行为
/// 文件对外接口：main
/// 文件包含：main、_FakePreviewRemoteDataSource
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/preview/data/datasources/preview_remote_data_source.dart';
import 'package:nasclient/features/preview/data/models/preview_item_dto.dart';
import 'package:nasclient/features/preview/data/repositories/preview_repository_impl.dart';
import 'package:nasclient/features/preview/domain/entities/preview_item_entity.dart';

void main() {
  group('PreviewRepositoryImpl', () {
    test('caches preview metadata without expiry', () async {
      final remoteDataSource = _FakePreviewRemoteDataSource(
        responses: const [
          PreviewItemDto(
            kind: 'image',
            strategy: 'direct',
            url: 'https://localhost:9443/a.jpg',
          ),
        ],
      );
      final repository = PreviewRepositoryImpl(
        remoteDataSource: remoteDataSource,
        nowProvider: () => DateTime.utc(2026, 4, 6, 7),
      );
      const path = NasPath(rootId: 'library', path: '/images/a.jpg');

      final first = await repository.loadPreview(path);
      final second = await repository.loadPreview(path);

      expect(remoteDataSource.callCount, 1);
      expect(_unwrapSuccess(first).url, 'https://localhost:9443/a.jpg');
      expect(_unwrapSuccess(second).url, 'https://localhost:9443/a.jpg');
    });

    test('refreshes preview metadata when cached url is expired', () async {
      final remoteDataSource = _FakePreviewRemoteDataSource(
        responses: const [
          PreviewItemDto(
            kind: 'image',
            strategy: 'direct',
            url: 'https://localhost:9443/a-old.jpg',
            expiresAt: '2026-04-06T07:00:10Z',
          ),
          PreviewItemDto(
            kind: 'image',
            strategy: 'direct',
            url: 'https://localhost:9443/a-new.jpg',
            expiresAt: '2026-04-06T07:10:00Z',
          ),
        ],
      );
      final repository = PreviewRepositoryImpl(
        remoteDataSource: remoteDataSource,
        nowProvider: () => DateTime.utc(2026, 4, 6, 7, 1),
      );
      const path = NasPath(rootId: 'library', path: '/images/a.jpg');

      final first = await repository.loadPreview(path);
      final second = await repository.loadPreview(path);

      expect(remoteDataSource.callCount, 2);
      expect(_unwrapSuccess(first).url, 'https://localhost:9443/a-old.jpg');
      expect(_unwrapSuccess(second).url, 'https://localhost:9443/a-new.jpg');
    });

    test('keeps cached preview metadata before expiry window', () async {
      final remoteDataSource = _FakePreviewRemoteDataSource(
        responses: const [
          PreviewItemDto(
            kind: 'image',
            strategy: 'direct',
            url: 'https://localhost:9443/a.jpg',
            expiresAt: '2026-04-06T07:05:00Z',
          ),
        ],
      );
      final repository = PreviewRepositoryImpl(
        remoteDataSource: remoteDataSource,
        nowProvider: () => DateTime.utc(2026, 4, 6, 7, 2),
      );
      const path = NasPath(rootId: 'library', path: '/images/a.jpg');

      final first = await repository.loadPreview(path);
      final second = await repository.loadPreview(path);

      expect(remoteDataSource.callCount, 1);
      expect(_unwrapSuccess(first).url, 'https://localhost:9443/a.jpg');
      expect(_unwrapSuccess(second).url, 'https://localhost:9443/a.jpg');
    });

    test('rejects public http preview metadata url', () async {
      final remoteDataSource = _FakePreviewRemoteDataSource(
        responses: const [
          PreviewItemDto(
            kind: 'image',
            strategy: 'direct',
            url: 'http://example.com/a.jpg',
          ),
        ],
      );
      final repository = PreviewRepositoryImpl(
        remoteDataSource: remoteDataSource,
        nowProvider: () => DateTime.utc(2026, 4, 6, 7),
      );
      const path = NasPath(rootId: 'library', path: '/images/a.jpg');

      final result = await repository.loadPreview(path);

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.code, 'HTTP_ADDRESS_NOT_ALLOWED');
    });
  });
}

PreviewItemEntity _unwrapSuccess(AppResult<PreviewItemEntity> result) {
  late PreviewItemEntity item;
  result.when(
    success: (data) => item = data,
    failure: (failure) =>
        fail('Expected success but got failure: ${failure.message}'),
  );
  return item;
}

class _FakePreviewRemoteDataSource extends PreviewRemoteDataSource {
  final List<PreviewItemDto> _responses;
  int callCount = 0;

  _FakePreviewRemoteDataSource({required List<PreviewItemDto> responses})
    : _responses = List.of(responses),
      super(
        apiClient: NasApiClient(
          baseUrl: 'https://localhost:9443',
          session: CurrentSession(),
          dio: Dio(),
        ),
      );

  @override
  Future<PreviewItemDto> loadPreview(NasPath path) async {
    callCount++;
    if (_responses.isEmpty) {
      throw StateError('No fake preview responses left for $path');
    }
    return _responses.removeAt(0);
  }
}
