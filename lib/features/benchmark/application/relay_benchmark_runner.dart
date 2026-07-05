import 'dart:developer' as developer;
import 'dart:io';

import '../../../core/device/device_file_service.dart';
import '../../../core/device/media_storage_service.dart';
import '../../../core/network/dio_path_download_service.dart';
import '../../../core/runtime/runtime_build_info.dart';
import '../../../core/session/current_session.dart';
import '../../relay/data/datasources/relay_remote_data_source.dart';
import '../../relay/data/datasources/relay_webdav_transport_client.dart';
import '../../relay/domain/entities/relay_transfer_entity.dart';
import '../data/benchmark_file_generator.dart';
import '../domain/benchmark_models.dart';
import 'direct_benchmark_runner.dart';

class RelayBenchmarkRunner {
  RelayBenchmarkRunner({
    required RelayRemoteDataSource relayRemoteDataSource,
    required RelayWebdavTransportClient transportClient,
    required BenchmarkFileGenerator fileGenerator,
    required DeviceFileService deviceFileService,
    required MediaStorageService mediaStorageService,
    required CurrentSession currentSession,
  }) : _relayRemoteDataSource = relayRemoteDataSource,
       _transportClient = transportClient,
       _fileGenerator = fileGenerator,
       _deviceFileService = deviceFileService,
       _mediaStorageService = mediaStorageService,
       _currentSession = currentSession;

  static const Duration _historyPollInterval = Duration(milliseconds: 350);
  static const Duration _historyPollTimeout = Duration(seconds: 20);

  final RelayRemoteDataSource _relayRemoteDataSource;
  final RelayWebdavTransportClient _transportClient;
  final BenchmarkFileGenerator _fileGenerator;
  final DeviceFileService _deviceFileService;
  final MediaStorageService _mediaStorageService;
  final CurrentSession _currentSession;

  Future<BenchmarkRunResult> run({
    required BenchmarkExecutionOptions options,
    BenchmarkProgressCallback? onProgress,
    BenchmarkLogCallback? onLog,
  }) async {
    return switch (options.mode) {
      BenchmarkTransferMode.upload => _runUpload(
        options: options,
        onProgress: onProgress,
        onLog: onLog,
      ),
      BenchmarkTransferMode.download => _runDownload(
        options: options,
        onProgress: onProgress,
        onLog: onLog,
      ),
    };
  }

