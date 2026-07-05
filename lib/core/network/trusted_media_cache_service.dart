import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../error/app_exception.dart';
import 'trusted_server_http_client_factory.dart';

class TrustedMediaCacheService {
  TrustedMediaCacheService({
    required TrustedServerHttpClientFactory trustedHttpClientFactory,
  }) : _trustedHttpClientFactory = trustedHttpClientFactory;

  static const String _cacheDirectoryName = 'trusted_media_cache';
  static const int _maxCacheSizeBytes = 500 << 20;

  final TrustedServerHttpClientFactory _trustedHttpClientFactory;
  final Map<String, Future<File>> _inflightDownloads = <String, Future<File>>{};

  Future<File?> getCachedFile({
    required String url,
    required String cacheKey,
  }) async {
    final file = await _resolveCacheFile(url: url, cacheKey: cacheKey);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<File> cacheFile({
    required String url,
    required String cacheKey,
    Map<String, String>? headers,
    bool forceRefresh = false,
  }) async {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      throw const AppException(
        code: 'MEDIA_URL_EMPTY',
        message: '媒体地址为空，无法建立 HTTPS 连接。',
      );
    }

    final file = await _resolveCacheFile(
      url: normalizedUrl,
      cacheKey: cacheKey,
    );
    if (!forceRefresh && await file.exists()) {
      return file;
    }

    final inflightKey = '$cacheKey|$normalizedUrl';
    final inflight = _inflightDownloads[inflightKey];
    if (inflight != null) {
      return inflight;
    }

    final future = _downloadToFile(
      url: normalizedUrl,
      cacheFile: file,
      headers: headers,
      forceRefresh: forceRefresh,
    );
    _inflightDownloads[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflightDownloads.remove(inflightKey);
    }
  }

  Future<bool> clearCachedFile({
    required String url,
    required String cacheKey,
  }) async {
    try {
      final file = await _resolveCacheFile(url: url, cacheKey: cacheKey);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> _downloadToFile({
    required String url,
    required File cacheFile,
    required Map<String, String>? headers,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && await cacheFile.exists()) {
      return cacheFile;
    }

    final uri = Uri.parse(url);
    final client = _createHttpClient(uri);
    final tempFile = File('${cacheFile.path}.part');
    RandomAccessFile? output;

    try {
      await cacheFile.parent.create(recursive: true);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final request = await client.getUrl(uri);
      _applyHeaders(request, headers);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain();
        throw AppException(
          code: 'MEDIA_DOWNLOAD_FAILED',
          message: '媒体资源请求失败（HTTP ${response.statusCode}）。',
        );
      }

      output = await tempFile.open(mode: FileMode.write);
      await for (final chunk in response) {
        await output.writeFrom(chunk);
      }
      await output.close();
      output = null;

      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      final finalFile = await tempFile.rename(cacheFile.path);
      unawaited(_evictIfNeeded());
      return finalFile;
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException(code: 'MEDIA_CACHE_FAILED', message: '媒体缓存失败：$error');
    } finally {
      client.close(force: true);
      await output?.close();
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<File> _resolveCacheFile({
    required String url,
    required String cacheKey,
  }) async {
    final directory = await _cacheDirectory();
    final fileName = _buildFileName(url: url, cacheKey: cacheKey);
    return File(p.join(directory.path, fileName));
  }

  Future<Directory> _cacheDirectory() async {
    final baseDirectory = await getTemporaryDirectory();
    return Directory(p.join(baseDirectory.path, _cacheDirectoryName));
  }

  String _buildFileName({required String url, required String cacheKey}) {
    return buildFileNameForTesting(url: url, cacheKey: cacheKey);
  }

  static String buildFileNameForTesting({
    required String url,
    required String cacheKey,
  }) {
    final keyLabel = _buildCacheKeyLabel(cacheKey);
    final digest = crypto.sha256
        .convert(utf8.encode('$keyLabel|$cacheKey|$url'))
        .toString();
    final extension = p.extension(Uri.parse(url).path);
    return '${keyLabel}_$digest${extension.isEmpty ? '.bin' : extension}';
  }

  static String _buildCacheKeyLabel(String cacheKey) {
    final raw = cacheKey.split(':').first.trim().toLowerCase();
    final sanitized = raw.replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    if (sanitized.isEmpty) {
      return 'media';
    }
    return sanitized.length <= 24 ? sanitized : sanitized.substring(0, 24);
  }

  HttpClient _createHttpClient(Uri uri) {
    if (uri.scheme != 'https') {
      throw const AppException(
        code: 'HTTP_ADDRESS_NOT_ALLOWED',
        message: '当前版本仅允许通过 HTTPS 缓存媒体资源。',
      );
    }
    return _trustedHttpClientFactory.createHttpClient(baseUrl: uri.toString());
  }

  void _applyHeaders(HttpClientRequest request, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return;
    }
    headers.forEach(request.headers.set);
  }

  Future<void> _evictIfNeeded() async {
    try {
      final directory = await _cacheDirectory();
      if (!await directory.exists()) {
        return;
      }
      final files = await directory.list().toList();
      var totalSize = 0;
      final entries = <_CacheEntry>[];
      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
          entries.add(_CacheEntry(file: entity, lastModified: stat.modified));
        }
      }
      if (totalSize <= _maxCacheSizeBytes) {
        return;
      }
      entries.sort((a, b) => a.lastModified.compareTo(b.lastModified));
      for (final entry in entries) {
        if (totalSize <= _maxCacheSizeBytes) {
          break;
        }
        try {
          final stat = await entry.file.stat();
          totalSize -= stat.size;
          await entry.file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

class _CacheEntry {
  final File file;
  final DateTime lastModified;
  const _CacheEntry({required this.file, required this.lastModified});
}
