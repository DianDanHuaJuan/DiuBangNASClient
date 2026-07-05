/// 文件输入：Flutter 绑定初始化、依赖注册器、本地存储初始化
/// 文件职责：完成应用启动前初始化，并调用 runApp
/// 文件对外接口：bootstrap
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'di/service_locator.dart';
import '../core/storage/key_value_store.dart';

Future<void> bootstrap() async {
  final prefs = await SharedPreferences.getInstance();
  final keyValueStore = KeyValueStore(prefs: prefs);

  await configureDependencies(
    keyValueStore: keyValueStore,
    sharedPreferences: prefs,
  );
  runApp(const App());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeDeferredStartupTasks());
  });
}

Future<void> _initializeDeferredStartupTasks() async {
  await serviceLocator.backupPlanScheduler.syncPlans();
}
