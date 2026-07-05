/// 文件输入：webdav 基础配置、认证头、HTTP 文件访问实现
/// 文件职责：实现 WebDAV 文件访问协议的具体操作
/// 文件对外接口：WebdavFileProtocolClient
/// 文件包含：WebdavFileProtocolClient
import 'dart:convert';
import 'package:dio/dio.dart';
import '../network/dio_path_download_service.dart';
import '../network/dio_debug_logging.dart';
import '../network/auth_headers.dart';
import '../network/trusted_server_http_client_factory.dart';
import '../transfer/client_transfer_tuning.dart';
import '../../features/files/domain/entities/file_entry_entity.dart';
import '../../features/files/domain/entities/file_type.dart';
import '../path/nas_path.dart';
import 'file_protocol_client.dart';
import 'path_download_capable_file_protocol_client.dart';
import 'upload_contract.dart';

class WebdavFileProtocolClient
    implements FileProtocolClient, PathDownloadCapableFileProtocolClient {
  static const int _rangeDownloadThresholdBytes = 16 * 1024 * 1024;
  static const PathDownloadStrategy _downloadStrategy =
      PathDownloadStrategy.directDownloadDefault;

  final Dio _dio;
  final String baseUrl;
  final String? _staticAuthHeader;
  final String? Function()? _authHeaderProvider;
  final Future<String> Function()? _clientIdProvider;
  final Future<String> Function()? _clientNameProvider;
  final TrustedServerHttpClientFactory? _trustedHttpClientFactory;
  late final DioPathDownloadService _pathDownloadService;

  static const Map<String, String> _rootPathPrefixes = {
    'fs': '/dav/fs',
    'library': '/dav/library',
  };

  WebdavFileProtocolClient({
    required this.baseUrl,
    String? authHeader,
    String? Function()? authHeaderProvider,
    String? username,
    String? password,
    Future<String> Function()? clientIdProvider,
    Future<String> Function()? clientNameProvider,
    TrustedServerHttpClientFactory? trustedHttpClientFactory,
    Dio? dio,
  }) : _staticAuthHeader = authHeaderProvider == null
           ? _resolveAuthHeader(
               authHeader: authHeader,
               username: username,
               password: password,
             )
           : authHeader,
       _authHeaderProvider = authHeaderProvider,
       _clientIdProvider = clientIdProvider,
       _clientNameProvider = clientNameProvider,
       _trustedHttpClientFactory = trustedHttpClientFactory,
       _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _trustedHttpClientFactory?.configureDio(
      _dio,
      baseUrl: baseUrl,
      maxConnectionsPerHost: 12,
    );
    attachDioDebugLogging(_dio, channel: 'WebdavFileProtocolClient');
    _pathDownloadService = DioPathDownloadService(dio: _dio);
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['Authorization'] = _currentAuthHeader;
          final clientId = await _resolveClientId();
          if (clientId != null) {
            options.headers[clientIdHeaderName] = clientId;
          }
          final clientName = await _resolveClientName();
          if (clientName != null) {
            options.headers[clientNameHeaderName] = clientName;
          }
          handler.next(options);
        },
      ),
    );
  }

  String get _currentAuthHeader {
    final dynamicHeader = _authHeaderProvider?.call()?.trim();
    if (dynamicHeader != null && dynamicHeader.isNotEmpty) {
      return dynamicHeader;
    }

    final staticHeader = _staticAuthHeader?.trim();
    if (staticHeader != null && staticHeader.isNotEmpty) {
      return staticHeader;
    }

    throw StateError('No authorization header in session');
  }

  Future<String?> _resolveClientId() async {
    final clientIdProvider = _clientIdProvider;
    if (clientIdProvider == null) {
      return null;
    }
    final clientId = (await clientIdProvider()).trim();
    return clientId.isEmpty ? null : clientId;
  }

  Future<String?> _resolveClientName() async {
    final clientNameProvider = _clientNameProvider;
    if (clientNameProvider == null) {
      return null;
    }
    final clientName = (await clientNameProvider()).trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return clientName.isEmpty ? null : clientName;
  }

  String _getRootPathPrefix(String rootId) {
    return _rootPathPrefixes[rootId] ?? '/dav/fs';
  }

  static String _resolveAuthHeader({
    String? authHeader,
    String? username,
    String? password,
  }) {
    final normalizedHeader = authHeader?.trim();
    if (normalizedHeader != null && normalizedHeader.isNotEmpty) {
      return normalizedHeader;
    }
    if (username != null && password != null) {
      final credentials = '$username:$password';
      return 'Basic ${base64Encode(utf8.encode(credentials))}';
    }
    throw ArgumentError(
      'Either authHeader or both username and password must be provided',
    );
  }

  String _buildUrl(NasPath path) {
    final baseUri = Uri.parse(baseUrl);
    final prefixParts = _getRootPathPrefix(path.rootId)
        .split('/')
        .where((segment) => segment.isNotEmpty);
    final uri = Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      pathSegments: [...prefixParts, ...path.segments],
    );
    return uri.toString();
  }

  String _extractRelativePath(String href, String rootId) {
    final prefix = _getRootPathPrefix(rootId);

    // 处理完整 URL 格式：https://192.168.1.10:8080/dav/library/xxx.jpg
    if (href.startsWith(baseUrl + prefix)) {
      return href.substring((baseUrl + prefix).length);
    }

    // 处理相对路径格式：/dav/library/xxx.jpg
    if (href.startsWith(prefix)) {
      return href.substring(prefix.length);
    }

    // 处理只有 baseUrl 的情况：https://192.168.1.10:8080/xxx.jpg
    if (href.startsWith(baseUrl)) {
      return href.substring(baseUrl.length);
    }

    return href;
  }

  @override
  Future<List<FileEntryEntity>> listDirectory(NasPath path) async {
    final url = _buildUrl(path);
    try {
      final response = await _dio.request(
        url,
        options: Options(
          method: 'PROPFIND',
          headers: {'Authorization': _currentAuthHeader, 'Depth': '1'},
        ),
      );
      if (response.statusCode == 207 || response.statusCode == 200) {
        final files = _parseWebDavResponse(response.data, path);
        return files;
      }
      return [];
    } on DioException {
      rethrow;
    }
  }

  List<FileEntryEntity> _parseWebDavResponse(String xml, NasPath nasPath) {
    final List<FileEntryEntity> entries = [];

    final responseRegex = RegExp(
      r'<[a-zA-Z]*:?response[^>]*>(.*?)</[a-zA-Z]*:?response>',
      caseSensitive: false,
      dotAll: true,
    );

    final responseMatches = responseRegex.allMatches(xml);

    for (final responseMatch in responseMatches) {
      final responseBlock = responseMatch.group(1) ?? '';
      if (responseBlock.isEmpty) continue;

      final hrefMatch = RegExp(
        r'<[a-zA-Z]*:?href[^>]*>(.*?)</[a-zA-Z]*:?href>',
        caseSensitive: false,
      ).firstMatch(responseBlock);
      final href = hrefMatch?.group(1) ?? '';
      if (href.isEmpty) continue;

      final displayMatch = RegExp(
        r'<[a-zA-Z]*:?displayname[^>]*>(.*?)</[a-zA-Z]*:?displayname>',
        caseSensitive: false,
      ).firstMatch(responseBlock);
      final displayName = displayMatch?.group(1) ?? href.split('/').last;

      final typeMatch = RegExp(
        r'<[a-zA-Z]*:?resourcetype[^>]*>(.*?)</[a-zA-Z]*:?resourcetype>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(responseBlock);
      final isDirectory = typeMatch?.group(1)?.contains('collection') == true;

      final sizeMatch = RegExp(
        r'<[a-zA-Z]*:?getcontentlength[^>]*>(.*?)</[a-zA-Z]*:?getcontentlength>',
        caseSensitive: false,
      ).firstMatch(responseBlock);
      final sizeStr = sizeMatch?.group(1) ?? '0';

      final modifiedMatch = RegExp(
        r'<[a-zA-Z]*:?getlastmodified[^>]*>(.*?)</[a-zA-Z]*:?getlastmodified>',
        caseSensitive: false,
      ).firstMatch(responseBlock);
      DateTime? modifiedAt;
      if (modifiedMatch != null) {
        try {
          modifiedAt = _parseHttpDate(modifiedMatch.group(1) ?? '');
        } catch (_) {}
      }

      final relativePath = _extractRelativePath(href, nasPath.rootId);

      final normalizedNasPath = nasPath.path.endsWith('/')
          ? nasPath.path
          : '${nasPath.path}/';
      if (relativePath == nasPath.path ||
          relativePath == normalizedNasPath ||
          (relativePath == '/' && nasPath.path == '/')) {
        continue;
      }
      if (relativePath.isEmpty) continue;

      final hasLeading = relativePath.startsWith('/');
      final decodedParts = <String>[];
      for (final p in relativePath.split('/').where((p) => p.isNotEmpty)) {
        try {
          decodedParts.add(Uri.decodeComponent(p));
        } on FormatException {
          decodedParts.add(p);
        }
      }
      final decodedRelativePath = decodedParts.isEmpty
          ? (hasLeading ? '/' : '')
          : '/${decodedParts.join('/')}';

      String decodedDisplayName;
      try {
        decodedDisplayName = Uri.decodeFull(displayName);
      } on FormatException {
        decodedDisplayName = displayName;
      }

      entries.add(
        FileEntryEntity(
          name: decodedDisplayName,
          path: decodedRelativePath,
          type: isDirectory ? FileType.directory : FileType.file,
          size: int.tryParse(sizeStr) ?? 0,
          modifiedAt: modifiedAt,
        ),
      );
    }

    return entries;
  }

  DateTime _parseHttpDate(String date) {
    try {
      return DateTime.parse(date);
    } catch (_) {
      try {
        final formats = [
          RegExp(r'(\d{1,2})\s+(\w+)\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})'),
        ];
        for (final format in formats) {
          final match = format.firstMatch(date);
          if (match != null) {
            final months = {
              'Jan': 1,
              'Feb': 2,
              'Mar': 3,
              'Apr': 4,
              'May': 5,
              'Jun': 6,
              'Jul': 7,
              'Aug': 8,
              'Sep': 9,
              'Oct': 10,
              'Nov': 11,
              'Dec': 12,
            };
            final day = int.parse(match.group(1)!);
            final month = months[match.group(2)] ?? 1;
            final year = int.parse(match.group(3)!);
            final hour = int.parse(match.group(4)!);
            final minute = int.parse(match.group(5)!);
            final second = int.parse(match.group(6)!);
            return DateTime(year, month, day, hour, minute, second);
          }
        }
      } catch (_) {}
      return DateTime.now();
    }
  }

  @override
  Future<void> createDirectory(NasPath path) async {
    final url = _buildUrl(path);
    await _dio.request(
      url,
      options: Options(
        method: 'MKCOL',
        headers: {'Authorization': _currentAuthHeader},
      ),
    );
  }

  @override
  Future<void> delete(NasPath path) async {
    final url = _buildUrl(path);
    final headers = {'Authorization': _currentAuthHeader};
    try {
      await _dio.delete(url, options: Options(headers: headers));
    } on DioException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  @override
  Future<UploadResult> upload({
    required NasPath targetPath,
    required Stream<List<int>> sourceStream,
    required int totalSize,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    Map<String, String>? extraHeaders,
    void Function(int sent)? onProgress,
  }) async {
    final url = _buildUrl(targetPath);
    final progressThrottler = ClientTransferTuning.uploadProgressThrottler();
    try {
      final response = await _dio.put(
        url,
        data: sourceStream,
        options: Options(
          headers: {
            'Authorization': _currentAuthHeader,
            'Content-Length': totalSize.toString(),
            'Content-Type': 'application/octet-stream',
            'X-NAS-Conflict-Policy': conflictPolicy.wireValue,
            ...?extraHeaders,
          },
        ),
        onSendProgress: (sent, total) {
          progressThrottler.reportValue(
            sent,
            totalBytes: total > 0 ? total : totalSize,
            onProgress: onProgress,
          );
        },
      );
      progressThrottler.completeValue(
        transferredBytes: totalSize,
        onProgress: onProgress,
      );

      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw Exception(
          'Upload failed with status: ${response.statusCode}, body: ${response.data}',
        );
      }
      return _parseUploadResult(targetPath, response.data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      if (status == 409) {
        throw _buildUploadConflictException(targetPath, body);
      }
      throw Exception(
        'Upload failed: status:$status body:$body message:${e.message}',
      );
    } catch (e) {
      throw Exception('Upload failed: ${e.toString()}');
    }
  }

  UploadResult _parseUploadResult(NasPath fallbackPath, dynamic responseBody) {
    final payload = _normalizeJsonMap(responseBody);
    if (payload == null) {
      return UploadResult.forTarget(fallbackPath);
    }

    final file = payload['file'] as Map<String, dynamic>?;
    final relativePath = file?['relativePath'] as String? ?? fallbackPath.path;
    final fileName =
        file?['name'] as String? ??
        UploadResult.forTarget(fallbackPath).fileName;

    return UploadResult(
      targetPath: NasPath(rootId: fallbackPath.rootId, path: relativePath),
      fileName: fileName,
      overwritten: payload['overwritten'] == true,
      autoRenamed: payload['renamed'] == true,
    );
  }

  UploadConflictException _buildUploadConflictException(
    NasPath fallbackPath,
    dynamic responseBody,
  ) {
    final payload = _normalizeJsonMap(responseBody);
    final file = payload?['file'] as Map<String, dynamic>?;
    final relativePath = file?['relativePath'] as String? ?? fallbackPath.path;
    final fileName =
        file?['name'] as String? ??
        UploadResult.forTarget(fallbackPath).fileName;
    final message = payload?['message'] as String? ?? '目标位置已存在同名文件';

    return UploadConflictException(
      targetPath: NasPath(rootId: fallbackPath.rootId, path: relativePath),
      fileName: fileName,
      message: message,
    );
  }

  Map<String, dynamic>? _normalizeJsonMap(dynamic value) {
    return switch (value) {
      Map<String, dynamic> map => map,
      Map<dynamic, dynamic> map => map.map(
        (key, entryValue) => MapEntry('$key', entryValue),
      ),
      String text when text.trim().isNotEmpty =>
        jsonDecode(text) as Map<String, dynamic>,
      _ => null,
    };
  }

  @override
  Future<Stream<List<int>>> download({
    required NasPath sourcePath,
    void Function(int received)? onProgress,
  }) async {
    final url = _buildUrl(sourcePath);
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        headers: {'Authorization': _currentAuthHeader},
        responseType: ResponseType.stream,
      ),
      onReceiveProgress: (received, total) {
        onProgress?.call(received);
      },
    );
    return response.data?.stream ?? const Stream.empty();
  }

  @override
  Future<bool> downloadToPath({
    required NasPath sourcePath,
    required String savePath,
    required int expectedSize,
    void Function(int received)? onProgress,
    bool Function()? shouldCancel,
  }) {
    final url = _buildUrl(sourcePath);
    return _resolveRangeSupport(url, expectedSize).then(
      (supportsRange) => _pathDownloadService
          .downloadToPath(
            url: url,
            savePath: savePath,
            expectedSize: expectedSize,
            supportsRange: supportsRange,
            strategy: _downloadStrategy,
            onReceiveProgress: (received, total) {
              onProgress?.call(received);
            },
            shouldCancel: shouldCancel,
          )
          .then((result) => result.usedConcurrentRanges),
    );
  }

  Future<bool> _resolveRangeSupport(String url, int expectedSize) async {
    if (expectedSize < _rangeDownloadThresholdBytes) {
      return false;
    }
    try {
      final response = await _dio.head(
        url,
        options: Options(headers: {'Authorization': _currentAuthHeader}),
      );
      final acceptRanges = response.headers.value('accept-ranges');
      if (acceptRanges == null) {
        return false;
      }
      return acceptRanges.toLowerCase() != 'none';
    } on DioException {
      return false;
    }
  }

  @override
  Future<bool> exists(NasPath path) async {
    final url = _buildUrl(path);
    try {
      await _dio.request(
        url,
        options: Options(
          method: 'HEAD',
          headers: {'Authorization': _currentAuthHeader},
        ),
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  @override
  Future<int> getFileSize(NasPath path) async {
    final url = _buildUrl(path);
    final response = await _dio.head(
      url,
      options: Options(headers: {'Authorization': _currentAuthHeader}),
    );
    final contentLength = response.headers.value('content-length');
    return int.tryParse(contentLength ?? '0') ?? 0;
  }
}
