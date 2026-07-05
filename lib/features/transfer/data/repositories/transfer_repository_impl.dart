/// 文件输入：本地数据源、执行器
/// 文件职责：实现传输仓库，管理任务状态、上传冲突与进度
/// 文件对外接口：TransferRepositoryImpl
/// 文件包含：TransferRepositoryImpl
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/error/app_failure.dart';
import '../../../../core/path/nas_path.dart';
import '../../../../core/protocol/upload_contract.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/transfer_direction.dart';
import '../../domain/entities/transfer_status.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/entities/upload_conflict_resolution.dart';
import '../../domain/repositories/transfer_repository.dart';
import '../datasources/transfer_executor_data_source.dart';
import '../datasources/transfer_local_data_source.dart';
import '../models/transfer_task_dto.dart';

class TransferRepositoryImpl implements TransferRepository {
  final TransferLocalDataSource _localDataSource;
  final TransferExecutorDataSource _executorDataSource;
  final Map<String, TransferTaskEntity> _activeTasks = {};
  final List<_QueuedUploadJob> _pendingUploadJobs = [];
  final _taskController = StreamController<TransferTaskEntity>.broadcast();
  bool _isUploadRunning = false;
  int _taskSequence = 0;
  _QueuedUploadJob? _pendingConflictJob;

  @override
  Stream<TransferTaskEntity> get taskStream => _taskController.stream;

  TransferRepositoryImpl({
    required TransferLocalDataSource localDataSource,
    required TransferExecutorDataSource executorDataSource,
  }) : _localDataSource = localDataSource,
       _executorDataSource = executorDataSource;

