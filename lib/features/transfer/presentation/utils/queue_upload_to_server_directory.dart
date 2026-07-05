import 'package:flutter/material.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/device/local_media_picker.dart';
import '../../../../core/path/nas_path.dart';
import '../../../files/application/params/list_directory_params.dart';
import '../../../files/domain/entities/file_category.dart';
import '../../../files/domain/entities/file_entry_entity.dart';
import '../../domain/entities/transfer_task_entity.dart';
import '../../domain/entities/upload_conflict_resolution.dart';
import '../cubit/transfer_cubit.dart';
import '../models/upload_conflict_plan.dart';
import '../widgets/upload_conflict_batch_dialog.dart';

class QueuedServerUploadResult {
  final List<PickedLocalMediaItem> pickedItems;
  final List<TransferTaskEntity> createdTasks;
  final int skippedCount;
  final int failedCount;
  final int unavailableCount;

  const QueuedServerUploadResult({
    required this.pickedItems,
    required this.createdTasks,
    required this.skippedCount,
    required this.failedCount,
    required this.unavailableCount,
  });
}

class QueueUploadToServerDirectory {
  static const LocalMediaPicker _localMediaPicker = LocalMediaPicker();
  static const UploadConflictPlanBuilder _uploadConflictPlanBuilder =
      UploadConflictPlanBuilder();

  const QueueUploadToServerDirectory();

  Future<QueuedServerUploadResult?> call(
    BuildContext context, {
    required TransferCubit transferCubit,
    required NasPath targetPath,
  }) async {
    final pickResult = await _localMediaPicker.pickMedia(context);
    if (pickResult.items.isEmpty) {
      return null;
    }

    return _queuePickedItems(
      context,
      transferCubit: transferCubit,
      targetPath: targetPath,
      items: pickResult.items,
      unavailableCount: pickResult.unavailableCount,
    );
  }

  Future<QueuedServerUploadResult?> pickFilesAndQueue(
    BuildContext context, {
    required TransferCubit transferCubit,
    required NasPath targetPath,
  }) async {
    final paths = await serviceLocator.deviceFileService.pickUploadFiles();
    if (paths.isEmpty) {
      return null;
    }

    final items = <PickedLocalMediaItem>[];
    for (final path in paths) {
      if (!context.mounted) {
        return null;
      }
      final displayName = await serviceLocator.deviceFileService.getFileName(
        path,
      );
      final size = await serviceLocator.deviceFileService.getFileSize(path);
      items.add(
        PickedLocalMediaItem(
          id: path,
          localPath: path,
          displayName: displayName,
          size: size,
          mimeType: guessMimeTypeFromFileName(displayName),
        ),
      );
    }

    if (!context.mounted) {
      return null;
    }

    return _queuePickedItems(
      context,
      transferCubit: transferCubit,
      targetPath: targetPath,
      items: items,
    );
  }

  Future<QueuedServerUploadResult?> _queuePickedItems(
    BuildContext context, {
    required TransferCubit transferCubit,
    required NasPath targetPath,
    required List<PickedLocalMediaItem> items,
    int unavailableCount = 0,
  }) async {
    final currentEntries = await _loadCurrentEntriesForConflictCheck(
      targetPath,
    );
    if (!context.mounted) {
      return null;
    }

    final plan = _uploadConflictPlanBuilder.build(
      selectedItems: items,
      currentEntries: currentEntries,
      resolveFileName: (item) => item.displayName,
    );
    var preparedPlan = plan.applyBatchResolution(
      UploadConflictBatchResolution.individually,
    );
    if (plan.hasConflicts) {
      final batchResolution = await showUploadConflictBatchDialog(
        context,
        conflictCount: plan.conflictCount,
        fileNames: plan.uniqueConflictFileNames,
      );
      if (!context.mounted || batchResolution == null) {
        return null;
      }
      preparedPlan = plan.applyBatchResolution(batchResolution);
    }

    final createdTasks = <TransferTaskEntity>[];
    var failedCount = 0;
    for (final preparedItem in preparedPlan.queuedItems) {
      final remotePath = targetPath.path == '/'
          ? '/${preparedItem.fileName}'
          : '${targetPath.path}/${preparedItem.fileName}';
      final task = await transferCubit.enqueueUpload(
        localPath: preparedItem.item.localPath,
        remotePath: remotePath,
        rootId: targetPath.rootId,
        conflictPolicy: preparedItem.conflictPolicy,
        requiresConflictResolution: preparedItem.requiresConflictResolution,
      );
      if (!context.mounted) {
        return null;
      }
      if (task == null) {
        failedCount += 1;
        continue;
      }
      createdTasks.add(task);
    }

    return QueuedServerUploadResult(
      pickedItems: items,
      createdTasks: List.unmodifiable(createdTasks),
      skippedCount: preparedPlan.skippedCount,
      failedCount: failedCount,
      unavailableCount: unavailableCount,
    );
  }

  Future<List<FileEntryEntity>> _loadCurrentEntriesForConflictCheck(
    NasPath targetPath,
  ) async {
    const pageLimit = 500;
    final seenPaths = <String>{};
    final entries = <FileEntryEntity>[];

    for (final category in FileCategory.values) {
      final page = await serviceLocator.fileRepository
          .listDirectory(
            ListDirectoryParams(
              path: targetPath,
              category: category,
              limit: pageLimit,
            ),
          )
          .then((result) => result.dataOrNull);
      if (page == null) {
        continue;
      }
      for (final entry in page.items) {
        if (seenPaths.add(entry.path)) {
          entries.add(entry);
        }
      }
    }
    return entries;
  }
}

void showQueuedUploadResultSnackBar(
  BuildContext context, {
  required QueuedServerUploadResult result,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final parts = <String>[];

  if (result.createdTasks.length == 1 &&
      result.failedCount == 0 &&
      result.unavailableCount == 0) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已加入上传队列: ${result.pickedItems.single.displayName}'),
      ),
    );
    return;
  }

  if (result.createdTasks.isNotEmpty) {
    parts.add('已加入 ${result.createdTasks.length} 个上传任务');
  }
  if (result.skippedCount > 0) {
    parts.add('已预先跳过 ${result.skippedCount} 个重名文件');
  }
  if (result.failedCount > 0) {
    parts.add('${result.failedCount} 个未加入');
  }
  if (result.unavailableCount > 0) {
    parts.add('${result.unavailableCount} 个无法读取');
  }

  if (parts.isEmpty) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('没有可上传的资源')));
    return;
  }

  if (result.createdTasks.isEmpty && result.skippedCount == 0) {
    parts.insert(0, '未创建上传任务');
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(parts.join('，'))));
}
