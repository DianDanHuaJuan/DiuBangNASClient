import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/device_file_service.dart';
import 'package:nasclient/core/device/media_storage_service.dart';
import 'package:nasclient/core/path/nas_path.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/features/files/domain/entities/file_entry_entity.dart';
import 'package:nasclient/features/files/domain/entities/file_type.dart';
import 'package:nasclient/features/preview/application/params/build_original_preview_download_path_params.dart';
import 'package:nasclient/features/preview/application/use_cases/build_original_preview_download_path_use_case.dart';
import 'package:nasclient/features/preview/application/use_cases/load_preview_use_case.dart';
import 'package:nasclient/features/preview/application/use_cases/resolve_preview_image_source_use_case.dart';
import 'package:nasclient/features/preview/application/use_cases/resolve_preview_video_source_use_case.dart';
import 'package:nasclient/features/preview/application/use_cases/save_original_to_public_storage_use_case.dart';
import 'package:nasclient/features/preview/domain/entities/preview_item_entity.dart';
import 'package:nasclient/features/preview/domain/entities/preview_kind.dart';
import 'package:nasclient/features/preview/domain/entities/preview_strategy.dart';
import 'package:nasclient/features/preview/domain/repositories/preview_repository.dart';
import 'package:nasclient/features/preview/presentation/cubit/gallery_cubit.dart';
import 'package:nasclient/features/transfer/application/params/enqueue_download_params.dart';
import 'package:nasclient/features/transfer/application/use_cases/enqueue_download_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/load_transfer_tasks_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/observe_transfer_tasks_use_case.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_direction.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_status.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_task_entity.dart';
import 'package:nasclient/features/transfer/domain/repositories/transfer_repository.dart';

void main() {
  group('GalleryCubit original download', () {
    late Directory tempDirectory;
    late String localPath;
    late StreamController<TransferTaskEntity> taskController;
    late _RecordingEnqueueDownloadUseCase enqueueDownloadUseCase;
    late GalleryCubit cubit;

    const image = FileEntryEntity(
      name: 'photo.jpg',
      path: '/photos/photo.jpg',
      type: FileType.file,
      size: 2048,
    );

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'nasclient-gallery-original-',
      );
      localPath = '${tempDirectory.path}/fs_photos_photo.jpg';
      taskController = StreamController<TransferTaskEntity>.broadcast();
      enqueueDownloadUseCase = _RecordingEnqueueDownloadUseCase(
        repository: _FakeTransferRepository(taskController.stream),
      );

      cubit = GalleryCubit(
        loadPreviewUseCase: LoadPreviewUseCase(
          repository: _FakePreviewRepository(),
        ),
        resolvePreviewImageSourceUseCase: ResolvePreviewImageSourceUseCase(
          baseUrl: 'http://localhost:8080',
        ),
        resolvePreviewVideoSourceUseCase: ResolvePreviewVideoSourceUseCase(
          baseUrl: 'http://localhost:8080',
        ),
        loadTransferTasksUseCase: LoadTransferTasksUseCase(
          repository: _FakeTransferRepository(taskController.stream),
        ),
        observeTransferTasksUseCase: ObserveTransferTasksUseCase(
          repository: _FakeTransferRepository(taskController.stream),
        ),
        enqueueDownloadUseCase: enqueueDownloadUseCase,
        buildOriginalPreviewDownloadPathUseCase:
            _FixedOriginalPreviewDownloadPathUseCase(localPath),
        saveOriginalToPublicStorageUseCase: SaveOriginalToPublicStorageUseCase(
          deviceFileService: _FakeDeviceFileService(tempDirectory.path),
          mediaStorageService: _FakeMediaStorageService(),
        ),
        mediaFiles: const <FileEntryEntity>[image],
        rootId: 'fs',
        initialIndex: 0,
        thumbnails: const <String, Uint8List>{},
      );
    });

    tearDown(() async {
      await cubit.close();
      await taskController.close();
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('handleOriginalAction leaves original not ready while downloading',
        () async {
      await cubit.stream.firstWhere((state) => state.hasPreviewItem(0));

      await cubit.handleOriginalAction(0);

      expect(enqueueDownloadUseCase.callCount, 1);
      final downloadingState = cubit.state.getOriginalState(0);
      expect(downloadingState.isDownloading, isTrue);
      expect(downloadingState.isOriginalReady, isFalse);
    });

    test('completed transfer with valid file marks original ready', () async {
      await cubit.stream.firstWhere((state) => state.hasPreviewItem(0));
      await cubit.handleOriginalAction(0);

      final file = File(localPath);
      await file.writeAsBytes(List<int>.generate(2048, (index) => index % 256));

      taskController.add(
        TransferTaskEntity(
          id: 'task-1',
          rootId: 'fs',
          localPath: localPath,
          remotePath: image.path,
          fileName: image.name,
          totalBytes: 2048,
          transferredBytes: 2048,
          direction: TransferDirection.download,
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      );

      await cubit.stream.firstWhere(
        (state) => state.getOriginalState(0).isOriginalReady,
      );
      expect(cubit.state.getOriginalState(0).isCached, isTrue);
    });

    test('failed download can be retried', () async {
      await cubit.stream.firstWhere((state) => state.hasPreviewItem(0));
      await cubit.handleOriginalAction(0);

      taskController.add(
        TransferTaskEntity(
          id: 'task-1',
          rootId: 'fs',
          localPath: localPath,
          remotePath: image.path,
          fileName: image.name,
          totalBytes: 0,
          transferredBytes: 0,
          direction: TransferDirection.download,
          status: TransferStatus.failed,
          createdAt: DateTime.now(),
          errorMessage: 'network error',
        ),
      );

      await cubit.stream.firstWhere(
        (state) => state.getOriginalState(0).hasFailure,
      );
      expect(cubit.state.getOriginalState(0).isOriginalReady, isFalse);

      await cubit.handleOriginalAction(0);
      expect(enqueueDownloadUseCase.callCount, 2);
    });

    test('completed transfer with empty file records failure', () async {
      await cubit.stream.firstWhere((state) => state.hasPreviewItem(0));
      await cubit.handleOriginalAction(0);

      await File(localPath).writeAsBytes(<int>[]);

      taskController.add(
        TransferTaskEntity(
          id: 'task-1',
          rootId: 'fs',
          localPath: localPath,
          remotePath: image.path,
          fileName: image.name,
          totalBytes: 0,
          transferredBytes: 0,
          direction: TransferDirection.download,
          status: TransferStatus.completed,
          createdAt: DateTime.now(),
        ),
      );

      await cubit.stream.firstWhere(
        (state) => state.getOriginalState(0).hasFailure,
      );
      expect(cubit.state.getOriginalState(0).isOriginalReady, isFalse);
    });
  });
}

