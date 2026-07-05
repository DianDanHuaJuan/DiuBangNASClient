import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/files/application/params/list_directory_params.dart';
import 'package:nasclient/features/files/application/use_cases/batch_delete_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/create_folder_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/delete_file_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/get_cached_thumbnail_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/is_root_writable_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/list_directory_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/load_visible_thumbnails_use_case.dart';
import 'package:nasclient/features/files/application/use_cases/switch_file_root_use_case.dart';
import 'package:nasclient/features/files/data/datasources/thumbnail_remote_data_source.dart';
import 'package:nasclient/features/files/data/models/thumbnail_batch_response.dart';
import 'package:nasclient/features/files/data/repositories/thumbnail_repository_impl.dart';
import 'package:nasclient/features/files/domain/entities/file_entry_entity.dart';
import 'package:nasclient/features/files/domain/entities/file_list_page_entity.dart';
import 'package:nasclient/features/files/domain/entities/file_type.dart';
import 'package:nasclient/features/files/domain/entities/thumbnail_item_entity.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/features/files/domain/repositories/file_repository.dart';
import 'package:nasclient/features/files/domain/entities/batch_delete_result_entity.dart';
import 'package:nasclient/features/files/presentation/cubit/file_browser_cubit.dart';
import 'package:nasclient/features/files/presentation/cubit/file_browser_state.dart';

const _testRoots = <RootInfo>[
  RootInfo(
    id: 'fs',
    name: 'FS',
    path: '/',
    type: 'local',
    writable: true,
  ),
  RootInfo(
    id: 'library',
    name: 'Library',
    path: '/library',
    type: 'mediastore',
    writable: false,
  ),
];

void main() {
  group('FileBrowserCubit thumbnail cache policy', () {
    late ThumbnailRepositoryImpl thumbnailRepository;
    late GetCachedThumbnailUseCase getCachedThumbnailUseCase;
    late LoadVisibleThumbnailsUseCase loadVisibleThumbnailsUseCase;
    late _FakeListDirectoryUseCase listDirectoryUseCase;
    late FileBrowserCubit cubit;

    const imageA = FileEntryEntity(
      name: 'a.jpg',
      path: '/photos/a.jpg',
      type: FileType.file,
      size: 100,
    );
    const imageB = FileEntryEntity(
      name: 'b.jpg',
      path: '/photos/b.jpg',
      type: FileType.file,
      size: 100,
    );

    setUp(() {
      final bytesA = Uint8List.fromList(<int>[1, 2, 3]);
      final bytesB = Uint8List.fromList(<int>[4, 5, 6]);
      thumbnailRepository = ThumbnailRepositoryImpl(
        remoteDataSource: _StubThumbnailRemoteDataSource(
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
        ),
      );
      getCachedThumbnailUseCase = GetCachedThumbnailUseCase(
        repository: thumbnailRepository,
      );
      loadVisibleThumbnailsUseCase = LoadVisibleThumbnailsUseCase(
        repository: thumbnailRepository,
      );
      listDirectoryUseCase = _FakeListDirectoryUseCase();
      cubit = _buildCubit(
        listDirectoryUseCase: listDirectoryUseCase,
        getCachedThumbnailUseCase: getCachedThumbnailUseCase,
        loadVisibleThumbnailsUseCase: loadVisibleThumbnailsUseCase,
      );
    });

    tearDown(() async {
      await cubit.close();
    });

    test('refreshDirectoryEntries preserves cached thumbnails', () async {
      listDirectoryUseCase.responses = <AppResult<FileListPageEntity>>[
        const Success(
          FileListPageEntity(
            items: <FileEntryEntity>[imageA],
            hasMore: false,
            nextCursor: null,
          ),
        ),
        const Success(
          FileListPageEntity(
            items: <FileEntryEntity>[imageA, imageB],
            hasMore: false,
            nextCursor: null,
          ),
        ),
      ];

      await cubit.loadRoot();
      await thumbnailRepository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg'],
      );
      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/a.jpg'), isTrue);

      await cubit.refreshDirectoryEntries(NasPath.root('fs'));

      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/a.jpg'), isTrue);
      final state = cubit.state as FileBrowserLoaded;
      expect(state.allFiles, hasLength(2));
    });

    test('deleteFile evicts only the deleted thumbnail', () async {
      await cubit.close();
      final fileRepository = _FakeFileRepository();
      cubit = _buildCubit(
        listDirectoryUseCase: listDirectoryUseCase,
        getCachedThumbnailUseCase: getCachedThumbnailUseCase,
        loadVisibleThumbnailsUseCase: loadVisibleThumbnailsUseCase,
        fileRepository: fileRepository,
      );

      listDirectoryUseCase.responses = <AppResult<FileListPageEntity>>[
        const Success(
          FileListPageEntity(
            items: <FileEntryEntity>[imageA, imageB],
            hasMore: false,
            nextCursor: null,
          ),
        ),
      ];

      await cubit.loadRoot();
      await thumbnailRepository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg', '/fs/photos/b.jpg'],
      );
      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/a.jpg'), isTrue);
      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/b.jpg'), isTrue);

      await cubit.deleteFile('/photos/a.jpg');

      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/a.jpg'), isFalse);
      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/b.jpg'), isTrue);
      final state = cubit.state as FileBrowserLoaded;
      expect(
        state.allFiles.map((file) => file.path),
        <String>['/photos/b.jpg'],
      );
    });

    test('canSkipDirectoryRefreshOnReconnect returns true when thumbnails are warm',
        () async {
      listDirectoryUseCase.responses = <AppResult<FileListPageEntity>>[
        const Success(
          FileListPageEntity(
            items: <FileEntryEntity>[imageA],
            hasMore: false,
            nextCursor: null,
          ),
        ),
      ];

      await cubit.loadRoot();
      expect(cubit.canSkipDirectoryRefreshOnReconnect(), isFalse);

      await thumbnailRepository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg'],
      );
      expect(cubit.canSkipDirectoryRefreshOnReconnect(), isTrue);
    });

    test('switchRoot clears thumbnail cache', () async {
      listDirectoryUseCase.responses = <AppResult<FileListPageEntity>>[
        const Success(
          FileListPageEntity(
            items: <FileEntryEntity>[imageA],
            hasMore: false,
            nextCursor: null,
          ),
        ),
        const Success(
          FileListPageEntity(
            items: <FileEntryEntity>[imageA],
            hasMore: false,
            nextCursor: null,
          ),
        ),
      ];

      await cubit.loadRoot();
      await thumbnailRepository.loadBatchThumbnails(
        paths: <String>['/fs/photos/a.jpg'],
      );
      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/a.jpg'), isTrue);

      await cubit.switchRoot('library');

      expect(thumbnailRepository.hasCachedThumbnail('/fs/photos/a.jpg'), isFalse);
    });
  });
}

