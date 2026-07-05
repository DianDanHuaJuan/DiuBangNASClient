/// 文件输入：立即备份用例、已选资源与传输任务状态
/// 文件职责：管理立即备份页面中的选择、入队和批次进度聚合逻辑
/// 文件对外接口：BackupCubit、BackupSelectionChange
/// 文件包含：BackupCubit、BackupSelectionChange
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../application/use_cases/complete_backup_run_use_case.dart';
import '../../domain/backup_run_cancellation.dart';
import '../../domain/entities/backup_upload_request.dart';
import '../../../transfer/application/use_cases/cancel_transfer_use_case.dart';
import '../../../transfer/domain/entities/transfer_status.dart';
import '../../../transfer/domain/entities/transfer_task_entity.dart';
import '../../application/params/run_backup_now_params.dart';
import '../../application/use_cases/run_backup_now_use_case.dart';
import '../../domain/entities/backup_preparation_progress.dart';
import '../../domain/entities/backup_run_result.dart';
import '../../domain/entities/backup_source_item.dart';
import 'backup_state.dart';

class BackupCubit extends Cubit<BackupState> {
  final RunBackupNowUseCase _runBackupNowUseCase;
  final CompleteBackupRunUseCase _completeBackupRunUseCase;
  final CancelTransferUseCase _cancelTransferUseCase;
  String? _finalizingRunId;
  BackupRunCancellation? _operationCancellation;
  BackupRunCancellation? _activeCancellation;

  bool get isBackupOperationCancelled =>
      _operationCancellation?.isCancelled ?? false;

  /// Starts a cancellable backup operation (gallery scan + runBackupNow).
  BackupRunCancellation beginBackupOperation() {
    final cancellation = BackupRunCancellation();
    _operationCancellation = cancellation;
    return cancellation;
  }

  void endBackupOperation() {
    _operationCancellation = null;
    _activeCancellation = null;
  }

  BackupCubit({
    required RunBackupNowUseCase runBackupNowUseCase,
    required CompleteBackupRunUseCase completeBackupRunUseCase,
    required CancelTransferUseCase cancelTransferUseCase,
  }) : _runBackupNowUseCase = runBackupNowUseCase,
       _completeBackupRunUseCase = completeBackupRunUseCase,
       _cancelTransferUseCase = cancelTransferUseCase,
       super(const BackupState());

  BackupSelectionChange addSelectedItems(List<BackupSourceItem> items) {
    if (items.isEmpty) {
      return const BackupSelectionChange(addedCount: 0, duplicateCount: 0);
    }

    final mergedItems = List<BackupSourceItem>.from(state.selectedItems);
    final existingIds = mergedItems.map((item) => item.id).toSet();
    var addedCount = 0;
    var duplicateCount = 0;

    for (final item in items) {
      if (!existingIds.add(item.id)) {
        duplicateCount += 1;
        continue;
      }
      mergedItems.add(item);
      addedCount += 1;
    }

    if (addedCount > 0) {
      emit(state.copyWith(selectedItems: List.unmodifiable(mergedItems)));
    }

    return BackupSelectionChange(
      addedCount: addedCount,
      duplicateCount: duplicateCount,
    );
  }

  void removeSelectedItem(String itemId) {
    if (!state.hasSelection) {
      return;
    }
    final updatedItems = state.selectedItems
        .where((item) => item.id != itemId)
        .toList(growable: false);
    emit(state.copyWith(selectedItems: updatedItems));
  }

  void clearSelection() {
    if (!state.hasSelection) {
      return;
    }
    emit(state.copyWith(selectedItems: const []));
  }

  void removeSelectedItemsByIds(Iterable<String> itemIds) {
    final ids = itemIds.toSet();
    if (ids.isEmpty || !state.hasSelection) {
      return;
    }

    final updatedItems = state.selectedItems
        .where((item) => !ids.contains(item.id))
        .toList(growable: false);
    emit(state.copyWith(selectedItems: updatedItems));
  }

  Future<void> stopCurrentBackup() async {
    if (!state.isBackupStoppable) {
      return;
    }

    final preservedSelection = state.selectedItems;
    emit(state.copyWith(isStopping: true));

    _operationCancellation?.cancel();
    _activeCancellation?.cancel();

    for (final taskId in state.trackedTaskIds) {
      await _cancelTransferUseCase.call(taskId);
    }

    final runId = state.activeRunId;
    if (runId != null) {
      _finalizingRunId = runId;
      final skippedCount =
          state.preflightSkippedCount + state.skippedTaskCount;
      final failedCount =
          state.failedToQueueCount + state.failedTaskCount;
      try {
        await _completeBackupRunUseCase.call(
          CompleteBackupRunParams(
            runId: runId,
            status: 'stopped',
            scannedCount: state.activeRunScannedCount,
            queuedCount: state.completedTaskCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            errorMessage: '用户已停止本次备份',
          ),
        );
      } finally {
        if (_finalizingRunId == runId) {
          _finalizingRunId = null;
        }
      }
    }

    emit(
      BackupState(
        selectedItems: preservedSelection,
      ),
    );
  }

