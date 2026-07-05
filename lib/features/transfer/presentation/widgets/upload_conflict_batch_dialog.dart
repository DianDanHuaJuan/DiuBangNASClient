/// 文件输入：冲突数量、冲突文件名示例
/// 文件职责：展示统一的批量重名处理对话框
/// 文件对外接口：showUploadConflictBatchDialog
/// 文件包含：showUploadConflictBatchDialog、_ConflictChoiceButton
import 'package:flutter/material.dart';

import '../../domain/entities/upload_conflict_resolution.dart';

Future<UploadConflictBatchResolution?> showUploadConflictBatchDialog(
  BuildContext context, {
  required int conflictCount,
  List<String> fileNames = const [],
}) {
  final previewNames = fileNames.take(4).toList(growable: false);
  final hasMoreNames = fileNames.length > previewNames.length;

  return showDialog<UploadConflictBatchResolution>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('检测到重名文件'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('检测到 $conflictCount 个重名文件。请选择这批冲突文件的处理方式：'),
            if (previewNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                hasMoreNames
                    ? '${previewNames.join('、')} 等'
                    : previewNames.join('、'),
                style: Theme.of(
                  dialogContext,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6D6C6A)),
              ),
            ],
            const SizedBox(height: 18),
            _ConflictChoiceButton(
              label: '跳过',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictBatchResolution.skip),
            ),
            const SizedBox(height: 10),
            _ConflictChoiceButton(
              label: '覆盖',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictBatchResolution.overwrite),
            ),
            const SizedBox(height: 10),
            _ConflictChoiceButton(
              label: '同时保留',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictBatchResolution.autoRename),
            ),
            const SizedBox(height: 10),
            _ConflictChoiceButton(
              label: '逐个选择',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictBatchResolution.individually),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConflictChoiceButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ConflictChoiceButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton(onPressed: onPressed, child: Text(label)),
    );
  }
}
