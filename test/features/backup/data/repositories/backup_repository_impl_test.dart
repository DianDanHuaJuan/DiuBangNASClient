import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/result/app_result.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/core/storage/app_database.dart';
import 'package:nasclient/features/backup/data/datasources/backup_local_data_source.dart';
import 'package:nasclient/features/backup/data/datasources/backup_remote_data_source.dart';
import 'package:nasclient/features/backup/data/models/backup_asset_state_dto.dart';
import 'package:nasclient/features/backup/data/repositories/backup_repository_impl.dart';
import 'package:nasclient/features/backup/domain/entities/backup_source_item.dart';
import 'package:nasclient/features/backup/domain/entities/backup_source_type.dart';
import 'package:nasclient/features/backup/domain/entities/backup_upload_request.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_direction.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_status.dart';
import 'package:nasclient/features/transfer/domain/entities/transfer_task_entity.dart';
import 'package:nasclient/features/transfer/domain/entities/upload_conflict_resolution.dart';
import 'package:nasclient/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:nasclient/core/protocol/upload_contract.dart';

void main() {
  group('BackupRepositoryImpl.runBackupNow', () {
    late Directory tempDir;
    late CurrentSession session;
    late _FakeTransferRepository transferRepository;
    late _FakeBackupLocalDataSource localDataSource;
    late _FakeBackupRemoteDataSource remoteDataSource;
    late BackupRepositoryImpl repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup-repo-test-');
      session = CurrentSession();
      session.set(
        serverId: 'server-1',
        serverName: 'Server',
        serverVersion: '1.0.0',
        serverStatus: 'ready',
        serverUrl: 'https://server.test',
        username: 'user',
        password: 'pass',
        protocol: 'webdav',
        rootId: 'fs',
        rootName: '共享目录',
        roots: const [
          RootInfo(
            id: 'fs',
            name: '共享目录',
            path: '/',
            type: 'local',
            writable: true,
          ),
        ],
      );
      transferRepository = _FakeTransferRepository();
      localDataSource = _FakeBackupLocalDataSource();
      remoteDataSource = _FakeBackupRemoteDataSource();
      repository = BackupRepositoryImpl(
        transferRepository: transferRepository,
        currentSession: session,
        deviceIdProvider: () async => 'android-device',
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
    });

    tearDown(() async {
      session.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'skips duplicates from preflight and enqueues only missing files',
      () async {
        final firstFile = File('${tempDir.path}\\first.jpg');
        final secondFile = File('${tempDir.path}\\second.jpg');
        await firstFile.writeAsBytes([1, 2, 3]);
        await secondFile.writeAsBytes([4, 5, 6]);

        final firstItem = BackupSourceItem(
          id: 'media:first',
          sourceType: BackupSourceType.media,
          localPath: firstFile.path,
          displayName: 'first.jpg',
          size: await firstFile.length(),
          modifiedAt: DateTime.utc(2026, 1, 1),
        );
        final secondItem = BackupSourceItem(
          id: 'media:second',
          sourceType: BackupSourceType.media,
          localPath: secondFile.path,
          displayName: 'second.jpg',
          size: await secondFile.length(),
          modifiedAt: DateTime.utc(2026, 1, 2),
        );

        remoteDataSource.onPreflight = (rootId, items) async {
          expect(rootId, 'fs');
          if (remoteDataSource.preflightCalls.length == 1) {
            expect(items, hasLength(2));
            expect(items[0].contentHash, isNull);
            expect(items[1].contentHash, isNull);
            return [
              BackupPreflightDecisionDto(
                id: items[0].id,
                action: BackupPreflightAction.skip,
                relativePath: '/already-there.jpg',
                reason: 'source_match',
              ),
              BackupPreflightDecisionDto(
                id: items[1].id,
                action: BackupPreflightAction.needHash,
                relativePath: '/',
                reason: 'hash_required',
              ),
            ];
          }
          expect(items, hasLength(1));
          expect(items.single.contentHash, isNotNull);
          return [
            BackupPreflightDecisionDto(
              id: items.single.id,
              action: BackupPreflightAction.upload,
              relativePath: '/new-file.jpg',
              reason: 'missing',
            ),
          ];
        };

        final result = await repository.runBackupNow([
          BackupUploadRequest.fromSource(firstItem),
          BackupUploadRequest.fromSource(secondItem),
        ]);

        expect(result.isSuccess, isTrue);
        final runResult = result.dataOrNull!;
        expect(runResult.scannedCount, 2);
        expect(runResult.skippedCount, 1);
        expect(runResult.queuedCount, 1);
        expect(remoteDataSource.preflightCalls, hasLength(2));
        expect(
          transferRepository.enqueuedUploads.single.remotePath,
          '/new-file.jpg',
        );

        final decodedMetadata =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(
                      base64Url.normalize(
                        transferRepository
                                .enqueuedUploads
                                .single
                                .uploadHeaders[BackupRepositoryImpl
                                .backupMetadataHeaderName] ??
                            '',
                      ),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        expect(decodedMetadata['contentHash'], isA<String>());
        expect(localDataSource.savedStates, hasLength(1));
      },
    );

    test('returns success when every file is skipped by preflight', () async {
      final file = File('${tempDir.path}\\already-backed-up.jpg');
      await file.writeAsBytes([9, 8, 7]);

      final item = BackupSourceItem(
        id: 'media:only',
        sourceType: BackupSourceType.media,
        localPath: file.path,
        displayName: 'already-backed-up.jpg',
        size: await file.length(),
        modifiedAt: DateTime.utc(2026, 2, 1),
      );

      remoteDataSource.onPreflight = (rootId, items) async {
        expect(items.single.contentHash, isNull);
        return [
          BackupPreflightDecisionDto(
            id: items.single.id,
            action: BackupPreflightAction.skip,
            relativePath: '/already-backed-up.jpg',
            reason: 'source_match',
          ),
        ];
      };

      final result = await repository.runBackupNow([
        BackupUploadRequest.fromSource(item),
      ]);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.queuedCount, 0);
      expect(result.dataOrNull!.skippedCount, 1);
      expect(remoteDataSource.preflightCalls, hasLength(1));
      expect(transferRepository.enqueuedUploads, isEmpty);
    });

    test(
      'creates a manual backup run and keeps it open while queued uploads are pending',
      () async {
        final file = File('${tempDir.path}\\queued.jpg');
        await file.writeAsBytes([1, 2, 3, 4]);

        final item = BackupSourceItem(
          id: 'media:queued',
          sourceType: BackupSourceType.media,
          localPath: file.path,
          displayName: 'queued.jpg',
          size: await file.length(),
          modifiedAt: DateTime.utc(2026, 2, 2),
        );

        remoteDataSource.onPreflight = (rootId, items) async {
          if (items.single.contentHash == null) {
            return [
              BackupPreflightDecisionDto(
                id: items.single.id,
                action: BackupPreflightAction.needHash,
                relativePath: '/',
                reason: 'hash_required',
              ),
            ];
          }
          return [
            BackupPreflightDecisionDto(
              id: items.single.id,
              action: BackupPreflightAction.upload,
              relativePath: '/queued.jpg',
              reason: 'missing',
            ),
          ];
        };

        final result = await repository.runBackupNow([
          BackupUploadRequest.fromSource(item),
        ]);

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull!.runId, isNotEmpty);
        expect(localDataSource.insertedRuns, hasLength(1));
        expect(localDataSource.insertedRuns.single.status, 'running');
        expect(localDataSource.completedRuns, isEmpty);
      },
    );
  });
}

