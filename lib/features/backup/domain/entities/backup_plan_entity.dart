import 'backup_mode.dart';
import 'backup_schedule_entity.dart';
import 'backup_plan_schedule_status.dart';

class BackupPlanEntity {
  final String id;
  final String name;
  final BackupMode mode;
  final String sourcePath;
  final String targetPath;
  final String? serverId;
  final String rootId;
  final BackupScheduleEntity? schedule;
  final bool enabled;
  final bool includeImages;
  final bool includeVideos;
  final DateTime? lastRunAt;
  final BackupPlanScheduleStatus scheduleStatus;
  final String? scheduleErrorMessage;
  final DateTime? scheduledRunAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BackupPlanEntity({
    required this.id,
    required this.name,
    required this.mode,
    required this.sourcePath,
    required this.targetPath,
    this.serverId,
    this.rootId = 'fs',
    this.schedule,
    this.enabled = true,
    this.includeImages = true,
    this.includeVideos = true,
    this.lastRunAt,
    this.scheduleStatus = BackupPlanScheduleStatus.unscheduled,
    this.scheduleErrorMessage,
    this.scheduledRunAt,
    required this.createdAt,
    required this.updatedAt,
  });
}
