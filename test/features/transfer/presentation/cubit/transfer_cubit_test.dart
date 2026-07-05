import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/features/transfer/application/use_cases/cancel_transfer_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/clear_completed_transfer_tasks_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/enqueue_download_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/enqueue_upload_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/load_transfer_tasks_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/observe_transfer_tasks_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/pause_transfer_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/resolve_upload_conflict_use_case.dart';
import 'package:nasclient/features/transfer/application/use_cases/resume_transfer_use_case.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_direction.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_status.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_task_entity.dart';
import 'package:nasclient/features/transfer/domain/entities/upload_conflict_resolution.dart';
import 'package:nasclient/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:nasclient/features/transfer/presentation/cubit/transfer_cubit.dart';
import 'package:nasclient/features/transfer/presentation/cubit/transfer_state.dart';

void main() {
  group('TransferCubit.clearCompleted', () {
    test(
      'removes completed tasks without cancelling active transfers',
      () async {
        final repository = _FakeTransferRepository(
          initialTasks: [
            _task(id: 'completed-1', status: TransferStatus.completed),
            _task(id: 'active-1', status: TransferStatus.transferring),
          ],
        );
        final cubit = TransferCubit(
          loadTasksUseCase: LoadTransferTasksUseCase(repository: repository),
          enqueueDownloadUseCase: EnqueueDownloadUseCase(
            repository: repository,
          ),
          enqueueUploadUseCase: EnqueueUploadUseCase(repository: repository),
          observeTransferTasksUseCase: ObserveTransferTasksUseCase(
            repository: repository,
          ),
          pauseTransferUseCase: PauseTransferUseCase(repository: repository),
          resumeTransferUseCase: ResumeTransferUseCase(repository: repository),
          cancelTransferUseCase: CancelTransferUseCase(repository: repository),
          clearCompletedTransferTasksUseCase:
              ClearCompletedTransferTasksUseCase(repository: repository),
          resolveUploadConflictUseCase: ResolveUploadConflictUseCase(
            repository: repository,
          ),
        );
        addTearDown(() async {
          await cubit.close();
          await repository.dispose();
        });

        await cubit.loadTasks();
        expect(cubit.state, isA<TransferLoaded>());
        final initialState = cubit.state as TransferLoaded;
        expect(initialState.tasks, hasLength(2));
        expect(initialState.completedCount, 1);
        expect(initialState.activeCount, 1);

        await cubit.clearCompleted();

        expect(repository.clearCompletedCallCount, 1);
        expect(repository.cancelledTaskIds, isEmpty);
        expect(cubit.state, isA<TransferLoaded>());
        final clearedState = cubit.state as TransferLoaded;
        expect(clearedState.tasks, hasLength(1));
        expect(clearedState.tasks.single.id, 'active-1');
        expect(clearedState.completedCount, 0);
        expect(clearedState.activeCount, 1);
      },
    );
  });
}

TransferTaskEntity _task({required String id, required TransferStatus status}) {
  return TransferTaskEntity(
    id: id,
    rootId: 'fs',
    localPath: 'C:\\temp\\$id.dat',
    remotePath: '/$id.dat',
    fileName: '$id.dat',
    totalBytes: 100,
    transferredBytes: status == TransferStatus.completed ? 100 : 50,
    direction: TransferDirection.upload,
    status: status,
    createdAt: DateTime(2026, 4, 12, 12),
  );
}

class _FakeTransferRepository implements TransferRepository {
  final List<TransferTaskEntity> _tasks;
  final _controller = StreamController<TransferTaskEntity>.broadcast();
  int clearCompletedCallCount = 0;
  final List<String> cancelledTaskIds = [];

  _FakeTransferRepository({required List<TransferTaskEntity> initialTasks})
    : _tasks = List<TransferTaskEntity>.from(initialTasks);

  @override
  Stream<TransferTaskEntity> get taskStream => _controller.stream;

  @override
  Future<AppResult<void>> cancelTask(String taskId) async {
    cancelledTaskIds.add(taskId);
    return const Success(null);
  }

  @override
  Future<AppResult<void>> clearCompletedTasks() async {
    clearCompletedCallCount += 1;
    _tasks.removeWhere((task) => task.status == TransferStatus.completed);
    return const Success(null);
  }

  @override
  Future<AppResult<TransferTaskEntity>> enqueueDownload({
    required String remotePath,
    required String localPath,
    String? rootId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<TransferTaskEntity>> enqueueUpload({
    required String localPath,
    required String remotePath,
    String? rootId,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    bool requiresConflictResolution = false,
    Map<String, String>? uploadHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<TransferTaskEntity>>> loadTasks() async {
    return Success(List<TransferTaskEntity>.from(_tasks));
  }

  @override
  Future<AppResult<void>> pauseTask(String taskId) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> resumeTask(String taskId) {
    throw UnimplementedError();
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
