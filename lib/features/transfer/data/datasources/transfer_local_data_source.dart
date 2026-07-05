/// 文件输入：键值存储、任务 DTO
/// 文件职责：传输任务的本地持久化存储
/// 文件对外接口：TransferLocalDataSource
/// 文件包含：TransferLocalDataSource
import 'dart:convert';
import '../../../../core/storage/key_value_store.dart';
import '../models/transfer_task_dto.dart';

class TransferLocalDataSource {
  final KeyValueStore _keyValueStore;
  static const String _tasksKey = 'transfer_tasks';

  TransferLocalDataSource({required KeyValueStore keyValueStore})
    : _keyValueStore = keyValueStore;

  Future<List<TransferTaskDto>> loadTasks() async {
    final jsonStr = _keyValueStore.getString(_tasksKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((json) => TransferTaskDto.fromJson(json)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTasks(List<TransferTaskDto> tasks) async {
    final jsonList = tasks.map((t) => t.toJson()).toList();
    await _keyValueStore.setString(_tasksKey, jsonEncode(jsonList));
  }

  Future<void> addTask(TransferTaskDto task) async {
    final tasks = await loadTasks();
    tasks.add(task);
    await saveTasks(tasks);
  }

  Future<void> updateTask(TransferTaskDto task) async {
    final tasks = await loadTasks();
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      tasks[index] = task;
      await saveTasks(tasks);
    }
  }

  Future<void> removeTask(String taskId) async {
    final tasks = await loadTasks();
    tasks.removeWhere((t) => t.id == taskId);
    await saveTasks(tasks);
  }

  Future<void> clearCompletedTasks() async {
    final tasks = await loadTasks();
    tasks.removeWhere((t) => t.status == 'completed');
    await saveTasks(tasks);
  }
}
