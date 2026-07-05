import 'dart:async';
import 'dart:developer' as developer;

import '../../../core/device/device_file_service.dart';
import '../../../core/device/media_storage_service.dart';
import '../../../core/network/dio_path_download_service.dart';
import '../../../core/runtime/runtime_build_info.dart';
import '../../../core/session/current_session.dart';
import '../data/benchmark_file_generator.dart';
import '../data/benchmark_remote_data_source.dart';
import '../domain/benchmark_models.dart';

typedef BenchmarkProgressCallback = void Function(double progress);
typedef BenchmarkLogCallback = void Function(String message);

class DirectBenchmarkRunner {
  DirectBenchmarkRunner({
    required BenchmarkRemoteDataSource remoteDataSource,
    required BenchmarkFileGenerator fileGenerator,
    required DeviceFileService deviceFileService,
    required MediaStorageService mediaStorageService,
    required CurrentSession currentSession,
  }) : _remoteDataSource = remoteDataSource,
       _fileGenerator = fileGenerator,
       _deviceFileService = deviceFileService,
       _mediaStorageService = mediaStorageService,
       _currentSession = currentSession;

  final BenchmarkRemoteDataSource _remoteDataSource;
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
    final runStopwatch = Stopwatch()..start();
    final sessionCreateStopwatch = Stopwatch()..start();
    onLog?.call('Creating upload benchmark session...');
    final session = await _remoteDataSource.createSession(
      mode: options.mode,
      transportType: options.transportType,
      fileSizeBytes: options.fileSizeBytes,
    );
    sessionCreateStopwatch.stop();

    final useHttp = _isHttpTransport(options.transportType);
    if (useHttp) {
      final httpPort = session.endpoints.httpPort;
      if (httpPort == null) {
        throw StateError(
          'Server did not return an HTTP port for HTTP transport',
        );
      }
      final httpsUri = Uri.parse(_remoteDataSource.baseUrl);
      final httpBaseUrl = 'http://${httpsUri.host}:$httpPort';
      _remoteDataSource.configureHttp(baseUrl: httpBaseUrl);
    }

    final generatedFile = await _fileGenerator.generate(
      fileSizeBytes: options.fileSizeBytes,
      fileName: '${session.traceId}.bin',
    );
    onLog?.call(
      'Generated ${generatedFile.fileSizeBytes} bytes in ${generatedFile.generationMs} ms',
    );

    var progressCallbackCount = 0;
    final transferStopwatch = Stopwatch()..start();
    await _remoteDataSource.uploadArtifact(
      sessionId: session.sessionId,
      filePath: generatedFile.filePath,
      totalSize: generatedFile.fileSizeBytes,
      uploadPath: _resolveUploadPath(session, options.transportType),
      useHttp: useHttp,
      onSendProgress: (sent, total) {
        progressCallbackCount += 1;
        if (total > 0) {
          onProgress?.call((sent / total).clamp(0.0, 1.0));
        }
      },
    );
    transferStopwatch.stop();
    runStopwatch.stop();
    onProgress?.call(1);

    final shouldKeepTemporaryFile = options.keepTemporaryFile;
    if (!shouldKeepTemporaryFile) {
      await _deviceFileService.deleteFile(generatedFile.filePath);
    }

