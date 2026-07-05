class BackupRunRecordEntity {
  const BackupRunRecordEntity({
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

  bool get isAbnormal => switch (status) {
    'completed' || 'running' || 'retrying' => false,
    _ => true,
  };
}
