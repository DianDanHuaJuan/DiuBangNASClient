import '../../domain/entities/backup_mode.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/entities/backup_schedule_entity.dart';

class CreateBackupPlanParams {
  final String id;
  final String name;
  final BackupMode mode;
  final String sourcePath;
  final String targetPath;
  final String? serverId;
  final String rootId;
  final BackupScheduleEntity? schedule;
  final bool includeImages;
  final bool includeVideos;
  final bool enabled;

  const CreateBackupPlanParams({
    required this.id,
    required this.name,
    required this.mode,
    this.sourcePath = 'gallery://all',
    this.targetPath = '/',
    this.serverId,
    this.rootId = 'fs',
    this.schedule,
    this.includeImages = true,
    this.includeVideos = true,
    this.enabled = true,
  });

  BackupPlanEntity toEntity() {
    final now = DateTime.now();
    return BackupPlanEntity(
      id: id,
      name: name,
      mode: mode,
      sourcePath: sourcePath,
      targetPath: targetPath,
      serverId: serverId,
      rootId: rootId,
      schedule: schedule,
      enabled: enabled,
      includeImages: includeImages,
      includeVideos: includeVideos,
      createdAt: now,
      updatedAt: now,
    );
  }
}
