/// 文件输入：BackupCubit、RunBackupNowUseCase、BackupRepository
/// 文件职责：验证立即备份 Cubit 的选择去重和批次进度聚合逻辑
/// 文件对外接口：main
/// 文件包含：main、_FakeBackupRepository
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/features/backup/application/use_cases/complete_backup_run_use_case.dart';
import 'package:nasclient/features/backup/application/use_cases/run_backup_now_use_case.dart';
import 'package:nasclient/features/backup/domain/entities/backup_plan_entity.dart';
import 'package:nasclient/features/backup/domain/entities/backup_preparation_progress.dart';
import 'package:nasclient/features/backup/domain/entities/backup_run_result.dart';
import 'package:nasclient/features/backup/domain/entities/backup_run_record_entity.dart';
import 'package:nasclient/features/backup/domain/entities/backup_source_item.dart';
import 'package:nasclient/features/backup/domain/entities/backup_source_type.dart';
import 'package:nasclient/features/backup/domain/entities/backup_upload_request.dart';
import 'package:nasclient/features/backup/domain/backup_run_cancellation.dart';
import 'package:nasclient/features/backup/domain/repositories/backup_repository.dart';
import 'package:nasclient/features/backup/presentation/cubit/backup_cubit.dart';
import 'package:nasclient/features/transfer/application/use_cases/cancel_transfer_use_case.dart';
import 'package:nasclient/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:nasclient/features/transfer/domain/entities/upload_conflict_resolution.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_direction.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_status.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_task_entity.dart';

