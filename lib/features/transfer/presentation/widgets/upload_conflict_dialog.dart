/// 文件输入：BuildContext、冲突文件名
/// 文件职责：展示统一的上传重名处理对话框
/// 文件对外接口：showUploadConflictDialog
/// 文件包含：showUploadConflictDialog
import 'package:flutter/material.dart';

import '../../domain/entities/upload_conflict_resolution.dart';

Future<UploadConflictResolution?> showUploadConflictDialog(
  BuildContext context, {
  required String fileName,
}) {
  return showDialog<UploadConflictResolution>(
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
            Text('“$fileName” 已存在于目标位置。请选择处理方式：'),
            const SizedBox(height: 18),
            _ConflictChoiceButton(
              label: '跳过',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictResolution.skip),
            ),
            const SizedBox(height: 10),
            _ConflictChoiceButton(
              label: '覆盖',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictResolution.overwrite),
            ),
            const SizedBox(height: 10),
            _ConflictChoiceButton(
              label: '同时保留',
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(UploadConflictResolution.autoRename),
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
