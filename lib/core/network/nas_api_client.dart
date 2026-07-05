/// 文件输入：服务器基地址、当前会话认证头、dio 客户端
/// 文件职责：统一封装控制面 API 请求，提供会话认证和错误处理
/// 文件对外接口：NasApiClient
/// 文件包含：NasApiClient
import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'auth_headers.dart';
import 'dio_debug_logging.dart';
import '../error/app_exception.dart';
import '../session/current_session.dart';
import 'trusted_server_http_client_factory.dart';

typedef SessionRecoveryHandler = Future<bool> Function();

const Duration nasApiDefaultConnectTimeout = Duration(seconds: 30);
const Duration nasApiDefaultReceiveTimeout = Duration(seconds: 30);

class NasApiClient {
  final Dio _dio;
  final String baseUrl;
  final CurrentSession _session;
  final Future<String> Function()? _deviceIdProvider;
  final Future<String> Function()? _deviceNameProvider;
  final SessionRecoveryHandler? _sessionRecoveryHandler;
  final TrustedServerHttpClientFactory? _trustedHttpClientFactory;

  Dio get dio => _dio;

  NasApiClient({
    required this.baseUrl,
    required CurrentSession session,
    Future<String> Function()? clientIdProvider,
    Future<String> Function()? clientNameProvider,
    Future<String> Function()? deviceIdProvider,
    Future<String> Function()? deviceNameProvider,
    SessionRecoveryHandler? sessionRecoveryHandler,
    TrustedServerHttpClientFactory? trustedHttpClientFactory,
    Dio? dio,
    bool useHttp2 = false,
  }) : _session = session,
       _deviceIdProvider = deviceIdProvider ?? clientIdProvider,
       _deviceNameProvider = deviceNameProvider ?? clientNameProvider,
       _sessionRecoveryHandler = sessionRecoveryHandler,
       _trustedHttpClientFactory = trustedHttpClientFactory,
       _dio = dio ?? Dio() {
    final parsedBaseUri = Uri.parse(baseUrl);
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = nasApiDefaultConnectTimeout;
    _dio.options.receiveTimeout = nasApiDefaultReceiveTimeout;
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.options.extra['trustedHttpClientFactory'] = _trustedHttpClientFactory;

    // 配置 HTTP/2 或优化 HTTP/1.1
    if (useHttp2 &&
        _trustedHttpClientFactory == null &&
        parsedBaseUri.scheme == 'https') {
      _dio.httpClientAdapter = Http2Adapter(
        ConnectionManager(idleTimeout: const Duration(minutes: 5)),
      );
    } else {
      if (_trustedHttpClientFactory != null &&
          parsedBaseUri.scheme == 'https') {
        _trustedHttpClientFactory.configureDio(
          _dio,
          baseUrl: baseUrl,
          maxConnectionsPerHost: 12,
        );
      } else {
        _dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient();
            client.maxConnectionsPerHost = 12;
            return client;
          },
        );
      }
    }

    attachDioDebugLogging(_dio, channel: 'NasApiClient');

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final authHeader = _authHeader;
          if (authHeader != null) {
            options.headers['Authorization'] = authHeader;
          }
          final deviceId = await _resolveDeviceId();
          if (deviceId != null) {
            options.headers[deviceIdHeaderName] = deviceId;
          }
          final sessionDeviceId = _session.deviceId?.trim();
          if (_session.isDeviceSession &&
              sessionDeviceId != null &&
              sessionDeviceId.isNotEmpty &&
              deviceId != null &&
              deviceId != sessionDeviceId) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'Device identity header mismatch',
              ),
            );
            return;
          }
          final deviceName = await _resolveDeviceName();
          if (deviceName != null) {
            options.headers[deviceNameHeaderName] = deviceName;
          }
          handler.next(options);
        },
      ),
    );
  }

  String? get _authHeader {
    return _session.authHeader;
  }

  Map<String, String> get _authHeaders {
    final header = _authHeader;
    if (header == null) return {};
    return {'Authorization': header};
  }

  Future<String?> _resolveDeviceId() async {
    final sessionDeviceId = _session.deviceId?.trim();
    if (sessionDeviceId != null && sessionDeviceId.isNotEmpty) {
      return sessionDeviceId;
    }
    final deviceIdProvider = _deviceIdProvider;
    if (deviceIdProvider == null) {
      return null;
    }
    final deviceId = (await deviceIdProvider()).trim();
    return deviceId.isEmpty ? null : deviceId;
  }

  Future<String?> _resolveDeviceName() async {
    final deviceNameProvider = _deviceNameProvider;
    if (deviceNameProvider == null) {
      return null;
    }
    final deviceName = _sanitizeHttpHeaderValue(await deviceNameProvider());
    return deviceName.isEmpty ? null : deviceName;
  }

  String _sanitizeHttpHeaderValue(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return '';
    }
    final asciiOnly = normalized.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ').trim();
    return asciiOnly.replaceAll(RegExp(r'\s+'), ' ');
  }

  /// 建立控制面 TLS 连接，供登录后预热复用。
  Future<void> warmupConnection() async {
    if (_authHeader == null) {
      return;
    }

    try {
      await _dio.get(
        '/api/v1/bootstrap',
        options: Options(headers: _authHeaders),
      );
    } catch (_) {
      // Best-effort warmup; callers should not block navigation on failure.
    }
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    return _executeRequest<dynamic, T>(
      request: () => _dio.get(
        path,
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders),
      ),
      transform: (response) {
        if (parser != null) {
          return parser(response.data);
        }
        return response.data as T;
      },
    );
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    return _executeRequest<dynamic, T>(
      request: () => _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders),
      ),
      transform: (response) {
        if (parser != null) {
          return parser(response.data);
        }
        return response.data as T;
      },
    );
  }

  Future<T> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    return _executeRequest<dynamic, T>(
      request: () => _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders),
      ),
      transform: (response) {
        if (parser != null) {
          return parser(response.data);
        }
        return response.data as T;
      },
    );
  }

  Future<List<int>> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _executeRequest<dynamic, List<int>>(
      request: () => _dio.get<List<int>>(
        path,
        queryParameters: queryParameters,
        options: Options(
          headers: _authHeaders,
          responseType: ResponseType.bytes,
        ),
      ),
      transform: (response) => response.data ?? const <int>[],
    );
  }

  Future<T> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    return _executeRequest<dynamic, T>(
      request: () => _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders),
      ),
      transform: (response) {
        if (parser != null) {
          return parser(response.data);
        }
        return response.data as T;
      },
    );
  }

  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic json)? parser,
  }) async {
    return _executeRequest<dynamic, T>(
      request: () => _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: _authHeaders),
      ),
      transform: (response) {
        if (parser != null) {
          return parser(response.data);
        }
        return response.data as T;
      },
    );
  }

  Future<T> putBytes<T>(
    String path, {
    required List<int> data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    T Function(dynamic json)? parser,
  }) async {
    return _executeRequest<dynamic, T>(
      request: () => _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: <String, dynamic>{..._authHeaders, ...?headers},
          contentType: 'application/octet-stream',
        ),
      ),
      transform: (response) {
        if (parser != null) {
          return parser(response.data);
        }
        return response.data as T;
      },
    );
  }

  Future<void> downloadToFile(
    String path,
    String savePath, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    ProgressCallback? onReceiveProgress,
  }) async {
    await _executeRequest<dynamic, void>(
      request: () => _dio.download(
        path,
        savePath,
        queryParameters: queryParameters,
        deleteOnError: true,
        onReceiveProgress: onReceiveProgress,
        options: Options(
          headers: <String, dynamic>{..._authHeaders, ...?headers},
          sendTimeout: const Duration(minutes: 10),
          receiveTimeout: const Duration(minutes: 10),
        ),
      ),
      transform: (_) {},
    );
  }

  Future<Response<List<int>>> postBytes(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    return _executeRequest<List<int>, Response<List<int>>>(
      request: () => _dio.post<List<int>>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: _authHeaders,
          responseType: ResponseType.bytes,
        ),
      ),
      transform: (response) => response,
    );
  }

  Future<R> _executeRequest<T, R>({
    required Future<Response<T>> Function() request,
    required R Function(Response<T> response) transform,
    bool allowSessionRecovery = true,
  }) async {
    try {
      final response = await request();
      return transform(response);
    } on DioException catch (e) {
      final exception = _handleDioError(e);
      if (allowSessionRecovery && _shouldAttemptSessionRecovery(exception)) {
        final recovered =
            await (_sessionRecoveryHandler?.call() ?? Future.value(false));
        if (recovered) {
          return _executeRequest<T, R>(
            request: request,
            transform: transform,
            allowSessionRecovery: false,
          );
        }
      }
      throw exception;
    }
  }

  bool _shouldAttemptSessionRecovery(AppException exception) {
    return exception.code == 'AUTH_INVALID' ||
        exception.code == 'AUTH_EXPIRED' ||
        exception.code == 'AUTH_REVOKED';
  }

  AppException _handleDioError(DioException e) {
    final debugRequestId = extractDioDebugRequestId(e.response);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppException(
          code: 'TIMEOUT',
          message: 'Connection timeout',
          originalError: e,
        );
      case DioExceptionType.connectionError:
        return AppException(
          code: 'CONNECTION_ERROR',
          message: 'Cannot connect to server',
          originalError: e,
        );
      case DioExceptionType.badResponse:
        final serverError = _extractServerError(e.response?.data);
        if (serverError != null) {
          return AppException(
            code: serverError.code,
            message: _withDebugRequestId(
              _userFacingMessageForServerError(serverError),
              debugRequestId,
            ),
            originalError: e,
          );
        }
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) {
          return AppException(
            code: 'AUTH_INVALID',
            message: _withDebugRequestId(
              'Invalid username or password',
              debugRequestId,
            ),
            originalError: e,
          );
        } else if (statusCode == 403) {
          return AppException(
            code: 'AUTH_REQUIRED',
            message: _withDebugRequestId(
              'Authentication required',
              debugRequestId,
            ),
            originalError: e,
          );
        } else if (statusCode == 404) {
          return AppException(
            code: 'NOT_FOUND',
            message: _withDebugRequestId('Resource not found', debugRequestId),
            originalError: e,
          );
        } else {
          return AppException(
            code: 'SERVER_ERROR',
            message: _withDebugRequestId(
              'Server error: ${e.response?.statusCode}',
              debugRequestId,
            ),
            originalError: e,
          );
        }
      case DioExceptionType.cancel:
        return AppException(
          code: 'CANCELLED',
          message: 'Request cancelled',
          originalError: e,
        );
      default:
        return AppException(
          code: 'UNKNOWN',
          message: e.message ?? 'Unknown error',
          originalError: e,
        );
    }
  }

  String _withDebugRequestId(String message, String? debugRequestId) {
    if (debugRequestId == null || debugRequestId.isEmpty) {
      return message;
    }
    return '$message (requestId: $debugRequestId)';
  }

  ({String code, String message})? _extractServerError(dynamic data) {
    final payload = switch (data) {
      Map<String, dynamic> map => map,
      Map<dynamic, dynamic> map => map.map(
        (key, value) => MapEntry('$key', value),
      ),
      String text when text.trim().isNotEmpty =>
        jsonDecode(text) as Map<String, dynamic>,
      _ => null,
    };
    if (payload == null) {
      return null;
    }

    final code = payload['code'];
    final message = payload['message'];
    if (code is! String || message is! String) {
      return null;
    }
    return (code: code, message: message);
  }

  String _userFacingMessageForServerError(
    ({String code, String message}) error,
  ) {
    switch (error.code) {
      case 'AUTH_INVALID':
        return 'Invalid username or password';
      case 'DEFAULT_OWNER_CHANGE_REQUIRED':
        return 'Change the default owner credentials in the NASServer app before signing in from this device';
      case 'AUTH_EXPIRED':
        return 'Session expired, please sign in again';
      case 'AUTH_REVOKED':
        return 'Session has been revoked, please sign in again';
      case 'CLIENT_ID_REQUIRED':
      case 'DEVICE_ID_REQUIRED':
        return 'This client version did not send a device identity header';
      case 'CLIENT_BINDING_CONFLICT':
      case 'DEVICE_BINDING_CONFLICT':
        return 'This device credential is already bound to another device';
      default:
        return error.message;
    }
  }
}