  Future<BenchmarkRunResult> _runUpload({
    required BenchmarkExecutionOptions options,
    BenchmarkProgressCallback? onProgress,
    BenchmarkLogCallback? onLog,
  }) async {
    final peerClientId = _requireRelayPeerClientId(options.relayPeerClientId);
    final runStopwatch = Stopwatch()..start();
    final generatedFile = await _fileGenerator.generate(
      fileSizeBytes: options.fileSizeBytes,
      fileName: 'relay-benchmark-${DateTime.now().millisecondsSinceEpoch}.bin',
    );
    onLog?.call(
      'Generated relay upload payload: ${generatedFile.fileSizeBytes} bytes',
    );

    final createTransferStopwatch = Stopwatch()..start();
    final createdTransfer = await _relayRemoteDataSource.createTransfer(
      targetClientIds: <String>[peerClientId],
      fileName: generatedFile.fileName,
      fileSize: generatedFile.fileSizeBytes,
    );
    createTransferStopwatch.stop();
    onLog?.call('Relay transfer created: ${createdTransfer.transferId}');

    var progressCallbackCount = 0;
    final uploadStopwatch = Stopwatch()..start();
    var uploadedTransfer = await _transportClient.uploadFile(
      relayPath: _requireUploadPath(createdTransfer),
      localPath: generatedFile.filePath,
      onSendProgress: (sent, total) {
        progressCallbackCount += 1;
        if (total > 0) {
          onProgress?.call((sent / total).clamp(0.0, 1.0));
        }
      },
    );
    uploadStopwatch.stop();
    onProgress?.call(1);

    var waitUntilReadyMs = 0;
    if (uploadedTransfer.readyAt == null &&
        uploadedTransfer.status != RelayTransferStatus.ready &&
        uploadedTransfer.status != RelayTransferStatus.completed) {
      onLog?.call('Waiting for relay transfer to become ready...');
      final waitStopwatch = Stopwatch()..start();
      uploadedTransfer = await _waitForTransfer(
        transferId: uploadedTransfer.transferId,
        predicate: (transfer) =>
            transfer.readyAt != null ||
            transfer.status == RelayTransferStatus.ready ||
            transfer.status == RelayTransferStatus.completed,
      );
      waitStopwatch.stop();
      waitUntilReadyMs = waitStopwatch.elapsedMilliseconds;
    }

    runStopwatch.stop();
    if (!options.keepTemporaryFile) {
      await _deleteIfExists(generatedFile.filePath);
    }

    final rawResult = <String, dynamic>{
      'transportType': BenchmarkTransportType.relay.name,
      'mode': options.mode.name,
      'relayBenchmark': <String, dynamic>{
        'role': BenchmarkRelayRole.sender.name,
        'transferId': uploadedTransfer.transferId,
        'peerClientId': peerClientId,
        'currentClientId': _currentSession.clientId,
        'clientBuild': RuntimeBuildInfo.toJson(),
        'serverVersion': _currentSession.serverVersion,
        'keepTemporaryFile': options.keepTemporaryFile,
        'temporaryFilePath': options.keepTemporaryFile
            ? generatedFile.filePath
            : null,
        'phaseMetrics': <String, dynamic>{
          'fileGenerationMs': generatedFile.generationMs,
          'createTransferMs': createTransferStopwatch.elapsedMilliseconds,
          'uploadRequestMs': uploadStopwatch.elapsedMilliseconds,
          'waitUntilReadyMs': waitUntilReadyMs,
          'uploadToReadyMs':
              uploadStopwatch.elapsedMilliseconds + waitUntilReadyMs,
          'totalMs': runStopwatch.elapsedMilliseconds,
          'serverCreateToReadyMs': _differenceMs(
            uploadedTransfer.createdAt,
            uploadedTransfer.readyAt,
          ),
        },
        'progressCallbackCount': progressCallbackCount,
        'transfer': _relayTransferToJson(uploadedTransfer),
      },
    };

    final result = BenchmarkRunResult(
      options: options,
      rawResult: rawResult,
      temporaryFilePath: options.keepTemporaryFile
          ? generatedFile.filePath
          : null,
    );
    developer.log(result.prettyJson, name: 'benchmark');
    return result;
  }

