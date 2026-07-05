import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nasclient/core/device/client_identity_service.dart';
import 'package:nasclient/core/network/trusted_server_store.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:nasclient/core/storage/secure_store.dart';
import 'package:nasclient/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:nasclient/features/auth/data/models/auth_session_dto.dart';
import 'package:nasclient/core/device/device_session_dto.dart';
import 'package:nasclient/core/storage/device_token_store.dart';
import 'package:nasclient/features/backup/application/services/backup_plan_scheduler_service.dart';
import 'package:nasclient/features/backup/domain/entities/backup_mode.dart';
import 'package:nasclient/features/backup/domain/entities/backup_plan_entity.dart';
import 'package:nasclient/features/backup/domain/entities/backup_plan_schedule_status.dart';
import 'package:nasclient/features/backup/domain/entities/backup_schedule_entity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupPlanExecutionProfileResolver', () {
    late SharedPreferences prefs;
    late _FakeSecureStore secureStore;
    late AuthLocalDataSource authLocalDataSource;
    late TrustedServerStore trustedServerStore;
    late BackupPlanExecutionProfileResolver resolver;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      secureStore = _FakeSecureStore();
      authLocalDataSource = AuthLocalDataSource(
        secureStore: secureStore,
        keyValueStore: KeyValueStore(prefs: prefs),
        deviceTokenStore: DeviceTokenStore(secureStore: secureStore),
      );
      trustedServerStore = TrustedServerStore(secureStore: secureStore);
      resolver = BackupPlanExecutionProfileResolver(
        authLocalDataSource: authLocalDataSource,
        clientIdentityService: _FakeClientIdentityService(prefs),
        trustedServerStore: trustedServerStore,
      );
    });

    test('builds native config for webdav full-gallery plan', () async {
      await authLocalDataSource.saveSession(
        const AuthSessionDto(
          serverUrl: 'https://nas.example.com:8443',
          serverId: 'server-1',
          serverName: 'NAS',
          role: 'device',
          deviceId: 'android_test_device',
          sessionId: 'session-1',
          accessToken: 'token-1',
          refreshToken: 'refresh-1',
          protocol: 'webdav',
          rootId: 'fs',
          rootName: '共享目录',
        ),
      );
      await authLocalDataSource.saveDeviceSession(
        serverId: 'server-1',
        session: const DeviceSessionDto(
          deviceId: 'android_test_device',
          accessToken: 'token-1',
          refreshToken: 'refresh-1',
          sessionId: 'session-1',
        ),
      );
      await trustedServerStore.trustServer(
        serverId: 'server-1',
        serverName: 'NAS',
        baseUrl: 'https://nas.example.com:8443',
        rootCaPem:
            '-----BEGIN CERTIFICATE-----\nZmFrZQ==\n-----END CERTIFICATE-----',
        caSha256: 'ca-sha',
      );

      final config = await resolver.build(
        BackupPlanEntity(
          id: 'plan-1',
          name: '定时图库自动备份',
          mode: BackupMode.fullGallery,
          sourcePath: 'gallery://all',
          targetPath: '/',
          serverId: 'server-1',
          rootId: 'fs',
          schedule: const BackupScheduleEntity(
            hour: 22,
            minute: 30,
            requiresWifi: true,
          ),
          includeImages: true,
          includeVideos: false,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      expect(config.isSuccess, isTrue);
      final resolvedConfig = config.dataOrNull;
      expect(resolvedConfig, isNotNull);
      expect(resolvedConfig!.serverUrl, 'https://nas.example.com:8443');
      expect(resolvedConfig.accessToken, 'token-1');
      expect(resolvedConfig.refreshToken, 'refresh-1');
      expect(resolvedConfig.deviceId, 'android_test_device');
      expect(resolvedConfig.deviceName, 'Test Device');
      expect(resolvedConfig.scheduleType, 'daily');
      expect(resolvedConfig.requiresWifi, isTrue);
      expect(resolvedConfig.includeVideos, isFalse);
    });

    test('returns failure when device session is missing', () async {
      await authLocalDataSource.saveSession(
        const AuthSessionDto(
          serverUrl: 'https://nas.example.com:8443',
          serverId: 'server-1',
          serverName: 'NAS',
          username: 'alice',
          accountId: 'account-1',
          role: 'client',
          sessionId: 'session-1',
          accessToken: 'token-1',
          protocol: 'webdav',
          rootId: 'fs',
          rootName: '共享目录',
        ),
      );
      await trustedServerStore.trustServer(
        serverId: 'server-1',
        serverName: 'NAS',
        baseUrl: 'https://nas.example.com:8443',
        rootCaPem:
            '-----BEGIN CERTIFICATE-----\nZmFrZQ==\n-----END CERTIFICATE-----',
        caSha256: 'ca-sha',
      );

      final config = await resolver.build(
        BackupPlanEntity(
          id: 'plan-1',
          name: '定时图库自动备份',
          mode: BackupMode.fullGallery,
          sourcePath: 'gallery://all',
          targetPath: '/',
          serverId: 'server-1',
          rootId: 'fs',
          schedule: const BackupScheduleEntity(hour: 22, minute: 30),
          includeImages: true,
          includeVideos: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      expect(config.isFailure, isTrue);
      expect(config.failureOrNull?.message, '定时备份需要已保存的设备会话，请重新扫描服务端连接二维码');
    });
  });

  group('BackupPlanScheduleRegistration', () {
    test('parses native schedule payload', () {
      final registration = BackupPlanScheduleRegistration.fromMap(const {
        'status': 'scheduled',
        'nextRunAtMillis': 1760000000000,
      });

      expect(registration.status, BackupPlanScheduleStatus.scheduled);
      expect(
        registration.scheduledRunAt,
        DateTime.fromMillisecondsSinceEpoch(1760000000000),
      );
    });
  });

  group('shouldPersistWorkerSnapshot', () {
    final startedAt = DateTime(2026, 6, 6, 10);

    BackupWorkerRunSnapshot run({
      required String id,
      String status = 'running',
      DateTime? finishedAt,
      int processedCount = 0,
    }) {
      return BackupWorkerRunSnapshot(
        id: id,
        planId: 'plan-1',
        triggerType: 'scheduled',
        status: status,
        scannedCount: 0,
        queuedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        processedCount: processedCount,
        totalCount: 100,
        startedAt: startedAt,
        finishedAt: finishedAt,
      );
    }

    BackupWorkerPlanSnapshot plan({
      String scheduleStatus = 'scheduled',
      DateTime? scheduledRunAt,
      DateTime? lastRunAt,
      String? scheduleErrorMessage,
    }) {
      return BackupWorkerPlanSnapshot(
        planId: 'plan-1',
        enabled: true,
        scheduleStatus: scheduleStatus,
        scheduledRunAt: scheduledRunAt,
        lastRunAt: lastRunAt,
        scheduleErrorMessage: scheduleErrorMessage,
      );
    }

    test('returns true when active run id changes', () {
      expect(
        shouldPersistWorkerSnapshot(
          previousActiveRun: run(id: 'run-a'),
          nextActiveRun: run(id: 'run-b'),
          previousPlan: plan(),
          nextPlan: plan(),
        ),
        isTrue,
      );
    });

    test('returns true when run status changes', () {
      expect(
        shouldPersistWorkerSnapshot(
          previousActiveRun: run(id: 'run-a', status: 'running'),
          nextActiveRun: run(id: 'run-a', status: 'completed'),
          previousPlan: plan(),
          nextPlan: plan(),
        ),
        isTrue,
      );
    });

    test('returns false for progress-only run updates', () {
      expect(
        shouldPersistWorkerSnapshot(
          previousActiveRun: run(id: 'run-a', processedCount: 1),
          nextActiveRun: run(id: 'run-a', processedCount: 42),
          previousPlan: plan(),
          nextPlan: plan(),
        ),
        isFalse,
      );
    });

    test('returns true when plan schedule status changes', () {
      expect(
        shouldPersistWorkerSnapshot(
          previousActiveRun: null,
          nextActiveRun: null,
          previousPlan: plan(scheduleStatus: 'scheduled'),
          nextPlan: plan(scheduleStatus: 'unscheduled'),
        ),
        isTrue,
      );
    });
  });
}

class _FakeSecureStore extends SecureStore {
  _FakeSecureStore() : super();

  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    _values['user:$serverUrl'] = username;
    _values['pass:$serverUrl'] = password;
  }

  @override
  Future<Map<String, String>?> loadCredentials({
    required String serverUrl,
  }) async {
    final username = _values['user:$serverUrl'];
    final password = _values['pass:$serverUrl'];
    if (username == null || password == null) {
      return null;
    }
    return <String, String>{'username': username, 'password': password};
  }

  @override
  Future<void> clearCredentials({required String serverUrl}) async {
    _values.remove('user:$serverUrl');
    _values.remove('pass:$serverUrl');
  }

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

class _FakeClientIdentityService extends ClientIdentityService {
  _FakeClientIdentityService(SharedPreferences prefs) : super(prefs: prefs);

  @override
  Future<String> getDeviceId() async => 'android_test_device';

  @override
  Future<String> getDeviceName() async => 'Test Device';
}
