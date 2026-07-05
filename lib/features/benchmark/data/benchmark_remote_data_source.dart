import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../../core/network/download_diagnostics.dart';
import '../../../core/network/dio_path_download_service.dart';
import '../../../core/network/nas_api_client.dart';
import '../../../core/transfer/client_transfer_tuning.dart';
import '../domain/benchmark_models.dart';

class BenchmarkRemoteDataSource {
  BenchmarkRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient,
      _pathDownloadService = DioPathDownloadService(dio: apiClient.dio);

  final NasApiClient _apiClient;
  final DioPathDownloadService _pathDownloadService;

  String get baseUrl => _apiClient.baseUrl;

  Dio? _httpDio;
  String? _httpBaseUrl;

  Future<BenchmarkSessionInfo> createSession({
    required BenchmarkTransferMode mode,
    required BenchmarkTransportType transportType,
    required int fileSizeBytes,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/debug/benchmark/sessions',
      data: <String, dynamic>{
        'mode': mode.name,
        'transportType': transportType.name,
        'fileSizeBytes': fileSizeBytes,
      },
    );
    return BenchmarkSessionInfo.fromEnvelope(response);
  }

  void configureHttp({
    required String baseUrl,
  }) {
    if (_httpBaseUrl == baseUrl && _httpDio != null) {
      return;
    }
    _httpDio?.close();
    _httpBaseUrl = baseUrl;
    _httpDio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 30),
    ));
    _httpDio!.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient(),
    );
  }

  void disposeHttp() {
    _httpDio?.close();
    _httpDio = null;
    _httpBaseUrl = null;
  }

  Future<Map<String, dynamic>> uploadArtifact({
    required String sessionId,
    required String filePath,
    required int totalSize,
    ProgressCallback? onSendProgress,
    String? uploadPath,
    bool useHttp = false,
  }) async {
    final dio = useHttp ? _httpDio! : _apiClient.dio;
    final progressThrottler = ClientTransferTuning.uploadProgressThrottler();
    final response = await dio.put<Map<String, dynamic>>(
      uploadPath ?? '/api/v1/debug/benchmark/sessions/$sessionId/upload',
      data: ClientTransferTuning.bufferUploadStream(File(filePath).openRead()),
      options: Options(
        headers: <String, dynamic>{'Content-Length': '$totalSize'},
        contentType: 'application/octet-stream',
        sendTimeout: const Duration(minutes: 30),
        receiveTimeout: const Duration(minutes: 30),
      ),
      onSendProgress: (sent, total) {
        progressThrottler.report(
          sent,
          totalBytes: total > 0 ? total : totalSize,
          onProgress: onSendProgress,
        );
      },
    );
    progressThrottler.complete(
      transferredBytes: totalSize,
      totalBytes: totalSize,
      onProgress: onSendProgress,
    );
    return _normalizeJsonMap(response.data);
  }

  Future<PathDownloadResult> downloadArtifact({
    required String sessionId,
    required String savePath,
    required int expectedSize,
    ProgressCallback? onReceiveProgress,
    PathDownloadStrategy strategy = DioPathDownloadService.defaultStrategy,
    String? downloadPath,
    bool supportsRange = true,
    bool useHttp = false,
  }) async {
    if (useHttp) {
      final httpDownloadService = DioPathDownloadService(dio: _httpDio!);
      return httpDownloadService.downloadToPath(
        url: downloadPath ??
            '/api/v1/debug/benchmark/sessions/$sessionId/download',
        savePath: savePath,
        expectedSize: expectedSize,
        supportsRange: supportsRange,
        onReceiveProgress: onReceiveProgress,
        strategy: strategy,
      );
    }
    return _pathDownloadService.downloadToPath(
      url: downloadPath ??
          '/api/v1/debug/benchmark/sessions/$sessionId/download',
      savePath: savePath,
      expectedSize: expectedSize,
      supportsRange: supportsRange,
      onReceiveProgress: onReceiveProgress,
      strategy: strategy,
    );
  }

  Future<Map<String, dynamic>> submitClientReport({
    required String sessionId,
    required Map<String, dynamic> clientReport,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/debug/benchmark/sessions/$sessionId/client-report',
      data: <String, dynamic>{'clientReport': clientReport},
    );
    return response;
  }

  Future<Map<String, dynamic>> loadSessionResult(String sessionId) async {
    return _apiClient.get<Map<String, dynamic>>(
      '/api/v1/debug/benchmark/sessions/$sessionId',
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await _apiClient.dio.delete<void>(
      '/api/v1/debug/benchmark/sessions/$sessionId',
    );
  }

  Map<String, dynamic> _normalizeJsonMap(dynamic value) {
    return switch (value) {
      Map<String, dynamic> map => map,
      Map<dynamic, dynamic> map => map.map(
        (key, entryValue) => MapEntry('$key', entryValue),
      ),
      _ => <String, dynamic>{},
    };
  }
}
