import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'download_diagnostics.dart';
import '../protocol/path_download_capable_file_protocol_client.dart';

class PathDownloadStrategy {
  static const int defaultRangeDownloadThresholdBytes = 16 * 1024 * 1024;
  static const int defaultPreferredConcurrentRequests = 4;
  static const int defaultInitialChunkSizeBytes = 24 * 1024 * 1024;
  static const int defaultRelayInitialChunkSizeBytes = 32 * 1024 * 1024;
  static const int defaultMinimumChunkSizeBytes = 8 * 1024 * 1024;
  static const Duration defaultStallTimeout = Duration(seconds: 6);
  static const Duration defaultSlowRangeGracePeriod = Duration(seconds: 2);
  static const int defaultSlowRangeMinimumBytes = 2 * 1024 * 1024;
  static const double defaultSlowRangeThroughputRatio = 0.6;
  static const int defaultMaxTaskRetries = 4;
  static const int defaultMaxWorkerStalls = 2;
  static const int defaultWriteBufferSize = 1024 * 1024;
  static const PathDownloadStrategy directDownloadDefault =
      PathDownloadStrategy();
  static const PathDownloadStrategy relayDownloadDefault = PathDownloadStrategy(
    preferredConcurrentRequests: defaultPreferredConcurrentRequests,
    initialChunkSizeBytes: defaultRelayInitialChunkSizeBytes,
    minimumChunkSizeBytes: defaultMinimumChunkSizeBytes,
    stallTimeout: defaultStallTimeout,
    maxTaskRetries: defaultMaxTaskRetries,
    maxWorkerStalls: defaultMaxWorkerStalls,
    writeBufferSize: defaultWriteBufferSize,
  );

  const PathDownloadStrategy({
    this.rangeDownloadThresholdBytes = defaultRangeDownloadThresholdBytes,
    this.preferredConcurrentRequests = defaultPreferredConcurrentRequests,
    this.initialChunkSizeBytes = defaultInitialChunkSizeBytes,
    this.minimumChunkSizeBytes = defaultMinimumChunkSizeBytes,
    this.stallTimeout = defaultStallTimeout,
    this.slowRangeGracePeriod = defaultSlowRangeGracePeriod,
    this.slowRangeMinimumBytes = defaultSlowRangeMinimumBytes,
    this.slowRangeThroughputRatio = defaultSlowRangeThroughputRatio,
    this.maxTaskRetries = defaultMaxTaskRetries,
    this.maxWorkerStalls = defaultMaxWorkerStalls,
    this.writeBufferSize = defaultWriteBufferSize,
  });

  final int rangeDownloadThresholdBytes;
  final int preferredConcurrentRequests;
  final int initialChunkSizeBytes;
  final int minimumChunkSizeBytes;
  final Duration stallTimeout;
  final Duration slowRangeGracePeriod;
  final int slowRangeMinimumBytes;
  final double slowRangeThroughputRatio;
  final int maxTaskRetries;
  final int maxWorkerStalls;
  final int writeBufferSize;

  PathDownloadStrategy normalized() {
    final normalizedMinimumChunkSizeBytes = minimumChunkSizeBytes <= 0
        ? 4 * 1024 * 1024
        : minimumChunkSizeBytes;
    final normalizedInitialChunkSizeBytes =
        initialChunkSizeBytes < normalizedMinimumChunkSizeBytes
        ? normalizedMinimumChunkSizeBytes
        : initialChunkSizeBytes;
    return PathDownloadStrategy(
      rangeDownloadThresholdBytes: rangeDownloadThresholdBytes <= 0
          ? defaultRangeDownloadThresholdBytes
          : rangeDownloadThresholdBytes,
      preferredConcurrentRequests: preferredConcurrentRequests <= 0
          ? 1
          : preferredConcurrentRequests,
      initialChunkSizeBytes: normalizedInitialChunkSizeBytes,
      minimumChunkSizeBytes: normalizedMinimumChunkSizeBytes,
      stallTimeout: stallTimeout == Duration.zero || stallTimeout.isNegative
          ? defaultStallTimeout
          : stallTimeout,
      slowRangeGracePeriod:
          slowRangeGracePeriod == Duration.zero ||
              slowRangeGracePeriod.isNegative
          ? defaultSlowRangeGracePeriod
          : slowRangeGracePeriod,
      slowRangeMinimumBytes: slowRangeMinimumBytes <= 0
          ? defaultSlowRangeMinimumBytes
          : slowRangeMinimumBytes,
      slowRangeThroughputRatio:
          slowRangeThroughputRatio <= 0 || slowRangeThroughputRatio >= 1
          ? defaultSlowRangeThroughputRatio
          : slowRangeThroughputRatio,
      maxTaskRetries: maxTaskRetries <= 0 ? 1 : maxTaskRetries,
      maxWorkerStalls: maxWorkerStalls <= 0 ? 1 : maxWorkerStalls,
      writeBufferSize: writeBufferSize <= 0
          ? defaultWriteBufferSize
          : writeBufferSize,
    );
  }

