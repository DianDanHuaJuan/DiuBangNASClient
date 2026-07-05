import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/network/auth_headers.dart';
import '../../../../core/network/trusted_server_http_client_factory.dart';
import '../models/auth_session_response_dto.dart';
import '../models/bootstrap_response_dto.dart';
import '../models/device_token_refresh_response_dto.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource({
    Future<String> Function()? clientIdProvider,
    Future<String> Function()? clientNameProvider,
    Future<String> Function()? deviceIdProvider,
    Future<String> Function()? deviceNameProvider,
    TrustedServerHttpClientFactory? trustedHttpClientFactory,
    Dio? dio,
  }) : _deviceIdProvider = deviceIdProvider ?? clientIdProvider,
        _deviceNameProvider = deviceNameProvider ?? clientNameProvider,
        _trustedHttpClientFactory = trustedHttpClientFactory,
        _dio = dio ?? Dio();

  final Future<String> Function()? _deviceIdProvider;
  final Future<String> Function()? _deviceNameProvider;
  final TrustedServerHttpClientFactory? _trustedHttpClientFactory;
  final Dio _dio;

  Future<AuthSessionResponseDto> createSession(
    String serverUrl,
    String username,
    String password,
  ) async {
    _dio.options.baseUrl = serverUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.headers['Content-Type'] = 'application/json';
    _trustedHttpClientFactory?.configureDio(_dio, baseUrl: serverUrl);

    try {
      final response = await _dio.post(
        '/api/v1/auth/session',
        options: Options(
          headers: await _buildAuthHeaders(
            username: username,
            password: password,
          ),
        ),
      );

      return AuthSessionResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (error, stackTrace) {
      throw _handleDioError(error, stackTrace);
    }
  }

  Future<BootstrapResponseDto> bootstrap(
    String serverUrl, {
    required String accessToken,
    String? deviceId,
  }) async {
    _dio.options.baseUrl = serverUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.headers['Content-Type'] = 'application/json';
    _trustedHttpClientFactory?.configureDio(_dio, baseUrl: serverUrl);

    try {
      final headers = <String, String>{'Authorization': 'Bearer $accessToken'};
      final resolvedDeviceId = deviceId?.trim();
      if (resolvedDeviceId != null && resolvedDeviceId.isNotEmpty) {
        headers[deviceIdHeaderName] = resolvedDeviceId;
      }
      final response = await _dio.get(
        '/api/v1/bootstrap',
        options: Options(headers: headers),
      );

      return BootstrapResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (error, stackTrace) {
      throw _handleDioError(error, stackTrace);
    }
  }

  Future<DeviceTokenRefreshResponseDto> refreshDeviceToken(
    String serverUrl, {
    required String refreshToken,
  }) async {
    _dio.options.baseUrl = serverUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.headers['Content-Type'] = 'application/json';
    _trustedHttpClientFactory?.configureDio(_dio, baseUrl: serverUrl);

    try {
      final response = await _dio.post(
        '/api/v1/auth/device/refresh',
        data: {'refreshToken': refreshToken},
      );

      return DeviceTokenRefreshResponseDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (error, stackTrace) {
      throw _handleDioError(error, stackTrace);
    }
  }

  String _encodeBasicAuth(String username, String password) {
    final credentials = '$username:$password';
    final encoded = base64Encode(utf8.encode(credentials));
    return 'Basic $encoded';
  }

  Future<Map<String, String>> _buildAuthHeaders({
    required String username,
    required String password,
  }) async {
    final headers = <String, String>{
      'Authorization': _encodeBasicAuth(username, password),
    };
    final deviceId = await _resolveDeviceId();
    if (deviceId != null) {
      headers[deviceIdHeaderName] = deviceId;
    }
    final deviceName = await _resolveDeviceName();
    if (deviceName != null) {
      headers[deviceNameHeaderName] = deviceName;
    }
    return headers;
  }

  Future<String?> _resolveDeviceId() async {
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
    final deviceName = (await deviceNameProvider()).trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return deviceName.isEmpty ? null : deviceName;
  }

  AppException _handleDioError(DioException error, StackTrace stackTrace) {
    final serverError = _extractServerError(error.response?.data);

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppException(
          code: 'TIMEOUT',
          message: 'Connection timeout',
          originalError: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.connectionError:
        if (_looksLikeTlsTrustFailure(error)) {
          return AppException(
            code: 'TLS_TRUST_FAILED',
            message: 'HTTPS 证书校验失败，请重新扫描服务端连接二维码后重试',
            originalError: error,
            stackTrace: stackTrace,
          );
        }
        return AppException(
          code: 'CONNECTION_ERROR',
          message: 'Cannot connect to server',
          originalError: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.badCertificate:
        return AppException(
          code: 'TLS_TRUST_FAILED',
          message: 'HTTPS 证书校验失败，请重新扫描服务端连接二维码后重试',
          originalError: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.badResponse:
        if (serverError != null) {
          return AppException(
            code: serverError.code,
            message: _userFacingMessageForServerError(serverError),
            originalError: error,
            stackTrace: stackTrace,
          );
        }
        return AppException(
          code: 'SERVER_ERROR',
          message: 'Server error: ${error.response?.statusCode}',
          originalError: error,
          stackTrace: stackTrace,
        );
      case DioExceptionType.cancel:
        return AppException(
          code: 'CANCELLED',
          message: 'Request cancelled',
          originalError: error,
          stackTrace: stackTrace,
        );
      default:
        if (_looksLikeTlsTrustFailure(error)) {
          return AppException(
            code: 'TLS_TRUST_FAILED',
            message: 'HTTPS 证书校验失败，请重新扫描服务端连接二维码后重试',
            originalError: error,
            stackTrace: stackTrace,
          );
        }
        return AppException(
          code: 'UNKNOWN',
          message: error.message ?? 'Unknown error',
          originalError: error,
          stackTrace: stackTrace,
        );
    }
  }

  bool _looksLikeTlsTrustFailure(DioException error) {
    final rawMessage = [
      error.message,
      error.error?.toString(),
    ].whereType<String>().join(' ').toLowerCase();
    return rawMessage.contains('certificate') ||
        rawMessage.contains('handshake') ||
        rawMessage.contains('cert_verify') ||
        rawMessage.contains('certificateverifyfailed');
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
      case 'DEVICE_ID_REQUIRED':
        return 'This client version did not send a device identity header';
      case 'DEVICE_BINDING_CONFLICT':
        return 'This client credential is already bound to another device';
      default:
        return error.message;
    }
  }
}
