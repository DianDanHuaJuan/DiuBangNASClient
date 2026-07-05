import 'dart:convert';

import '../../domain/entities/backup_schedule_entity.dart';

class BackupScheduleDto {
  final BackupScheduleType type;
  final int hour;
  final int minute;
  final int? weekday;
  final int? dayOfMonth;
  final DateTime? onceAt;
  final bool requiresWifi;
  final bool requiresCharging;

  const BackupScheduleDto({
    required this.type,
    required this.hour,
    required this.minute,
    this.weekday,
    this.dayOfMonth,
    this.onceAt,
    required this.requiresWifi,
    required this.requiresCharging,
  });

  factory BackupScheduleDto.fromEntity(BackupScheduleEntity entity) {
    return BackupScheduleDto(
      type: entity.type,
      hour: entity.hour,
      minute: entity.minute,
      weekday: entity.weekday,
      dayOfMonth: entity.dayOfMonth,
      onceAt: entity.onceAt,
      requiresWifi: entity.requiresWifi,
      requiresCharging: entity.requiresCharging,
    );
  }

  static BackupScheduleDto? fromDatabaseMap(Map<String, Object?> map) {
    final typeValue = map['schedule_type'] as String?;
    final timeValue = map['schedule_time'] as String?;
    if (typeValue == null || timeValue == null || timeValue.trim().isEmpty) {
      return null;
    }

    final parts = timeValue.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final daysValue = map['schedule_days'] as String?;
    int? weekday;
    int? dayOfMonth = map['schedule_day_of_month'] as int?;
    DateTime? onceAt = () {
      final value = map['schedule_once_at'];
      if (value is! String || value.trim().isEmpty) {
        return null;
      }
      return DateTime.tryParse(value);
    }();
    if (daysValue != null && daysValue.trim().isNotEmpty) {
      final raw = jsonDecode(daysValue);
      if (raw is Map) {
        final weekdayValue = raw['weekday'];
        if (weekdayValue is int) {
          weekday = weekdayValue;
        } else if (weekdayValue is num) {
          weekday = weekdayValue.toInt();
        }
        final dayOfMonthValue = raw['dayOfMonth'];
        if (dayOfMonthValue is int) {
          dayOfMonth = dayOfMonthValue;
        } else if (dayOfMonthValue is num) {
          dayOfMonth = dayOfMonthValue.toInt();
        }
        final onceAtValue = raw['onceAt'];
        if (onceAtValue is String && onceAtValue.trim().isNotEmpty) {
          onceAt = DateTime.tryParse(onceAtValue);
        }
      } else if (raw is List) {
        for (final value in raw) {
          if (value is int) {
            weekday ??= value;
          } else if (value is num) {
            weekday ??= value.toInt();
          }
        }
      }
    }

    return BackupScheduleDto(
      type: switch (typeValue) {
        'weekly' => BackupScheduleType.weekly,
        'monthly' => BackupScheduleType.monthly,
        'once' => BackupScheduleType.once,
        _ => BackupScheduleType.daily,
      },
      hour: hour,
      minute: minute,
      weekday: weekday,
      dayOfMonth: dayOfMonth,
      onceAt: onceAt,
      requiresWifi: (map['requires_wifi'] as int? ?? 0) == 1,
      requiresCharging: (map['requires_charging'] as int? ?? 0) == 1,
    );
  }

  BackupScheduleEntity toEntity() {
    return BackupScheduleEntity(
      type: type,
      hour: hour,
      minute: minute,
      weekday: weekday,
      dayOfMonth: dayOfMonth,
      onceAt: onceAt,
      requiresWifi: requiresWifi,
      requiresCharging: requiresCharging,
    );
  }

  String get typeValue => switch (type) {
    BackupScheduleType.daily => 'daily',
    BackupScheduleType.weekly => 'weekly',
    BackupScheduleType.monthly => 'monthly',
    BackupScheduleType.once => 'once',
  };

  String get timeValue =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get daysValue => switch (type) {
    BackupScheduleType.daily => jsonEncode(const <String, Object?>{}),
    BackupScheduleType.weekly => jsonEncode({'weekday': weekday}),
    BackupScheduleType.monthly => jsonEncode({'dayOfMonth': dayOfMonth}),
    BackupScheduleType.once => jsonEncode({
      'onceAt': onceAt?.toIso8601String(),
    }),
  };

  int get requiresWifiValue => requiresWifi ? 1 : 0;

  int get requiresChargingValue => requiresCharging ? 1 : 0;
}
