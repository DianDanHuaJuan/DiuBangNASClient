import '../../domain/entities/backup_run_record_entity.dart';

class BackupRunRecordDto {
  const BackupRunRecordDto({
    required this.id,
    required this.planId,
    required this.triggerType,
    required this.status,
    required this.scannedCount,
    required this.queuedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.startedAt,
    this.finishedAt,
    this.errorMessage,
  });

  factory BackupRunRecordDto.fromMap(Map<String, Object?> map) {
    return BackupRunRecordDto(
      id: map['id'] as String,
      planId: map['plan_id'] as String?,
      triggerType: map['trigger_type'] as String? ?? 'scheduled',
      status: map['status'] as String? ?? 'failed',
      scannedCount: map['scanned_count'] as int? ?? 0,
      queuedCount: map['queued_count'] as int? ?? 0,
      skippedCount: map['skipped_count'] as int? ?? 0,
      failedCount: map['failed_count'] as int? ?? 0,
      startedAt: _parseDateTime(map['started_at']) ?? DateTime.now(),
      finishedAt: _parseDateTime(map['finished_at']),
      errorMessage: map['error_message'] as String?,
    );
  }

  final String id;
  final String? planId;
  final String triggerType;
  final String status;
  final int scannedCount;
  final int queuedCount;
  final int skippedCount;
  final int failedCount;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? errorMessage;

  BackupRunRecordEntity toEntity() {
    return BackupRunRecordEntity(
      id: id,
      planId: planId,
      triggerType: triggerType,
      status: status,
      scannedCount: scannedCount,
      queuedCount: queuedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      startedAt: startedAt,
      finishedAt: finishedAt,
      errorMessage: errorMessage,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
