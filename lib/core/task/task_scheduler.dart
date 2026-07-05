/// 文件输入：计划任务配置、系统后台调度能力、任务触发请求
/// 文件职责：统一封装即时任务与定时任务调度，管理备份计划的定时触发
/// 文件对外接口：TaskScheduler
/// 文件包含：TaskScheduler
import 'dart:async';

class ScheduledTask {
  final String id;
  final String name;
  final DateTime scheduledTime;
  final bool repeat;
  final Duration? repeatInterval;
  final void Function()? callback;

  ScheduledTask({
    required this.id,
    required this.name,
    required this.scheduledTime,
    this.repeat = false,
    this.repeatInterval,
    this.callback,
  });
}

class TaskScheduler {
  final Map<String, Timer> _timers = {};
  final List<ScheduledTask> _scheduledTasks = [];

  TaskScheduler();

  Future<void> schedule(ScheduledTask task) async {
    _scheduledTasks.add(task);
    _startTimer(task);
  }

  void _startTimer(ScheduledTask task) {
    final now = DateTime.now();
    var delay = task.scheduledTime.difference(now);

    if (delay.isNegative) {
      if (task.repeat && task.repeatInterval != null) {
        delay = task.repeatInterval!;
      } else {
        return;
      }
    }

    final timer = Timer(delay, () {
      task.callback?.call();
      if (task.repeat && task.repeatInterval != null) {
        _scheduleNext(task);
      } else {
        _scheduledTasks.removeWhere((t) => t.id == task.id);
      }
    });

    _timers[task.id] = timer;
  }

  void _scheduleNext(ScheduledTask task) {
    final timer = Timer(task.repeatInterval!, () {
      task.callback?.call();
      _scheduleNext(task);
    });
    _timers[task.id] = timer;
  }

  Future<void> cancel(String taskId) async {
    final timer = _timers.remove(taskId);
    timer?.cancel();
    _scheduledTasks.removeWhere((t) => t.id == taskId);
  }

  Future<void> cancelAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _scheduledTasks.clear();
  }

  List<ScheduledTask> get scheduledTasks => List.unmodifiable(_scheduledTasks);

  bool isScheduled(String taskId) {
    return _timers.containsKey(taskId);
  }
}
