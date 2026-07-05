import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/unified_node.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/core/use_case/no_params.dart';
import 'package:nasclient/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:nasclient/features/startup/application/use_cases/resolve_start_route_use_case.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const serverUrl = 'https://192.168.1.10:9443';

  late KeyValueStore keyValueStore;
  late _FakeAuthLocalDataSource authLocalDataSource;
  late bool onlineProbeResult;
  late ResolveStartRouteUseCase useCase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    keyValueStore = KeyValueStore(prefs: prefs);
    authLocalDataSource = _FakeAuthLocalDataSource(recoverable: false);
    onlineProbeResult = true;
    useCase = ResolveStartRouteUseCase(
      keyValueStore: keyValueStore,
      authLocalDataSource: authLocalDataSource,
      onlineProbe: (_) async => onlineProbeResult,
    );
  });

  Future<void> seedSavedServer() async {
    await keyValueStore.saveLastServerUrl(serverUrl);
    await keyValueStore.saveServerNodes([
      UnifiedNode.savedServer(
        serverUrl: serverUrl,
        displayName: 'MiniNAS',
        serverId: 'server-1',
      ),
    ]);
  }

  test('returns server list when last server url is missing', () async {
    final result = await useCase.call(NoParams());

    expect(result.route, StartRoute.serverList);
    expect(result.shouldRestoreSession, isFalse);
  });

  test('returns server list when last url has no matching saved server', () async {
    await keyValueStore.saveLastServerUrl(serverUrl);

    final result = await useCase.call(NoParams());

    expect(result.route, StartRoute.serverList);
    expect(result.shouldRestoreSession, isFalse);
  });

  test('returns server list when session is not recoverable', () async {
    await seedSavedServer();
    authLocalDataSource.recoverable = false;

    final result = await useCase.call(NoParams());

    expect(result.route, StartRoute.serverList);
    expect(result.shouldRestoreSession, isFalse);
  });

  test('returns server list when saved server is offline', () async {
    await seedSavedServer();
    authLocalDataSource.recoverable = true;
    onlineProbeResult = false;

    final result = await useCase.call(NoParams());

    expect(result.route, StartRoute.serverList);
    expect(result.shouldRestoreSession, isFalse);
  });

  test('returns home with session restore when last server is online', () async {
    await seedSavedServer();
    authLocalDataSource.recoverable = true;
    onlineProbeResult = true;

    final result = await useCase.call(NoParams());

    expect(result.route, StartRoute.home);
    expect(result.shouldRestoreSession, isTrue);
  });
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  _FakeAuthLocalDataSource({required this.recoverable});

  bool recoverable;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> hasRecoverableSession() async => recoverable;
}
