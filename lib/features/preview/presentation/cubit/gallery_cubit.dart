/// 文件输入：媒体文件列表、rootId、预览 UseCase、传输 UseCase
/// 文件职责：管理 Gallery 页面状态，处理预览加载、原图下载与原图保存
/// 文件对外接口：GalleryCubit
/// 文件包含：GalleryCubit
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/path/nas_path.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../files/domain/entities/file_entry_entity.dart';
import '../../../transfer/application/params/enqueue_download_params.dart';
import '../../../transfer/application/use_cases/enqueue_download_use_case.dart';
import '../../../transfer/application/use_cases/load_transfer_tasks_use_case.dart';
import '../../../transfer/application/use_cases/observe_transfer_tasks_use_case.dart';
import '../../../transfer/domain/entities/transfer_direction.dart';
import '../../../transfer/domain/entities/transfer_status.dart';
import '../../../transfer/domain/entities/transfer_task_entity.dart';
import '../../application/params/build_original_preview_download_path_params.dart';
import '../../application/params/resolve_preview_image_source_params.dart';
import '../../application/params/resolve_preview_video_source_params.dart';
import '../../application/params/save_original_to_public_storage_params.dart';
import '../../application/use_cases/build_original_preview_download_path_use_case.dart';
import '../../application/use_cases/load_preview_use_case.dart';
import '../../application/use_cases/resolve_preview_image_source_use_case.dart';
import '../../application/use_cases/resolve_preview_video_source_use_case.dart';
import '../../application/use_cases/save_original_to_public_storage_use_case.dart';
import '../../domain/entities/preview_image_source.dart';
import '../../domain/entities/preview_item_entity.dart';
import '../../domain/entities/preview_video_source.dart';
import 'gallery_original_download_state.dart';
import 'gallery_state.dart';

class GalleryCubit extends Cubit<GalleryState> {
  final LoadPreviewUseCase _loadPreviewUseCase;
  final ResolvePreviewImageSourceUseCase _resolvePreviewImageSourceUseCase;
  final ResolvePreviewVideoSourceUseCase _resolvePreviewVideoSourceUseCase;
  final LoadTransferTasksUseCase _loadTransferTasksUseCase;
  final ObserveTransferTasksUseCase _observeTransferTasksUseCase;
  final EnqueueDownloadUseCase _enqueueDownloadUseCase;
  final BuildOriginalPreviewDownloadPathUseCase
  _buildOriginalPreviewDownloadPathUseCase;
  final SaveOriginalToPublicStorageUseCase _saveOriginalToPublicStorageUseCase;
  final Map<String, int> _filePathToIndex;

  StreamSubscription<TransferTaskEntity>? _taskSubscription;

  static const int preloadRange = 1;

  GalleryCubit({
    required LoadPreviewUseCase loadPreviewUseCase,
    required ResolvePreviewImageSourceUseCase resolvePreviewImageSourceUseCase,
    required ResolvePreviewVideoSourceUseCase resolvePreviewVideoSourceUseCase,
    required LoadTransferTasksUseCase loadTransferTasksUseCase,
    required ObserveTransferTasksUseCase observeTransferTasksUseCase,
    required EnqueueDownloadUseCase enqueueDownloadUseCase,
    required BuildOriginalPreviewDownloadPathUseCase
    buildOriginalPreviewDownloadPathUseCase,
    required SaveOriginalToPublicStorageUseCase
    saveOriginalToPublicStorageUseCase,
    required List<FileEntryEntity> mediaFiles,
    required String rootId,
    required int initialIndex,
    required Map<String, Uint8List> thumbnails,
  }) : _loadPreviewUseCase = loadPreviewUseCase,
       _resolvePreviewImageSourceUseCase = resolvePreviewImageSourceUseCase,
       _resolvePreviewVideoSourceUseCase = resolvePreviewVideoSourceUseCase,
       _loadTransferTasksUseCase = loadTransferTasksUseCase,
       _observeTransferTasksUseCase = observeTransferTasksUseCase,
       _enqueueDownloadUseCase = enqueueDownloadUseCase,
       _buildOriginalPreviewDownloadPathUseCase =
           buildOriginalPreviewDownloadPathUseCase,
       _saveOriginalToPublicStorageUseCase = saveOriginalToPublicStorageUseCase,
       _filePathToIndex = _buildFilePathIndex(mediaFiles),
       super(
         GalleryState.initial(
           mediaFiles: mediaFiles,
           rootId: rootId,
           initialIndex: initialIndex,
           thumbnails: thumbnails,
         ),
       ) {
    _initialize(initialIndex);
  }

  @override
  Future<void> close() {
    _taskSubscription?.cancel();
    return super.close();
  }

