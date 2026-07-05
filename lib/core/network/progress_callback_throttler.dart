class ProgressCallbackThrottler {
  ProgressCallbackThrottler({
    this.minStepBytes = 512 * 1024,
    this.minInterval = const Duration(milliseconds: 150),
  });

  final int minStepBytes;
  final Duration minInterval;

  int _lastReportedBytes = -1;
  DateTime? _lastReportedAt;

  void report(
    int transferredBytes, {
    int totalBytes = 0,
    void Function(int transferredBytes, int totalBytes)? onProgress,
  }) {
    if (onProgress == null || !_shouldReport(transferredBytes, totalBytes)) {
      return;
    }
    onProgress(transferredBytes, totalBytes);
  }

  void reportValue(
    int transferredBytes, {
    int totalBytes = 0,
    void Function(int transferredBytes)? onProgress,
  }) {
    if (onProgress == null || !_shouldReport(transferredBytes, totalBytes)) {
      return;
    }
    onProgress(transferredBytes);
  }

  void complete({
    required int transferredBytes,
    int totalBytes = 0,
    void Function(int transferredBytes, int totalBytes)? onProgress,
  }) {
    if (onProgress == null || transferredBytes == _lastReportedBytes) {
      return;
    }
    _markReported(transferredBytes);
    onProgress(transferredBytes, totalBytes);
  }

  void completeValue({
    required int transferredBytes,
    void Function(int transferredBytes)? onProgress,
  }) {
    if (onProgress == null || transferredBytes == _lastReportedBytes) {
      return;
    }
    _markReported(transferredBytes);
    onProgress(transferredBytes);
  }

  bool _shouldReport(int transferredBytes, int totalBytes) {
    if (transferredBytes < 0) {
      return false;
    }

    final now = DateTime.now();
    if (_lastReportedBytes < 0) {
      _markReported(transferredBytes, timestamp: now);
      return true;
    }

    if (transferredBytes <= _lastReportedBytes) {
      return false;
    }

    final isTerminal = totalBytes > 0 && transferredBytes >= totalBytes;
    final reachedByteStep =
        transferredBytes - _lastReportedBytes >= minStepBytes;
    final reachedTimeStep =
        now.difference(_lastReportedAt ?? now) >= minInterval;
    if (!isTerminal && !reachedByteStep && !reachedTimeStep) {
      return false;
    }

    _markReported(transferredBytes, timestamp: now);
    return true;
  }

  void _markReported(int transferredBytes, {DateTime? timestamp}) {
    _lastReportedBytes = transferredBytes;
    _lastReportedAt = timestamp ?? DateTime.now();
  }
}