/// 输入：Flutter test runtime。
/// 职责：验证立即备份页面状态在选择和任务执行过程中的关键变化。
/// 对外接口：main。
void main() {
  group('BackupCubit', () {
    test('deduplicates selected items by stable id', () {
      final repository = _FakeBackupRepository(
        result: const Success(
          BackupRunResult(
            runId: 'run-1',
            rootId: 'fs',
            rootName: 'NASServer',
            scannedCount: 0,
            queuedTaskIds: <String>[],
            skippedCount: 0,
            failedItems: <BackupSourceItem>[],
            failureMessages: <String>[],
          ),
        ),
      );
      final cubit = BackupCubit(
        runBackupNowUseCase: RunBackupNowUseCase(repository: repository),
        completeBackupRunUseCase: CompleteBackupRunUseCase(
          repository: repository,
        ),
        cancelTransferUseCase: CancelTransferUseCase(
          repository: _FakeTransferRepository(),
        ),
      );
      addTearDown(cubit.close);

      const mediaItem = BackupSourceItem(
        id: 'media:1',
        sourceType: BackupSourceType.media,
        localPath: 'C:\\camera\\photo.jpg',
        displayName: 'photo.jpg',
        size: 100,
      );
      const fileItem = BackupSourceItem(
        id: 'C:\\docs\\note.txt',
        sourceType: BackupSourceType.file,
        localPath: 'C:\\docs\\note.txt',
        displayName: 'note.txt',
        size: 20,
      );

      final firstChange = cubit.addSelectedItems(const [mediaItem, fileItem]);
      final duplicateChange = cubit.addSelectedItems(const [mediaItem]);

      expect(firstChange.addedCount, 2);
      expect(firstChange.duplicateCount, 0);
      expect(duplicateChange.addedCount, 0);
      expect(duplicateChange.duplicateCount, 1);
      expect(cubit.state.selectedItems, const [mediaItem, fileItem]);
    });

    test('tracks queued batch progress from transfer task updates', () async {
      final repository = _FakeBackupRepository(
        result: const Success(
          BackupRunResult(
            runId: 'run-1',
            rootId: 'fs',
            rootName: 'NASServer',
            scannedCount: 2,
            queuedTaskIds: <String>['task-1', 'task-2'],
            skippedCount: 0,
            failedItems: <BackupSourceItem>[],
            failureMessages: <String>[],
          ),
        ),
      );
      final cubit = BackupCubit(
        runBackupNowUseCase: RunBackupNowUseCase(repository: repository),
        completeBackupRunUseCase: CompleteBackupRunUseCase(
          repository: repository,
        ),
        cancelTransferUseCase: CancelTransferUseCase(
          repository: _FakeTransferRepository(),
        ),
      );
      addTearDown(cubit.close);

      cubit.addSelectedItems(const [
        BackupSourceItem(
          id: 'media:1',
          sourceType: BackupSourceType.media,
          localPath: 'C:\\camera\\photo.jpg',
          displayName: 'photo.jpg',
          size: 100,
        ),
        BackupSourceItem(
          id: 'media:2',
          sourceType: BackupSourceType.media,
          localPath: 'C:\\camera\\clip.mp4',
          displayName: 'clip.mp4',
          size: 200,
        ),
      ]);

      final runResult = await cubit.runBackupNow();

      expect(runResult.isSuccess, isTrue);
      expect(cubit.state.selectedItems, isEmpty);
      expect(cubit.state.queuedTaskCount, 2);
      expect(cubit.state.pendingTaskCount, 2);

      cubit.syncTrackedTasks([
        _task(
          id: 'task-1',
          fileName: 'photo.jpg',
          totalBytes: 100,
          transferredBytes: 40,
          status: TransferStatus.transferring,
        ),
        _task(
          id: 'task-2',
          fileName: 'clip.mp4',
          totalBytes: 200,
          transferredBytes: 0,
          status: TransferStatus.pending,
        ),
      ]);

      expect(cubit.state.activeTaskCount, 1);
      expect(cubit.state.pendingTaskCount, 1);
      expect(cubit.state.activeFileName, 'photo.jpg');
      expect(cubit.state.batchProgress, closeTo(40 / 300, 0.0001));

      cubit.syncTrackedTasks([
        _task(
          id: 'task-1',
          fileName: 'photo.jpg',
          totalBytes: 100,
          transferredBytes: 100,
          status: TransferStatus.completed,
        ),
        _task(
          id: 'task-2',
          fileName: 'clip.mp4',
          totalBytes: 200,
          transferredBytes: 50,
          status: TransferStatus.failed,
        ),
      ]);

      expect(cubit.state.isBatchFinished, isTrue);
      expect(cubit.state.completedTaskCount, 1);
      expect(cubit.state.failedTaskCount, 1);
      expect(cubit.state.pendingTaskCount, 0);
      expect(cubit.state.batchProgress, closeTo(150 / 300, 0.0001));
      await Future<void>.delayed(Duration.zero);
      expect(repository.completedRuns, hasLength(1));
      expect(repository.completedRuns.single.status, 'partial_failed');
      expect(repository.completedRuns.single.queuedCount, 1);
      expect(repository.completedRuns.single.failedCount, 1);
    });

    test('treats skipped upload tasks as terminal batch items', () async {
      final repository = _FakeBackupRepository(
        result: const Success(
          BackupRunResult(
            runId: 'run-2',
            rootId: 'fs',
            rootName: 'NASServer',
            scannedCount: 2,
            queuedTaskIds: <String>['task-1', 'task-2'],
            skippedCount: 0,
            failedItems: <BackupSourceItem>[],
            failureMessages: <String>[],
          ),
        ),
      );
      final cubit = BackupCubit(
        runBackupNowUseCase: RunBackupNowUseCase(repository: repository),
        completeBackupRunUseCase: CompleteBackupRunUseCase(
          repository: repository,
        ),
        cancelTransferUseCase: CancelTransferUseCase(
          repository: _FakeTransferRepository(),
        ),
      );
      addTearDown(cubit.close);

      cubit.addSelectedItems(const [
        BackupSourceItem(
          id: 'media:1',
          sourceType: BackupSourceType.media,
          localPath: 'C:\\camera\\photo.jpg',
          displayName: 'photo.jpg',
          size: 100,
        ),
      ]);

      await cubit.runBackupNow();

      cubit.syncTrackedTasks([
        _task(
          id: 'task-1',
          fileName: 'photo.jpg',
          totalBytes: 100,
          transferredBytes: 100,
          status: TransferStatus.completed,
        ),
        _task(
          id: 'task-2',
          fileName: 'clip.mp4',
          totalBytes: 200,
          transferredBytes: 0,
          status: TransferStatus.skipped,
        ),
      ]);

      expect(cubit.state.isBatchFinished, isTrue);
      expect(cubit.state.completedTaskCount, 1);
      expect(cubit.state.skippedTaskCount, 1);
      expect(cubit.state.pendingTaskCount, 0);
      await Future<void>.delayed(Duration.zero);
      expect(repository.completedRuns.single.status, 'completed');
      expect(repository.completedRuns.single.skippedCount, 1);
    });

    test('ignores preparation progress after gallery scan stop', () async {
      final repository = _FakeBackupRepository(
        result: const Success(
          BackupRunResult(
            runId: 'run-stop',
            rootId: 'fs',
            rootName: 'NASServer',
            scannedCount: 0,
            queuedTaskIds: <String>[],
            skippedCount: 0,
            failedItems: <BackupSourceItem>[],
            failureMessages: <String>[],
          ),
        ),
      );
      final cubit = BackupCubit(
        runBackupNowUseCase: RunBackupNowUseCase(repository: repository),
        completeBackupRunUseCase: CompleteBackupRunUseCase(
          repository: repository,
        ),
        cancelTransferUseCase: CancelTransferUseCase(
          repository: _FakeTransferRepository(),
        ),
      );
      addTearDown(cubit.close);

      final cancellation = cubit.beginBackupOperation();
      cubit.updatePreparationProgress(
        const BackupPreparationProgress(
          phase: BackupPreparationPhase.scanningGallery,
          processedCount: 1,
          totalCount: 100,
          detail: 'scanning',
        ),
      );

      expect(cubit.state.isPreparing, isTrue);
      expect(cancellation.isCancelled, isFalse);

      await cubit.stopCurrentBackup();

      expect(cancellation.isCancelled, isTrue);
      expect(cubit.isBackupOperationCancelled, isTrue);
      expect(cubit.state.isPreparing, isFalse);

      cubit.updatePreparationProgress(
        const BackupPreparationProgress(
          phase: BackupPreparationPhase.scanningGallery,
          processedCount: 50,
          totalCount: 100,
          detail: 'should be ignored',
        ),
      );

      expect(cubit.state.isPreparing, isFalse);
      expect(cubit.state.preparationProcessedCount, 0);
    });

    test(
      'still starts backup after external preparation progress is shown',
      () async {
        final repository = _FakeBackupRepository(
          result: const Success(
            BackupRunResult(
              runId: 'run-3',
              rootId: 'fs',
              rootName: 'NASServer',
              scannedCount: 1,
              queuedTaskIds: <String>['task-1'],
              skippedCount: 0,
              failedItems: <BackupSourceItem>[],
              failureMessages: <String>[],
            ),
          ),
        );
        final cubit = BackupCubit(
          runBackupNowUseCase: RunBackupNowUseCase(repository: repository),
          completeBackupRunUseCase: CompleteBackupRunUseCase(
            repository: repository,
          ),
          cancelTransferUseCase: CancelTransferUseCase(
            repository: _FakeTransferRepository(),
          ),
        );
        addTearDown(cubit.close);

        cubit.updatePreparationProgress(
          const BackupPreparationProgress(
            phase: BackupPreparationPhase.scanningGallery,
            processedCount: 10,
            totalCount: 100,
            detail: '已扫描 10 / 100 项',
          ),
        );

        const item = BackupSourceItem(
          id: 'media:1',
          sourceType: BackupSourceType.media,
          localPath: 'C:\\camera\\photo.jpg',
          displayName: 'photo.jpg',
          size: 100,
        );

        final result = await cubit.runBackupNow(
          requests: [BackupUploadRequest.fromSource(item)],
        );

        expect(result.isSuccess, isTrue);
        expect(cubit.state.queuedTaskCount, 1);
        expect(cubit.state.isPreparing, isFalse);
        expect(cubit.state.isSubmitting, isFalse);
      },
    );
  });
}

