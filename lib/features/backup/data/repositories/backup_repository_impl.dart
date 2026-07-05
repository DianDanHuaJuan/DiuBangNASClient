/// 文件输入：当前会话、传输仓库、待备份资源列表
/// 文件职责：实现立即备份编排，解析服务端固定写入根目录并批量创建上传任务
/// 文件对外接口：BackupRepositoryImpl
/// 文件包含：BackupRepositoryImpl
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import '../../../../core/auth/root_info.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/session/current_session.dart';
import '../../../transfer/domain/repositories/transfer_repository.dart';
import '../datasources/backup_local_data_source.dart';
import '../datasources/backup_remote_data_source.dart';
import '../models/backup_asset_state_dto.dart';
import '../models/backup_plan_dto.dart';
import '../../domain/entities/backup_preparation_progress.dart';
import '../../domain/entities/backup_plan_entity.dart';
import '../../domain/entities/backup_run_record_entity.dart';
import '../../domain/entities/backup_run_result.dart';
import '../../domain/entities/backup_source_item.dart';
import '../../domain/entities/backup_upload_request.dart';
import '../../domain/repositories/backup_repository.dart';
import '../../domain/backup_run_cancellation.dart';

class BackupRepositoryImpl implements BackupRepository {
  static const String backupMetadataHeaderName = 'X-NAS-Backup-Metadata';
  static const int _preflightBatchSize = 100;

  final TransferRepository _transferRepository;
  final CurrentSession _currentSession;
  final Future<String> Function() _deviceIdProvider;
  final BackupLocalDataSource _localDataSource;
  final BackupRemoteDataSource _remoteDataSource;

  BackupRepositoryImpl({
    required TransferRepository transferRepository,
    required CurrentSession currentSession,
    required Future<String> Function() deviceIdProvider,
    required BackupLocalDataSource localDataSource,
    required BackupRemoteDataSource remoteDataSource,
  }) : _transferRepository = transferRepository,
       _currentSession = currentSession,
       _deviceIdProvider = deviceIdProvider,
       _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource;

