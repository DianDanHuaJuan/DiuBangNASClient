/// 文件输入：远程数据源、本地数据源、当前会话
/// 文件职责：实现认证仓库具体业务逻辑
/// 文件对外接口：AuthRepositoryImpl
/// 文件包含：AuthRepositoryImpl
import '../../../../core/device/client_identity_service.dart';
import '../../../../core/device/device_id_normalizer.dart';
import '../../../../core/device/device_session_dto.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/network/nas_network_access_policy.dart';
import '../../../../core/node/unified_node_store.dart';
import '../../../../core/session/current_session.dart';
import '../../domain/entities/auth_session_entity.dart';
import '../../domain/entities/server_profile_entity.dart';
import '../../domain/entities/file_access_config_entity.dart';
import '../../domain/entities/server_capabilities_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/auth_local_data_source.dart';
import '../models/auth_session_dto.dart';
import '../models/bootstrap_response_dto.dart';
import '../pairing_client.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;
  final CurrentSession _currentSession;
  final UnifiedNodeStore _unifiedNodeStore;
  final ClientIdentityService _clientIdentityService;

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
    required CurrentSession currentSession,
    required UnifiedNodeStore unifiedNodeStore,
    required ClientIdentityService clientIdentityService,
  }) : _remoteDataSource = remoteDataSource,
       _localDataSource = localDataSource,
       _currentSession = currentSession,
       _unifiedNodeStore = unifiedNodeStore,
       _clientIdentityService = clientIdentityService;

  @override
  Future<AppResult<AuthSessionEntity>> bootstrapDeviceSession({
    required PairingResult pairingResult,
  }) async {
    try {
      final normalizedServerUrl = NasNetworkAccessPolicy.normalizeServerUrl(
        pairingResult.baseUrl,
      );
      final deviceSession = DeviceSessionDto(
        deviceId: pairingResult.deviceId,
        accessToken: pairingResult.accessToken,
        refreshToken: pairingResult.refreshToken,
        sessionId: pairingResult.sessionId,
        expiresAt: pairingResult.accessExpiresAt?.toUtc().toIso8601String(),
      );
      final session = await _bootstrapWithDeviceTokens(
        serverUrl: normalizedServerUrl,
        deviceSession: deviceSession,
      );

      await _localDataSource.saveDeviceSession(
        serverId: session.serverProfile.serverId,
        session: deviceSession,
      );
      await _localDataSource.saveSession(
        AuthSessionDto(
          serverUrl: normalizedServerUrl,
          serverId: session.serverProfile.serverId,
          serverName: session.serverProfile.serverName,
          role: 'device',
          deviceId: pairingResult.deviceId,
          sessionId: pairingResult.sessionId ?? '',
          accessToken: pairingResult.accessToken,
          refreshToken: pairingResult.refreshToken,
          expiresAt: pairingResult.accessExpiresAt?.toUtc().toIso8601String(),
          protocol: session.fileAccess.protocol,
          rootId: session.rootId,
          rootName: session.rootName,
        ),
      );
      await _localDataSource.saveLastServerUrl(normalizedServerUrl);
      await _persistServerHistory(
        serverUrl: normalizedServerUrl,
        session: session,
      );

      return Success(session);
    } on AppException catch (e) {
      return Failure(AppFailure(code: e.code, message: e.message));
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'BOOTSTRAP_ERROR',
          message: 'Failed to connect to server: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<AuthSessionEntity>> restoreSession() async {
    try {
      final savedSession = await _localDataSource.loadSession();

      if (savedSession != null) {
        try {
          final restoredSession = await _restoreFromSavedSession(savedSession);
          await _localDataSource.saveLastServerUrl(savedSession.serverUrl);
          await _persistServerHistory(
            serverUrl: savedSession.serverUrl,
            session: restoredSession,
          );
          return Success(restoredSession);
        } on AppException catch (_) {
          await _localDataSource.clearSession();
        }
      }

      final serverUrl = _localDataSource.getLastServerUrl();
      if (serverUrl == null) {
        return Failure(
          AppFailure(code: 'NO_SERVER', message: 'No saved server'),
        );
      }

      final normalizedServerUrl = NasNetworkAccessPolicy.normalizeServerUrl(
        serverUrl,
      );
      final savedSessionByUrl = await _localDataSource.loadSession();
      final serverId = savedSessionByUrl?.serverId.trim() ?? '';
      if (serverId.isEmpty) {
        return Failure(
          AppFailure(code: 'NO_SESSION', message: 'No saved session'),
        );
      }

      final deviceSession = await _localDataSource.loadDeviceSession(
        serverId: serverId,
      );
      if (deviceSession == null) {
        return Failure(
          AppFailure(code: 'NO_SESSION', message: 'No saved device session'),
        );
      }

      final refreshedDeviceSession = await _ensureFreshDeviceSession(
        serverUrl: normalizedServerUrl,
        deviceSession: deviceSession,
      );
      await _ensureEnrolledDeviceIdentityMatchesPhysical(
        deviceSession: refreshedDeviceSession,
      );
      final session = await _bootstrapWithDeviceTokens(
        serverUrl: normalizedServerUrl,
        deviceSession: refreshedDeviceSession,
      );

      await _localDataSource.saveDeviceSession(
        serverId: serverId,
        session: refreshedDeviceSession,
      );
      await _localDataSource.saveSession(
        AuthSessionDto(
          serverUrl: normalizedServerUrl,
          serverId: session.serverProfile.serverId,
          serverName: session.serverProfile.serverName,
          role: 'device',
          deviceId: refreshedDeviceSession.deviceId,
          sessionId: refreshedDeviceSession.sessionId ?? '',
          accessToken: refreshedDeviceSession.accessToken,
          refreshToken: refreshedDeviceSession.refreshToken,
          expiresAt: refreshedDeviceSession.expiresAt,
          protocol: session.fileAccess.protocol,
          rootId: session.rootId,
          rootName: session.rootName,
        ),
      );
      await _localDataSource.saveLastServerUrl(normalizedServerUrl);
      await _persistServerHistory(
        serverUrl: normalizedServerUrl,
        session: session,
      );

      return Success(session);
    } on AppException catch (e) {
      return Failure(AppFailure(code: e.code, message: e.message));
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'RESTORE_ERROR',
          message: 'Failed to restore session: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<void>> logout() async {
    try {
      final savedSession = await _localDataSource.loadSession();
      final serverId = savedSession?.serverId.trim() ?? '';
      await _localDataSource.clearSession();
      if (serverId.isNotEmpty) {
        await _localDataSource.clearDeviceSession(serverId: serverId);
      }
      _currentSession.clear();
      _unifiedNodeStore.clear();
      return Success(null);
    } catch (e) {
      return Failure(
        AppFailure.fromException(
          code: 'LOGOUT_ERROR',
          message: 'Failed to logout: ${e.toString()}',
        ),
      );
    }
  }

  @override
  Future<AppResult<ServerProfileEntity>> getServerProfile() async {
    final currentServer = _unifiedNodeStore.currentServer;
    if (currentServer == null) {
      return Failure(
        AppFailure(code: 'NO_SESSION', message: 'No active session'),
      );
    }
    return Success(
      ServerProfileEntity(
        serverId: currentServer.identity.serverId ?? '',
        serverName: currentServer.identity.displayName,
        serverVersion: currentServer.server?.serverVersion ?? '',
        serverStatus: currentServer.runtime.status ?? '',
      ),
    );
  }

  @override
  Future<AppResult<ServerCapabilitiesEntity>> getServerCapabilities() async {
    final currentServer = _unifiedNodeStore.currentServer;
    final capabilities = currentServer?.server?.capabilities;
    if (currentServer == null || capabilities == null) {
      return Failure(
        AppFailure(code: 'NO_SESSION', message: 'No active session'),
      );
    }
    return Success(
      ServerCapabilitiesEntity(
        dashboard: capabilities['dashboard'],
        preview: capabilities['preview'],
        relay: capabilities['relay'],
        realtime: capabilities['realtime'],
      ),
    );
  }

  Map<String, dynamic>? _normalizeWebdavConfig(Map<String, dynamic>? config) {
    if (config == null) {
      return null;
    }

    final baseUrl = config['baseUrl'];
    if (baseUrl is! String || baseUrl.trim().isEmpty) {
      return config;
    }

    return {
      ...config,
      'baseUrl': NasNetworkAccessPolicy.normalizeAbsoluteUrl(baseUrl),
    };
  }

  Future<AuthSessionEntity> _bootstrapWithDeviceTokens({
    required String serverUrl,
    required DeviceSessionDto deviceSession,
  }) async {
    final bootstrapDto = await _remoteDataSource.bootstrap(
      serverUrl,
      accessToken: deviceSession.accessToken,
      deviceId: deviceSession.deviceId,
    );
    final webdavConfig = _normalizeWebdavConfig(bootstrapDto.webdavConfig);
    final session = _buildSessionEntity(
      bootstrapDto: bootstrapDto,
      webdavConfig: webdavConfig,
    );

    _currentSession.set(
      serverId: bootstrapDto.serverId,
      serverName: bootstrapDto.serverName,
      serverVersion: bootstrapDto.serverVersion,
      serverStatus: bootstrapDto.serverStatus,
      serverPlatform: bootstrapDto.platform,
      serverUrl: serverUrl,
      role: 'device',
      deviceId: deviceSession.deviceId,
      sessionId: deviceSession.sessionId,
      accessToken: deviceSession.accessToken,
      expiresAt: deviceSession.expiresAtDateTime,
      protocol: bootstrapDto.protocol,
      rootId: bootstrapDto.rootId,
      rootName: bootstrapDto.rootName,
      roots: bootstrapDto.roots,
      webdavConfig: webdavConfig,
      capabilities: bootstrapDto.capabilities,
    );

    return session;
  }

  Future<AuthSessionEntity> _restoreFromSavedSession(
    AuthSessionDto savedSession,
  ) async {
    final normalizedServerUrl = NasNetworkAccessPolicy.normalizeServerUrl(
      savedSession.serverUrl,
    );
    final serverId = savedSession.serverId.trim();
    final storedDeviceSession =
        serverId.isEmpty
            ? null
            : await _localDataSource.loadDeviceSession(serverId: serverId);
    final deviceSession =
        storedDeviceSession ??
        DeviceSessionDto(
          deviceId: savedSession.deviceId ?? '',
          accessToken: savedSession.accessToken,
          refreshToken: savedSession.refreshToken ?? '',
          sessionId: savedSession.sessionId,
          expiresAt: savedSession.expiresAt,
        );
    final refreshedDeviceSession = await _ensureFreshDeviceSession(
      serverUrl: normalizedServerUrl,
      deviceSession: deviceSession,
    );
    await _ensureEnrolledDeviceIdentityMatchesPhysical(
      deviceSession: refreshedDeviceSession,
    );
    final session = await _bootstrapWithDeviceTokens(
      serverUrl: normalizedServerUrl,
      deviceSession: refreshedDeviceSession,
    );

    if (serverId.isNotEmpty) {
      await _localDataSource.saveDeviceSession(
        serverId: serverId,
        session: refreshedDeviceSession,
      );
    }

    return session;
  }

  Future<DeviceSessionDto> _ensureFreshDeviceSession({
    required String serverUrl,
    required DeviceSessionDto deviceSession,
  }) async {
    final expiresAt = deviceSession.expiresAtDateTime;
    final now = DateTime.now().toUtc();
    if (expiresAt != null && expiresAt.isAfter(now.add(const Duration(minutes: 1)))) {
      return deviceSession;
    }

    final refreshed = await _remoteDataSource.refreshDeviceToken(
      serverUrl,
      refreshToken: deviceSession.refreshToken,
    );
    return DeviceSessionDto(
      deviceId: refreshed.deviceId.isNotEmpty
          ? refreshed.deviceId
          : deviceSession.deviceId,
      accessToken: refreshed.accessToken,
      refreshToken: deviceSession.refreshToken,
      sessionId: refreshed.sessionId.isNotEmpty
          ? refreshed.sessionId
          : deviceSession.sessionId,
      expiresAt: refreshed.expiresAt,
    );
  }

  Future<void> _ensureEnrolledDeviceIdentityMatchesPhysical({
    required DeviceSessionDto deviceSession,
  }) async {
    final enrolledId = DeviceIdNormalizer.normalize(deviceSession.deviceId);
    if (enrolledId == null || enrolledId.isEmpty) {
      return;
    }

    final physicalId = DeviceIdNormalizer.normalize(
      await _clientIdentityService.getDeviceId(),
    );
    if (physicalId == null || physicalId.isEmpty) {
      return;
    }

    if (physicalId != enrolledId) {
      throw const AppException(
        code: 'DEVICE_IDENTITY_MISMATCH',
        message: '设备标识已变化，请重新扫描服务端连接二维码完成配对',
      );
    }
  }

  Future<void> _persistServerHistory({
    required String serverUrl,
    required AuthSessionEntity session,
  }) async {
    final certificateSha256 = _unifiedNodeStore
        .findServerByUrl(serverUrl)
        ?.server
        ?.certificateSha256;
    await _localDataSource.addServerToHistory(
      name: session.serverProfile.serverName,
      url: serverUrl,
      serverId: session.serverProfile.serverId,
      platform: session.serverProfile.platform,
      certificateSha256: certificateSha256,
    );
  }

  AuthSessionEntity _buildSessionEntity({
    required BootstrapResponseDto bootstrapDto,
    required Map<String, dynamic>? webdavConfig,
  }) {
    return AuthSessionEntity(
      serverProfile: ServerProfileEntity(
        serverId: bootstrapDto.serverId,
        serverName: bootstrapDto.serverName,
        serverVersion: bootstrapDto.serverVersion,
        serverStatus: bootstrapDto.serverStatus,
        platform: bootstrapDto.platform,
      ),
      fileAccess: FileAccessConfigEntity(
        protocol: bootstrapDto.protocol,
        webdavConfig: webdavConfig,
      ),
      capabilities: ServerCapabilitiesEntity(
        dashboard: bootstrapDto.capabilities?['dashboard'],
        preview: bootstrapDto.capabilities?['preview'],
        relay: bootstrapDto.capabilities?['relay'],
        realtime: bootstrapDto.capabilities?['realtime'],
      ),
      rootId: bootstrapDto.rootId,
      rootName: bootstrapDto.rootName,
    );
  }
}
