import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/core/protocol/file_protocol_client.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/features/files/application/params/list_directory_params.dart';
import 'package:nasclient/features/files/data/repositories/file_repository_impl.dart';
import 'package:nasclient/features/files/domain/entities/file_category.dart';
import 'package:nasclient/features/files/domain/entities/file_entry_entity.dart';
import 'package:nasclient/features/files/domain/entities/file_type.dart';

void main() {
  group('FileRepositoryImpl.listDirectory', () {
    test('uses paged file list api when available', () async {
      final apiClient = _FakeNasApiClient.success();
      final protocolClient = _FakeFileProtocolClient();
      final repository = FileRepositoryImpl(
        protocolClient: protocolClient,
        apiClient: apiClient,
      );

      final result = await repository.listDirectory(
        const ListDirectoryParams(
          path: NasPath(rootId: 'fs', path: '/'),
          category: FileCategory.photo,
          limit: 2,
        ),
      );

      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.items, hasLength(2));
      expect(page.items.first.path, '/nested/a.jpg');
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '2');
      expect(protocolClient.listedPaths, isEmpty);
    });

    test('falls back to protocol listing and paginates locally', () async {
      final apiClient = _FakeNasApiClient.failing();
      final protocolClient = _FakeFileProtocolClient(
        listedFiles: const [
          FileEntryEntity(
            name: 'a.jpg',
            path: '/a.jpg',
            type: FileType.file,
            size: 1,
          ),
          FileEntryEntity(
            name: 'b.jpg',
            path: '/folder/b.jpg',
            type: FileType.file,
            size: 2,
          ),
          FileEntryEntity(
            name: 'c.mp4',
            path: '/c.mp4',
            type: FileType.file,
            size: 3,
          ),
        ],
      );
      final repository = FileRepositoryImpl(
        protocolClient: protocolClient,
        apiClient: apiClient,
      );

      final result = await repository.listDirectory(
        const ListDirectoryParams(
          path: NasPath(rootId: 'fs', path: '/'),
          category: FileCategory.photo,
          cursor: '1',
          limit: 1,
        ),
      );

      expect(result.isSuccess, isTrue);
      final page = result.dataOrNull!;
      expect(page.items.single.path, '/folder/b.jpg');
      expect(page.hasMore, isFalse);
      expect(protocolClient.listedPaths.single.path, '/');
    });
  });

  group('FileRepositoryImpl.batchDelete', () {
    test('uses canonical api paths when batch endpoint is available', () async {
      final apiClient = _FakeNasApiClient.success();
      final protocolClient = _FakeFileProtocolClient();
      final repository = FileRepositoryImpl(
        protocolClient: protocolClient,
        apiClient: apiClient,
      );

      final result = await repository.batchDelete(const [
        NasPath(rootId: 'fs', path: '/photos/IMG 1 (2).jpg'),
      ]);

      expect(result.isSuccess, isTrue);
      expect(apiClient.postedPayloads.single['paths'], [
        '/fs/photos/IMG%201%20(2).jpg',
      ]);
      expect(protocolClient.deletedPaths, isEmpty);
    });
  });
}

class _FakeNasApiClient extends NasApiClient {
  _FakeNasApiClient._({required this.onGet, required this.onPost})
    : super(
        baseUrl: 'http://localhost:8080',
        session: CurrentSession(),
        dio: Dio(),
      );

  final Future<Map<String, dynamic>> Function(
    String path,
    Map<String, dynamic>? queryParameters,
  )
  onGet;
  final Future<Map<String, dynamic>> Function(String path, dynamic data) onPost;
  final List<Map<String, dynamic>> postedPayloads = [];
  int callCount = 0;

  factory _FakeNasApiClient.success() {
    return _FakeNasApiClient._(
      onGet: (path, queryParameters) async {
        return {
          'items': [
            {
              'name': 'a.jpg',
              'path': '/nested/a.jpg',
              'type': 'file',
              'size': 1,
              'modifiedAt': '2026-01-01T00:00:00.000Z',
            },
            {
              'name': 'b.jpg',
              'path': '/b.jpg',
              'type': 'file',
              'size': 2,
              'modifiedAt': '2026-01-02T00:00:00.000Z',
            },
          ],
          'hasMore': true,
          'nextCursor': '2',
        };
      },
      onPost: (path, data) async {
        return {
          'results': [
            for (final item in (data['paths'] as List<dynamic>))
              {'path': item, 'success': true},
          ],
        };
      },
    );
  }

  factory _FakeNasApiClient.failing() {
    return _FakeNasApiClient._(
      onGet: (path, queryParameters) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/api/v1/files/list'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/files/list'),
            statusCode: 404,
          ),
        );
      },
      onPost: (path, data) async => {'results': const []},
    );
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    final response = await onGet(path, queryParameters);
    if (parser != null) {
      return parser(response);
    }
    return response as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    callCount++;
    if (data is Map<String, dynamic>) {
      postedPayloads.add(Map<String, dynamic>.from(data));
    }
    final response = await onPost(path, data);
    if (parser != null) {
      return parser(response);
    }
    return response as T;
  }
}

class _FakeFileProtocolClient implements FileProtocolClient {
  _FakeFileProtocolClient({this.listedFiles = const []});

  final List<FileEntryEntity> listedFiles;
  final List<NasPath> deletedPaths = [];
  final List<NasPath> listedPaths = [];

  @override
  Future<void> createDirectory(NasPath path) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(NasPath path) async {
    deletedPaths.add(path);
  }

  @override
  Future<Stream<List<int>>> download({
    required NasPath sourcePath,
    void Function(int received)? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> exists(NasPath path) {
    throw UnimplementedError();
  }

  @override
  Future<int> getFileSize(NasPath path) {
    throw UnimplementedError();
  }

  @override
  Future<List<FileEntryEntity>> listDirectory(NasPath path) async {
    listedPaths.add(path);
    return listedFiles;
  }

  @override
  Future<UploadResult> upload({
    required NasPath targetPath,
    required Stream<List<int>> sourceStream,
    required int totalSize,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    Map<String, String>? extraHeaders,
    void Function(int sent)? onProgress,
  }) {
    throw UnimplementedError();
  }
}
