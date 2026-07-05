/// 文件输入：Flutter 运行时入口、bootstrap
/// 文件职责：提供应用唯一入口，启动应用引导
/// 文件对外接口：main
import 'package:flutter/material.dart';
import 'app/bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PaintingBinding.instance.imageCache.maximumSize = 2000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;

  await bootstrap();
}