  @override
  Future<AppResult<List<TransferTaskEntity>>> loadTasks() async {
    try {
      final dtos = await _localDataSource.loadTasks();
      final tasks = dtos
          .map(
            (dto) => TransferTaskEntity(
              id: dto.id,
              rootId: dto.rootId,
              localPath: dto.localPath,
              remotePath: dto.remotePath,
              fileName: dto.fileName,
              totalBytes: dto.totalBytes,
              transferredBytes: dto.transferredBytes,
              direction: dto.directionEnum,
              status: dto.statusEnum,
              createdAt: DateTime.tryParse(dto.createdAt) ?? DateTime.now(),
              errorMessage: dto.errorMessage,
            ),
          )
          .toList();
      return Success([...tasks, ..._activeTasks.values]);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'LOAD_TASKS_ERROR',
          message: 'Failed to load tasks: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<TransferTaskEntity>> enqueueDownload({
    required String remotePath,
    required String localPath,
    String? rootId,
  }) async {
    try {
      final taskId = _nextTaskId();
      final actualRootId = rootId ?? 'fs';
      final nasPath = NasPath(rootId: actualRootId, path: remotePath);
      final fileName = remotePath.split('/').last;

      final task = TransferTaskEntity(
        id: taskId,
        rootId: actualRootId,
        localPath: localPath,
        remotePath: remotePath,
        fileName: fileName,
        totalBytes: 0,
        transferredBytes: 0,
        direction: TransferDirection.download,
        status: TransferStatus.transferring,
        createdAt: DateTime.now(),
        errorMessage: null,
      );

      _activeTasks[taskId] = task;
      _taskController.add(task);

      _executorDataSource.download(
        taskId: taskId,
        remotePath: nasPath,
        localPath: localPath,
        onProgress: (received, total) {
          final updatedTask = task.copyWith(
            transferredBytes: received,
            totalBytes: total > 0 ? total : task.totalBytes,
          );
          _activeTasks[taskId] = updatedTask;
          _taskController.add(updatedTask);
        },
        onComplete: () {
          final currentTask = _activeTasks[taskId] ?? task;
          final completedTask = currentTask.copyWith(
            status: TransferStatus.completed,
            transferredBytes: currentTask.totalBytes,
          );
          _activeTasks.remove(taskId);
          unawaited(_persistCompletedTask(completedTask));
          _taskController.add(completedTask);
        },
        onError: (error) {
          final failedTask = task.copyWith(
            status: TransferStatus.failed,
            errorMessage: error,
          );
          _activeTasks.remove(taskId);
          _taskController.add(failedTask);
        },
      );

      return Success(task);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'ENQUEUE_DOWNLOAD_ERROR',
          message: 'Failed to enqueue download: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<TransferTaskEntity>> enqueueUpload({
    required String localPath,
    required String remotePath,
    String? rootId,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    bool requiresConflictResolution = false,
    Map<String, String>? uploadHeaders,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        return Failure(
          AppFailure.fromException(
            code: 'UPLOAD_FILE_MISSING',
            message: 'Local file not found: $localPath',
          ),
        );
      }

      final taskId = _nextTaskId();
      final actualRootId = rootId ?? 'fs';
      final nasPath = NasPath(rootId: actualRootId, path: remotePath);
      final fileName = p.basename(localPath);
      final totalBytes = await file.length();
      final shouldStartImmediately = !_isUploadRunning;

      final task = TransferTaskEntity(
        id: taskId,
        rootId: actualRootId,
        localPath: localPath,
        remotePath: remotePath,
        fileName: fileName,
        totalBytes: totalBytes,
        transferredBytes: 0,
        direction: TransferDirection.upload,
        status: shouldStartImmediately
            ? requiresConflictResolution
                  ? TransferStatus.awaitingConflictResolution
                  : TransferStatus.transferring
            : TransferStatus.pending,
        createdAt: DateTime.now(),
      );

      _activeTasks[taskId] = task;
      _taskController.add(task);

      final job = _QueuedUploadJob(
        taskId: taskId,
        localPath: localPath,
        remotePath: nasPath,
        conflictPolicy: conflictPolicy,
        requiresConflictResolution: requiresConflictResolution,
        uploadHeaders: uploadHeaders,
      );

      if (shouldStartImmediately) {
        _isUploadRunning = true;
        _startUploadJob(job);
      } else {
        _pendingUploadJobs.add(job);
      }

      return Success(task);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'ENQUEUE_UPLOAD_ERROR',
          message: 'Failed to enqueue upload: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  }) async {
    try {
      final pendingConflictJob = _pendingConflictJob;
      final currentTask = _activeTasks[taskId];
      if (pendingConflictJob == null ||
          pendingConflictJob.taskId != taskId ||
          currentTask == null) {
        return Failure(
          AppFailure.fromException(
            code: 'UPLOAD_CONFLICT_NOT_PENDING',
            message: '当前任务没有等待处理的重名冲突',
          ),
        );
      }

      _pendingConflictJob = null;

      if (resolution == UploadConflictResolution.skip) {
        final skippedTask = currentTask.copyWith(
          status: TransferStatus.skipped,
          errorMessage: null,
          transferredBytes: 0,
        );
        _activeTasks.remove(taskId);
        _taskController.add(skippedTask);
        _finishUploadAndStartNext();
        return const Success(null);
      }

      final resumedTask = currentTask.copyWith(
        status: TransferStatus.transferring,
        transferredBytes: 0,
        errorMessage: null,
      );
      _activeTasks[taskId] = resumedTask;
      _taskController.add(resumedTask);
      _startUploadJob(
        pendingConflictJob.copyWith(
          conflictPolicy: resolution.uploadPolicy ?? UploadConflictPolicy.fail,
          requiresConflictResolution: false,
        ),
      );
      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'RESOLVE_UPLOAD_CONFLICT_ERROR',
          message: 'Failed to resolve upload conflict: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> pauseTask(String taskId) async {
    try {
      _executorDataSource.pause(taskId);
      final task = _activeTasks[taskId];
      if (task != null) {
        final pausedTask = task.copyWith(status: TransferStatus.paused);
        _activeTasks[taskId] = pausedTask;
        _taskController.add(pausedTask);
      }
      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'PAUSE_TASK_ERROR',
          message: 'Failed to pause task: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> resumeTask(String taskId) async {
    try {
      _executorDataSource.resume(taskId);
      final task = _activeTasks[taskId];
      if (task != null) {
        final resumedTask = task.copyWith(status: TransferStatus.transferring);
        _activeTasks[taskId] = resumedTask;
        _taskController.add(resumedTask);
      }
      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'RESUME_TASK_ERROR',
          message: 'Failed to resume task: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> cancelTask(String taskId) async {
    try {
      _pendingUploadJobs.removeWhere((job) => job.taskId == taskId);

      final wasPendingConflict = _pendingConflictJob?.taskId == taskId;
      if (wasPendingConflict) {
        _pendingConflictJob = null;
      }

      _executorDataSource.cancel(taskId);
      final task = _activeTasks.remove(taskId);
      if (task != null) {
        final cancelledTask = task.copyWith(status: TransferStatus.cancelled);
        _taskController.add(cancelledTask);
      }

      if (wasPendingConflict) {
        _finishUploadAndStartNext();
      }

      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'CANCEL_TASK_ERROR',
          message: 'Failed to cancel task: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> clearCompletedTasks() async {
    try {
      await _localDataSource.clearCompletedTasks();
      return const Success(null);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'CLEAR_COMPLETED_TASKS_ERROR',
          message: 'Failed to clear completed tasks: ${e.toString()}',
        ),
      );
    }
  }

  void dispose() {
    _taskController.close();
  }

  String _nextTaskId() {
    _taskSequence += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_taskSequence';
  }

  Future<void> _persistCompletedTask(TransferTaskEntity task) {
    return _localDataSource.addTask(
      TransferTaskDto(
        id: task.id,
        rootId: task.rootId,
        localPath: task.localPath,
        remotePath: task.remotePath,
        fileName: task.fileName,
        totalBytes: task.totalBytes,
        transferredBytes: task.transferredBytes,
        direction: task.direction == TransferDirection.download
            ? 'download'
            : 'upload',
        status: 'completed',
        createdAt: task.createdAt.toIso8601String(),
      ),
    );
  }

  void _startUploadJob(_QueuedUploadJob job) {
    final currentTask = _activeTasks[job.taskId];
    if (currentTask == null) {
      _finishUploadAndStartNext();
      return;
    }

    if (job.requiresConflictResolution &&
        job.conflictPolicy == UploadConflictPolicy.fail) {
      final conflictTask = currentTask.copyWith(
        status: TransferStatus.awaitingConflictResolution,
        transferredBytes: 0,
        errorMessage: null,
      );
      _activeTasks[job.taskId] = conflictTask;
      _pendingConflictJob = job;
      _taskController.add(conflictTask);
      return;
    }

    _executorDataSource.upload(
      taskId: job.taskId,
      localPath: job.localPath,
      remotePath: job.remotePath,
      conflictPolicy: job.conflictPolicy,
      uploadHeaders: job.uploadHeaders,
      onProgress: (sent) {
        final currentTask = _activeTasks[job.taskId];
        if (currentTask == null) {
          return;
        }
        final updatedTask = currentTask.copyWith(transferredBytes: sent);
        _activeTasks[job.taskId] = updatedTask;
        _taskController.add(updatedTask);
      },
      onComplete: (result) {
        final completingTask = _activeTasks[job.taskId];
        if (completingTask == null) {
          _finishUploadAndStartNext();
          return;
        }

        final completedTask = completingTask.copyWith(
          status: TransferStatus.completed,
          remotePath: result.targetPath.path,
          fileName: result.fileName,
          transferredBytes: completingTask.totalBytes,
          errorMessage: null,
        );
        _activeTasks.remove(job.taskId);
        unawaited(_persistCompletedTask(completedTask));
        _taskController.add(completedTask);
        _finishUploadAndStartNext();
      },
      onError: (error) {
        final failedOrConflictedTask = _activeTasks[job.taskId];
        if (failedOrConflictedTask == null) {
          _finishUploadAndStartNext();
          return;
        }

        if (error is UploadConflictException &&
            job.conflictPolicy == UploadConflictPolicy.fail) {
          final conflictTask = failedOrConflictedTask.copyWith(
            status: TransferStatus.awaitingConflictResolution,
            remotePath: error.targetPath.path,
            fileName: error.fileName,
            transferredBytes: 0,
            errorMessage: null,
          );
          _activeTasks[job.taskId] = conflictTask;
          _pendingConflictJob = job;
          _taskController.add(conflictTask);
          return;
        }

        final failedTask = failedOrConflictedTask.copyWith(
          status: TransferStatus.failed,
          errorMessage: error.toString(),
        );
        _activeTasks.remove(job.taskId);
        _taskController.add(failedTask);
        _finishUploadAndStartNext();
      },
    );
  }

  void _finishUploadAndStartNext() {
    if (_pendingConflictJob != null) {
      return;
    }

    if (_pendingUploadJobs.isEmpty) {
      _isUploadRunning = false;
      return;
    }

    final nextJob = _pendingUploadJobs.removeAt(0);
    final pendingTask = _activeTasks[nextJob.taskId];
    if (pendingTask == null) {
      _finishUploadAndStartNext();
      return;
    }

    final transferringTask = pendingTask.copyWith(
      status: nextJob.requiresConflictResolution
          ? TransferStatus.awaitingConflictResolution
          : TransferStatus.transferring,
      errorMessage: null,
    );
    _activeTasks[nextJob.taskId] = transferringTask;
    _taskController.add(transferringTask);
    _isUploadRunning = true;
    _startUploadJob(nextJob);
  }
}

class _QueuedUploadJob {
  final String taskId;
  final String localPath;
  final NasPath remotePath;
  final UploadConflictPolicy conflictPolicy;
  final bool requiresConflictResolution;
  final Map<String, String>? uploadHeaders;

  const _QueuedUploadJob({
    required this.taskId,
    required this.localPath,
    required this.remotePath,
    this.conflictPolicy = UploadConflictPolicy.fail,
    this.requiresConflictResolution = false,
    this.uploadHeaders,
  });

  _QueuedUploadJob copyWith({
    UploadConflictPolicy? conflictPolicy,
    bool? requiresConflictResolution,
    Map<String, String>? uploadHeaders,
  }) {
    return _QueuedUploadJob(
      taskId: taskId,
      localPath: localPath,
      remotePath: remotePath,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      requiresConflictResolution:
          requiresConflictResolution ?? this.requiresConflictResolution,
      uploadHeaders: uploadHeaders ?? this.uploadHeaders,
    );
  }
}