  bool shouldUseConcurrentRanges({
    required int totalBytes,
    required bool supportsRange,
  }) {
    if (!supportsRange || preferredConcurrentRequests <= 1) {
      return false;
    }
    if (totalBytes < rangeDownloadThresholdBytes) {
      return false;
    }
    return totalBytes > minimumChunkSizeBytes;
  }

  int resolveEffectiveConcurrency(int totalBytes) {
    if (preferredConcurrentRequests <= 1 ||
        totalBytes <= minimumChunkSizeBytes) {
      return 1;
    }
    final maxBySize = math.max(1, totalBytes ~/ minimumChunkSizeBytes);
    return math.min(preferredConcurrentRequests, maxBySize);
  }

  int resolveInitialChunkSize({
    required int totalBytes,
    required int concurrency,
  }) {
    if (concurrency <= 1 || totalBytes <= 0) {
      return totalBytes;
    }
    final evenlyDistributedChunkSize = (totalBytes / concurrency).ceil();
    final boundedChunkSize = math.max(
      minimumChunkSizeBytes,
      evenlyDistributedChunkSize,
    );
    return math.min(initialChunkSizeBytes, boundedChunkSize);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rangeDownloadThresholdBytes': rangeDownloadThresholdBytes,
      'preferredConcurrentRequests': preferredConcurrentRequests,
      'initialChunkSizeBytes': initialChunkSizeBytes,
      'minimumChunkSizeBytes': minimumChunkSizeBytes,
      'stallTimeoutMs': stallTimeout.inMilliseconds,
      'slowRangeGracePeriodMs': slowRangeGracePeriod.inMilliseconds,
      'slowRangeMinimumBytes': slowRangeMinimumBytes,
      'slowRangeThroughputRatio': slowRangeThroughputRatio,
      'maxTaskRetries': maxTaskRetries,
      'maxWorkerStalls': maxWorkerStalls,
      'writeBufferSize': writeBufferSize,
    };
  }
}

class DioPathDownloadService {
  static const PathDownloadStrategy defaultStrategy =
      PathDownloadStrategy.directDownloadDefault;