TransferTaskEntity _task({
  required String id,
  required String fileName,
  required int totalBytes,
  required int transferredBytes,
  required TransferStatus status,
}) {
  return TransferTaskEntity(
    id: id,
    rootId: 'fs',
    localPath: 'C:\\temp\\$fileName',
    remotePath: '/$fileName',
    fileName: fileName,
    totalBytes: totalBytes,
    transferredBytes: transferredBytes,
    direction: TransferDirection.upload,
    status: status,
    createdAt: DateTime(2026, 4, 10),
  );
}

/// 输入：预设的运行结果。
/// 职责：为 BackupCubit 测试提供可控的立即备份用例后端。
/// 对外接口：runBackupNow()。
class _FakeBackupRepository implements BackupRepository {
  final AppResult<BackupRunResult> result;
  final List<_CompletedRun> completedRuns = <_CompletedRun>[];

  _FakeBackupRepository({required this.result});

  @override
  Future<AppResult<BackupPlanEntity>> createPlan(BackupPlanEntity plan) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<BackupPlanEntity>>> loadPlans() async {
    return const Success(<BackupPlanEntity>[]);
  }

  @override
  Future<AppResult<List<BackupRunRecordEntity>>> loadRecentRuns({
    String? planId,
    int limit = 10,
    bool onlyAbnormal = false,
  }) async {
    return const Success(<BackupRunRecordEntity>[]);
  }