    await _remoteDataSource.submitClientReport(
      sessionId: session.sessionId,
      clientReport: <String, dynamic>{
        'transportType': options.transportType.name,
        'mode': options.mode.name,
        'fileSizeBytes': options.fileSizeBytes,
        'clientBuild': RuntimeBuildInfo.toJson(),
        'serverVersion': _currentSession.serverVersion,
        'sessionCreateMs': sessionCreateStopwatch.elapsedMilliseconds,
        'fileGenerationMs': generatedFile.generationMs,
        'transferMs': transferStopwatch.elapsedMilliseconds,
        'totalMs': runStopwatch.elapsedMilliseconds,
        'progressCallbackCount': progressCallbackCount,
        'uiStateEmitCountEstimate': progressCallbackCount,
        'savedToPublicStorage': false,
        'saveToPublicStorageMs': 0,
        'usedMemorySave': false,
        'keepTemporaryFile': shouldKeepTemporaryFile,
        'temporaryFilePath': shouldKeepTemporaryFile
            ? generatedFile.filePath
            : null,
        'publicUri': null,
      },
    );
    final result = await _remoteDataSource.loadSessionResult(session.sessionId);
    developer.log(
      BenchmarkRunResult(
        options: options,
        rawResult: result,
        temporaryFilePath: shouldKeepTemporaryFile
            ? generatedFile.filePath
            : null,
      ).prettyJson,
      name: 'benchmark',
    );
    return BenchmarkRunResult(
      options: options,
      rawResult: result,
      temporaryFilePath: shouldKeepTemporaryFile
          ? generatedFile.filePath
          : null,
    );
  }

  Future<BenchmarkRunResult> _runDownload({
    required BenchmarkExecutionOptions options,
    BenchmarkProgressCallback? onProgress,
    BenchmarkLogCallback? onLog,
  }) async {
    final runStopwatch = Stopwatch()..start();
    final sessionCreateStopwatch = Stopwatch()..start();
    onLog?.call('Creating download benchmark session...');
    final session = await _remoteDataSource.createSession(
      mode: options.mode,
      transportType: options.transportType,
      fileSizeBytes: options.fileSizeBytes,
    );
    sessionCreateStopwatch.stop();

    final useHttp = _isHttpTransport(options.transportType);
    if (useHttp) {
      final httpPort = session.endpoints.httpPort;
      if (httpPort == null) {
        throw StateError(
          'Server did not return an HTTP port for HTTP download',
        );
      }
      final httpsUri = Uri.parse(_remoteDataSource.baseUrl);
      final httpBaseUrl = 'http://${httpsUri.host}:$httpPort';
      _remoteDataSource.configureHttp(baseUrl: httpBaseUrl);
    }

    final fileName = '${session.traceId}.bin';
    final tempPath = await _fileGenerator.createTemporaryPath(
      fileName: fileName,
    );
    final downloadStrategy = _buildDownloadStrategy(options);
    var progressCallbackCount = 0;
    final networkStopwatch = Stopwatch()..start();
    final downloadResult = await _remoteDataSource.downloadArtifact(
      sessionId: session.sessionId,
      savePath: tempPath,
      expectedSize: options.fileSizeBytes,
      downloadPath: _resolveDownloadPath(session, options.transportType),
      supportsRange: true,
      useHttp: useHttp,
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

    var saveToPublicStorageMs = 0;
    var usedMemorySave = false;
    String? publicUri;
    if (options.saveDownloadToPublicStorage) {
      usedMemorySave = _mediaStorageService.shouldUseMemory(
        options.fileSizeBytes,
      );
      final saveStopwatch = Stopwatch()..start();
      if (usedMemorySave) {
        final bytes = await _deviceFileService.readFileAsBytes(tempPath);
        publicUri = await _mediaStorageService.saveToPublicStorage(
          fileName: fileName,
          data: bytes,
          fileType: MediaFileType.document,
        );
      } else {
        publicUri = await _mediaStorageService.saveFileToPublicStorage(
          fileName: fileName,
          filePath: tempPath,
          fileType: MediaFileType.document,
        );
      }
      saveStopwatch.stop();
      saveToPublicStorageMs = saveStopwatch.elapsedMilliseconds;
      onLog?.call(
        'Saved benchmark artifact to public storage in $saveToPublicStorageMs ms',
      );
    }

    runStopwatch.stop();
    final shouldKeepTemporaryFile = options.keepTemporaryFile;
    if (!shouldKeepTemporaryFile) {
      await _deviceFileService.deleteFile(tempPath);
    }

    await _remoteDataSource.submitClientReport(
      sessionId: session.sessionId,
      clientReport: <String, dynamic>{
        'transportType': options.transportType.name,
        'mode': options.mode.name,
        'fileSizeBytes': options.fileSizeBytes,
        'clientBuild': RuntimeBuildInfo.toJson(),
        'serverVersion': _currentSession.serverVersion,
        'sessionCreateMs': sessionCreateStopwatch.elapsedMilliseconds,
        'fileGenerationMs': 0,
        'transferMs': networkStopwatch.elapsedMilliseconds,
        'downloadNetworkMs': networkStopwatch.elapsedMilliseconds,
        'saveToPublicStorageMs': saveToPublicStorageMs,
        'totalMs': runStopwatch.elapsedMilliseconds,
        'progressCallbackCount': progressCallbackCount,
        'uiStateEmitCountEstimate': progressCallbackCount,
        'usedConcurrentRanges': usedConcurrentRanges,
        'downloadStrategy': downloadStrategy.toJson(),
        'downloadDiagnostics': downloadResult.diagnostics.toJson(),
        'savedToPublicStorage': options.saveDownloadToPublicStorage,
        'usedMemorySave': usedMemorySave,
        'keepTemporaryFile': shouldKeepTemporaryFile,
        'temporaryFilePath': shouldKeepTemporaryFile ? tempPath : null,
        'publicUri': publicUri,
      },
    );
    final result = await _remoteDataSource.loadSessionResult(session.sessionId);
    developer.log(
      BenchmarkRunResult(
        options: options,
        rawResult: result,
        temporaryFilePath: shouldKeepTemporaryFile ? tempPath : null,
        publicUri: publicUri,
      ).prettyJson,
      name: 'benchmark',
    );
    return BenchmarkRunResult(
      options: options,
      rawResult: result,
      temporaryFilePath: shouldKeepTemporaryFile ? tempPath : null,
      publicUri: publicUri,
    );
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

  String _resolveUploadPath(
    BenchmarkSessionInfo session,
    BenchmarkTransportType transportType,
  ) {
    return switch (transportType) {
      BenchmarkTransportType.direct ||
      BenchmarkTransportType.directHttp =>
        session.endpoints.uploadPath,
      BenchmarkTransportType.directDav ||
      BenchmarkTransportType.directDavHttp =>
        session.endpoints.davUploadPath ??
            (throw StateError('Benchmark session is missing davUploadPath')),
      BenchmarkTransportType.relay => session.endpoints.uploadPath,
    };
  }

  String _resolveDownloadPath(
    BenchmarkSessionInfo session,
    BenchmarkTransportType transportType,
  ) {
    return switch (transportType) {
      BenchmarkTransportType.direct ||
      BenchmarkTransportType.directHttp =>
        session.endpoints.downloadPath,
      BenchmarkTransportType.directDav ||
      BenchmarkTransportType.directDavHttp =>
        session.endpoints.davDownloadPath ??
            (throw StateError('Benchmark session is missing davDownloadPath')),
      BenchmarkTransportType.relay => session.endpoints.downloadPath,
    };
  }

  bool _isHttpTransport(BenchmarkTransportType transportType) {
    return switch (transportType) {
      BenchmarkTransportType.directHttp => true,
      BenchmarkTransportType.directDavHttp => true,
      _ => false,
    };
  }
}