FileBrowserCubit _buildCubit({
  required _FakeListDirectoryUseCase listDirectoryUseCase,
  required GetCachedThumbnailUseCase getCachedThumbnailUseCase,
  required LoadVisibleThumbnailsUseCase loadVisibleThumbnailsUseCase,
  FileRepository? fileRepository,
}) {
  final session = CurrentSession()
    ..set(
      serverId: 'server-1',
      serverName: 'NAS',
      serverVersion: '1',
      serverStatus: 'online',
      serverUrl: 'http://localhost:8080',
      protocol: 'http',
      rootId: 'fs',
      rootName: 'FS',
      roots: _testRoots,
    );
  final repository = fileRepository ?? _ThrowingFileRepository();
  return FileBrowserCubit(
    listDirectoryUseCase: listDirectoryUseCase,
    createFolderUseCase: CreateFolderUseCase(repository: repository),
    deleteFileUseCase: DeleteFileUseCase(repository: repository),
    batchDeleteUseCase: BatchDeleteUseCase(repository: repository),
    loadVisibleThumbnailsUseCase: loadVisibleThumbnailsUseCase,
    getCachedThumbnailUseCase: getCachedThumbnailUseCase,
    switchFileRootUseCase: SwitchFileRootUseCase(currentSession: session),
    isRootWritableUseCase: IsRootWritableUseCase(currentSession: session),
  );
}

class _FakeListDirectoryUseCase extends ListDirectoryUseCase {
  _FakeListDirectoryUseCase()
    : super(repository: _ThrowingFileRepository());

  List<AppResult<FileListPageEntity>> responses =
      const <AppResult<FileListPageEntity>>[];
  var _callIndex = 0;

  @override
  Future<AppResult<FileListPageEntity>> call(ListDirectoryParams params) async {
    if (responses.isEmpty) {
      throw StateError('No fake list directory responses configured');
    }
    final result = responses[_callIndex.clamp(0, responses.length - 1)];
    _callIndex++;
    return result;
  }
}

class _FakeFileRepository implements FileRepository {
  @override
  Future<AppResult<void>> deleteFile(NasPath path) async {
    return const Success(null);
  }

  @override
  Future<AppResult<FileListPageEntity>> listDirectory(
    ListDirectoryParams params,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> createFolder(NasPath path) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<BatchDeleteResultEntity>>> batchDelete(
    List<NasPath> paths,
  ) {
    throw UnimplementedError();
  }
}

class _ThrowingFileRepository implements FileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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