  DioPathDownloadService({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<PathDownloadResult> downloadToPath({
    required String url,
    required String savePath,
    required int expectedSize,
    bool supportsRange = false,
    ProgressCallback? onReceiveProgress,
    bool Function()? shouldCancel,
    PathDownloadStrategy strategy = defaultStrategy,
  }) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);
    final resolvedStrategy = strategy.normalized();

    try {
      if (resolvedStrategy.shouldUseConcurrentRanges(
        totalBytes: expectedSize,
        supportsRange: supportsRange,
      )) {
        try {
          final diagnostics = await _downloadToPathWithRanges(
            url: url,
            savePath: savePath,
            totalBytes: expectedSize,
            onReceiveProgress: onReceiveProgress,
            shouldCancel: shouldCancel,
            strategy: resolvedStrategy,
          );
          return PathDownloadResult(
            usedConcurrentRanges: true,
            diagnostics: diagnostics,
          );
        } on _RangeRequestRejectedException {
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      final diagnostics = await _downloadToPathSingleStream(
        url: url,
        savePath: savePath,
        totalBytes: expectedSize,
        onReceiveProgress: onReceiveProgress,
        shouldCancel: shouldCancel,
        strategy: resolvedStrategy,
      );
      return PathDownloadResult(
        usedConcurrentRanges: false,
        diagnostics: diagnostics,
      );
    } on _PathDownloadCancelledException {
      if (await file.exists()) {
        await file.delete();
      }
      throw const PathDownloadCancelledException();
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  Future<PathDownloadDiagnostics> _downloadToPathSingleStream({
    required String url,
    required String savePath,
    required int totalBytes,
    ProgressCallback? onReceiveProgress,
    bool Function()? shouldCancel,
    required PathDownloadStrategy strategy,
  }) async {
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    final responseBody = response.data;
    if (responseBody == null) {
      throw Exception('Download returned an empty response body');
    }

    final fileHandle = await File(savePath).open(mode: FileMode.write);
    final buffer = BytesBuilder(copy: false);
    final operationStopwatch = Stopwatch()..start();
    var receivedBytes = 0;
    var localWriteMs = 0;
    var flushCount = 0;
    var flushWriteMs = 0;

    Future<void> flushBuffer() async {
      if (buffer.isEmpty) {
        return;
      }
      final bytes = buffer.takeBytes();
      final writeStopwatch = Stopwatch()..start();
      await fileHandle.writeFrom(bytes);
      writeStopwatch.stop();
      final writeMs = writeStopwatch.elapsedMilliseconds;
      localWriteMs += writeMs;
      flushCount += 1;
      flushWriteMs += writeMs;
      receivedBytes += bytes.length;
      onReceiveProgress?.call(receivedBytes, totalBytes);
    }

    try {
      await for (final chunk in responseBody.stream) {
        if (shouldCancel?.call() == true) {
          throw const _PathDownloadCancelledException();
        }
        buffer.add(chunk);
        if (buffer.length >= strategy.writeBufferSize) {
          await flushBuffer();
        }
      }

      await flushBuffer();
      if (totalBytes > 0) {
        onReceiveProgress?.call(totalBytes, totalBytes);
      }
    } finally {
      await fileHandle.close();
    }
    operationStopwatch.stop();
    return PathDownloadDiagnostics(
      usedConcurrentRanges: false,
      totalBytes: totalBytes,
      totalMs: operationStopwatch.elapsedMilliseconds,
      filePreparationMs: 0,
      networkReceiveMs: _nonNegativeMs(
        operationStopwatch.elapsedMilliseconds - localWriteMs,
      ),
      localWriteMs: localWriteMs,
      flushCount: flushCount,
      flushWriteMs: flushWriteMs,
      configuredConcurrency: strategy.preferredConcurrentRequests,
      effectiveConcurrency: 1,
      initialChunkSizeBytes: strategy.initialChunkSizeBytes,
      minimumChunkSizeBytes: strategy.minimumChunkSizeBytes,
      slowRangeCount: 0,
      retryCount: 0,
      stallCount: 0,
      splitCount: 0,
      requeueCount: 0,
      stealCount: 0,
      rangeRequests: const <PathDownloadRangeRequestDiagnostics>[],
      workers: <PathDownloadWorkerDiagnostics>[
        PathDownloadWorkerDiagnostics(
          workerId: 0,
          requestCount: 1,
          bytesReceived: receivedBytes,
          slowRangeCount: 0,
          stallCount: 0,
          retryCount: 0,
          stealCount: 0,
          retired: false,
        ),
      ],
    );
  }

  Future<PathDownloadDiagnostics> _downloadToPathWithRanges({
    required String url,
    required String savePath,
    required int totalBytes,
    ProgressCallback? onReceiveProgress,
    bool Function()? shouldCancel,
    required PathDownloadStrategy strategy,
  }) async {
    final effectiveConcurrency = strategy.resolveEffectiveConcurrency(
      totalBytes,
    );
    if (effectiveConcurrency <= 1) {
      return _downloadToPathSingleStream(
        url: url,
        savePath: savePath,
        totalBytes: totalBytes,
        onReceiveProgress: onReceiveProgress,
        shouldCancel: shouldCancel,
        strategy: strategy,
      );
    }

    final initialChunkSize = strategy.resolveInitialChunkSize(
      totalBytes: totalBytes,
      concurrency: effectiveConcurrency,
    );
    if (initialChunkSize <= 0 || initialChunkSize >= totalBytes) {
      return _downloadToPathSingleStream(
        url: url,
        savePath: savePath,
        totalBytes: totalBytes,
        onReceiveProgress: onReceiveProgress,
        shouldCancel: shouldCancel,
        strategy: strategy,
      );
    }

    final outputFile = File(savePath);
    final operationStopwatch = Stopwatch()..start();
    final seedHandle = await outputFile.open(mode: FileMode.write);
    final filePreparationStopwatch = Stopwatch()..start();
    try {
      await seedHandle.truncate(totalBytes);
    } finally {
      filePreparationStopwatch.stop();
      await seedHandle.close();
    }

    final taskQueue = _RangeTaskQueue(
      _buildInitialTasks(totalBytes: totalBytes, chunkSize: initialChunkSize),
    );
    final progress = _RangeDownloadProgress(
      totalBytes: totalBytes,
      callback: onReceiveProgress,
    );
    final rangeRequestMetrics = <_PathDownloadRangeRequestRuntime>[];
    final workerCount = math.min(effectiveConcurrency, taskQueue.length);
    final workerFileHandles = await Future.wait<RandomAccessFile>(
      List<Future<RandomAccessFile>>.generate(
        workerCount,
        (_) => outputFile.open(mode: FileMode.writeOnly),
        growable: false,
      ),
    );
    final workerRuntimes = List<_PathDownloadWorkerRuntime>.generate(
      workerCount,
      (index) => _PathDownloadWorkerRuntime(index, workerFileHandles[index]),
      growable: false,
    );
    var nextTaskId = taskQueue.nextTaskId;
    var nextRequestIndex = 0;
    var retiredWorkerCount = 0;
    var inFlightRequestCount = 0;
    final activeRequests = <int, _ActiveRangeRequest>{};
    var bestObservedThroughputBytesPerSecond = 0.0;
    var slowRangeCount = 0;
    var retryCount = 0;
    var stallCount = 0;
    var splitCount = 0;
    var requeueCount = 0;
    var stealCount = 0;

    Future<void> worker(_PathDownloadWorkerRuntime runtime) async {
      while (true) {
        if (shouldCancel?.call() == true) {
          throw const _PathDownloadCancelledException();
        }

        final task = taskQueue.takeNext(runtime.workerId);
        if (task == null) {
          if (_maybeScheduleSlowRangeSplit(
            idleWorkerId: runtime.workerId,
            strategy: strategy,
            taskQueue: taskQueue,
            activeRequests: activeRequests,
            bestObservedThroughputBytesPerSecond:
                bestObservedThroughputBytesPerSecond,
          )) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            continue;
          }
          if (inFlightRequestCount > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            continue;
          }
          return;
        }

        if (task.originWorkerId != null &&
            task.originWorkerId != runtime.workerId) {
          runtime.stealCount += 1;
          stealCount += 1;
        }

        final requestIndex = nextRequestIndex;
        nextRequestIndex += 1;
        inFlightRequestCount += 1;
        final activeRequest = _ActiveRangeRequest(
          task: task,
          workerId: runtime.workerId,
        );
        activeRequests[runtime.workerId] = activeRequest;
        late final _RangeDownloadOutcome outcome;
        try {
          outcome = await _downloadRangeChunk(
            requestIndex: requestIndex,
            url: url,
            task: task,
            activeRequest: activeRequest,
            fileHandle: runtime.fileHandle,
            workerId: runtime.workerId,
            progress: progress,
            shouldCancel: shouldCancel,
            strategy: strategy,
            nextTaskIdBuilder: () {
              final taskId = nextTaskId;
              nextTaskId += 1;
              return taskId;
            },
          );
        } finally {
          activeRequests.remove(runtime.workerId);
          inFlightRequestCount -= 1;
        }
        rangeRequestMetrics.add(outcome.runtime);
        runtime.requestCount += 1;
        runtime.bytesReceived += outcome.runtime.bytesReceived;
        if (outcome.runtime.throughputBytesPerSecond >
            bestObservedThroughputBytesPerSecond) {
          bestObservedThroughputBytesPerSecond =
              outcome.runtime.throughputBytesPerSecond;
        }
        if (outcome.runtime.wasSlow) {
          runtime.slowRangeCount += 1;
          slowRangeCount += 1;
        }
        if (outcome.runtime.wasStalled) {
          runtime.stallCount += 1;
          stallCount += 1;
        }
        if (outcome.retryTriggered) {
          runtime.retryCount += 1;
          retryCount += 1;
        }
        if (outcome.followUpTasks.isNotEmpty) {
          if (outcome.wasSplit) {
            splitCount += 1;
          }
          requeueCount += outcome.followUpTasks.length;
          taskQueue.addAll(outcome.followUpTasks);
        }
        if (outcome.runtime.wasStalled &&
            runtime.stallCount >= strategy.maxWorkerStalls &&
            retiredWorkerCount < workerRuntimes.length - 1) {
          runtime.retired = true;
          retiredWorkerCount += 1;
          return;
        }
      }
    }

    try {
      await Future.wait(workerRuntimes.map(worker));
      if (taskQueue.isNotEmpty) {
        throw const _PathDownloadRetryLimitExceededException();
      }
    } finally {
      for (final fileHandle in workerFileHandles) {
        await fileHandle.close();
      }
    }
    progress.complete();
    operationStopwatch.stop();

    rangeRequestMetrics.sort(
      (left, right) => left.index.compareTo(right.index),
    );
    final localWriteMs = rangeRequestMetrics.fold<int>(
      0,
      (sum, metrics) => sum + metrics.localWriteMs,
    );
    final flushCount = rangeRequestMetrics.fold<int>(
      0,
      (sum, metrics) => sum + metrics.flushCount,
    );
    final flushWriteMs = rangeRequestMetrics.fold<int>(
      0,
      (sum, metrics) => sum + metrics.flushWriteMs,
    );
    final filePreparationMs = filePreparationStopwatch.elapsedMilliseconds;
    return PathDownloadDiagnostics(
      usedConcurrentRanges: true,
      totalBytes: totalBytes,
      totalMs: operationStopwatch.elapsedMilliseconds,
      filePreparationMs: filePreparationMs,
      networkReceiveMs: _nonNegativeMs(
        operationStopwatch.elapsedMilliseconds -
            filePreparationMs -
            localWriteMs,
      ),
      localWriteMs: localWriteMs,
      flushCount: flushCount,
      flushWriteMs: flushWriteMs,
      configuredConcurrency: strategy.preferredConcurrentRequests,
      effectiveConcurrency: workerRuntimes.length,
      initialChunkSizeBytes: initialChunkSize,
      minimumChunkSizeBytes: strategy.minimumChunkSizeBytes,
      slowRangeCount: slowRangeCount,
      retryCount: retryCount,
      stallCount: stallCount,
      splitCount: splitCount,
      requeueCount: requeueCount,
      stealCount: stealCount,
      rangeRequests: rangeRequestMetrics
          .map((metrics) => metrics.toDiagnostics())
          .toList(growable: false),
      workers: workerRuntimes
          .map((runtime) => runtime.toDiagnostics())
          .toList(growable: false),
    );
  }

  Future<_RangeDownloadOutcome> _downloadRangeChunk({
    required int requestIndex,
    required String url,
    required _RangeTask task,
    required _ActiveRangeRequest activeRequest,
    required RandomAccessFile fileHandle,
    required int workerId,
    required _RangeDownloadProgress progress,
    bool Function()? shouldCancel,
    required PathDownloadStrategy strategy,
    required int Function() nextTaskIdBuilder,
  }) async {
    final requestStopwatch = Stopwatch()..start();
    var localWriteMs = 0;
    var flushCount = 0;
    var flushWriteMs = 0;
    var bytesReceived = 0;

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        headers: <String, dynamic>{
          'Range': 'bytes=${task.start}-${task.endInclusive}',
        },
        responseType: ResponseType.stream,
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
      cancelToken: activeRequest.cancelToken,
    );
    if (response.statusCode != HttpStatus.partialContent) {
      throw const _RangeRequestRejectedException();
    }
    final responseBody = response.data;
    if (responseBody == null) {
      throw Exception('Range download returned an empty response body');
    }
    final buffer = BytesBuilder(copy: false);

    Future<void> flushBuffer() async {
      if (buffer.isEmpty) {
        return;
      }
      final bytes = buffer.takeBytes();
      final writeStopwatch = Stopwatch()..start();
      await fileHandle.writeFrom(bytes);
      writeStopwatch.stop();
      final writeMs = writeStopwatch.elapsedMilliseconds;
      localWriteMs += writeMs;
      flushCount += 1;
      flushWriteMs += writeMs;
      bytesReceived += bytes.length;
      progress.add(bytes.length);
    }

    try {
      await fileHandle.setPosition(task.start);
      await for (final chunk in responseBody.stream.timeout(
        strategy.stallTimeout,
      )) {
        if (shouldCancel?.call() == true) {
          activeRequest.cancelToken.cancel('cancelled');
          throw const _PathDownloadCancelledException();
        }
        activeRequest.recordNetworkBytes(chunk.length);
        buffer.add(chunk);
        if (buffer.length >= strategy.writeBufferSize) {
          await flushBuffer();
        }
      }

      await flushBuffer();
      requestStopwatch.stop();
      return _RangeDownloadOutcome(
        runtime: _PathDownloadRangeRequestRuntime(
          index: requestIndex,
          workerId: workerId,
          attempt: task.attempt,
          splitDepth: task.splitDepth,
          start: task.start,
          endInclusive: task.endInclusive,
          bytesReceived: bytesReceived,
          totalMs: requestStopwatch.elapsedMilliseconds,
          localWriteMs: localWriteMs,
          flushCount: flushCount,
          flushWriteMs: flushWriteMs,
          wasSlow: false,
          wasStalled: false,
        ),
        followUpTasks: const <_RangeTask>[],
        retryTriggered: false,
        wasSplit: false,
      );
    } on _PathDownloadCancelledException {
      rethrow;
    } on TimeoutException {
      activeRequest.cancelToken.cancel('stalled');
      await flushBuffer();
      requestStopwatch.stop();
      final runtime = _PathDownloadRangeRequestRuntime(
        index: requestIndex,
        workerId: workerId,
        attempt: task.attempt,
        splitDepth: task.splitDepth,
        start: task.start,
        endInclusive: task.endInclusive,
        bytesReceived: bytesReceived,
        totalMs: requestStopwatch.elapsedMilliseconds,
        localWriteMs: localWriteMs,
        flushCount: flushCount,
        flushWriteMs: flushWriteMs,
        wasSlow: false,
        wasStalled: true,
      );
      return _buildRetryOutcome(
        runtime: runtime,
        task: task,
        bytesReceived: bytesReceived,
        workerId: workerId,
        strategy: strategy,
        nextTaskIdBuilder: nextTaskIdBuilder,
      );
    } on DioException catch (error) {
      await flushBuffer();
      requestStopwatch.stop();
      if (activeRequest.slowSplitRequested) {
        final runtime = _PathDownloadRangeRequestRuntime(
          index: requestIndex,
          workerId: workerId,
          attempt: task.attempt,
          splitDepth: task.splitDepth,
          start: task.start,
          endInclusive: task.endInclusive,
          bytesReceived: bytesReceived,
          totalMs: requestStopwatch.elapsedMilliseconds,
          localWriteMs: localWriteMs,
          flushCount: flushCount,
          flushWriteMs: flushWriteMs,
          wasSlow: true,
          wasStalled: false,
        );
        return _buildRetryOutcome(
          runtime: runtime,
          task: task,
          bytesReceived: bytesReceived,
          workerId: workerId,
          strategy: strategy,
          nextTaskIdBuilder: nextTaskIdBuilder,
          preferredWorkerId: activeRequest.stealingWorkerId,
          preferTailSteal: true,
        );
      }
      if (error.type == DioExceptionType.cancel &&
          shouldCancel?.call() == true) {
        throw const _PathDownloadCancelledException();
      }
      if (error.response?.statusCode ==
          HttpStatus.requestedRangeNotSatisfiable) {
        throw const _RangeRequestRejectedException();
      }
      final runtime = _PathDownloadRangeRequestRuntime(
        index: requestIndex,
        workerId: workerId,
        attempt: task.attempt,
        splitDepth: task.splitDepth,
        start: task.start,
        endInclusive: task.endInclusive,
        bytesReceived: bytesReceived,
        totalMs: requestStopwatch.elapsedMilliseconds,
        localWriteMs: localWriteMs,
        flushCount: flushCount,
        flushWriteMs: flushWriteMs,
        wasSlow: false,
        wasStalled: false,
      );
      return _buildRetryOutcome(
        runtime: runtime,
        task: task,
        bytesReceived: bytesReceived,
        workerId: workerId,
        strategy: strategy,
        nextTaskIdBuilder: nextTaskIdBuilder,
      );
    }
  }

  _RangeDownloadOutcome _buildRetryOutcome({
    required _PathDownloadRangeRequestRuntime runtime,
    required _RangeTask task,
    required int bytesReceived,
    required int workerId,
    required PathDownloadStrategy strategy,
    required int Function() nextTaskIdBuilder,
    int? preferredWorkerId,
    bool preferTailSteal = false,
  }) {
    final remainingStart = task.start + bytesReceived;
    if (remainingStart > task.endInclusive) {
      return _RangeDownloadOutcome(
        runtime: runtime,
        followUpTasks: const <_RangeTask>[],
        retryTriggered: false,
        wasSplit: false,
      );
    }

    final remainingBytes = task.endInclusive - remainingStart + 1;
    final canSplit = remainingBytes >= strategy.minimumChunkSizeBytes * 2;
    if (task.attempt >= strategy.maxTaskRetries &&
        !canSplit &&
        !preferTailSteal) {
      throw const _PathDownloadRetryLimitExceededException();
    }

    final nextAttempt =
        task.attempt >= strategy.maxTaskRetries && preferTailSteal
        ? task.attempt
        : task.attempt + 1;
    if (canSplit) {
      final midpoint = remainingStart + (remainingBytes ~/ 2) - 1;
      return _RangeDownloadOutcome(
        runtime: runtime,
        followUpTasks: <_RangeTask>[
          _RangeTask(
            id: nextTaskIdBuilder(),
            start: remainingStart,
            endInclusive: midpoint,
            attempt: nextAttempt,
            splitDepth: task.splitDepth + 1,
            originWorkerId: workerId,
            preferredWorkerId: preferTailSteal ? workerId : null,
          ),
          _RangeTask(
            id: nextTaskIdBuilder(),
            start: midpoint + 1,
            endInclusive: task.endInclusive,
            attempt: nextAttempt,
            splitDepth: task.splitDepth + 1,
            originWorkerId: workerId,
            preferredWorkerId: preferTailSteal ? preferredWorkerId : null,
          ),
        ],
        retryTriggered: true,
        wasSplit: true,
      );
    }

    return _RangeDownloadOutcome(
      runtime: runtime,
      followUpTasks: <_RangeTask>[
        _RangeTask(
          id: nextTaskIdBuilder(),
          start: remainingStart,
          endInclusive: task.endInclusive,
          attempt: nextAttempt,
          splitDepth: task.splitDepth,
          originWorkerId: workerId,
          preferredWorkerId: preferTailSteal ? preferredWorkerId : null,
        ),
      ],
      retryTriggered: true,
      wasSplit: false,
    );
  }

  bool _maybeScheduleSlowRangeSplit({
    required int idleWorkerId,
    required PathDownloadStrategy strategy,
    required _RangeTaskQueue taskQueue,
    required Map<int, _ActiveRangeRequest> activeRequests,
    required double bestObservedThroughputBytesPerSecond,
  }) {
    if (taskQueue.isNotEmpty || activeRequests.isEmpty) {
      return false;
    }

    final referenceThroughput = _resolveReferenceThroughput(
      strategy: strategy,
      activeRequests: activeRequests,
      bestObservedThroughputBytesPerSecond:
          bestObservedThroughputBytesPerSecond,
    );
    if (referenceThroughput <= 0) {
      return false;
    }

    _ActiveRangeRequest? candidate;
    var candidateRatio = 1.0;
    var candidateRemainingBytes = 0;
    for (final activeRequest in activeRequests.values) {
      if (activeRequest.workerId == idleWorkerId ||
          activeRequest.slowSplitRequested ||
          activeRequest.elapsedMilliseconds <
              strategy.slowRangeGracePeriod.inMilliseconds ||
          activeRequest.remainingBytesEstimate <
              strategy.minimumChunkSizeBytes ||
          !activeRequest.hasEnoughObservation(strategy)) {
        continue;
      }
      final throughput = activeRequest.throughputBytesPerSecond;
      final ratio = throughput / referenceThroughput;
      if (ratio >= strategy.slowRangeThroughputRatio) {
        continue;
      }
      if (candidate == null ||
          ratio < candidateRatio ||
          (ratio == candidateRatio &&
              activeRequest.remainingBytesEstimate > candidateRemainingBytes)) {
        candidate = activeRequest;
        candidateRatio = ratio;
        candidateRemainingBytes = activeRequest.remainingBytesEstimate;
      }
    }

    if (candidate == null) {
      return false;
    }
    candidate.requestSlowSplit(idleWorkerId);
    return true;
  }

  double _resolveReferenceThroughput({
    required PathDownloadStrategy strategy,
    required Map<int, _ActiveRangeRequest> activeRequests,
    required double bestObservedThroughputBytesPerSecond,
  }) {
    var referenceThroughput = bestObservedThroughputBytesPerSecond;
    for (final activeRequest in activeRequests.values) {
      if (!activeRequest.hasEnoughObservation(strategy)) {
        continue;
      }
      if (activeRequest.throughputBytesPerSecond > referenceThroughput) {
        referenceThroughput = activeRequest.throughputBytesPerSecond;
      }
    }
    return referenceThroughput;
  }

  List<_RangeTask> _buildInitialTasks({
    required int totalBytes,
    required int chunkSize,
  }) {
    final tasks = <_RangeTask>[];
    var nextTaskId = 0;
    var start = 0;
    while (start < totalBytes) {
      final end = math.min(start + chunkSize, totalBytes) - 1;
      tasks.add(
        _RangeTask(
          id: nextTaskId,
          start: start,
          endInclusive: end,
          attempt: 1,
          splitDepth: 0,
        ),
      );
      nextTaskId += 1;
      start = end + 1;
    }
    return tasks;
  }

  int _nonNegativeMs(int value) {
    return value < 0 ? 0 : value;
  }
}

class _RangeDownloadProgress {
  _RangeDownloadProgress({required this.totalBytes, this.callback});

  final int totalBytes;
  final ProgressCallback? callback;
  int _receivedBytes = 0;

  void add(int byteCount) {
    _receivedBytes += byteCount;
    callback?.call(_receivedBytes, totalBytes);
  }

  void complete() {
    callback?.call(totalBytes, totalBytes);
  }
}

class _RangeTask {
  const _RangeTask({
    required this.id,
    required this.start,
    required this.endInclusive,
    required this.attempt,
    required this.splitDepth,
    this.originWorkerId,
    this.preferredWorkerId,
  });

  final int id;
  final int start;
  final int endInclusive;
  final int attempt;
  final int splitDepth;
  final int? originWorkerId;
  final int? preferredWorkerId;

  int get length => endInclusive - start + 1;
}

class _RangeTaskQueue {
  _RangeTaskQueue(List<_RangeTask> tasks)
    : _tasks = List<_RangeTask>.from(tasks);

  final List<_RangeTask> _tasks;

  int get length => _tasks.length;
  bool get isNotEmpty => _tasks.isNotEmpty;
  int get nextTaskId =>
      _tasks.fold<int>(0, (maxId, task) => math.max(maxId, task.id + 1));

  _RangeTask? takeNext(int workerId) {
    if (_tasks.isEmpty) {
      return null;
    }
    final preferredTasks = _tasks
        .where((task) => task.preferredWorkerId == workerId)
        .toList(growable: false);
    if (preferredTasks.isNotEmpty) {
      preferredTasks.sort((left, right) => right.length.compareTo(left.length));
      final selectedTask = preferredTasks.first;
      _tasks.remove(selectedTask);
      return selectedTask;
    }
    _tasks.sort((left, right) => right.length.compareTo(left.length));
    return _tasks.removeAt(0);
  }

  void addAll(Iterable<_RangeTask> tasks) {
    _tasks.addAll(tasks);
  }
}

class _ActiveRangeRequest {
  _ActiveRangeRequest({required this.task, required this.workerId})
    : cancelToken = CancelToken(),
      _stopwatch = Stopwatch()..start();

  final _RangeTask task;
  final int workerId;
  final CancelToken cancelToken;
  final Stopwatch _stopwatch;
  int observedBytesReceived = 0;
  bool slowSplitRequested = false;
  int? stealingWorkerId;

  int get elapsedMilliseconds => _stopwatch.elapsedMilliseconds;
  int get remainingBytesEstimate =>
      math.max(0, task.length - observedBytesReceived);
  double get throughputBytesPerSecond {
    final elapsedMs = elapsedMilliseconds;
    if (elapsedMs <= 0) {
      return 0;
    }
    return observedBytesReceived * 1000 / elapsedMs;
  }

  bool hasEnoughObservation(PathDownloadStrategy strategy) {
    if (observedBytesReceived >= strategy.slowRangeMinimumBytes) {
      return true;
    }
    return elapsedMilliseconds >=
        strategy.slowRangeGracePeriod.inMilliseconds * 2;
  }

  void recordNetworkBytes(int byteCount) {
    observedBytesReceived += byteCount;
  }

  void requestSlowSplit(int idleWorkerId) {
    if (slowSplitRequested) {
      return;
    }
    slowSplitRequested = true;
    stealingWorkerId = idleWorkerId;
    cancelToken.cancel('slow-range-split');
  }
}

class _RangeDownloadOutcome {
  const _RangeDownloadOutcome({
    required this.runtime,
    required this.followUpTasks,
    required this.retryTriggered,
    required this.wasSplit,
  });

  final _PathDownloadRangeRequestRuntime runtime;
  final List<_RangeTask> followUpTasks;
  final bool retryTriggered;
  final bool wasSplit;
}

class _PathDownloadRangeRequestRuntime {
  const _PathDownloadRangeRequestRuntime({
    required this.index,
    required this.workerId,
    required this.attempt,
    required this.splitDepth,
    required this.start,
    required this.endInclusive,
    required this.bytesReceived,
    required this.totalMs,
    required this.localWriteMs,
    required this.flushCount,
    required this.flushWriteMs,
    required this.wasSlow,
    required this.wasStalled,
  });

  final int index;
  final int workerId;
  final int attempt;
  final int splitDepth;
  final int start;
  final int endInclusive;
  final int bytesReceived;
  final int totalMs;
  final int localWriteMs;
  final int flushCount;
  final int flushWriteMs;
  final bool wasSlow;
  final bool wasStalled;

  double get throughputBytesPerSecond {
    if (totalMs <= 0) {
      return 0;
    }
    return bytesReceived * 1000 / totalMs;
  }

  PathDownloadRangeRequestDiagnostics toDiagnostics() {
    return PathDownloadRangeRequestDiagnostics(
      index: index,
      workerId: workerId,
      attempt: attempt,
      splitDepth: splitDepth,
      start: start,
      endInclusive: endInclusive,
      bytesReceived: bytesReceived,
      totalMs: totalMs,
      networkReceiveMs: totalMs - localWriteMs < 0 ? 0 : totalMs - localWriteMs,
      localWriteMs: localWriteMs,
      flushCount: flushCount,
      flushWriteMs: flushWriteMs,
      wasSlow: wasSlow,
      wasStalled: wasStalled,
      wasRetried: attempt > 1,
    );
  }
}

class _PathDownloadWorkerRuntime {
  _PathDownloadWorkerRuntime(this.workerId, this.fileHandle);

  final int workerId;
  final RandomAccessFile fileHandle;
  int requestCount = 0;
  int bytesReceived = 0;
  int slowRangeCount = 0;
  int stallCount = 0;
  int retryCount = 0;
  int stealCount = 0;
  bool retired = false;

  PathDownloadWorkerDiagnostics toDiagnostics() {
    return PathDownloadWorkerDiagnostics(
      workerId: workerId,
      requestCount: requestCount,
      bytesReceived: bytesReceived,
      slowRangeCount: slowRangeCount,
      stallCount: stallCount,
      retryCount: retryCount,
      stealCount: stealCount,
      retired: retired,
    );
  }
}

class _PathDownloadCancelledException implements Exception {
  const _PathDownloadCancelledException();
}

class _RangeRequestRejectedException implements Exception {
  const _RangeRequestRejectedException();
}

class _PathDownloadRetryLimitExceededException implements Exception {
  const _PathDownloadRetryLimitExceededException();
}
