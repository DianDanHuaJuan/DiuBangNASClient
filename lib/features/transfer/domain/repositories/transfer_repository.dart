/// 文件输入：无参数
/// 文件职责：定义传输仓库抽象接口
/// 文件对外接口：TransferRepository
/// 文件包含：TransferRepository
import 'dart:async';

import '../../../../core/protocol/upload_contract.dart';
import '../../../../core/result/app_result.dart';
import '../entities/transfer_task_entity.dart';
import '../entities/upload_conflict_resolution.dart';

abstract class TransferRepository {
  Stream<TransferTaskEntity> get taskStream;
  Future<AppResult<List<TransferTaskEntity>>> loadTasks();
  Future<AppResult<TransferTaskEntity>> enqueueDownload({
    required String remotePath,
    required String localPath,
    String? rootId,
  });
  Future<AppResult<TransferTaskEntity>> enqueueUpload({
    required String localPath,
    required String remotePath,
    String? rootId,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    bool requiresConflictResolution = false,
    Map<String, String>? uploadHeaders,
  });
  Future<AppResult<void>> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  });
  Future<AppResult<void>> pauseTask(String taskId);
  Future<AppResult<void>> resumeTask(String taskId);
  Future<AppResult<void>> cancelTask(String taskId);
  Future<AppResult<void>> clearCompletedTasks();
}