  Future<AppResult<BackupRunResult>> runBackupNow({
    List<BackupUploadRequest>? requests,
  }) async {
    if (state.isSubmitting) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_ALREADY_SUBMITTING',
          message: '正在创建备份任务，请稍候',
        ),
      );
    }

    if (state.isBatchRunning) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_BATCH_RUNNING',
          message: '当前批次仍在执行，请等待完成后再开始下一次备份',
        ),
      );
    }

    final hasExplicitRequests = requests != null && requests.isNotEmpty;
    if (!state.hasSelection && !hasExplicitRequests) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_NOTHING_SELECTED',
          message: '请先选择要备份的资源',
        ),
      );
    }

    final effectiveRequests =
        requests ??
        state.selectedItems
            .map((item) => BackupUploadRequest.fromSource(item))
            .toList(growable: false);

    emit(
      state.copyWith(
        isSubmitting: true,
        isPreparing: true,
        isStopping: false,
        trackedTaskIds: const [],
        queuedTaskCount: 0,
        failedToQueueCount: 0,
        completedTaskCount: 0,
        failedTaskCount: 0,
        preflightSkippedCount: 0,
        skippedTaskCount: 0,
        pendingTaskCount: 0,
        activeTaskCount: 0,
        totalBytes: 0,
        transferredBytes: 0,
        activeFileName: null,
        activeRunId: null,
        activeRunScannedCount: 0,
        activeRunErrorMessage: null,
        showFloatingStatusBar: false,
        preparationPhase: BackupPreparationPhase.inspectingFiles,
        preparationProcessedCount: 0,
        preparationTotalCount: effectiveRequests.length,
        preparationDetail: '正在检查本地文件',
      ),
    );

    final operationStartedHere = _operationCancellation == null;
    final cancellation = _operationCancellation ?? BackupRunCancellation();
    if (operationStartedHere) {
      _operationCancellation = cancellation;
    }
    _activeCancellation = cancellation;
    final result = await _runBackupNowUseCase.call(
      RunBackupNowParams(
        requests: effectiveRequests,
        onProgress: updatePreparationProgress,
        cancellation: cancellation,
      ),
    );
    _activeCancellation = null;
    if (operationStartedHere) {
      _operationCancellation = null;
    }

    if (cancellation.isCancelled) {
      return result;
    }

    result.when(
      success: (runResult) {
        emit(
          state.copyWith(
            isSubmitting: false,
            isPreparing: false,
            selectedItems: List.unmodifiable(runResult.failedItems),
            trackedTaskIds: List.unmodifiable(runResult.queuedTaskIds),
            queuedTaskCount: runResult.queuedCount,
            failedToQueueCount: runResult.failedCount,
            completedTaskCount: 0,
            failedTaskCount: 0,
            preflightSkippedCount: runResult.skippedCount,
            skippedTaskCount: 0,
            pendingTaskCount: runResult.queuedCount,
            activeTaskCount: 0,
            totalBytes: 0,
            transferredBytes: 0,
            activeFileName: null,
            activeRunId: runResult.hasQueuedTasks ? runResult.runId : null,
            activeRunScannedCount: runResult.scannedCount,
            activeRunErrorMessage: runResult.failureMessages.isEmpty
                ? null
                : runResult.failureMessages.first,
            showFloatingStatusBar: runResult.queuedCount > 0,
            preparationPhase: null,
            preparationProcessedCount: 0,
            preparationTotalCount: 0,
            preparationDetail: null,
          ),
        );
      },
      failure: (failure) {
        if (failure.code == 'BACKUP_RUN_CANCELLED') {
          emit(
            BackupState(
              selectedItems: state.selectedItems,
            ),
          );
          return;
        }
        emit(
          state.copyWith(
            isSubmitting: false,
            isPreparing: false,
            showFloatingStatusBar: false,
            preparationPhase: null,
            preparationProcessedCount: 0,
            preparationTotalCount: 0,
            preparationDetail: null,
          ),
        );
      },
    );

    return result;
  }

  void updatePreparationProgress(BackupPreparationProgress progress) {
    if (state.isStopping || isBackupOperationCancelled) {
      return;
    }
    emit(
      state.copyWith(
        isPreparing: true,
        preparationPhase: progress.phase,
        preparationProcessedCount: progress.processedCount,
        preparationTotalCount: progress.totalCount,
        preparationDetail: progress.detail,
      ),
    );
  }

  void clearPreparationProgress() {
    emit(
      state.copyWith(
        isPreparing: false,
        preparationPhase: null,
        preparationProcessedCount: 0,
        preparationTotalCount: 0,
        preparationDetail: null,
      ),
    );
  }

  void dismissFloatingStatusBar() {
    if (!state.showFloatingStatusBar) {
      return;
    }
    emit(state.copyWith(showFloatingStatusBar: false));
  }

  void syncTrackedTasks(List<TransferTaskEntity> tasks) {
    if (!state.hasTrackedBatch || state.trackedTaskIds.isEmpty) {
      return;
    }

    final trackedIds = state.trackedTaskIds.toSet();
    final trackedTasks = <TransferTaskEntity>[];
    for (final task in tasks) {
      if (trackedIds.contains(task.id)) {
        trackedTasks.add(task);
      }
    }

    if (trackedTasks.isEmpty) {
      return;
    }

    var completedTaskCount = 0;
    var failedTaskCount = 0;
    var skippedTaskCount = 0;
    var activeTaskCount = 0;
    var totalBytes = 0;
    var transferredBytes = 0;
    String? activeFileName;
    String? firstTaskErrorMessage;

    for (final task in trackedTasks) {
      totalBytes += task.totalBytes;
      switch (task.status) {
        case TransferStatus.completed:
          completedTaskCount += 1;
          transferredBytes += task.totalBytes;
          break;
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          failedTaskCount += 1;
          transferredBytes += task.transferredBytes;
          firstTaskErrorMessage ??= task.errorMessage;
          break;
        case TransferStatus.skipped:
          skippedTaskCount += 1;
          transferredBytes += task.transferredBytes;
          break;
        case TransferStatus.transferring:
        case TransferStatus.awaitingConflictResolution:
          activeTaskCount += 1;
          transferredBytes += task.transferredBytes;
          activeFileName ??= task.fileName;
          break;
        case TransferStatus.pending:
        case TransferStatus.paused:
          transferredBytes += task.transferredBytes;
          activeFileName ??= task.fileName;
          break;
      }
    }

    final pendingTaskCount =
        (state.queuedTaskCount -
                completedTaskCount -
                failedTaskCount -
                skippedTaskCount -
                activeTaskCount)
            .clamp(0, state.queuedTaskCount);

    final nextState = state.copyWith(
      completedTaskCount: completedTaskCount,
      failedTaskCount: failedTaskCount,
      skippedTaskCount: skippedTaskCount,
      pendingTaskCount: pendingTaskCount,
      activeTaskCount: activeTaskCount,
      totalBytes: totalBytes,
      transferredBytes: transferredBytes,
      activeFileName: activeFileName,
      activeRunErrorMessage:
          firstTaskErrorMessage ?? state.activeRunErrorMessage,
    );

    if (nextState.isBatchFinished && nextState.activeRunId != null) {
      emit(nextState);
      if (_finalizingRunId != nextState.activeRunId) {
        unawaited(_finalizeActiveRun(nextState));
      }
      return;
    }

    emit(nextState);
  }

  Future<void> _finalizeActiveRun(BackupState currentState) async {
    final runId = currentState.activeRunId;
    if (runId == null) {
      return;
    }
    _finalizingRunId = runId;
    final skippedCount =
        currentState.preflightSkippedCount + currentState.skippedTaskCount;
    final failedCount =
        currentState.failedToQueueCount + currentState.failedTaskCount;
    try {
      await _completeBackupRunUseCase.call(
        CompleteBackupRunParams(
          runId: runId,
          status: _resolveRunStatus(
            completedCount: currentState.completedTaskCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
          ),
          scannedCount: currentState.activeRunScannedCount,
          queuedCount: currentState.completedTaskCount,
          skippedCount: skippedCount,
          failedCount: failedCount,
          errorMessage: currentState.activeRunErrorMessage,
        ),
      );
      emit(state.copyWith(activeRunId: null, activeRunScannedCount: 0));
    } finally {
      if (_finalizingRunId == runId) {
        _finalizingRunId = null;
      }
    }
  }

  String _resolveRunStatus({
    required int completedCount,
    required int skippedCount,
    required int failedCount,
  }) {
    if (failedCount > 0) {
      return completedCount > 0 || skippedCount > 0
          ? 'partial_failed'
          : 'failed';
    }
    return 'completed';
  }
}

class BackupSelectionChange {
  final int addedCount;
  final int duplicateCount;

  const BackupSelectionChange({
    required this.addedCount,
    required this.duplicateCount,
  });
}