  Future<void> handleOriginalAction(int index) async {
    if (index < 0 || index >= state.length) {
      return;
    }

    final originalState = state.getOriginalState(index);
    if (originalState.isDownloading || originalState.isSaving) {
      return;
    }
    if (originalState.isOriginalReady) {
      return;
    }

    final file = state.getFile(index);

    final localPath = await _buildOriginalPreviewDownloadPathUseCase.call(
      BuildOriginalPreviewDownloadPathParams(
        rootId: state.rootId,
        remotePath: file.path,
      ),
    );

    final enqueueResult = await _enqueueDownloadUseCase.call(
      EnqueueDownloadParams(
        remotePath: file.path,
        localPath: localPath,
        rootId: state.rootId,
      ),
    );

    if (isClosed) {
      return;
    }

    enqueueResult.when(
      success: (task) {
        _emitOriginalState(
          index,
          originalState.copyWith(
            taskId: task.id,
            localPath: localPath,
            publicUri: null,
            progress: _normalizeProgress(task.progress),
            isDownloading: true,
            isSaving: false,
            errorMessage: null,
          ),
        );
      },
      failure: (failure) {
        _emitOriginalState(
          index,
          originalState.copyWith(
            taskId: null,
            localPath: null,
            publicUri: null,
            progress: 0,
            isDownloading: false,
            isSaving: false,
            errorMessage: failure.message,
          ),
        );
      },
    );
  }

  Future<void> handleSaveOriginal(int index) async {
    if (index < 0 || index >= state.length) {
      return;
    }

    final originalState = state.getOriginalState(index);
    if (!originalState.canSaveToPublic) {
      return;
    }

    await _saveOriginalToPublicStorage(
      index,
      originalState.localPath!,
      state.getFile(index),
    );
  }

  Future<void> _initialize(int initialIndex) async {
    _taskSubscription = _observeTransferTasksUseCase.call().listen(
      _handleTransferTaskChanged,
    );
    await Future.wait([
      _loadPreviewWithAdjacent(initialIndex),
      _hydrateOriginalDownloads(),
    ]);
  }

  Future<void> _hydrateOriginalDownloads() async {
    final result = await _loadTransferTasksUseCase.call(NoParams());
    result.when(
      success: (tasks) {
        final latestTasksByIndex = <int, TransferTaskEntity>{};
        for (final task in tasks) {
          final index = _resolveIndexForTask(task);
          if (index == null) {
            continue;
          }

          final existingTask = latestTasksByIndex[index];
          if (existingTask == null ||
              task.createdAt.isAfter(existingTask.createdAt)) {
            latestTasksByIndex[index] = task;
          }
        }

        for (final entry in latestTasksByIndex.entries) {
          _applyTransferTask(entry.key, entry.value);
        }
      },
      failure: (_) {},
    );
  }

  Future<void> _loadPreviewWithAdjacent(int centerIndex) async {
    final indices = _getIndicesToPreload(centerIndex);
    if (indices.isEmpty) {
      return;
    }

    final currentIndex = indices.first;
    if (!state.hasPreviewItem(currentIndex) && !state.isLoading(currentIndex)) {
      await _loadPreview(currentIndex);
    }

    final adjacentLoads = indices
        .skip(1)
        .where((index) => !state.hasPreviewItem(index) && !state.isLoading(index))
        .map(_loadPreview)
        .toList(growable: false);
    if (adjacentLoads.isNotEmpty) {
      unawaited(Future.wait(adjacentLoads));
    }
  }

  List<int> _getIndicesToPreload(int centerIndex) {
    final indices = <int>[];
    final offsets = <int>[0];

    for (var distance = 1; distance <= preloadRange; distance++) {
      offsets
        ..add(distance)
        ..add(-distance);
    }

    for (final offset in offsets) {
      final candidate = centerIndex + offset;
      if (candidate < 0 || candidate >= state.length) {
        continue;
      }
      if (!indices.contains(candidate)) {
        indices.add(candidate);
      }
    }

    return indices;
  }

  Future<void> _loadPreview(int index) async {
    if (index < 0 || index >= state.length) {
      return;
    }

    final file = state.getFile(index);
    final nasPath = _buildNasPath(file);

    emit(state.copyWith(loadingStates: {...state.loadingStates, index: true}));

    final result = await _loadPreviewUseCase(nasPath);
    if (isClosed) {
      return;
    }

    result.when(
      success: (item) {
        final imageSources = {...state.imageSources};
        final videoSources = {...state.videoSources};
        if (item.isImage) {
          imageSources[index] = _resolvePreviewImageSourceUseCase.call(
            ResolvePreviewImageSourceParams(
              nasPath: nasPath,
              item: item,
              thumbnailData: state.getThumbnail(file.path),
            ),
          );
        } else if (item.isVideo) {
          videoSources[index] = _resolvePreviewVideoSourceUseCase.call(
            ResolvePreviewVideoSourceParams(
              nasPath: nasPath,
              item: item,
              thumbnailData: state.getThumbnail(file.path),
            ),
          );
        }

        emit(
          state.copyWith(
            previewItems: {...state.previewItems, index: item},
            imageSources: imageSources,
            videoSources: videoSources,
            loadingStates: {...state.loadingStates, index: false},
          ),
        );
      },
      failure: (_) {
        emit(
          state.copyWith(loadingStates: {...state.loadingStates, index: false}),
        );
      },
    );
  }

