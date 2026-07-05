import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/error/app_exception.dart';
import 'package:nasclient/core/network/auth_headers.dart';
import 'package:nasclient/features/auth/data/datasources/auth_remote_data_source.dart';

void main() {
  group('AuthRemoteDataSource', () {
    test('sends the client id header during session creation', () async {
      final dio = Dio();
      late RequestOptions capturedRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _sessionPayload,
              ),
            );
          },
        ),
      );

      final dataSource = AuthRemoteDataSource(
        clientIdProvider: () async => 'android-device-01',
        clientNameProvider: () async => 'Xiaomi Pad 6',
        dio: dio,
      );

      final response = await dataSource.createSession(
        'http://localhost:8080',
        'client-user',
        'client-pass',
      );

      expect(response.sessionId, 'sess-1');
      expect(capturedRequest.headers[clientIdHeaderName], 'android-device-01');
      expect(capturedRequest.headers[clientNameHeaderName], 'Xiaomi Pad 6');
      expect(
        capturedRequest.headers['Authorization'] as String,
        startsWith('Basic '),
      );
    });

    test('uses bearer token for bootstrap after session creation', () async {
      final dio = Dio();
      late RequestOptions capturedRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _bootstrapPayload,
              ),
            );
          },
        ),
      );

      final dataSource = AuthRemoteDataSource(dio: dio);

      final response = await dataSource.bootstrap(
        'http://localhost:8080',
        accessToken: 'access-token-1',
      );

      expect(response.serverId, 'server-1');
      expect(capturedRequest.headers['Authorization'], 'Bearer access-token-1');
    });

    test('maps binding errors into an AppException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 401,
                  data: const {
                    'code': 'CLIENT_BINDING_CONFLICT',
                    'message':
                        'This client credential is already bound to another device',
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final dataSource = AuthRemoteDataSource(
        clientIdProvider: () async => 'android-device-01',
        clientNameProvider: () async => 'Xiaomi Pad 6',
        dio: dio,
      );

      await expectLater(
        dataSource.createSession(
          'http://localhost:8080',
          'client-user',
          'client-pass',
        ),
        throwsA(
          isA<AppException>()
              .having((error) => error.code, 'code', 'CLIENT_BINDING_CONFLICT')
              .having(
                (error) => error.message,
                'message',
                'This client credential is already bound to another device',
              ),
        ),
      );
    });

    test('maps default owner gate errors into a clear AppException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 403,
                  data: const {
                    'code': 'DEFAULT_OWNER_CHANGE_REQUIRED',
                    'message':
                        'Change the default owner credentials on the server before allowing remote sign-in',
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final dataSource = AuthRemoteDataSource(dio: dio);

      await expectLater(
        dataSource.createSession('http://localhost:8080', 'admin', 'admin'),
        throwsA(
          isA<AppException>()
              .having(
                (error) => error.code,
                'code',
                'DEFAULT_OWNER_CHANGE_REQUIRED',
              )
              .having(
                (error) => error.message,
                'message',
                'Change the default owner credentials in the NASServer app before signing in from this device',
              ),
        ),
      );
    });
  });
}

const Map<String, dynamic> _sessionPayload = {
  'accountId': 'acct-1',
  'role': 'client',
  'clientId': 'android-device-01',
  'sessionId': 'sess-1',
  'accessToken': 'access-token-1',
  'expiresAt': '2026-04-20T12:00:00Z',
};

const Map<String, dynamic> _bootstrapPayload = {
  'server': {
    'id': 'server-1',
    'name': 'NAS Server',
    'version': '1.0.0',
    'status': 'running',
  },
  'fileAccess': {
    'protocol': 'webdav',
    'roots': [
      {
        'id': 'fs',
        'name': '文件',
        'path': '/fs',
        'type': 'local',
        'writable': true,
      },
    ],
    'webdav': {'baseUrl': 'http://localhost:8080/dav'},
  },
  'capabilities': {'dashboard': true},
};
