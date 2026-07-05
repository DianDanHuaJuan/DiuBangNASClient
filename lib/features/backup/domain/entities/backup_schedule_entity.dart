enum BackupScheduleType { daily, weekly, monthly, once }

class BackupScheduleEntity {
  final BackupScheduleType type;
  final int hour;
  final int minute;
  final int? weekday;
  final int? dayOfMonth;
  final DateTime? onceAt;
  final bool requiresWifi;
  final bool requiresCharging;

  const BackupScheduleEntity({
    this.type = BackupScheduleType.daily,
    required this.hour,
    required this.minute,
    this.weekday,
    this.dayOfMonth,
    this.onceAt,
    this.requiresWifi = false,
    this.requiresCharging = false,
  });
}