  void _handleTransferTaskChanged(TransferTaskEntity task) {
    final index = _resolveIndexForTask(task);
    if (index == null) {
      return;
    }
    _applyTransferTask(index, task);
  }

  void _applyTransferTask(int index, TransferTaskEntity task) {
    final currentOriginalState = state.getOriginalState(index);
    final nextLocalPath = task.localPath.isNotEmpty
        ? task.localPath
        : currentOriginalState.localPath;

    if (task.status == TransferStatus.completed && nextLocalPath != null) {
      final file = File(nextLocalPath);
      if (!file.existsSync() || file.lengthSync() <= 0) {
        _emitOriginalState(
          index,
          currentOriginalState.copyWith(
            taskId: task.id,
            localPath: nextLocalPath,
            progress: 0,
            isDownloading: false,
            isSaving: false,
            errorMessage: '原图下载失败，请重试。',
          ),
        );
        return;
      }

      final completedState = currentOriginalState.copyWith(
        taskId: task.id,
        localPath: nextLocalPath,
        progress: 1,
        isDownloading: false,
        errorMessage: null,
      );
      _emitOriginalState(index, completedState);
      return;
    }

    _emitOriginalState(
      index,
      currentOriginalState.copyWith(
        taskId: task.id,
        localPath: nextLocalPath,
        progress: _normalizeProgress(task.progress),
        isDownloading:
            task.status == TransferStatus.transferring ||
            task.status == TransferStatus.pending,
        isSaving: false,
        errorMessage: task.status == TransferStatus.failed
            ? (task.errorMessage ?? '原图下载失败，请重试。')
            : null,
      ),
    );
  }

  Future<void> _saveOriginalToPublicStorage(
    int index,
    String localPath,
    FileEntryEntity file,
  ) async {
    final currentOriginalState = state.getOriginalState(index);
    if (currentOriginalState.isSaved || currentOriginalState.isSaving) {
      return;
    }

    _emitOriginalState(
      index,
      currentOriginalState.copyWith(
        localPath: localPath,
        isDownloading: false,
        isSaving: true,
        errorMessage: null,
      ),
    );

    final result = await _saveOriginalToPublicStorageUseCase.call(
      SaveOriginalToPublicStorageParams(
        localPath: localPath,
        fileName: file.name,
      ),
    );

    if (isClosed) {
      return;
    }

    result.when(
      success: (publicUri) {
        _emitOriginalState(
          index,
          state
              .getOriginalState(index)
              .copyWith(
                localPath: localPath,
                publicUri: publicUri,
                progress: 1,
                isDownloading: false,
                isSaving: false,
                errorMessage: null,
              ),
        );
      },
      failure: (failure) {
        _emitOriginalState(
          index,
          state
              .getOriginalState(index)
              .copyWith(
                localPath: failure.code == 'PREVIEW_ORIGINAL_MISSING'
                    ? null
                    : localPath,
                publicUri: null,
                isDownloading: false,
                isSaving: false,
                errorMessage: failure.message,
              ),
        );
      },
    );
  }

  int? _resolveIndexForTask(TransferTaskEntity task) {
    if (task.direction != TransferDirection.download ||
        task.rootId != state.rootId) {
      return null;
    }
    return _filePathToIndex[task.remotePath];
  }

  void _emitOriginalState(
    int index,
    GalleryOriginalDownloadState originalState,
  ) {
    emit(
      state.copyWith(
        originalStates: {...state.originalStates, index: originalState},
      ),
    );
  }

  static Map<String, int> _buildFilePathIndex(
    List<FileEntryEntity> mediaFiles,
  ) {
    final filePathToIndex = <String, int>{};
    for (var index = 0; index < mediaFiles.length; index++) {
      filePathToIndex[mediaFiles[index].path] = index;
    }
    return filePathToIndex;
  }

  double _normalizeProgress(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  NasPath _buildNasPath(FileEntryEntity file) {
    return NasPath(rootId: state.rootId, path: file.path);
  }

  void onPageChanged(int newIndex) {
    if (newIndex < 0 || newIndex >= state.length) {
      return;
    }

    emit(state.copyWith(currentIndex: newIndex));
    _loadPreviewWithAdjacent(newIndex);
  }

  PreviewItemEntity? getPreviewItem(int index) => state.getPreviewItem(index);

  PreviewImageSource? getImageSource(int index) => state.getImageSource(index);

  PreviewVideoSource? getVideoSource(int index) => state.getVideoSource(index);

  Uint8List? getThumbnail(String fileName) => state.getThumbnail(fileName);

  FileEntryEntity getFile(int index) => state.getFile(index);
}
