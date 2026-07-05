import 'package:sqflite/sqflite.dart';

import '../../../../core/storage/app_database.dart';
import '../../domain/entities/backup_plan_schedule_status.dart';
import '../models/backup_asset_state_dto.dart';
import '../models/backup_plan_dto.dart';
import '../models/backup_run_record_dto.dart';

class BackupLocalDataSource {
  BackupLocalDataSource({required AppDatabase appDatabase})
    : _appDatabase = appDatabase;

  final AppDatabase _appDatabase;

  Future<List<BackupPlanDto>> loadPlans() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'backup_plans',
      orderBy: 'updated_at DESC, created_at DESC',
    );
    return rows.map(BackupPlanDto.fromMap).toList(growable: false);
  }

  Future<BackupPlanDto?> loadPlanById(String planId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'backup_plans',
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return BackupPlanDto.fromMap(rows.first);
  }

  Future<void> savePlan(BackupPlanDto plan) async {
    final db = await _appDatabase.database;
    await db.insert(
      'backup_plans',
      plan.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePlanEnabled(String planId, bool enabled) async {
    final db = await _appDatabase.database;
    await db.update(
      'backup_plans',
      {
        'enabled': enabled ? 1 : 0,
        if (!enabled) ...<String, Object?>{
          'schedule_status': BackupPlanScheduleStatus.unscheduled.wireValue,
          'schedule_error': null,
          'scheduled_run_at': null,
        },
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [planId],
    );
  }

  Future<void> updatePlanLastRun(String planId, DateTime lastRunAt) async {
    final db = await _appDatabase.database;
    await db.update(
      'backup_plans',
      {
        'last_run_at': lastRunAt.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [planId],
    );
  }

  Future<void> updatePlanScheduleState(
    String planId, {
    required BackupPlanScheduleStatus status,
    String? scheduleErrorMessage,
    DateTime? scheduledRunAt,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      'backup_plans',
      {
        'schedule_status': status.wireValue,
        'schedule_error': scheduleErrorMessage,
        'scheduled_run_at': scheduledRunAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [planId],
    );
  }

  Future<void> insertRun({
    required String runId,
    String? planId,
    required String triggerType,
    required String status,
    required DateTime startedAt,
  }) async {
    final db = await _appDatabase.database;
    await db.insert('backup_runs', {
      'id': runId,
      'plan_id': planId,
      'trigger_type': triggerType,
      'status': status,
      'started_at': startedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> completeRun({
    required String runId,
    required String status,
    required int scannedCount,
    required int queuedCount,
    required int skippedCount,
    required int failedCount,
    required DateTime finishedAt,
    String? errorMessage,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      'backup_runs',
      {
        'status': status,
        'scanned_count': scannedCount,
        'queued_count': queuedCount,
        'skipped_count': skippedCount,
        'failed_count': failedCount,
        'finished_at': finishedAt.toIso8601String(),
        'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  Future<bool> hasActiveRun(String planId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'backup_runs',
      columns: const ['id'],
      where: 'plan_id = ? AND status IN (?, ?, ?)',
      whereArgs: [planId, 'running', 'retrying', 'stopping'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasRecentUserStoppedRun(
    String planId, {
    Duration window = const Duration(minutes: 5),
  }) async {
    final db = await _appDatabase.database;
    final cutoff = DateTime.now().subtract(window).toUtc().toIso8601String();
    final rows = await db.query(
      'backup_runs',
      columns: const ['id'],
      where: 'plan_id = ? AND status = ? AND finished_at >= ?',
      whereArgs: [planId, 'stopped', cutoff],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasRecordedRunForPlanSince(String planId, DateTime since) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      'backup_runs',
      columns: const ['id'],
      where: 'plan_id = ? AND started_at >= ?',
      whereArgs: [planId, since.toUtc().toIso8601String()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<BackupRunRecordDto>> loadRecentRuns({
    String? planId,
    int limit = 10,
    bool onlyAbnormal = false,
  }) async {
    final db = await _appDatabase.database;
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (planId != null && planId.trim().isNotEmpty) {
      whereParts.add('plan_id = ?');
      whereArgs.add(planId);
    }
    if (onlyAbnormal) {
      whereParts.add('status NOT IN (?, ?, ?)');
      whereArgs.addAll(const ['completed', 'running', 'retrying']);
    }
    final rows = await db.query(
      'backup_runs',
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'COALESCE(finished_at, started_at) DESC, started_at DESC',
      limit: limit,
    );
    return rows.map(BackupRunRecordDto.fromMap).toList(growable: false);
  }

  Future<void> applyNativeWorkerState({
    required Iterable<Map<String, Object?>> planStates,
    required Iterable<Map<String, Object?>> runRecords,
  }) async {
    final normalizedPlanStates = planStates.toList(growable: false);
    final normalizedRunRecords = runRecords.toList(growable: false);
    if (normalizedPlanStates.isEmpty && normalizedRunRecords.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      final updatedAt = DateTime.now().toIso8601String();
      for (final planState in normalizedPlanStates) {
        final planId = planState['planId'] as String?;
        if (planId == null || planId.trim().isEmpty) {
          continue;
        }
        batch.update(
          'backup_plans',
          {
            'last_run_at': _millisToIso8601(planState['lastRunAtMillis']),
            'schedule_status':
                planState['scheduleStatus'] as String? ??
                BackupPlanScheduleStatus.unscheduled.wireValue,
            'schedule_error': planState['scheduleErrorMessage'] as String?,
            'scheduled_run_at': _millisToIso8601(
              planState['scheduledRunAtMillis'],
            ),
            'updated_at': updatedAt,
          },
          where: 'id = ?',
          whereArgs: [planId],
        );
      }

      for (final runRecord in normalizedRunRecords) {
        final runId = runRecord['id'] as String?;
        if (runId == null || runId.trim().isEmpty) {
          continue;
        }
        batch.insert('backup_runs', {
          'id': runId,
          'plan_id': runRecord['planId'] as String?,
          'trigger_type': runRecord['triggerType'] as String? ?? 'scheduled',
          'status': runRecord['status'] as String? ?? 'failed',
          'scanned_count': _asInt(runRecord['scannedCount']),
          'queued_count': _asInt(runRecord['queuedCount']),
          'skipped_count': _asInt(runRecord['skippedCount']),
          'failed_count': _asInt(runRecord['failedCount']),
          'started_at':
              _millisToIso8601(runRecord['startedAtMillis']) ??
              DateTime.now().toIso8601String(),
          'finished_at': _millisToIso8601(runRecord['finishedAtMillis']),
          'error_message': runRecord['errorMessage'] as String?,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, BackupAssetStateDto>> loadAssetStates({
    required String serverId,
    required String rootId,
    required Iterable<String> sourceFingerprints,
  }) async {
    final fingerprints = sourceFingerprints
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (fingerprints.isEmpty) {
      return const <String, BackupAssetStateDto>{};
    }

    final db = await _appDatabase.database;
    final result = <String, BackupAssetStateDto>{};
    for (final chunk in _chunk(fingerprints, 200)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await db.query(
        'backup_asset_state',
        where:
            'server_id = ? AND root_id = ? AND source_fingerprint IN ($placeholders)',
        whereArgs: [serverId, rootId, ...chunk],
      );
      for (final row in rows) {
        final dto = BackupAssetStateDto.fromMap(row);
        result[dto.sourceFingerprint] = dto;
      }
    }
    return result;
  }

  Future<void> upsertAssetStates(List<BackupAssetStateDto> states) async {
    if (states.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final state in states) {
        batch.insert(
          'backup_asset_state',
          state.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Iterable<List<T>> _chunk<T>(List<T> values, int size) sync* {
    for (var start = 0; start < values.length; start += size) {
      final end = (start + size).clamp(0, values.length);
      yield values.sublist(start, end);
    }
  }

  static int _asInt(Object? value) {
    return switch (value) {
      int exact => exact,
      num numeric => numeric.toInt(),
      _ => 0,
    };
  }

  static String? _millisToIso8601(Object? value) {
    final millis = switch (value) {
      int exact => exact,
      num numeric => numeric.toInt(),
      _ => null,
    };
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String();
  }
}