  Future<BenchmarkRunResult> _runDownload({
    required BenchmarkExecutionOptions options,
    BenchmarkProgressCallback? onProgress,
    BenchmarkLogCallback? onLog,
  }) async {
    final runStopwatch = Stopwatch()..start();
    final selectionStopwatch = Stopwatch()..start();
    final selectedTransfer = await _resolveDownloadTransfer(options);
    selectionStopwatch.stop();
    onLog?.call('Selected relay transfer: ${selectedTransfer.transferId}');

    final tempPath = await _fileGenerator.createTemporaryPath(
      fileName:
          '${selectedTransfer.transferId}_${selectedTransfer.fileName.trim()}',
    );
    final downloadStrategy = _buildDownloadStrategy(options);
    var progressCallbackCount = 0;
    final networkStopwatch = Stopwatch()..start();
    final downloadResult = await _transportClient.downloadToPath(
      relayPath: _requireDownloadPath(selectedTransfer),
      savePath: tempPath,
      expectedSize: selectedTransfer.fileSize,
      supportsRange:
          selectedTransfer.transport?.download.supportsRange ?? false,
      strategy: downloadStrategy,
      onReceiveProgress: (received, total) {
        progressCallbackCount += 1;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      },
    );
    final usedConcurrentRanges = downloadResult.usedConcurrentRanges;
    networkStopwatch.stop();
    onProgress?.call(1);

    RelayTransferEntity? finalizedTransfer;
    var acknowledgeMs = 0;
    if (usedConcurrentRanges) {
      onLog?.call(
        'Downloading used concurrent ranges; acknowledging completion',
      );
      final acknowledgeStopwatch = Stopwatch()..start();
      finalizedTransfer = await _relayRemoteDataSource
          .acknowledgeDownloadCompleted(
            transferId: selectedTransfer.transferId,
          );
      acknowledgeStopwatch.stop();
      acknowledgeMs = acknowledgeStopwatch.elapsedMilliseconds;
    }

    var saveToPublicStorageMs = 0;
    var usedMemorySave = false;
    String? publicUri;
    if (options.saveDownloadToPublicStorage) {
      usedMemorySave = _mediaStorageService.shouldUseMemory(
        selectedTransfer.fileSize,
      );
      final saveStopwatch = Stopwatch()..start();
      publicUri = await _saveToPublicStorage(
        localPath: tempPath,
        fileName: selectedTransfer.fileName,
        usedMemorySave: usedMemorySave,
      );
      saveStopwatch.stop();
      saveToPublicStorageMs = saveStopwatch.elapsedMilliseconds;
      onLog?.call('Saved relay artifact to public storage');
    }
    final userVisibleMs = runStopwatch.elapsedMilliseconds;

    var completionAfterSaveMs = 0;
    if (!usedConcurrentRanges) {
      onLog?.call('Waiting for relay server completion record...');
      final completionStopwatch = Stopwatch()..start();
      finalizedTransfer = await _waitForTransfer(
        transferId: selectedTransfer.transferId,
        predicate: (transfer) => _isCompletedForCurrentClient(transfer),
      );
      completionStopwatch.stop();
      completionAfterSaveMs = completionStopwatch.elapsedMilliseconds;
    }

    runStopwatch.stop();
    if (!options.keepTemporaryFile) {
      await _deleteIfExists(tempPath);
    }

    final rawResult = <String, dynamic>{
      'transportType': BenchmarkTransportType.relay.name,
      'mode': options.mode.name,
      'relayBenchmark': <String, dynamic>{
        'role': BenchmarkRelayRole.receiver.name,
        'transferId': selectedTransfer.transferId,
        'peerClientId':
            _trimOrNull(options.relayPeerClientId) ??
            selectedTransfer.senderClientId,
        'currentClientId': _currentSession.clientId,
        'usedConcurrentRanges': usedConcurrentRanges,
        'clientBuild': RuntimeBuildInfo.toJson(),
        'serverVersion': _currentSession.serverVersion,
        'keepTemporaryFile': options.keepTemporaryFile,
        'temporaryFilePath': options.keepTemporaryFile ? tempPath : null,
        'savedToPublicStorage': options.saveDownloadToPublicStorage,
        'usedMemorySave': usedMemorySave,
        'publicUri': publicUri,
        'downloadStrategy': downloadStrategy.toJson(),
        'phaseMetrics': <String, dynamic>{
          'historyLookupMs': selectionStopwatch.elapsedMilliseconds,
          'downloadNetworkMs': networkStopwatch.elapsedMilliseconds,
          'acknowledgeMs': acknowledgeMs,
          'saveToPublicStorageMs': saveToPublicStorageMs,
          'completionAfterSaveMs': completionAfterSaveMs,
          'userVisibleMs': userVisibleMs,
          'totalMs': runStopwatch.elapsedMilliseconds,
        },
        'downloadDiagnostics': downloadResult.diagnostics.toJson(),
        'progressCallbackCount': progressCallbackCount,
        'selectedTransfer': _relayTransferToJson(selectedTransfer),
        'finalTransfer': finalizedTransfer == null
            ? null
            : _relayTransferToJson(finalizedTransfer),
      },
    };

    final result = BenchmarkRunResult(
      options: options,
      rawResult: rawResult,
      temporaryFilePath: options.keepTemporaryFile ? tempPath : null,
      publicUri: publicUri,
    );
    developer.log(result.prettyJson, name: 'benchmark');
    return result;
  }

