import '../../domain/entities/backup_schedule_entity.dart';

class BackupScheduleUtils {
  static const Duration _onceMissedRunGrace = Duration(hours: 24);

  static DateTime nextRunAt(BackupScheduleEntity schedule, {DateTime? now}) {
    final current = now ?? DateTime.now();
    return switch (schedule.type) {
      BackupScheduleType.daily => _nextDaily(schedule, current),
      BackupScheduleType.weekly => _nextWeekly(schedule, current),
      BackupScheduleType.monthly => _nextMonthly(schedule, current),
      BackupScheduleType.once => schedule.onceAt ?? current,
    };
  }

  static Duration initialDelay(BackupScheduleEntity schedule, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final delay = nextRunAt(schedule, now: current).difference(current);
    return delay.isNegative ? Duration.zero : delay;
  }

  static String formatTime(BackupScheduleEntity schedule) {
    return switch (schedule.type) {
      BackupScheduleType.daily =>
        '每日 ${_formatClock(schedule.hour, schedule.minute)}',
      BackupScheduleType.weekly =>
        '每周${_weekdayLabel(schedule.weekday ?? DateTime.monday)} ${_formatClock(schedule.hour, schedule.minute)}',
      BackupScheduleType.monthly =>
        '每月 ${schedule.dayOfMonth ?? 1} 日 ${_formatClock(schedule.hour, schedule.minute)}${_monthlySuffix(schedule.dayOfMonth)}',
      BackupScheduleType.once =>
        schedule.onceAt == null
            ? '仅一次'
            : '仅一次 ${_formatDateTime(schedule.onceAt!)}',
    };
  }

  static String? describeRule(BackupScheduleEntity schedule) {
    return switch (schedule.type) {
      BackupScheduleType.monthly when (schedule.dayOfMonth ?? 1) > 28 =>
        '如果当月没有这一天，会自动改为当月最后一天执行',
      BackupScheduleType.once => '仅执行一次；错过或执行完成后不会再次触发',
      _ => null,
    };
  }

  static bool isRecurring(BackupScheduleEntity schedule) {
    return schedule.type != BackupScheduleType.once;
  }

  static bool shouldTreatRunAsMissed(
    BackupScheduleEntity schedule,
    DateTime scheduledRunAt, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    if (scheduledRunAt.isAfter(current)) {
      return false;
    }
    if (isRecurring(schedule)) {
      final nextOccurrence = nextRunAt(
        schedule,
        now: scheduledRunAt.add(const Duration(milliseconds: 1)),
      );
      return !current.isBefore(nextOccurrence);
    }
    return current.difference(scheduledRunAt) > _onceMissedRunGrace;
  }

  static DateTime _nextDaily(BackupScheduleEntity schedule, DateTime current) {
    final scheduledToday = DateTime(
      current.year,
      current.month,
      current.day,
      schedule.hour,
      schedule.minute,
    );
    if (scheduledToday.isAfter(current)) {
      return scheduledToday;
    }
    return scheduledToday.add(const Duration(days: 1));
  }

  static DateTime _nextWeekly(BackupScheduleEntity schedule, DateTime current) {
    final rawWeekday = schedule.weekday ?? DateTime.monday;
    final targetWeekday = rawWeekday < DateTime.monday
        ? DateTime.monday
        : rawWeekday > DateTime.sunday
        ? DateTime.sunday
        : rawWeekday;
    final todayTarget = DateTime(
      current.year,
      current.month,
      current.day,
      schedule.hour,
      schedule.minute,
    );
    var daysUntil = (targetWeekday - current.weekday) % 7;
    if (daysUntil == 0 && !todayTarget.isAfter(current)) {
      daysUntil = 7;
    }
    return todayTarget.add(Duration(days: daysUntil));
  }

  static DateTime _nextMonthly(
    BackupScheduleEntity schedule,
    DateTime current,
  ) {
    final currentMonthCandidate = _monthlyOccurrence(
      year: current.year,
      month: current.month,
      dayOfMonth: schedule.dayOfMonth ?? current.day,
      hour: schedule.hour,
      minute: schedule.minute,
    );
    if (currentMonthCandidate.isAfter(current)) {
      return currentMonthCandidate;
    }
    final nextMonth = current.month == 12
        ? DateTime(current.year + 1, 1, 1)
        : DateTime(current.year, current.month + 1, 1);
    return _monthlyOccurrence(
      year: nextMonth.year,
      month: nextMonth.month,
      dayOfMonth: schedule.dayOfMonth ?? 1,
      hour: schedule.hour,
      minute: schedule.minute,
    );
  }

  static DateTime _monthlyOccurrence({
    required int year,
    required int month,
    required int dayOfMonth,
    required int hour,
    required int minute,
  }) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = dayOfMonth < 1
        ? 1
        : dayOfMonth > lastDay
        ? lastDay
        : dayOfMonth;
    return DateTime(year, month, safeDay, hour, minute);
  }

  static String _formatClock(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '一',
      DateTime.tuesday => '二',
      DateTime.wednesday => '三',
      DateTime.thursday => '四',
      DateTime.friday => '五',
      DateTime.saturday => '六',
      DateTime.sunday => '日',
      _ => '一',
    };
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${_formatClock(local.hour, local.minute)}';
  }

  static String _monthlySuffix(int? dayOfMonth) {
    return (dayOfMonth ?? 1) > 28 ? '（短月自动顺延至月底）' : '';
  }
}