  @override
  Future<AppResult<BackupRunResult>> runBackupNow(
    List<BackupUploadRequest> requests, {
    void Function(BackupPreparationProgress progress)? onProgress,
    BackupRunCancellation? cancellation,
  }) async {
    if (result.isFailure) {
      return result;
    }

    final success = result.dataOrNull!;
    return Success(
      BackupRunResult(
        runId: success.runId,
        rootId: success.rootId,
        rootName: success.rootName,
        scannedCount: success.scannedCount,
        queuedTaskIds: success.queuedTaskIds,
        skippedCount: success.skippedCount,
        failedItems: success.failedItems,
        failureMessages: success.failureMessages,
      ),
    );
  }

  @override
  Future<AppResult<void>> completeRun({
    required String runId,
    required String status,
    required int scannedCount,
    required int queuedCount,
    required int skippedCount,
    required int failedCount,
    String? errorMessage,
  }) async {
    completedRuns.add(
      _CompletedRun(
        runId: runId,
        status: status,
        scannedCount: scannedCount,
        queuedCount: queuedCount,
        skippedCount: skippedCount,
        failedCount: failedCount,
        errorMessage: errorMessage,
      ),
    );
    return const Success(null);
  }

  @override
  Future<AppResult<void>> togglePlan(String planId, bool enabled) async {
    return const Success(null);
  }
}

class _FakeTransferRepository implements TransferRepository {
  @override
  Stream<TransferTaskEntity> get taskStream => const Stream.empty();

  @override
  Future<AppResult<void>> cancelTask(String taskId) async {
    return const Success(null);
  }

  @override
  Future<AppResult<void>> clearCompletedTasks() async {
    return const Success(null);
  }

  @override
  Future<AppResult<TransferTaskEntity>> enqueueDownload({
    required String localPath,
    required String remotePath,
    String? rootId,
  }) async {
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
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> pauseTask(String taskId) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<void>> resumeTask(String taskId) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<List<TransferTaskEntity>>> loadTasks() async {
    return const Success(<TransferTaskEntity>[]);
  }

  @override
  Future<AppResult<void>> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  }) async {
    throw UnimplementedError();
  }
}

class _CompletedRun {
  const _CompletedRun({
    required this.runId,
    required this.status,
    required this.scannedCount,
    required this.queuedCount,
    required this.skippedCount,
    required this.failedCount,
    this.errorMessage,
  });

  final String runId;
  final String status;
  final int scannedCount;
  final int queuedCount;
  final int skippedCount;
  final int failedCount;
  final String? errorMessage;
}
