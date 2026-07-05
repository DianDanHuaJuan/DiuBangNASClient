/// 文件输入：待上传项、目标目录现有目录项、批量冲突处理动作
/// 文件职责：在上传前识别重名冲突，并把批量处理动作转换为可入队任务计划
/// 文件对外接口：UploadConflictPlanBuilder、UploadConflictPlan、PreparedUploadPlan
/// 文件包含：UploadConflictType、UploadConflictItem、UploadConflictPlanEntry、UploadConflictPlan、PreparedUploadItem、PreparedUploadPlan、UploadConflictPlanBuilder
import '../../../../core/protocol/upload_contract.dart';
import '../../../files/domain/entities/file_entry_entity.dart';
import '../../domain/entities/upload_conflict_resolution.dart';

enum UploadConflictType { existingEntry, selectedDuplicate }

class UploadConflictItem<T> {
  final T item;
  final String fileName;
  final UploadConflictType type;

  const UploadConflictItem({
    required this.item,
    required this.fileName,
    required this.type,
  });
}

class UploadConflictPlanEntry<T> {
  final T item;
  final String fileName;
  final UploadConflictType? conflictType;

  const UploadConflictPlanEntry({
    required this.item,
    required this.fileName,
    this.conflictType,
  });

  bool get hasConflict => conflictType != null;
}

class UploadConflictPlan<T> {
  final List<UploadConflictPlanEntry<T>> entries;
  final int existingEntryConflictCount;
  final int selectedDuplicateConflictCount;

  const UploadConflictPlan({
    required this.entries,
    this.existingEntryConflictCount = 0,
    this.selectedDuplicateConflictCount = 0,
  });

  bool get hasConflicts => conflictItems.isNotEmpty;

  int get conflictCount => conflictItems.length;

  List<T> get uploadableItems {
    return List.unmodifiable(
      entries.where((entry) => !entry.hasConflict).map((entry) => entry.item),
    );
  }

  List<UploadConflictItem<T>> get conflictItems {
    final items = <UploadConflictItem<T>>[];
    for (final entry in entries) {
      final conflictType = entry.conflictType;
      if (conflictType == null) {
        continue;
      }
      items.add(
        UploadConflictItem(
          item: entry.item,
          fileName: entry.fileName,
          type: conflictType,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  List<String> get conflictFileNames {
    return List.unmodifiable(conflictItems.map((item) => item.fileName));
  }

  List<String> get uniqueConflictFileNames {
    final seen = <String>{};
    final names = <String>[];
    for (final name in conflictFileNames) {
      if (seen.add(name)) {
        names.add(name);
      }
    }
    return List.unmodifiable(names);
  }

  PreparedUploadPlan<T> applyBatchResolution(
    UploadConflictBatchResolution resolution,
  ) {
    final queuedItems = <PreparedUploadItem<T>>[];
    final skippedItems = <T>[];

    for (final entry in entries) {
      if (!entry.hasConflict) {
        queuedItems.add(
          PreparedUploadItem(item: entry.item, fileName: entry.fileName),
        );
        continue;
      }

      switch (resolution) {
        case UploadConflictBatchResolution.skip:
          skippedItems.add(entry.item);
          break;
        case UploadConflictBatchResolution.overwrite:
          queuedItems.add(
            PreparedUploadItem(
              item: entry.item,
              fileName: entry.fileName,
              conflictPolicy: UploadConflictPolicy.overwrite,
            ),
          );
          break;
        case UploadConflictBatchResolution.autoRename:
          queuedItems.add(
            PreparedUploadItem(
              item: entry.item,
              fileName: entry.fileName,
              conflictPolicy: UploadConflictPolicy.autoRename,
            ),
          );
          break;
        case UploadConflictBatchResolution.individually:
          queuedItems.add(
            PreparedUploadItem(
              item: entry.item,
              fileName: entry.fileName,
              requiresConflictResolution: true,
            ),
          );
          break;
      }
    }

    return PreparedUploadPlan(
      queuedItems: List.unmodifiable(queuedItems),
      skippedItems: List.unmodifiable(skippedItems),
    );
  }
}

class PreparedUploadItem<T> {
  final T item;
  final String fileName;
  final UploadConflictPolicy conflictPolicy;
  final bool requiresConflictResolution;

  const PreparedUploadItem({
    required this.item,
    required this.fileName,
    this.conflictPolicy = UploadConflictPolicy.fail,
    this.requiresConflictResolution = false,
  });
}

class PreparedUploadPlan<T> {
  final List<PreparedUploadItem<T>> queuedItems;
  final List<T> skippedItems;

  const PreparedUploadPlan({
    required this.queuedItems,
    required this.skippedItems,
  });

  int get skippedCount => skippedItems.length;
}

class UploadConflictPlanBuilder {
  const UploadConflictPlanBuilder();

  UploadConflictPlan<T> build<T>({
    required List<T> selectedItems,
    required List<FileEntryEntity> currentEntries,
    required String Function(T item) resolveFileName,
  }) {
    final existingNames = currentEntries
        .map((entry) => entry.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final seenSelectedNames = <String>{};
    final entries = <UploadConflictPlanEntry<T>>[];
    var existingEntryConflictCount = 0;
    var selectedDuplicateConflictCount = 0;

    for (final item in selectedItems) {
      final fileName = resolveFileName(item).trim();
      UploadConflictType? conflictType;

      if (fileName.isNotEmpty) {
        if (existingNames.contains(fileName)) {
          conflictType = UploadConflictType.existingEntry;
          existingEntryConflictCount += 1;
        } else if (!seenSelectedNames.add(fileName)) {
          conflictType = UploadConflictType.selectedDuplicate;
          selectedDuplicateConflictCount += 1;
        }
      }

      entries.add(
        UploadConflictPlanEntry(
          item: item,
          fileName: fileName,
          conflictType: conflictType,
        ),
      );
    }

    return UploadConflictPlan(
      entries: List.unmodifiable(entries),
      existingEntryConflictCount: existingEntryConflictCount,
      selectedDuplicateConflictCount: selectedDuplicateConflictCount,
    );
  }
}
