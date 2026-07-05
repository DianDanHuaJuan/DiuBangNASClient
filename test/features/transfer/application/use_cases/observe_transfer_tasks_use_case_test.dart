/// 文件输入：ObserveTransferTasksUseCase、TransferRepository
/// 文件职责：验证传输任务观察用例会透传任务事件流
/// 文件对外接口：main
/// 文件包含：main、_FakeTransferRepository
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/features/transfer/application/use_cases/observe_transfer_tasks_use_case.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_direction.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_status.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_task_entity.dart';
import 'package:nasclient/features/transfer/domain/entities/upload_conflict_resolution.dart';
import 'package:nasclient/features/transfer/domain/repositories/transfer_repository.dart';

/// 输入：Flutter test runtime。
/// 职责：验证传输任务订阅用例不会改写仓库发出的任务事件。
/// 对外接口：main。
void main() {
  group('ObserveTransferTasksUseCase', () {
    test('forwards repository task stream events', () async {
      final repository = _FakeTransferRepository();
      addTearDown(repository.dispose);
      final useCase = ObserveTransferTasksUseCase(repository: repository);

      final expectedTask = TransferTaskEntity(
        id: 'task-1',
        rootId: 'library',
        localPath: 'C:\\temp\\clip.mp4',
        remotePath: '/camera/clip.mp4',
        fileName: 'clip.mp4',
        totalBytes: 10,
        transferredBytes: 4,
        direction: TransferDirection.download,
        status: TransferStatus.transferring,
        createdAt: DateTime(2026, 4, 9),
      );

      final expectation = expectLater(
        useCase.call(),
        emits(
          isA<TransferTaskEntity>()
              .having((task) => task.id, 'id', expectedTask.id)
              .having((task) => task.rootId, 'rootId', expectedTask.rootId)
              .having(
                (task) => task.remotePath,
                'remotePath',
                expectedTask.remotePath,
              ),
        ),
      );

      repository.controller.add(expectedTask);
      await expectation;
    });
  });
}

/// 输入：无。
/// 职责：为传输任务观察用例测试提供可控的任务事件流。
/// 对外接口：taskStream、dispose()。
class _FakeTransferRepository implements TransferRepository {
  final StreamController<TransferTaskEntity> controller =
      StreamController<TransferTaskEntity>.broadcast();

  @override
  Stream<TransferTaskEntity> get taskStream => controller.stream;

  @override
  Future<AppResult<void>> cancelTask(String taskId) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> clearCompletedTasks() {
    throw UnimplementedError();
  }

  void dispose() {
    controller.close();
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
  Future<AppResult<void>> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<TransferTaskEntity>>> loadTasks() {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> pauseTask(String taskId) {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> resumeTask(String taskId) {
    throw UnimplementedError();
  }
}