  Future<RelayTransferEntity> _resolveDownloadTransfer(
    BenchmarkExecutionOptions options,
  ) async {
    final currentClientId = _requireCurrentClientId();
    final transfers = await _relayRemoteDataSource.loadHistory();
    final requestedPeerClientId = _trimOrNull(options.relayPeerClientId);
    final candidates =
        transfers
            .where((transfer) => transfer.isReceiver(currentClientId))
            .where((transfer) => transfer.canDownloadAs(currentClientId))
            .where(
              (transfer) =>
                  requestedPeerClientId == null ||
                  transfer.senderClientId == requestedPeerClientId,
            )
            .toList(growable: false)
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    if (candidates.isEmpty) {
      throw StateError(
        requestedPeerClientId == null
            ? 'No downloadable relay transfer is currently available'
            : 'No downloadable relay transfer matches the selected sender deviceId',
      );
    }
    return candidates.first;
  }

  Future<RelayTransferEntity> _waitForTransfer({
    required String transferId,
    required bool Function(RelayTransferEntity transfer) predicate,
  }) async {
    final deadline = DateTime.now().add(_historyPollTimeout);
    RelayTransferEntity? lastSeenTransfer;
    while (DateTime.now().isBefore(deadline)) {
      final transfers = await _relayRemoteDataSource.loadHistory();
      for (final transfer in transfers) {
        if (transfer.transferId != transferId) {
          continue;
        }
        lastSeenTransfer = transfer;
        if (predicate(transfer)) {
          return transfer;
        }
      }
      await Future<void>.delayed(_historyPollInterval);
    }
    if (lastSeenTransfer != null) {
      throw StateError(
        'Timed out while waiting for relay transfer "$transferId"; latest status is ${lastSeenTransfer.status.name}',
      );
    }
    throw StateError(
      'Timed out while waiting for relay transfer "$transferId"',
    );
  }

  Future<String> _saveToPublicStorage({
    required String localPath,
    required String fileName,
    required bool usedMemorySave,
  }) async {
    final fileType = _mediaStorageService.getFileTypeFromExtension(fileName);
    final publicUri = usedMemorySave
        ? await _mediaStorageService.saveToPublicStorage(
            fileName: fileName,
            data: await _deviceFileService.readFileAsBytes(localPath),
            fileType: fileType,
          )
        : await _mediaStorageService.saveFileToPublicStorage(
            fileName: fileName,
            filePath: localPath,
            fileType: fileType,
          );
    if (publicUri == null || publicUri.trim().isEmpty) {
      throw StateError(
        'Relay benchmark save to public storage returned empty URI',
      );
    }
    return publicUri;
  }

  bool _isCompletedForCurrentClient(RelayTransferEntity transfer) {
    final clientId = _requireCurrentClientId();
    final target = transfer.targetForClient(clientId);
    return target?.deliveryState == RelayTransferTargetState.completed ||
        target?.downloadCompletedAt != null ||
        transfer.status == RelayTransferStatus.completed;
  }

  String _requireRelayPeerClientId(String? value) {
    final peerClientId = _trimOrNull(value);
    if (peerClientId == null) {
      throw StateError('Relay benchmark requires a target peer deviceId');
    }
    return peerClientId;
  }

  String _requireCurrentClientId() {
    final clientId = _trimOrNull(_currentSession.clientId);
    if (clientId == null) {
      throw StateError('Current session is missing a relay-capable deviceId');
    }
    return clientId;
  }

