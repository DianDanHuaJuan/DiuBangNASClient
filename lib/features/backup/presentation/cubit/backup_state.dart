/// 文件输入：已选资源、批次任务追踪与聚合进度信息
/// 文件职责：表达立即备份页面的稳定状态，供 UI 渲染选择结果和执行进度
/// 文件对外接口：BackupState
/// 文件包含：BackupState
import '../../domain/entities/backup_source_item.dart';
import '../../domain/entities/backup_preparation_progress.dart';

class BackupState {
  static const Object _unset = Object();

  final List<BackupSourceItem> selectedItems;
  final bool isSubmitting;
  final bool isPreparing;
  final List<String> trackedTaskIds;
  final int queuedTaskCount;
  final int failedToQueueCount;
  final int completedTaskCount;
  final int failedTaskCount;
  final int preflightSkippedCount;
  final int skippedTaskCount;
  final int pendingTaskCount;
  final int activeTaskCount;
  final int totalBytes;
  final int transferredBytes;
  final String? activeFileName;
  final bool showFloatingStatusBar;
  final BackupPreparationPhase? preparationPhase;
  final int preparationProcessedCount;
  final int preparationTotalCount;
  final String? preparationDetail;
  final String? activeRunId;
  final int activeRunScannedCount;
  final String? activeRunErrorMessage;
  final bool isStopping;

  const BackupState({
    this.selectedItems = const [],
    this.isSubmitting = false,
    this.isPreparing = false,
    this.trackedTaskIds = const [],
    this.queuedTaskCount = 0,
    this.failedToQueueCount = 0,
    this.completedTaskCount = 0,
    this.failedTaskCount = 0,
    this.preflightSkippedCount = 0,
    this.skippedTaskCount = 0,
    this.pendingTaskCount = 0,
    this.activeTaskCount = 0,
    this.totalBytes = 0,
    this.transferredBytes = 0,
    this.activeFileName,
    this.showFloatingStatusBar = false,
    this.preparationPhase,
    this.preparationProcessedCount = 0,
    this.preparationTotalCount = 0,
    this.preparationDetail,
    this.activeRunId,
    this.activeRunScannedCount = 0,
    this.activeRunErrorMessage,
    this.isStopping = false,
  });

  int get selectedTotalBytes =>
      selectedItems.fold<int>(0, (sum, item) => sum + item.size);

  int get duplicateNameCount {
    final seenNames = <String>{};
    var duplicates = 0;
    for (final item in selectedItems) {
      final normalizedName = item.displayName.trim().toLowerCase();
      if (normalizedName.isEmpty) {
        continue;
      }
      if (!seenNames.add(normalizedName)) {
        duplicates += 1;
      }
    }
    return duplicates;
  }

  bool get hasSelection => selectedItems.isNotEmpty;

  bool get hasTrackedBatch => queuedTaskCount > 0;

  bool get isBusyPreparing => isPreparing || isSubmitting;

  bool get isBatchRunning =>
      hasTrackedBatch &&
      completedTaskCount + failedTaskCount + skippedTaskCount < queuedTaskCount;

  bool get isBatchFinished => hasTrackedBatch && !isBatchRunning;

  bool get isBackupStoppable =>
      !isStopping && (isBusyPreparing || isBatchRunning);

  bool get shouldConfirmBackNavigation =>
      isBackupStoppable || isStopping;

  double get batchProgress {
    if (totalBytes > 0) {
      return transferredBytes / totalBytes;
    }
    if (!hasTrackedBatch) {
      return 0;
    }
    return isBatchFinished ? 1 : 0;
  }

  double get preparationProgress {
    if (preparationTotalCount <= 0) {
      return 0;
    }
    return preparationProcessedCount / preparationTotalCount;
  }

  BackupState copyWith({
    List<BackupSourceItem>? selectedItems,
    bool? isSubmitting,
    bool? isPreparing,
    List<String>? trackedTaskIds,
    int? queuedTaskCount,
    int? failedToQueueCount,
    int? completedTaskCount,
    int? failedTaskCount,
    int? preflightSkippedCount,
    int? skippedTaskCount,
    int? pendingTaskCount,
    int? activeTaskCount,
    int? totalBytes,
    int? transferredBytes,
    Object? activeFileName = _unset,
    bool? showFloatingStatusBar,
    Object? preparationPhase = _unset,
    int? preparationProcessedCount,
    int? preparationTotalCount,
    Object? preparationDetail = _unset,
    Object? activeRunId = _unset,
    int? activeRunScannedCount,
    Object? activeRunErrorMessage = _unset,
    bool? isStopping,
  }) {
    return BackupState(
      selectedItems: selectedItems ?? this.selectedItems,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isPreparing: isPreparing ?? this.isPreparing,
      trackedTaskIds: trackedTaskIds ?? this.trackedTaskIds,
      queuedTaskCount: queuedTaskCount ?? this.queuedTaskCount,
      failedToQueueCount: failedToQueueCount ?? this.failedToQueueCount,
      completedTaskCount: completedTaskCount ?? this.completedTaskCount,
      failedTaskCount: failedTaskCount ?? this.failedTaskCount,
      preflightSkippedCount:
          preflightSkippedCount ?? this.preflightSkippedCount,
      skippedTaskCount: skippedTaskCount ?? this.skippedTaskCount,
      pendingTaskCount: pendingTaskCount ?? this.pendingTaskCount,
      activeTaskCount: activeTaskCount ?? this.activeTaskCount,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      activeFileName: identical(activeFileName, _unset)
          ? this.activeFileName
          : activeFileName as String?,
      showFloatingStatusBar:
          showFloatingStatusBar ?? this.showFloatingStatusBar,
      preparationPhase: identical(preparationPhase, _unset)
          ? this.preparationPhase
          : preparationPhase as BackupPreparationPhase?,
      preparationProcessedCount:
          preparationProcessedCount ?? this.preparationProcessedCount,
      preparationTotalCount:
          preparationTotalCount ?? this.preparationTotalCount,
      preparationDetail: identical(preparationDetail, _unset)
          ? this.preparationDetail
          : preparationDetail as String?,
      activeRunId: identical(activeRunId, _unset)
          ? this.activeRunId
          : activeRunId as String?,
      activeRunScannedCount:
          activeRunScannedCount ?? this.activeRunScannedCount,
      activeRunErrorMessage: identical(activeRunErrorMessage, _unset)
          ? this.activeRunErrorMessage
          : activeRunErrorMessage as String?,
      isStopping: isStopping ?? this.isStopping,
    );
  }
}