  @override
  Future<AppResult<List<BackupPlanEntity>>> loadPlans() async {
    try {
      final plans = await _localDataSource.loadPlans();
      return Success(
        plans.map((plan) => plan.toEntity()).toList(growable: false),
      );
    } catch (error) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_LOAD_PLANS_FAILED',
          message: '加载备份计划失败: $error',
        ),
      );
    }
  }

  @override
  Future<AppResult<List<BackupRunRecordEntity>>> loadRecentRuns({
    String? planId,
    int limit = 10,
    bool onlyAbnormal = false,
  }) async {
    try {
      final runs = await _localDataSource.loadRecentRuns(
        planId: planId,
        limit: limit,
        onlyAbnormal: onlyAbnormal,
      );
      return Success(runs.map((run) => run.toEntity()).toList(growable: false));
    } catch (error) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_LOAD_RUNS_FAILED',
          message: '加载备份运行记录失败: $error',
        ),
      );
    }
  }

  @override
  Future<AppResult<BackupPlanEntity>> createPlan(BackupPlanEntity plan) async {
    try {
      await _localDataSource.savePlan(BackupPlanDto.fromEntity(plan));
      return Success(plan);
    } catch (error) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_CREATE_PLAN_FAILED',
          message: '保存备份计划失败: $error',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> togglePlan(String planId, bool enabled) async {
    try {
      await _localDataSource.updatePlanEnabled(planId, enabled);
      return const Success(null);
    } catch (error) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_TOGGLE_PLAN_FAILED',
          message: '更新备份计划状态失败: $error',
        ),
      );
    }
  }

  @override
  Future<AppResult<BackupRunResult>> runBackupNow(
    List<BackupUploadRequest> requests, {
    void Function(BackupPreparationProgress progress)? onProgress,
    BackupRunCancellation? cancellation,
  }) async {
    if (requests.isEmpty) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_ITEMS_EMPTY',
          message: '请先选择要备份的资源',
        ),
      );
    }

    final backupRoot = _resolveBackupRoot();
    if (backupRoot == null) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_ROOT_UNAVAILABLE',
          message: '当前服务器没有可写入的备份目录',
        ),
      );
    }

    final startedAt = DateTime.now();
    final runId = 'manual-${startedAt.microsecondsSinceEpoch}';
    await _localDataSource.insertRun(
      runId: runId,
      planId: null,
      triggerType: 'manual',
      status: 'running',
      startedAt: startedAt,
    );

    try {
      _ensureNotCancelled(cancellation);
      final queuedTaskIds = <String>[];
      final failedItems = <BackupSourceItem>[];
      final failureMessages = <String>[];
      final deviceId = await _deviceIdProvider();
      final serverId =
          (_currentSession.serverId ?? _currentSession.serverUrl ?? 'unknown')
              .trim();
      final initialCandidates = await _buildInitialCandidates(
        requests,
        deviceId: deviceId,
        failedItems: failedItems,
        failureMessages: failureMessages,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      _ensureNotCancelled(cancellation);
      final cachedStates = await _localDataSource.loadAssetStates(
        serverId: serverId,
        rootId: backupRoot.id,
        sourceFingerprints: initialCandidates.map(
          (item) => item.sourceFingerprint,
        ),
      );

      var skippedCount = 0;
      var hashedCount = 0;
      var hashTargetCount = 0;
      var preflightProcessedCount = 0;
      var queueProcessedCount = 0;
      final assetStateUpdates = <BackupAssetStateDto>[];
      for (final batch in _chunk(initialCandidates, _preflightBatchSize)) {
        _ensureNotCancelled(cancellation);
        try {
          final decisionById = <String, BackupPreflightDecisionDto>{};
          final preparedById = <String, _PreparedBackupItem>{};
          _reportProgress(
            onProgress,
            phase: BackupPreparationPhase.preflighting,
            processedCount: preflightProcessedCount,
            totalCount: initialCandidates.length,
            detail:
                '正在把第 ${preflightProcessedCount + 1}-${(preflightProcessedCount + batch.length).clamp(0, initialCandidates.length)} 项发给服务端预检',
          );
          final initialDecisions = await _remoteDataSource.preflight(
            rootId: backupRoot.id,
            items: batch
                .map(
                  (item) => BackupPreflightItemDto(
                    id: item.sourceFingerprint,
                    sourceFingerprint: item.sourceFingerprint,
                    extension: item.extension,
                    sizeBytes: item.sizeBytes,
                    modifiedMs: item.modifiedMs,
                    mimeType: item.item.mimeType,
                  ),
                )
                .toList(growable: false),
          );
          for (final decision in initialDecisions) {
            decisionById[decision.id] = decision;
          }

          final itemsNeedingHash = <_PreparedBackupItem>[];
          for (final candidate in batch) {
            final decision = decisionById[candidate.sourceFingerprint];
            if (decision == null ||
                decision.action != BackupPreflightAction.needHash) {
              continue;
            }
            final cachedState = cachedStates[candidate.sourceFingerprint];
            final contentHash =
                cachedState?.contentHash ??
                await _computeContentHash(candidate.file);
            if (cachedState?.contentHash == null) {
              hashTargetCount += 1;
              hashedCount += 1;
              _reportProgress(
                onProgress,
                phase: BackupPreparationPhase.hashingFiles,
                processedCount: hashedCount,
                totalCount: hashTargetCount,
                detail: '已生成 $hashedCount / $hashTargetCount 个文件指纹',
              );
            }
            final prepared = _PreparedBackupItem(
              request: candidate.request,
              item: candidate.item,
              file: candidate.file,
              sourceFingerprint: candidate.sourceFingerprint,
              sizeBytes: candidate.sizeBytes,
              modifiedMs: candidate.modifiedMs,
              extension: candidate.extension,
              contentHash: contentHash,
            );
            itemsNeedingHash.add(prepared);
            preparedById[candidate.sourceFingerprint] = prepared;
          }

          if (itemsNeedingHash.isNotEmpty) {
            final hashedDecisions = await _remoteDataSource.preflight(
              rootId: backupRoot.id,
              items: itemsNeedingHash
                  .map(
                    (item) => BackupPreflightItemDto(
                      id: item.sourceFingerprint,
                      sourceFingerprint: item.sourceFingerprint,
                      contentHash: item.contentHash,
                      extension: item.extension,
                      sizeBytes: item.sizeBytes,
                      modifiedMs: item.modifiedMs,
                      mimeType: item.item.mimeType,
                    ),
                  )
                  .toList(growable: false),
            );
            for (final decision in hashedDecisions) {
              decisionById[decision.id] = decision;
            }
          }

          preflightProcessedCount += batch.length;
          _reportProgress(
            onProgress,
            phase: BackupPreparationPhase.preflighting,
            processedCount: preflightProcessedCount,
            totalCount: initialCandidates.length,
            detail:
                '服务端已完成 $preflightProcessedCount / ${initialCandidates.length} 项比对',
          );
          for (final candidate in batch) {
            _ensureNotCancelled(cancellation);
            final decision = decisionById[candidate.sourceFingerprint];
            if (decision == null) {
              failedItems.add(candidate.item);
              failureMessages.add('${candidate.item.displayName}: 服务端预检返回缺失');
              continue;
            }

            final cachedState = cachedStates[candidate.sourceFingerprint];
            var contentHash =
                preparedById[candidate.sourceFingerprint]?.contentHash ??
                cachedState?.contentHash;
            if (contentHash == null &&
                decision.action == BackupPreflightAction.upload) {
              contentHash = await _computeContentHash(candidate.file);
            }

            if (contentHash != null &&
                decision.action != BackupPreflightAction.needHash) {
              assetStateUpdates.add(
                BackupAssetStateDto(
                  serverId: serverId,
                  rootId: backupRoot.id,
                  sourceFingerprint: candidate.sourceFingerprint,
                  sourceId: candidate.item.id,
                  displayName: candidate.item.displayName,
                  localPath: candidate.item.localPath,
                  sizeBytes: candidate.sizeBytes,
                  modifiedMs: candidate.modifiedMs,
                  mimeType: candidate.item.mimeType,
                  contentHash: contentHash,
                  remotePath: decision.relativePath,
                  updatedAt: DateTime.now(),
                ),
              );
            }

            if (decision.action == BackupPreflightAction.skip) {
              skippedCount += 1;
              queueProcessedCount += 1;
              _reportProgress(
                onProgress,
                phase: BackupPreparationPhase.queueingUploads,
                processedCount: queueProcessedCount,
                totalCount: initialCandidates.length,
                detail: '已自动跳过 $skippedCount 个已备份/重复文件',
              );
              continue;
            }
            if (decision.action == BackupPreflightAction.needHash) {
              failedItems.add(candidate.item);
              failureMessages.add(
                '${candidate.item.displayName}: 服务端未返回最终预检结果',
              );
              continue;
            }
            if (contentHash == null) {
              failedItems.add(candidate.item);
              failureMessages.add('${candidate.item.displayName}: 无法生成备份指纹');
              continue;
            }

            final result = await _transferRepository.enqueueUpload(
              localPath: candidate.item.localPath,
              remotePath: decision.relativePath,
              rootId: backupRoot.id,
              conflictPolicy: candidate.request.conflictPolicy,
              requiresConflictResolution:
                  candidate.request.requiresConflictResolution,
              uploadHeaders: {
                backupMetadataHeaderName: _buildBackupMetadataHeader(
                  sourceFingerprint: candidate.sourceFingerprint,
                  contentHash: contentHash,
                  deviceId: deviceId,
                  sourceId: candidate.item.id,
                  sizeBytes: candidate.sizeBytes,
                  modifiedMs: candidate.modifiedMs,
                ),
              },
            );
            result.when(
              success: (task) {
                queuedTaskIds.add(task.id);
              },
              failure: (failure) {
                failedItems.add(candidate.item);
                failureMessages.add(
                  '${candidate.item.displayName}: ${failure.message}',
                );
              },
            );
            queueProcessedCount += 1;
            _reportProgress(
              onProgress,
              phase: BackupPreparationPhase.queueingUploads,
              processedCount: queueProcessedCount,
              totalCount: initialCandidates.length,
              detail: '已创建 ${queuedTaskIds.length} 个上传任务，自动跳过 $skippedCount 个',
            );
          }
        } catch (error) {
          for (final prepared in batch) {
            failedItems.add(prepared.item);
            failureMessages.add('${prepared.item.displayName}: 预检失败: $error');
          }
        }
      }

      await _localDataSource.upsertAssetStates(assetStateUpdates);

      if (queuedTaskIds.isEmpty && skippedCount == 0) {
        await _localDataSource.completeRun(
          runId: runId,
          status: failedItems.isNotEmpty ? 'failed' : 'failed',
          scannedCount: requests.length,
          queuedCount: 0,
          skippedCount: 0,
          failedCount: failedItems.length,
          finishedAt: DateTime.now(),
          errorMessage: failureMessages.isNotEmpty
              ? failureMessages.first
              : '未能创建备份任务',
        );
        return Failure(
          AppFailure.fromException(
            code: 'BACKUP_QUEUE_FAILED',
            message: failureMessages.isNotEmpty
                ? failureMessages.first
                : '未能创建备份任务',
            details: {'failedCount': failedItems.length},
          ),
        );
      }

      if (queuedTaskIds.isEmpty) {
        final failedCount = failedItems.length;
        final status = failedCount > 0 ? 'partial_failed' : 'completed';
        await _localDataSource.completeRun(
          runId: runId,
          status: status,
          scannedCount: requests.length,
          queuedCount: 0,
          skippedCount: skippedCount,
          failedCount: failedCount,
          finishedAt: DateTime.now(),
          errorMessage: failureMessages.isNotEmpty
              ? failureMessages.first
              : null,
        );
      }

      return Success(
        BackupRunResult(
          runId: runId,
          rootId: backupRoot.id,
          rootName: backupRoot.name,
          scannedCount: requests.length,
          skippedCount: skippedCount,
          queuedTaskIds: List.unmodifiable(queuedTaskIds),
          failedItems: List.unmodifiable(failedItems),
          failureMessages: List.unmodifiable(failureMessages),
        ),
      );
    } on BackupRunCancelledException catch (error) {
      await _localDataSource.completeRun(
        runId: runId,
        status: 'stopped',
        scannedCount: requests.length,
        queuedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        finishedAt: DateTime.now(),
        errorMessage: error.message,
      );
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_RUN_CANCELLED',
          message: error.message,
        ),
      );
    } catch (error) {
      await _localDataSource.completeRun(
        runId: runId,
        status: 'failed',
        scannedCount: requests.length,
        queuedCount: 0,
        skippedCount: 0,
        failedCount: requests.length,
        finishedAt: DateTime.now(),
        errorMessage: '$error',
      );
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_RUN_FAILED',
          message: '创建备份任务失败: $error',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> completeRun({
    required String runId,
    required String status,
    required int scannedCount,
    required int queuedCount,
    required int skippedCount,
    required int failedCount,
    String? errorMessage,
  }) async {
    try {
      await _localDataSource.completeRun(
        runId: runId,
        status: status,
        scannedCount: scannedCount,
        queuedCount: queuedCount,
        skippedCount: skippedCount,
        failedCount: failedCount,
        finishedAt: DateTime.now(),
        errorMessage: errorMessage,
      );
      return const Success(null);
    } catch (error) {
      return Failure(
        AppFailure.fromException(
          code: 'BACKUP_COMPLETE_RUN_FAILED',
          message: '更新备份记录失败: $error',
        ),
      );
    }
  }

  RootInfo? _resolveBackupRoot() {
    final fsRoot = _currentSession.getRootById('fs');
    if (fsRoot != null && fsRoot.writable) {
      return fsRoot;
    }

    final writableRoots = _currentSession.writableRoots;
    if (writableRoots.isEmpty) {
      return null;
    }
    return writableRoots.first;
  }

  Future<List<_InitialPreparedBackupItem>> _buildInitialCandidates(
    List<BackupUploadRequest> requests, {
    required String deviceId,
    required List<BackupSourceItem> failedItems,
    required List<String> failureMessages,
    void Function(BackupPreparationProgress progress)? onProgress,
    BackupRunCancellation? cancellation,
  }) async {
    final initialCandidates = <_InitialPreparedBackupItem>[];
    var inspectedCount = 0;

    for (final request in requests) {
      _ensureNotCancelled(cancellation);
      final item = request.item;
      final file = File(item.localPath);
      if (!await file.exists()) {
        failedItems.add(item);
        failureMessages.add('${item.displayName}: 本地文件不存在');
        continue;
      }

      FileStat? stat;
      final needsStat = item.size <= 0 || item.modifiedAt == null;
      if (needsStat) {
        stat = await file.stat();
      }
      final sizeBytes = item.size > 0 ? item.size : (stat?.size ?? 0);
      final modifiedAt = item.modifiedAt ?? stat?.modified ?? DateTime.now();
      final modifiedMs = modifiedAt.millisecondsSinceEpoch;
      final sourceFingerprint = _buildSourceFingerprint(
        deviceId: deviceId,
        sourceId: item.id,
        sizeBytes: sizeBytes,
        modifiedMs: modifiedMs,
      );

      initialCandidates.add(
        _InitialPreparedBackupItem(
          request: request,
          item: item,
          file: file,
          sourceFingerprint: sourceFingerprint,
          sizeBytes: sizeBytes,
          modifiedMs: modifiedMs,
          extension: _resolveExtension(item),
        ),
      );
      inspectedCount += 1;
      _reportProgress(
        onProgress,
        phase: BackupPreparationPhase.inspectingFiles,
        processedCount: inspectedCount,
        totalCount: requests.length,
        detail: '已检查 $inspectedCount / ${requests.length} 个本地文件',
      );
    }
    return initialCandidates;
  }

  String _resolveExtension(BackupSourceItem item) {
    final displayExtension = p.extension(item.displayName).toLowerCase();
    if (displayExtension.isNotEmpty) {
      return displayExtension;
    }
    return p.extension(item.localPath).toLowerCase();
  }

  String _buildSourceFingerprint({
    required String deviceId,
    required String sourceId,
    required int sizeBytes,
    required int modifiedMs,
  }) {
    return '$deviceId|$sourceId|$sizeBytes|$modifiedMs';
  }

  Future<String> _computeContentHash(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _buildBackupMetadataHeader({
    required String sourceFingerprint,
    required String contentHash,
    required String deviceId,
    required String sourceId,
    required int sizeBytes,
    required int modifiedMs,
  }) {
    return base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'sourceFingerprint': sourceFingerprint,
          'contentHash': contentHash,
          'deviceId': deviceId,
          'sourceId': sourceId,
          'sizeBytes': sizeBytes,
          'modifiedMs': modifiedMs,
        }),
      ),
    );
  }

  Iterable<List<T>> _chunk<T>(List<T> values, int size) sync* {
    for (var start = 0; start < values.length; start += size) {
      final end = (start + size).clamp(0, values.length);
      yield values.sublist(start, end);
    }
  }

  void _ensureNotCancelled(BackupRunCancellation? cancellation) {
    if (cancellation?.isCancelled ?? false) {
      throw const BackupRunCancelledException();
    }
  }

  void _reportProgress(
    void Function(BackupPreparationProgress progress)? onProgress, {
    required BackupPreparationPhase phase,
    required int processedCount,
    required int totalCount,
    String? detail,
  }) {
    if (onProgress == null) {
      return;
    }
    final safeProcessed = processedCount.clamp(0, totalCount);
    if (totalCount > 0 &&
        safeProcessed != totalCount &&
        safeProcessed != 0 &&
        safeProcessed % 25 != 0) {
      return;
    }
    onProgress(
      BackupPreparationProgress(
        phase: phase,
        processedCount: safeProcessed,
        totalCount: totalCount,
        detail: detail,
      ),
    );
  }
}

class _InitialPreparedBackupItem {
  const _InitialPreparedBackupItem({
    required this.request,
    required this.item,
    required this.file,
    required this.sourceFingerprint,
    required this.sizeBytes,
    required this.modifiedMs,
    required this.extension,
  });

  final BackupUploadRequest request;
  final BackupSourceItem item;
  final File file;
  final String sourceFingerprint;
  final int sizeBytes;
  final int modifiedMs;
  final String extension;
}

class _PreparedBackupItem extends _InitialPreparedBackupItem {
  const _PreparedBackupItem({
    required super.request,
    required super.item,
    required super.file,
    required super.sourceFingerprint,
    required super.sizeBytes,
    required super.modifiedMs,
    required super.extension,
    required this.contentHash,
  });

  final String contentHash;
}
