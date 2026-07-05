import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

import '../../../../core/network/download_diagnostics.dart';
import '../../../../core/network/dio_path_download_service.dart';
import '../../../../core/network/nas_api_client.dart';
import '../../../../core/network/progress_callback_throttler.dart';
import '../../../../core/network/trusted_server_http_client_factory.dart';
import '../../../../core/transfer/client_transfer_tuning.dart';
import '../../domain/entities/relay_transfer_entity.dart';
import '../models/relay_transfer_dto.dart';

class RelayWebdavTransportClient {
  RelayWebdavTransportClient({
    required NasApiClient apiClient,
    bool useHttp2 = false,
  }) : _apiClient = apiClient,
       _dio = _createDio(apiClient.dio, useHttp2);

  final NasApiClient _apiClient;
  final Dio _dio;
  late final DioPathDownloadService _pathDownloadService =
      DioPathDownloadService(dio: _dio);

  /// 创建配置好的 Dio 实例
  static Dio _createDio(Dio baseDio, bool useHttp2) {
    final dio = Dio(baseDio.options);

    final baseUrl = baseDio.options.baseUrl;
    final trustedHttpClientFactory = _tryReadTrustedHttpClientFactory(baseDio);

    if (useHttp2 &&
        trustedHttpClientFactory == null &&
        Uri.parse(baseUrl).scheme == 'https') {
      // 使用 HTTP/2 Adapter
      dio.httpClientAdapter = Http2Adapter(
        ConnectionManager(idleTimeout: const Duration(minutes: 5)),
      );
    } else {
      if (trustedHttpClientFactory != null &&
          Uri.parse(baseUrl).scheme == 'https') {
        trustedHttpClientFactory.configureDio(
          dio,
          baseUrl: baseUrl,
          maxConnectionsPerHost: 12,
        );
      } else {
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.maxConnectionsPerHost = 12;
            return client;
          },
        );
      }
    }

    // 复制拦截器
    dio.interceptors.addAll(baseDio.interceptors);

    return dio;
  }

  static TrustedServerHttpClientFactory? _tryReadTrustedHttpClientFactory(
    Dio baseDio,
  ) {
    final options = baseDio.options.extra['trustedHttpClientFactory'];
    return options is TrustedServerHttpClientFactory ? options : null;
  }

  Future<RelayTransferEntity> uploadFile({
    required String relayPath,
    required String localPath,
    ProgressCallback? onSendProgress,
  }) async {
    final file = File(localPath);
    final fileLength = await file.length();
    final progressThrottler = ClientTransferTuning.uploadProgressThrottler();
    final response = await _dio.put<Map<String, dynamic>>(
      _resolveUrl(relayPath),
      data: ClientTransferTuning.bufferUploadStream(file.openRead()),
      options: Options(
        headers: <String, dynamic>{
          'Content-Length': '$fileLength',
          'Content-Type': 'application/octet-stream',
        },
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
      onSendProgress: (sent, total) {
        progressThrottler.report(
          sent,
          totalBytes: total > 0 ? total : fileLength,
          onProgress: onSendProgress,
        );
      },
    );
    progressThrottler.complete(
      transferredBytes: fileLength,
      totalBytes: fileLength,
      onProgress: onSendProgress,
    );
    return RelayTransferDto.parseEnvelopeTransfer(
      response.data,
      context: 'webdavUploadPut',
    );
  }

  Future<void> uploadThumbnail({
    required String relayPath,
    required String thumbnailPath,
    ProgressCallback? onSendProgress,
  }) async {
    final file = File(thumbnailPath);
    final fileLength = await file.length();
    final contentType = thumbnailPath.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    final url = _resolveUrl(relayPath);
    final progressThrottler = ClientTransferTuning.uploadProgressThrottler();
    try {
      await _dio.put<dynamic>(
        url,
        data: ClientTransferTuning.bufferUploadStream(file.openRead()),
        options: Options(
          headers: <String, dynamic>{
            'Content-Length': '$fileLength',
            'Content-Type': contentType,
          },
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
        onSendProgress: (sent, total) {
          progressThrottler.report(
            sent,
            totalBytes: total > 0 ? total : fileLength,
            onProgress: onSendProgress,
          );
        },
      );
      progressThrottler.complete(
        transferredBytes: fileLength,
        totalBytes: fileLength,
        onProgress: onSendProgress,
      );

    } catch (error) {

      rethrow;
    }
  }

  Future<PathDownloadResult> downloadToPath({
    required String relayPath,
    required String savePath,
    required int expectedSize,
    required bool supportsRange,
    ProgressCallback? onReceiveProgress,
    PathDownloadStrategy strategy = PathDownloadStrategy.relayDownloadDefault,
  }) async {
    final isThumbnail = _isThumbnailRelayPath(relayPath);
    final url = _resolveUrl(relayPath);

    int totalBytes;
    if (expectedSize > 0) {
      totalBytes = expectedSize;
    } else if (isThumbnail) {

      totalBytes = 0;
    } else {
      totalBytes = await _resolveDownloadSize(relayPath);
    }
    final progressThrottler = ProgressCallbackThrottler();
    try {
      final result = await _pathDownloadService.downloadToPath(
        url: url,
        savePath: savePath,
        expectedSize: totalBytes,
        supportsRange: supportsRange,
        onReceiveProgress: (received, total) {
          progressThrottler.report(
            received,
            totalBytes: totalBytes > 0 ? totalBytes : total,
            onProgress: onReceiveProgress,
          );
        },
        strategy: strategy,
      );
      progressThrottler.complete(
        transferredBytes: totalBytes,
        totalBytes: totalBytes,
        onProgress: onReceiveProgress,
      );
      return result;
    } catch (error) {

      rethrow;
    }
  }

  Future<int> _resolveDownloadSize(String relayPath) async {
    final url = _resolveUrl(relayPath);

    try {
      final response = await _dio.head<dynamic>(
        url,
        options: Options(
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
      final contentLength =
          int.tryParse(response.headers.value('content-length') ?? '0') ?? 0;

      return contentLength;
    } catch (error) {

      rethrow;
    }
  }

  bool _isThumbnailRelayPath(String relayPath) {
    final normalized = relayPath.toLowerCase();
    return normalized.contains('/thumbnail') || normalized.endsWith('/thumb');
  }

  String _resolveUrl(String relayPath) {
    final baseUri = Uri.parse(_apiClient.baseUrl);
    return baseUri.resolve(relayPath).toString();
  }
}
