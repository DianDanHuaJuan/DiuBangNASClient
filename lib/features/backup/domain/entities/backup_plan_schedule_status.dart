enum BackupPlanScheduleStatus {
  unscheduled,
  scheduled,
  failed;

  String get wireValue => switch (this) {
    BackupPlanScheduleStatus.unscheduled => 'unscheduled',
    BackupPlanScheduleStatus.scheduled => 'scheduled',
    BackupPlanScheduleStatus.failed => 'failed',
  };

  static BackupPlanScheduleStatus fromWireValue(String? value) {
    return switch (value) {
      'scheduled' => BackupPlanScheduleStatus.scheduled,
      'failed' => BackupPlanScheduleStatus.failed,
      _ => BackupPlanScheduleStatus.unscheduled,
    };
  }
}
