import '../../domain/entities/backup_mode.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/entities/backup_plan_schedule_status.dart';
import 'backup_schedule_dto.dart';

class BackupPlanDto {
  final String id;
  final String name;
  final String sourcePath;
  final String targetPath;
  final BackupMode mode;
  final String? serverId;
  final String rootId;
  final BackupScheduleDto? schedule;
  final bool enabled;
  final bool includeImages;
  final bool includeVideos;
  final DateTime? lastRunAt;
  final BackupPlanScheduleStatus scheduleStatus;
  final String? scheduleErrorMessage;
  final DateTime? scheduledRunAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BackupPlanDto({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.targetPath,
    required this.mode,
    this.serverId,
    required this.rootId,
    this.schedule,
    required this.enabled,
    required this.includeImages,
    required this.includeVideos,
    this.lastRunAt,
    this.scheduleStatus = BackupPlanScheduleStatus.unscheduled,
    this.scheduleErrorMessage,
    this.scheduledRunAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BackupPlanDto.fromEntity(BackupPlanEntity entity) {
    return BackupPlanDto(
      id: entity.id,
      name: entity.name,
      sourcePath: entity.sourcePath,
      targetPath: entity.targetPath,
      mode: entity.mode,
      serverId: entity.serverId,
      rootId: entity.rootId,
      schedule: entity.schedule == null
          ? null
          : BackupScheduleDto.fromEntity(entity.schedule!),
      enabled: entity.enabled,
      includeImages: entity.includeImages,
      includeVideos: entity.includeVideos,
      lastRunAt: entity.lastRunAt,
      scheduleStatus: entity.scheduleStatus,
      scheduleErrorMessage: entity.scheduleErrorMessage,
      scheduledRunAt: entity.scheduledRunAt,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  factory BackupPlanDto.fromMap(Map<String, Object?> map) {
    return BackupPlanDto(
      id: map['id'] as String,
      name: map['name'] as String,
      sourcePath: map['source_path'] as String? ?? 'gallery://all',
      targetPath: map['target_path'] as String? ?? '/',
      mode: BackupModeWireValue.fromWireValue(map['mode'] as String? ?? ''),
      serverId: map['server_id'] as String?,
      rootId: map['root_id'] as String? ?? 'fs',
      schedule: BackupScheduleDto.fromDatabaseMap(map),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      includeImages: (map['include_images'] as int? ?? 1) == 1,
      includeVideos: (map['include_videos'] as int? ?? 1) == 1,
      lastRunAt: _parseDateTime(map['last_run_at']),
      scheduleStatus: BackupPlanScheduleStatus.fromWireValue(
        map['schedule_status'] as String?,
      ),
      scheduleErrorMessage: map['schedule_error'] as String?,
      scheduledRunAt: _parseDateTime(map['scheduled_run_at']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updated_at']) ?? DateTime.now(),
    );
  }

  BackupPlanEntity toEntity() {
    return BackupPlanEntity(
      id: id,
      name: name,
      sourcePath: sourcePath,
      targetPath: targetPath,
      mode: mode,
      serverId: serverId,
      rootId: rootId,
      schedule: schedule?.toEntity(),
      enabled: enabled,
      includeImages: includeImages,
      includeVideos: includeVideos,
      lastRunAt: lastRunAt,
      scheduleStatus: scheduleStatus,
      scheduleErrorMessage: scheduleErrorMessage,
      scheduledRunAt: scheduledRunAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'source_path': sourcePath,
      'target_path': targetPath,
      'mode': mode.wireValue,
      'server_id': serverId,
      'root_id': rootId,
      'schedule_type': schedule?.typeValue,
      'schedule_time': schedule?.timeValue,
      'schedule_days': schedule?.daysValue,
      'schedule_day_of_month': schedule?.dayOfMonth,
      'schedule_once_at': schedule?.onceAt?.toIso8601String(),
      'requires_wifi': schedule?.requiresWifiValue ?? 0,
      'requires_charging': schedule?.requiresChargingValue ?? 0,
      'include_images': includeImages ? 1 : 0,
      'include_videos': includeVideos ? 1 : 0,
      'enabled': enabled ? 1 : 0,
      'last_run_at': lastRunAt?.toIso8601String(),
      'schedule_status': scheduleStatus.wireValue,
      'schedule_error': scheduleErrorMessage,
      'scheduled_run_at': scheduledRunAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
