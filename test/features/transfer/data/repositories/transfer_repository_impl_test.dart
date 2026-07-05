import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/core/protocol/file_protocol_client.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/features/files/domain/entities/file_entry_entity.dart';
import 'package:nasclient/features/transfer/data/datasources/transfer_executor_data_source.dart';
import 'package:nasclient/features/transfer/data/datasources/transfer_local_data_source.dart';
import 'package:nasclient/features/transfer/data/models/transfer_task_dto.dart';
import 'package:nasclient/features/transfer/data/repositories/transfer_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TransferRepositoryImpl.clearCompletedTasks', () {
    test('removes only completed tasks from persistent storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final keyValueStore = KeyValueStore(prefs: prefs);
      final localDataSource = TransferLocalDataSource(
        keyValueStore: keyValueStore,
      );
      await localDataSource.saveTasks([
        const TransferTaskDto(
          id: 'completed-1',
          rootId: 'fs',
          localPath: 'C:\\done\\photo.jpg',
          remotePath: '/photo.jpg',
          fileName: 'photo.jpg',
          totalBytes: 100,
          transferredBytes: 100,
          direction: 'upload',
          status: 'completed',
          createdAt: '2026-04-12T10:00:00.000',
        ),
        const TransferTaskDto(
          id: 'failed-1',
          rootId: 'fs',
          localPath: 'C:\\done\\clip.mp4',
          remotePath: '/clip.mp4',
          fileName: 'clip.mp4',
          totalBytes: 200,
          transferredBytes: 50,
          direction: 'download',
          status: 'failed',
          createdAt: '2026-04-12T10:05:00.000',
          errorMessage: 'network error',
        ),
      ]);

      final repository = TransferRepositoryImpl(
        localDataSource: localDataSource,
        executorDataSource: TransferExecutorDataSource(
          protocolClient: _NoopFileProtocolClient(),
        ),
      );

      final clearResult = await repository.clearCompletedTasks();
      final tasksResult = await repository.loadTasks();

      expect(clearResult.isSuccess, isTrue);
      expect(tasksResult.isSuccess, isTrue);
      expect(tasksResult.dataOrNull, hasLength(1));
      expect(tasksResult.dataOrNull!.single.id, 'failed-1');
      expect(tasksResult.dataOrNull!.single.status.name, 'failed');
    });
  });
}

class _NoopFileProtocolClient implements FileProtocolClient {
  @override
  Future<void> createDirectory(NasPath path) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(NasPath path) {
    throw UnimplementedError();
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
  Future<List<FileEntryEntity>> listDirectory(NasPath path) {
    throw UnimplementedError();
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