  String _requireUploadPath(RelayTransferEntity transfer) {
    final path = _trimOrNull(transfer.transport?.upload.path);
    if (path == null) {
      throw StateError('Relay benchmark upload path is missing');
    }
    return path;
  }

  String _requireDownloadPath(RelayTransferEntity transfer) {
    final path = _trimOrNull(transfer.transport?.download.path);
    if (path == null) {
      throw StateError('Relay benchmark download path is missing');
    }
    return path;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String? _trimOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _differenceMs(DateTime? start, DateTime? end) {
    if (start == null || end == null) {
      return null;
    }
    return end.difference(start).inMilliseconds;
  }

  Map<String, dynamic> _relayTransferToJson(RelayTransferEntity transfer) {
    return <String, dynamic>{
      'transferId': transfer.transferId,
      'senderAccountId': transfer.senderAccountId,
      'senderLabel': transfer.senderLabel,
      'senderClientId': transfer.senderClientId,
      'targetCount': transfer.targetCount,
      'fileName': transfer.fileName,
      'mimeType': transfer.mimeType,
      'fileSize': transfer.fileSize,
      'checksum': transfer.checksum,
      'checksumAlgorithm': transfer.checksumAlgorithm,
      'chunkSize': transfer.chunkSize,
      'storageMode': transfer.storageMode,
      'status': transfer.status.name,
      'createdAt': transfer.createdAt.toIso8601String(),
      'updatedAt': transfer.updatedAt.toIso8601String(),
      'expiresAt': transfer.expiresAt.toIso8601String(),
      'readyAt': transfer.readyAt?.toIso8601String(),
      'completedAt': transfer.completedAt?.toIso8601String(),
      'failedAt': transfer.failedAt?.toIso8601String(),
      'cancelledAt': transfer.cancelledAt?.toIso8601String(),
      'interruptedAt': transfer.interruptedAt?.toIso8601String(),
      'failureCode': transfer.failureCode,
      'failureMessage': transfer.failureMessage,
      'artifact': <String, dynamic>{
        'tempPath': transfer.artifact.tempPath,
        'sealedPath': transfer.artifact.sealedPath,
        'chunkCount': transfer.artifact.chunkCount,
        'receivedBytes': transfer.artifact.receivedBytes,
        'isSealed': transfer.artifact.isSealed,
        'cleanupState': transfer.artifact.cleanupState.name,
        'updatedAt': transfer.artifact.updatedAt.toIso8601String(),
      },
      'targets': transfer.targets
          .map(
            (target) => <String, dynamic>{
              'receiverClientId': target.receiverClientId,
              'deliveryState': target.deliveryState.name,
              'updatedAt': target.updatedAt.toIso8601String(),
              'deliveredAt': target.deliveredAt?.toIso8601String(),
              'downloadStartedAt': target.downloadStartedAt?.toIso8601String(),
              'downloadCompletedAt': target.downloadCompletedAt
                  ?.toIso8601String(),
            },
          )
          .toList(growable: false),
      'transport': transfer.transport == null
          ? null
          : <String, dynamic>{
              'protocol': transfer.transport!.protocol,
              'upload': <String, dynamic>{
                'method': transfer.transport!.upload.method,
                'path': transfer.transport!.upload.path,
                'supportsRange': transfer.transport!.upload.supportsRange,
              },
              'download': <String, dynamic>{
                'method': transfer.transport!.download.method,
                'path': transfer.transport!.download.path,
                'supportsRange': transfer.transport!.download.supportsRange,
              },
            },
    };
  }

  PathDownloadStrategy _buildDownloadStrategy(
    BenchmarkExecutionOptions options,
  ) {
    return PathDownloadStrategy(
      preferredConcurrentRequests: options.downloadConcurrency,
      initialChunkSizeBytes: options.downloadInitialChunkSizeBytes,
      minimumChunkSizeBytes: options.downloadMinimumChunkSizeBytes,
      stallTimeout: options.downloadStallTimeout,
    );
  }
}
