/// 文件输入：传输任务相关 UseCase
/// 文件职责：管理传输页面交互与任务操作
/// 文件对外接口：TransferCubit
/// 文件包含：TransferCubit
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/protocol/upload_contract.dart';
import '../../../../core/use_case/no_params.dart';
import '../../application/use_cases/load_transfer_tasks_use_case.dart';
import '../../application/use_cases/enqueue_download_use_case.dart';
import '../../application/use_cases/enqueue_upload_use_case.dart';
import '../../application/use_cases/observe_transfer_tasks_use_case.dart';
import '../../application/use_cases/pause_transfer_use_case.dart';
import '../../application/use_cases/resume_transfer_use_case.dart';
import '../../application/use_cases/cancel_transfer_use_case.dart';
import '../../application/use_cases/clear_completed_transfer_tasks_use_case.dart';
import '../../application/use_cases/resolve_upload_conflict_use_case.dart';
import '../../application/params/enqueue_download_params.dart';
import '../../application/params/enqueue_upload_params.dart';
import '../../application/params/resolve_upload_conflict_params.dart';
import '../../domain/entities/transfer_status.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/entities/upload_conflict_resolution.dart';
import 'transfer_state.dart';

class TransferCubit extends Cubit<TransferState> {
  final LoadTransferTasksUseCase _loadTasksUseCase;
  final EnqueueDownloadUseCase _enqueueDownloadUseCase;
  final EnqueueUploadUseCase _enqueueUploadUseCase;
  final ObserveTransferTasksUseCase _observeTransferTasksUseCase;
  final PauseTransferUseCase _pauseTransferUseCase;
  final ResumeTransferUseCase _resumeTransferUseCase;
  final CancelTransferUseCase _cancelTransferUseCase;
  final ClearCompletedTransferTasksUseCase _clearCompletedTransferTasksUseCase;
  final ResolveUploadConflictUseCase _resolveUploadConflictUseCase;

  StreamSubscription<TransferTaskEntity>? _taskSubscription;

  TransferCubit({
    required LoadTransferTasksUseCase loadTasksUseCase,
    required EnqueueDownloadUseCase enqueueDownloadUseCase,
    required EnqueueUploadUseCase enqueueUploadUseCase,
    required ObserveTransferTasksUseCase observeTransferTasksUseCase,
    required PauseTransferUseCase pauseTransferUseCase,
    required ResumeTransferUseCase resumeTransferUseCase,
    required CancelTransferUseCase cancelTransferUseCase,
    required ClearCompletedTransferTasksUseCase
    clearCompletedTransferTasksUseCase,
    required ResolveUploadConflictUseCase resolveUploadConflictUseCase,
  }) : _loadTasksUseCase = loadTasksUseCase,
       _enqueueDownloadUseCase = enqueueDownloadUseCase,
       _enqueueUploadUseCase = enqueueUploadUseCase,
       _observeTransferTasksUseCase = observeTransferTasksUseCase,
       _pauseTransferUseCase = pauseTransferUseCase,
       _resumeTransferUseCase = resumeTransferUseCase,
       _cancelTransferUseCase = cancelTransferUseCase,
       _clearCompletedTransferTasksUseCase = clearCompletedTransferTasksUseCase,
       _resolveUploadConflictUseCase = resolveUploadConflictUseCase,
       super(const TransferInitial()) {
    _subscribeToTaskStream();
  }

  void _subscribeToTaskStream() {
    _taskSubscription = _observeTransferTasksUseCase.call().listen((task) {
      final currentTasks = state is TransferLoaded
          ? List<TransferTaskEntity>.from((state as TransferLoaded).tasks)
          : <TransferTaskEntity>[];
      final tasks = _upsertTask(currentTasks, task);
      emit(_buildLoadedState(tasks));
    });
  }

  @override
  Future<void> close() {
    _taskSubscription?.cancel();
    return super.close();
  }

  Future<void> loadTasks() async {
    if (state is! TransferLoaded) {
      emit(const TransferLoading());
    }
    final result = await _loadTasksUseCase.call(NoParams());
    result.when(
      success: (tasks) => emit(_buildLoadedState(tasks)),
      failure: (failure) => emit(TransferError(failure.message)),
    );
  }

  Future<TransferTaskEntity?> enqueueDownload({
    required String remotePath,
    required String localPath,
    String? rootId,
  }) async {
    final result = await _enqueueDownloadUseCase.call(
      EnqueueDownloadParams(
        remotePath: remotePath,
        localPath: localPath,
        rootId: rootId,
      ),
    );
    TransferTaskEntity? createdTask;
    result.when(
      success: (task) {
        createdTask = task;
      },
      failure: (failure) => emit(TransferError(failure.message)),
    );
    return createdTask;
  }

  Future<TransferTaskEntity?> enqueueUpload({
    required String localPath,
    required String remotePath,
    String? rootId,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    bool requiresConflictResolution = false,
    Map<String, String>? uploadHeaders,
  }) async {
    final result = await _enqueueUploadUseCase.call(
      EnqueueUploadParams(
        localPath: localPath,
        remotePath: remotePath,
        rootId: rootId,
        conflictPolicy: conflictPolicy,
        requiresConflictResolution: requiresConflictResolution,
        uploadHeaders: uploadHeaders,
      ),
    );
    TransferTaskEntity? createdTask;
    result.when(
      success: (task) {
        createdTask = task;
      },
      failure: (_) {},
    );
    return createdTask;
  }

  Future<void> pauseTask(String taskId) async {
    final result = await _pauseTransferUseCase.call(taskId);
    if (result.isSuccess) {
      await loadTasks();
      return;
    }
    emit(TransferError(result.failureOrNull!.message));
  }

  Future<void> resumeTask(String taskId) async {
    final result = await _resumeTransferUseCase.call(taskId);
    if (result.isSuccess) {
      await loadTasks();
      return;
    }
    emit(TransferError(result.failureOrNull!.message));
  }

  Future<void> cancelTask(String taskId) async {
    final result = await _cancelTransferUseCase.call(taskId);
    if (result.isSuccess) {
      await loadTasks();
      return;
    }
    emit(TransferError(result.failureOrNull!.message));
  }

  Future<void> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  }) async {
    final result = await _resolveUploadConflictUseCase.call(
      ResolveUploadConflictParams(taskId: taskId, resolution: resolution),
    );
    result.when(
      success: (_) {},
      failure: (failure) => emit(TransferError(failure.message)),
    );
  }

  Future<void> clearCompleted() async {
    final result = await _clearCompletedTransferTasksUseCase.call(
      const NoParams(),
    );
    if (result.isSuccess) {
      await loadTasks();
      return;
    }
    emit(TransferError(result.failureOrNull!.message));
  }

  TransferLoaded _buildLoadedState(List<TransferTaskEntity> tasks) {
    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final activeCount = tasks
        .where(
          (t) =>
              t.status == TransferStatus.transferring ||
              t.status == TransferStatus.pending ||
              t.status == TransferStatus.awaitingConflictResolution,
        )
        .length;
    final completedCount = tasks
        .where((t) => t.status == TransferStatus.completed)
        .length;
    return TransferLoaded(
      tasks: tasks,
      activeCount: activeCount,
      completedCount: completedCount,
    );
  }

  List<TransferTaskEntity> _upsertTask(
    List<TransferTaskEntity> tasks,
    TransferTaskEntity task,
  ) {
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      tasks.add(task);
      return tasks;
    }
    tasks[index] = task;
    return tasks;
  }
}