class _FakeTransferRepository implements TransferRepository {
  final List<_CapturedUpload> enqueuedUploads = <_CapturedUpload>[];

  @override
  Stream<TransferTaskEntity> get taskStream => const Stream.empty();

  @override
  Future<AppResult<void>> cancelTask(String taskId) async =>
      const Success(null);

  @override
  Future<AppResult<void>> clearCompletedTasks() async => const Success(null);

  @override
  Future<AppResult<TransferTaskEntity>> enqueueDownload({
    required String remotePath,
    required String localPath,
    String? rootId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<AppResult<TransferTaskEntity>> enqueueUpload({
    required String localPath,
    required String remotePath,
    String? rootId,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    bool requiresConflictResolution = false,
    Map<String, String>? uploadHeaders,
  }) async {
    enqueuedUploads.add(
      _CapturedUpload(
        localPath: localPath,
        remotePath: remotePath,
        uploadHeaders: uploadHeaders ?? const <String, String>{},
      ),
    );
    return Success(
      TransferTaskEntity(
        id: 'task-${enqueuedUploads.length}',
        rootId: rootId ?? 'fs',
        localPath: localPath,
        remotePath: remotePath,
        fileName: remotePath.split('/').last,
        totalBytes: 0,
        transferredBytes: 0,
        direction: TransferDirection.upload,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<AppResult<List<TransferTaskEntity>>> loadTasks() async =>
      const Success(<TransferTaskEntity>[]);

  @override
  Future<AppResult<void>> pauseTask(String taskId) async => const Success(null);

  @override
  Future<AppResult<void>> resolveUploadConflict({
    required String taskId,
    required UploadConflictResolution resolution,
  }) async => const Success(null);

  @override
  Future<AppResult<void>> resumeTask(String taskId) async =>
      const Success(null);
}

class _CapturedUpload {
  const _CapturedUpload({
    required this.localPath,
    required this.remotePath,
    required this.uploadHeaders,
  });

  final String localPath;
  final String remotePath;
  final Map<String, String> uploadHeaders;
}

class _FakeBackupLocalDataSource extends BackupLocalDataSource {
  _FakeBackupLocalDataSource() : super(appDatabase: AppDatabase());

  final List<BackupAssetStateDto> savedStates = <BackupAssetStateDto>[];
  final List<_CapturedRunInsert> insertedRuns = <_CapturedRunInsert>[];
  final List<_CapturedRunCompletion> completedRuns = <_CapturedRunCompletion>[];

  @override
  Future<Map<String, BackupAssetStateDto>> loadAssetStates({
    required String serverId,
    required String rootId,
    required Iterable<String> sourceFingerprints,
  }) async {
    return const <String, BackupAssetStateDto>{};
  }

  @override
  Future<void> upsertAssetStates(List<BackupAssetStateDto> states) async {
    savedStates.addAll(states);
  }

  @override
  Future<void> insertRun({
    required String runId,
    String? planId,
    required String triggerType,
    required String status,
    required DateTime startedAt,
  }) async {
    insertedRuns.add(
      _CapturedRunInsert(
        runId: runId,
        planId: planId,
        triggerType: triggerType,
        status: status,
        startedAt: startedAt,
      ),
    );
  }

  @override
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
    completedRuns.add(
      _CapturedRunCompletion(
        runId: runId,
        status: status,
        scannedCount: scannedCount,
        queuedCount: queuedCount,
        skippedCount: skippedCount,
        failedCount: failedCount,
        finishedAt: finishedAt,
        errorMessage: errorMessage,
      ),
    );
  }
}

class _CapturedRunInsert {
  const _CapturedRunInsert({
    required this.runId,
    required this.planId,
    required this.triggerType,
    required this.status,
    required this.startedAt,
  });

  final String runId;
  final String? planId;
  final String triggerType;
  final String status;
  final DateTime startedAt;
}

class _CapturedRunCompletion {
  const _CapturedRunCompletion({
    required this.runId,
    required this.status,
    required this.scannedCount,
    required this.queuedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.finishedAt,
    this.errorMessage,
  });

  final String runId;
  final String status;
  final int scannedCount;
  final int queuedCount;
  final int skippedCount;
  final int failedCount;
  final DateTime finishedAt;
  final String? errorMessage;
}

class _FakeBackupRemoteDataSource extends BackupRemoteDataSource {
  _FakeBackupRemoteDataSource() : super(apiClient: _FakeNasApiClient());

  final List<List<BackupPreflightItemDto>> preflightCalls =
      <List<BackupPreflightItemDto>>[];

  Future<List<BackupPreflightDecisionDto>> Function(
    String rootId,
    List<BackupPreflightItemDto> items,
  )?
  onPreflight;

  @override
  Future<List<BackupPreflightDecisionDto>> preflight({
    required String rootId,
    required List<BackupPreflightItemDto> items,
  }) async {
    preflightCalls.add(List<BackupPreflightItemDto>.from(items));
    return onPreflight?.call(rootId, items) ??
        const <BackupPreflightDecisionDto>[];
  }
}

class _FakeNasApiClient extends NasApiClient {
  _FakeNasApiClient()
    : super(
        baseUrl: 'http://localhost:8080',
        session: CurrentSession(),
        dio: Dio(),
      );
}
