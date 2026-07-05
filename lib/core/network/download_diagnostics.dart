class PathDownloadResult {
  const PathDownloadResult({
    required this.usedConcurrentRanges,
    required this.diagnostics,
  });

  final bool usedConcurrentRanges;
  final PathDownloadDiagnostics diagnostics;
}

class PathDownloadDiagnostics {
  const PathDownloadDiagnostics({
    required this.usedConcurrentRanges,
    required this.totalBytes,
    required this.totalMs,
    required this.filePreparationMs,
    required this.networkReceiveMs,
    required this.localWriteMs,
    required this.flushCount,
    required this.flushWriteMs,
    required this.configuredConcurrency,
    required this.effectiveConcurrency,
    required this.initialChunkSizeBytes,
    required this.minimumChunkSizeBytes,
    required this.slowRangeCount,
    required this.retryCount,
    required this.stallCount,
    required this.splitCount,
    required this.requeueCount,
    required this.stealCount,
    required this.rangeRequests,
    required this.workers,
  });

  final bool usedConcurrentRanges;
  final int totalBytes;
  final int totalMs;
  final int filePreparationMs;
  final int networkReceiveMs;
  final int localWriteMs;
  final int flushCount;
  final int flushWriteMs;
  final int configuredConcurrency;
  final int effectiveConcurrency;
  final int initialChunkSizeBytes;
  final int minimumChunkSizeBytes;
  final int slowRangeCount;
  final int retryCount;
  final int stallCount;
  final int splitCount;
  final int requeueCount;
  final int stealCount;
  final List<PathDownloadRangeRequestDiagnostics> rangeRequests;
  final List<PathDownloadWorkerDiagnostics> workers;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'usedConcurrentRanges': usedConcurrentRanges,
      'totalBytes': totalBytes,
      'totalMs': totalMs,
      'filePreparationMs': filePreparationMs,
      'networkReceiveMs': networkReceiveMs,
      'localWriteMs': localWriteMs,
      'flushCount': flushCount,
      'flushWriteMs': flushWriteMs,
      'configuredConcurrency': configuredConcurrency,
      'effectiveConcurrency': effectiveConcurrency,
      'initialChunkSizeBytes': initialChunkSizeBytes,
      'minimumChunkSizeBytes': minimumChunkSizeBytes,
      'slowRangeCount': slowRangeCount,
      'retryCount': retryCount,
      'stallCount': stallCount,
      'splitCount': splitCount,
      'requeueCount': requeueCount,
      'stealCount': stealCount,
      'rangeRequestCount': rangeRequests.length,
      'rangeRequests': rangeRequests
          .map((request) => request.toJson())
          .toList(growable: false),
      'workerCount': workers.length,
      'workers': workers
          .map((worker) => worker.toJson())
          .toList(growable: false),
    };
  }
}

class PathDownloadRangeRequestDiagnostics {
  const PathDownloadRangeRequestDiagnostics({
    required this.index,
    required this.workerId,
    required this.attempt,
    required this.splitDepth,
    required this.start,
    required this.endInclusive,
    required this.bytesReceived,
    required this.totalMs,
    required this.networkReceiveMs,
    required this.localWriteMs,
    required this.flushCount,
    required this.flushWriteMs,
    required this.wasSlow,
    required this.wasStalled,
    required this.wasRetried,
  });

  final int index;
  final int workerId;
  final int attempt;
  final int splitDepth;
  final int start;
  final int endInclusive;
  final int bytesReceived;
  final int totalMs;
  final int networkReceiveMs;
  final int localWriteMs;
  final int flushCount;
  final int flushWriteMs;
  final bool wasSlow;
  final bool wasStalled;
  final bool wasRetried;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'index': index,
      'workerId': workerId,
      'attempt': attempt,
      'splitDepth': splitDepth,
      'start': start,
      'endInclusive': endInclusive,
      'bytesReceived': bytesReceived,
      'totalMs': totalMs,
      'networkReceiveMs': networkReceiveMs,
      'localWriteMs': localWriteMs,
      'flushCount': flushCount,
      'flushWriteMs': flushWriteMs,
      'wasSlow': wasSlow,
      'wasStalled': wasStalled,
      'wasRetried': wasRetried,
    };
  }
}

class PathDownloadWorkerDiagnostics {
  const PathDownloadWorkerDiagnostics({
    required this.workerId,
    required this.requestCount,
    required this.bytesReceived,
    required this.slowRangeCount,
    required this.stallCount,
    required this.retryCount,
    required this.stealCount,
    required this.retired,
  });

  final int workerId;
  final int requestCount;
  final int bytesReceived;
  final int slowRangeCount;
  final int stallCount;
  final int retryCount;
  final int stealCount;
  final bool retired;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'workerId': workerId,
      'requestCount': requestCount,
      'bytesReceived': bytesReceived,
      'slowRangeCount': slowRangeCount,
      'stallCount': stallCount,
      'retryCount': retryCount,
      'stealCount': stealCount,
      'retired': retired,
    };
  }
}
