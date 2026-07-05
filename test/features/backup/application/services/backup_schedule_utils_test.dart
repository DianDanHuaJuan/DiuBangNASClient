import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/features/backup/application/services/backup_schedule_utils.dart';
import 'package:nasclient/features/backup/domain/entities/backup_schedule_entity.dart';

void main() {
  group('BackupScheduleUtils', () {
    test('returns later today when schedule has not passed yet', () {
      const schedule = BackupScheduleEntity(hour: 22, minute: 30);
      final now = DateTime(2026, 1, 1, 20, 15);

      final nextRun = BackupScheduleUtils.nextRunAt(schedule, now: now);

      expect(nextRun, DateTime(2026, 1, 1, 22, 30));
      expect(
        BackupScheduleUtils.initialDelay(schedule, now: now),
        const Duration(hours: 2, minutes: 15),
      );
    });

    test('rolls over to tomorrow when today time already passed', () {
      const schedule = BackupScheduleEntity(hour: 2, minute: 0);
      final now = DateTime(2026, 1, 1, 5, 45);

      final nextRun = BackupScheduleUtils.nextRunAt(schedule, now: now);

      expect(nextRun, DateTime(2026, 1, 2, 2, 0));
      expect(
        BackupScheduleUtils.initialDelay(schedule, now: now),
        const Duration(hours: 20, minutes: 15),
      );
    });

    test('schedules the next weekly run on the selected weekday', () {
      const schedule = BackupScheduleEntity(
        type: BackupScheduleType.weekly,
        hour: 9,
        minute: 0,
        weekday: DateTime.friday,
      );
      final now = DateTime(2026, 1, 5, 10, 30);

      final nextRun = BackupScheduleUtils.nextRunAt(schedule, now: now);

      expect(nextRun, DateTime(2026, 1, 9, 9, 0));
    });

    test('clamps monthly schedule to the last day of shorter months', () {
      const schedule = BackupScheduleEntity(
        type: BackupScheduleType.monthly,
        hour: 7,
        minute: 15,
        dayOfMonth: 31,
      );
      final now = DateTime(2026, 2, 1, 8, 0);

      final nextRun = BackupScheduleUtils.nextRunAt(schedule, now: now);

      expect(nextRun, DateTime(2026, 2, 28, 7, 15));
    });

    test('uses the explicit datetime for one-off schedules', () {
      final schedule = BackupScheduleEntity(
        type: BackupScheduleType.once,
        hour: 6,
        minute: 45,
        onceAt: DateTime(2026, 3, 12, 6, 45),
      );
      final now = DateTime(2026, 3, 10, 8, 0);

      final nextRun = BackupScheduleUtils.nextRunAt(schedule, now: now);

      expect(nextRun, DateTime(2026, 3, 12, 6, 45));
      expect(
        BackupScheduleUtils.initialDelay(schedule, now: now),
        const Duration(days: 1, hours: 22, minutes: 45),
      );
    });

    test(
      'does not mark recurring runs missed just because they start later',
      () {
        const schedule = BackupScheduleEntity(hour: 9, minute: 0);

        final missed = BackupScheduleUtils.shouldTreatRunAsMissed(
          schedule,
          DateTime(2026, 1, 1, 9, 0),
          now: DateTime(2026, 1, 1, 10, 30),
        );

        expect(missed, isFalse);
      },
    );

    test('marks recurring runs missed once the next occurrence is reached', () {
      const schedule = BackupScheduleEntity(hour: 9, minute: 0);

      final missed = BackupScheduleUtils.shouldTreatRunAsMissed(
        schedule,
        DateTime(2026, 1, 1, 9, 0),
        now: DateTime(2026, 1, 2, 9, 0),
      );

      expect(missed, isTrue);
    });

    test(
      'gives one-off schedules a wider grace window before marking missed',
      () {
        final schedule = BackupScheduleEntity(
          type: BackupScheduleType.once,
          hour: 6,
          minute: 45,
          onceAt: DateTime(2026, 3, 12, 6, 45),
        );

        expect(
          BackupScheduleUtils.shouldTreatRunAsMissed(
            schedule,
            DateTime(2026, 3, 12, 6, 45),
            now: DateTime(2026, 3, 12, 20, 0),
          ),
          isFalse,
        );
        expect(
          BackupScheduleUtils.shouldTreatRunAsMissed(
            schedule,
            DateTime(2026, 3, 12, 6, 45),
            now: DateTime(2026, 3, 13, 7, 0),
          ),
          isTrue,
        );
      },
    );
  });
}