class _RecordingEnqueueDownloadUseCase extends EnqueueDownloadUseCase {
  _RecordingEnqueueDownloadUseCase({required TransferRepository repository})
    : super(repository: repository);

  var callCount = 0;

  @override
  Future<AppResult<TransferTaskEntity>> call(
    EnqueueDownloadParams params,
  ) async {
    callCount++;
    return Success(
      TransferTaskEntity(
        id: 'task-$callCount',
        rootId: params.rootId ?? 'fs',
        localPath: params.localPath,
        remotePath: params.remotePath,
        fileName: params.remotePath.split('/').last,
        totalBytes: 0,
        transferredBytes: 0,
        direction: TransferDirection.download,
        status: TransferStatus.transferring,
        createdAt: DateTime.now(),
      ),
    );
  }
}

class _FixedOriginalPreviewDownloadPathUseCase
    extends BuildOriginalPreviewDownloadPathUseCase {
  _FixedOriginalPreviewDownloadPathUseCase(this.path)
    : super(deviceFileService: _FakeDeviceFileService(''));

  final String path;

  @override
  Future<String> call(BuildOriginalPreviewDownloadPathParams params) async {
    return path;
  }
}

class _FakePreviewRepository implements PreviewRepository {
  @override
  Future<AppResult<PreviewItemEntity>> loadPreview(NasPath path) async {
    return const Success(
      PreviewItemEntity(
        kind: PreviewKind.image,
        strategy: PreviewStrategy.native,
        url: 'http://localhost:8080/preview.jpg',
      ),
    );
  }
}

class _FakeTransferRepository implements TransferRepository {
  _FakeTransferRepository(this._taskStream);

  final Stream<TransferTaskEntity> _taskStream;

  @override
  Stream<TransferTaskEntity> get taskStream => _taskStream;

  @override
  Future<AppResult<List<TransferTaskEntity>>> loadTasks() async {
    return const Success(<TransferTaskEntity>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeDeviceFileService extends DeviceFileService {
  _FakeDeviceFileService(this.cacheDirectory);

  final String cacheDirectory;

  @override
  Future<String> getAppCacheDirectory() async => cacheDirectory;
}

class _FakeMediaStorageService extends MediaStorageService {
  @override
  bool shouldUseMemory(int fileSizeBytes) => true;

  @override
  Future<String?> saveToPublicStorage({
    required String fileName,
    required Uint8List data,
    required MediaFileType fileType,
  }) async {
    return 'content://images/original-1';
  }
}
