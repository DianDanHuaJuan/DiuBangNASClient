/// 文件输入：URL、headers、并发数、块大小
/// 文件职责：并发分块下载大文件，支持进度回调
/// 文件对外接口：ChunkedDownloadService
/// 文件包含：ChunkedDownloadService
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../error/app_exception.dart';
import 'trusted_server_http_client_factory.dart';

class ChunkedDownloadService {
  final int maxConcurrentChunks;
  final int chunkSize;
  final TrustedServerHttpClientFactory? _trustedHttpClientFactory;

  ChunkedDownloadService({
    this.maxConcurrentChunks = 4,
    this.chunkSize = 512 * 1024,
    TrustedServerHttpClientFactory? trustedHttpClientFactory,
  }) : _trustedHttpClientFactory = trustedHttpClientFactory;

  Future<Uint8List> download({
    required String url,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse(url);
    final client = _createHttpClient(uri);

    try {
      final totalSize = await _getFileSize(client, uri, headers);

      if (totalSize <= 0 || totalSize <= chunkSize) {
        return _downloadDirect(client, uri, headers, onProgress);
      }

      return _downloadChunked(client, uri, headers, totalSize, onProgress);
    } finally {
      client.close(force: true);
    }
  }

  HttpClient _createHttpClient(Uri uri) {
    if (uri.scheme != 'https') {
      throw const AppException(
        code: 'HTTP_ADDRESS_NOT_ALLOWED',
        message: '当前版本仅允许通过 HTTPS 下载资源。',
      );
    }
    if (_trustedHttpClientFactory != null) {
      return _trustedHttpClientFactory.createHttpClient(baseUrl: uri.toString());
    }
    throw const AppException(
      code: 'TRUSTED_SERVER_REQUIRED',
      message: '未找到服务器 HTTPS 信任信息，无法建立下载连接。',
    );
  }

  Future<int> _getFileSize(
    HttpClient client,
    Uri uri,
    Map<String, String>? headers,
  ) async {
    final request = await client.headUrl(uri);
    _applyHeaders(request, headers);

    final response = await request.close();
    final contentLength = response.contentLength;
    await response.drain();

    return contentLength;
  }

  Future<Uint8List> _downloadDirect(
    HttpClient client,
    Uri uri,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
  ) async {
    final request = await client.getUrl(uri);
    _applyHeaders(request, headers);

    final response = await request.close();
    final chunks = <int>[];

    await for (final chunk in response) {
      chunks.addAll(chunk);
      onProgress?.call(1.0);
    }

    return Uint8List.fromList(chunks);
  }

  Future<Uint8List> _downloadChunked(
    HttpClient client,
    Uri uri,
    Map<String, String>? headers,
    int totalSize,
    void Function(double progress)? onProgress,
  ) async {
    final chunks = <int, Uint8List>{};
    final totalChunks = (totalSize / chunkSize).ceil();
    final downloaded = <int, int>{};

    final semaphore = _Semaphore(maxConcurrentChunks);
    final futures = <Future<void>>[];

    for (var i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize - 1).clamp(0, totalSize - 1);

      futures.add(
        _downloadChunk(
          client: client,
          uri: uri,
          headers: headers,
          index: i,
          start: start,
          end: end,
          semaphore: semaphore,
          onChunkComplete: (index, data) {
            chunks[index] = data;
            downloaded[index] = data.length;

            final totalDownloaded = downloaded.values.fold(0, (a, b) => a + b);
            onProgress?.call(totalDownloaded / totalSize);
          },
        ),
      );
    }

    await Future.wait(futures);

    final result = Uint8List(totalSize);
    var offset = 0;
    for (var i = 0; i < totalChunks; i++) {
      final chunk = chunks[i]!;
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  Future<void> _downloadChunk({
    required HttpClient client,
    required Uri uri,
    required Map<String, String>? headers,
    required int index,
    required int start,
    required int end,
    required _Semaphore semaphore,
    required void Function(int index, Uint8List data) onChunkComplete,
  }) async {
    await semaphore.acquire();

    try {
      final request = await client.getUrl(uri);
      _applyHeaders(request, headers);
      request.headers.set('Range', 'bytes=$start-$end');

      final response = await request.close();
      final chunks = <int>[];

      await for (final chunk in response) {
        chunks.addAll(chunk);
      }

      onChunkComplete(index, Uint8List.fromList(chunks));
    } catch (e) {
      rethrow;
    } finally {
      semaphore.release();
    }
  }

  void _applyHeaders(HttpClientRequest request, Map<String, String>? headers) {
    if (headers == null) return;

    headers.forEach((key, value) {
      if (key.toLowerCase() != 'range') {
        request.headers.set(key, value);
      }
    });
  }
}

class _Semaphore {
  int _permits;
  final List<Completer<void>> _waitQueue = [];

  _Semaphore(this._permits);

  Future<void> acquire() async {
    if (_permits > 0) {
      _permits--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _permits++;
    }
  }
}
