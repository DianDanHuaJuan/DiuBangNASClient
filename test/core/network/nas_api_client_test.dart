import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/error/app_exception.dart';
import 'package:nasclient/core/network/auth_headers.dart';
import 'package:nasclient/core/network/nas_api_client.dart';
import 'package:nasclient/core/session/current_session.dart';

void main() {
  group('NasApiClient', () {
    test('adds authorization and client id headers to requests', () async {
      final session = CurrentSession();
      session.clear();
      session.set(
        serverId: 'server-1',
        serverName: 'NAS Server',
        serverVersion: '1.0.0',
        serverStatus: 'running',
        serverUrl: 'http://localhost:8080',
        accountId: 'acct-1',
        role: 'client',
        clientId: 'android-device-01',
        sessionId: 'sess-1',
        accessToken: 'access-token-1',
        username: 'client-user',
        password: 'client-pass',
        protocol: 'webdav',
        rootId: 'fs',
        rootName: '文件',
        roots: const [
          RootInfo(
            id: 'fs',
            name: '文件',
            path: '/fs',
            type: 'local',
            writable: true,
          ),
        ],
      );

      final dio = Dio();
      final client = NasApiClient(
        baseUrl: 'http://localhost:8080',
        session: session,
        clientIdProvider: () async => 'android-device-01',
        clientNameProvider: () async => 'Xiaomi Pad 6',
        dio: dio,
      );
      late RequestOptions capturedRequest;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedRequest = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: const {'ok': true},
              ),
            );
          },
        ),
      );

      final response = await client.get<Map<String, dynamic>>(
        '/api/v1/bootstrap',
      );

      expect(response['ok'], isTrue);
      expect(capturedRequest.headers['Authorization'], 'Bearer access-token-1');
      expect(capturedRequest.headers[clientIdHeaderName], 'android-device-01');
      expect(capturedRequest.headers[clientNameHeaderName], 'Xiaomi Pad 6');
    });

    test('surfaces server auth codes from bad responses', () async {
      final session = CurrentSession();
      session.clear();
      session.set(
        serverId: 'server-1',
        serverName: 'NAS Server',
        serverVersion: '1.0.0',
        serverStatus: 'running',
        serverUrl: 'http://localhost:8080',
        accountId: 'acct-1',
        role: 'client',
        clientId: 'android-device-01',
        sessionId: 'sess-1',
        accessToken: 'access-token-1',
        username: 'client-user',
        password: 'client-pass',
        protocol: 'webdav',
        rootId: 'fs',
        rootName: '文件',
        roots: const [
          RootInfo(
            id: 'fs',
            name: '文件',
            path: '/fs',
            type: 'local',
            writable: true,
          ),
        ],
      );

      final dio = Dio();
      final client = NasApiClient(
        baseUrl: 'http://localhost:8080',
        session: session,
        dio: dio,
      );
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
                    'code': 'CLIENT_ID_REQUIRED',
                    'message':
                        'Client credentials require the X-NAS-Client-Id request header',
                  },
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      await expectLater(
        client.get<Map<String, dynamic>>('/api/v1/bootstrap'),
        throwsA(
          isA<AppException>()
              .having((error) => error.code, 'code', 'CLIENT_ID_REQUIRED')
              .having(
                (error) => error.message,
                'message',
                'This client version did not send a device identity header',
              ),
        ),
      );
    });

    test('surfaces the default owner gate message from server errors', () async {
      final session = CurrentSession();
      session.clear();
      session.set(
        serverId: 'server-1',
        serverName: 'NAS Server',
        serverVersion: '1.0.0',
        serverStatus: 'running',
        serverUrl: 'http://localhost:8080',
        accountId: 'acct-1',
        role: 'client',
        clientId: 'android-device-01',
        sessionId: 'sess-1',
        accessToken: 'access-token-1',
        username: 'client-user',
        password: 'client-pass',
        protocol: 'webdav',
        rootId: 'fs',
        rootName: '文件',
        roots: const [
          RootInfo(
            id: 'fs',
            name: '文件',
            path: '/fs',
            type: 'local',
            writable: true,
          ),
        ],
      );

      final dio = Dio();
      final client = NasApiClient(
        baseUrl: 'http://localhost:8080',
        session: session,
        dio: dio,
      );
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

      await expectLater(
        client.get<Map<String, dynamic>>('/api/v1/bootstrap'),
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

    test(
      'recovers the session once and retries with the refreshed bearer token',
      () async {
        final session = CurrentSession();
        session.clear();
        session.set(
          serverId: 'server-1',
          serverName: 'NAS Server',
          serverVersion: '1.0.0',
          serverStatus: 'running',
          serverUrl: 'http://localhost:8080',
          accountId: 'acct-1',
          role: 'client',
          clientId: 'android-device-01',
          sessionId: 'sess-1',
          accessToken: 'expired-token',
          username: 'client-user',
          password: 'client-pass',
          protocol: 'webdav',
          rootId: 'fs',
          rootName: '文件',
          roots: const [
            RootInfo(
              id: 'fs',
              name: '文件',
              path: '/fs',
              type: 'local',
              writable: true,
            ),
          ],
        );

        final dio = Dio();
        var requestCount = 0;
        final authorizationHeaders = <Object?>[];
        final client = NasApiClient(
          baseUrl: 'http://localhost:8080',
          session: session,
          sessionRecoveryHandler: () async {
            session.set(
              serverId: 'server-1',
              serverName: 'NAS Server',
              serverVersion: '1.0.0',
              serverStatus: 'running',
              serverUrl: 'http://localhost:8080',
              accountId: 'acct-1',
              role: 'client',
              clientId: 'android-device-01',
              sessionId: 'sess-2',
              accessToken: 'fresh-token',
              username: 'client-user',
              password: 'client-pass',
              protocol: 'webdav',
              rootId: 'fs',
              rootName: '文件',
              roots: const [
                RootInfo(
                  id: 'fs',
                  name: '文件',
                  path: '/fs',
                  type: 'local',
                  writable: true,
                ),
              ],
            );
            return true;
          },
          dio: dio,
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestCount += 1;
              authorizationHeaders.add(options.headers['Authorization']);
              if (requestCount == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 401,
                      data: const {
                        'code': 'AUTH_EXPIRED',
                        'message': 'Session has expired',
                      },
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
                return;
              }

              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {'ok': true},
                ),
              );
            },
          ),
        );

        final response = await client.get<Map<String, dynamic>>(
          '/api/v1/bootstrap',
        );

        expect(response['ok'], isTrue);
        expect(requestCount, 2);
        expect(authorizationHeaders, [
          'Bearer expired-token',
          'Bearer fresh-token',
        ]);
      },
    );
  });

  group('defaults', () {
    test('uses 30 second connect and receive timeouts', () {
      final session = CurrentSession();
      session.clear();
      session.set(
        serverId: 'server-1',
        serverName: 'NAS Server',
        serverVersion: '1.0.0',
        serverStatus: 'running',
        serverUrl: 'https://localhost:8080',
        accountId: 'acct-1',
        role: 'device',
        deviceId: 'android-device-01',
        sessionId: 'sess-1',
        accessToken: 'access-token-1',
        username: 'client-user',
        password: 'client-pass',
        protocol: 'webdav',
        rootId: 'fs',
        rootName: '文件',
        roots: const [
          RootInfo(
            id: 'fs',
            name: '文件',
            path: '/fs',
            type: 'local',
            writable: true,
          ),
        ],
      );

      final client = NasApiClient(
        baseUrl: 'https://localhost:8080',
        session: session,
      );

      expect(
        client.dio.options.connectTimeout,
        nasApiDefaultConnectTimeout,
      );
      expect(
        client.dio.options.receiveTimeout,
        nasApiDefaultReceiveTimeout,
      );
    });
  });
}
