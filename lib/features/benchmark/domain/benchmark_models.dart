import 'dart:convert';

import '../../../core/network/dio_path_download_service.dart';

enum BenchmarkTransferMode { upload, download }

enum BenchmarkTransportType { direct, directDav, directHttp, directDavHttp, relay }

enum BenchmarkRelayRole { sender, receiver }

class BenchmarkExecutionOptions {
  const BenchmarkExecutionOptions({
    required this.fileSizeBytes,
    required this.mode,
    this.transportType = BenchmarkTransportType.direct,
    this.saveDownloadToPublicStorage = false,
    this.keepTemporaryFile = false,
    this.relayPeerClientId,
    this.downloadConcurrency =
        PathDownloadStrategy.defaultPreferredConcurrentRequests,
    this.downloadInitialChunkSizeBytes =
        PathDownloadStrategy.defaultInitialChunkSizeBytes,
    this.downloadMinimumChunkSizeBytes =
        PathDownloadStrategy.defaultMinimumChunkSizeBytes,
    this.downloadStallTimeout = PathDownloadStrategy.defaultStallTimeout,
  });

  final int fileSizeBytes;
  final BenchmarkTransferMode mode;
  final BenchmarkTransportType transportType;
  final bool saveDownloadToPublicStorage;
  final bool keepTemporaryFile;
  final String? relayPeerClientId;
  final int downloadConcurrency;
  final int downloadInitialChunkSizeBytes;
  final int downloadMinimumChunkSizeBytes;
  final Duration downloadStallTimeout;
}

class BenchmarkSessionEndpoints {
  const BenchmarkSessionEndpoints({
    required this.uploadPath,
    required this.downloadPath,
    required this.reportPath,
    required this.resultPath,
    this.davUploadPath,
    this.davDownloadPath,
    this.httpPort,
  });

  final String uploadPath;
  final String downloadPath;
  final String reportPath;
  final String resultPath;
  final String? davUploadPath;
  final String? davDownloadPath;
  final int? httpPort;

  factory BenchmarkSessionEndpoints.fromJson(
    Map<String, dynamic>? json, {
    required String sessionId,
  }) {
    final fallbackUploadPath =
        '/api/v1/debug/benchmark/sessions/$sessionId/upload';
    final fallbackDownloadPath =
        '/api/v1/debug/benchmark/sessions/$sessionId/download';
    final fallbackReportPath =
        '/api/v1/debug/benchmark/sessions/$sessionId/client-report';
    final fallbackResultPath = '/api/v1/debug/benchmark/sessions/$sessionId';
    final normalized = json ?? const <String, dynamic>{};
    return BenchmarkSessionEndpoints(
      uploadPath: normalized['uploadPath'] as String? ?? fallbackUploadPath,
      downloadPath:
          normalized['downloadPath'] as String? ?? fallbackDownloadPath,
      reportPath: normalized['reportPath'] as String? ?? fallbackReportPath,
      resultPath: normalized['resultPath'] as String? ?? fallbackResultPath,
      davUploadPath: normalized['davUploadPath'] as String?,
      davDownloadPath: normalized['davDownloadPath'] as String?,
      httpPort: _readInt(normalized['httpPort']),
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class BenchmarkSessionInfo {
  const BenchmarkSessionInfo({
    required this.sessionId,
    required this.traceId,
    required this.mode,
    required this.transportType,
    required this.fileSizeBytes,
    required this.endpoints,
  });

  final String sessionId;
  final String traceId;
  final BenchmarkTransferMode mode;
  final BenchmarkTransportType transportType;
  final int fileSizeBytes;
  final BenchmarkSessionEndpoints endpoints;

  factory BenchmarkSessionInfo.fromEnvelope(Map<String, dynamic> envelope) {
    final session = envelope['session'];
    if (session is! Map) {
      throw const FormatException('Benchmark response is missing session data');
    }
    final normalized = session is Map<String, dynamic>
        ? session
        : session.map((key, value) => MapEntry('$key', value));
    return BenchmarkSessionInfo(
      sessionId: normalized['sessionId'] as String? ?? '',
      traceId: normalized['traceId'] as String? ?? '',
      mode: BenchmarkTransferMode.values.firstWhere(
        (value) => value.name == normalized['mode'],
        orElse: () => BenchmarkTransferMode.upload,
      ),
      transportType: BenchmarkTransportType.values.firstWhere(
        (value) => value.name == normalized['transportType'],
        orElse: () => BenchmarkTransportType.direct,
      ),
      fileSizeBytes: _readInt(normalized['fileSizeBytes']),
      endpoints: BenchmarkSessionEndpoints.fromJson(
        _optionalMap(envelope['endpoints']),
        sessionId: normalized['sessionId'] as String? ?? '',
      ),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

Map<String, dynamic>? _optionalMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, entryValue) => MapEntry('$key', entryValue));
  }
  return null;
}

class BenchmarkRunResult {
  const BenchmarkRunResult({
    required this.options,
    required this.rawResult,
    this.temporaryFilePath,
    this.publicUri,
  });

  final BenchmarkExecutionOptions options;
  final Map<String, dynamic> rawResult;
  final String? temporaryFilePath;
  final String? publicUri;

  String get prettyJson {
    return const JsonEncoder.withIndent('  ').convert(rawResult);
  }
}
