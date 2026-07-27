/// 文件输入：BuildContext
/// 文件职责：在发现页/登录页展示短暂的服务器连接失败提示
/// 文件对外接口：showServerConnectionFailedDialog
import 'package:flutter/material.dart';

Future<void> showServerConnectionFailedDialog(BuildContext context) async {
  if (!context.mounted) {
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return const AlertDialog(
        content: Text('服务器连接失败', textAlign: TextAlign.center),
      );
    },
  );

  await Future<void>.delayed(const Duration(milliseconds: 2500));
  if (!context.mounted) {
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
}
