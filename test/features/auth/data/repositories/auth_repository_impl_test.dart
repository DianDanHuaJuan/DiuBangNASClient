import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/device/client_identity_service.dart';
import 'package:nasclient/core/device/device_session_dto.dart';
import 'package:nasclient/core/node/unified_node_store.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/core/storage/device_token_store.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/core/storage/secure_store.dart';
import 'package:nasclient/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:nasclient/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:nasclient/features/auth/data/models/auth_session_dto.dart';
import 'package:nasclient/features/auth/data/models/bootstrap_response_dto.dart';
import 'package:nasclient/features/auth/data/models/device_token_refresh_response_dto.dart';
import 'package:nasclient/features/auth/data/pairing_client.dart';
import 'package:nasclient/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const serverUrl = 'https://192.168.1.10:9443';
  late KeyValueStore keyValueStore;
  late _FakeSecureStore secureStore;
  late AuthLocalDataSource localDataSource;
  late _FakeAuthRemoteDataSource remoteDataSource;
  late AuthRepositoryImpl repository;
  final session = CurrentSession();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    keyValueStore = KeyValueStore(prefs: prefs);
    secureStore = _FakeSecureStore();
    localDataSource = AuthLocalDataSource(
      secureStore: secureStore,
      keyValueStore: keyValueStore,
      deviceTokenStore: DeviceTokenStore(secureStore: secureStore),
    );
    remoteDataSource = _FakeAuthRemoteDataSource();
    repository = AuthRepositoryImpl(
      remoteDataSource: remoteDataSource,
      localDataSource: localDataSource,
      currentSession: session,
      unifiedNodeStore: UnifiedNodeStore(),
      clientIdentityService: _FakeClientIdentityService(),
    );
    session.clear();
  });

  tearDown(() {
    session.clear();
  });

  test('bootstrapDeviceSession stores device tokens and session', () async {
    final result = await repository.bootstrapDeviceSession(
      pairingResult: const PairingResult(
        serverId: 'server-1',
        baseUrl: serverUrl,
        certificate: 'pem',
        deviceId: 'android-device-01',
        accessToken: 'access-token-1',
        refreshToken: 'refresh-token-1',
        sessionId: 'sess-1',
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(
      await localDataSource.loadDeviceSession(serverId: 'server-1'),
      isNotNull,
    );
    expect(
      (await localDataSource.loadSession())?.accessToken,
      'access-token-1',
    );
    expect(keyValueStore.getLastServerUrl(), serverUrl);
    expect(remoteDataSource.bootstrapCallCount, 1);
    expect(session.role, 'device');
    expect(session.authHeader, 'Bearer access-token-1');
  });

  test('logout clears saved session and device tokens', () async {
    await repository.bootstrapDeviceSession(
      pairingResult: const PairingResult(
        serverId: 'server-1',
        baseUrl: serverUrl,
        certificate: 'pem',
        deviceId: 'android-device-01',
        accessToken: 'access-token-1',
        refreshToken: 'refresh-token-1',
        sessionId: 'sess-1',
      ),
    );

    final result = await repository.logout();

    expect(result.isSuccess, isTrue);
    expect(await localDataSource.loadSession(), isNull);
    expect(await localDataSource.loadDeviceSession(serverId: 'server-1'), isNull);
    expect(session.isInitialized, isFalse);
  });

  test('restoreSession prefers saved bearer session', () async {
    await localDataSource.saveDeviceSession(
      serverId: 'server-1',
      session: const DeviceSessionDto(
        deviceId: 'android-device-01',
        accessToken: 'saved-token',
        refreshToken: 'refresh-token-1',
        sessionId: 'sess-1',
      ),
    );
    await localDataSource.saveSession(
      const AuthSessionDto(
        serverUrl: serverUrl,
        serverId: 'server-1',
        serverName: 'MiniNAS',
        role: 'device',
        deviceId: 'android-device-01',
        sessionId: 'sess-1',
        accessToken: 'saved-token',
        refreshToken: 'refresh-token-1',
        protocol: 'webdav',
        rootId: 'fs',
        rootName: 'NASServer',
      ),
    );

    final result = await repository.restoreSession();

    expect(result.isSuccess, isTrue);
    expect(remoteDataSource.restoreBootstrapToken, 'saved-token');
    expect(session.authHeader, 'Bearer saved-token');
  });
}

class _FakeSecureStore extends SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FakeAuthRemoteDataSource extends AuthRemoteDataSource {
  int bootstrapCallCount = 0;
  String? restoreBootstrapToken;

  _FakeAuthRemoteDataSource() : super();

  @override
  Future<BootstrapResponseDto> bootstrap(
    String serverUrl, {
    required String accessToken,
    String? deviceId,
  }) async {
    bootstrapCallCount += 1;
    restoreBootstrapToken = accessToken;
    return BootstrapResponseDto(
      serverId: 'server-1',
      serverName: 'MiniNAS',
      serverVersion: '1.0.0',
      serverStatus: 'online',
      protocol: 'webdav',
      rootId: 'fs',
      rootName: 'NASServer',
      roots: const [
        RootInfo(
          id: 'fs',
          name: 'NASServer',
          path: '/fs',
          type: 'local',
          writable: true,
        ),
      ],
      webdavConfig: {'baseUrl': '$serverUrl/dav/fs'},
      capabilities: const {
        'dashboard': true,
        'preview': {'image': true},
        'relay': {'enabled': true},
        'realtime': {'websocket': true},
      },
    );
  }

  @override
  Future<DeviceTokenRefreshResponseDto> refreshDeviceToken(
    String serverUrl, {
    required String refreshToken,
  }) async {
    return const DeviceTokenRefreshResponseDto(
      deviceId: 'android-device-01',
      accessToken: 'refreshed-token',
      sessionId: 'sess-2',
      expiresAt: '2026-04-20T12:00:00Z',
    );
  }
}

class _FakeClientIdentityService implements ClientIdentityService {
  @override
  Future<String> getDeviceId() async => 'android-device-01';

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
