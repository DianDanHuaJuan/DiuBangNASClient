/// 文件输入：安全存储、本地会话键值、设备令牌存储
/// 文件职责：存取本地会话与设备令牌
/// 文件对外接口：AuthLocalDataSource
/// 文件包含：AuthLocalDataSource
import 'dart:convert';

import '../../../../core/device/device_session_dto.dart';
import '../../../../core/node/unified_node.dart';
import '../../../../core/storage/device_token_store.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../../core/storage/secure_store.dart';
import '../models/auth_session_dto.dart';

class AuthLocalDataSource {
  final SecureStore _secureStore;
  final KeyValueStore _keyValueStore;
  final DeviceTokenStore _deviceTokenStore;

  static const _keySession = 'auth_session';

  AuthLocalDataSource({
    required SecureStore secureStore,
    required KeyValueStore keyValueStore,
    required DeviceTokenStore deviceTokenStore,
  }) : _secureStore = secureStore,
       _keyValueStore = keyValueStore,
       _deviceTokenStore = deviceTokenStore;

  Future<void> saveSession(AuthSessionDto session) async {
    await _secureStore.write(_keySession, jsonEncode(session.toJson()));
  }

  Future<AuthSessionDto?> loadSession() async {
    final sessionJson = await _secureStore.read(_keySession);
    if (sessionJson == null) return null;
    final decoded = jsonDecode(sessionJson);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return AuthSessionDto.fromJson(decoded);
  }

  Future<void> clearSession() async {
    await _secureStore.delete(_keySession);
  }

  Future<void> saveDeviceSession({
    required String serverId,
    required DeviceSessionDto session,
  }) async {
    await _deviceTokenStore.saveSession(serverId: serverId, session: session);
  }

  Future<DeviceSessionDto?> loadDeviceSession({required String serverId}) async {
    return _deviceTokenStore.loadSession(serverId: serverId);
  }

  Future<void> clearDeviceSession({required String serverId}) async {
    await _deviceTokenStore.clearSession(serverId: serverId);
  }

  Future<void> clearCredentials({required String serverUrl}) async {
    await _secureStore.clearCredentials(serverUrl: serverUrl);
  }

  Future<void> saveLastServerUrl(String url) async {
    await _keyValueStore.saveLastServerUrl(url);
  }

  String? getLastServerUrl() {
    return _keyValueStore.getString('last_server_url');
  }

  Future<bool> hasRecoverableSession() async {
    final savedSession = await loadSession();
    final sessionServerUrl = savedSession?.serverUrl.trim() ?? '';
    if (sessionServerUrl.isNotEmpty &&
        (savedSession?.accessToken.trim().isNotEmpty ?? false)) {
      return true;
    }

    final lastServerUrl = getLastServerUrl()?.trim() ?? '';
    if (lastServerUrl.isEmpty) {
      return false;
    }

    final savedSessionByUrl = savedSession;
    final serverId = savedSessionByUrl?.serverId.trim() ?? '';
    if (serverId.isNotEmpty) {
      final deviceSession = await loadDeviceSession(serverId: serverId);
      if (deviceSession != null &&
          deviceSession.accessToken.trim().isNotEmpty &&
          deviceSession.refreshToken.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  Future<void> addServerToHistory({
    required String name,
    required String url,
    String? serverId,
    String? platform,
    String? certificateSha256,
    bool isTrusted = false,
    List<String> trustedHosts = const <String>[],
  }) async {
    final servers = _keyValueStore.getServerNodes().toList(growable: true);
    final now = DateTime.now().toUtc();
    final existingIndex = servers.indexWhere((server) {
      if (server.network.connectBaseUrl == url) {
        return true;
      }
      if ((serverId?.trim().isNotEmpty ?? false) &&
          server.identity.serverId == serverId!.trim()) {
        return true;
      }
      return false;
    });

    final nextNode = UnifiedNode.savedServer(
      serverUrl: url,
      serverId: serverId,
      displayName: name,
      platform: platform,
      certificateSha256: certificateSha256,
      trustedHosts: trustedHosts,
      isTrusted: isTrusted,
      updatedAt: now,
    );

    if (existingIndex != -1) {
      final previous = servers[existingIndex];
      servers[existingIndex] = previous.copyWith(
        relations: <NodeRelation>{...previous.relations, NodeRelation.saved},
        identity: previous.identity.copyWith(
          displayName: name.trim().isNotEmpty
              ? name.trim()
              : previous.identity.displayName,
          serverId: serverId ?? previous.identity.serverId,
          platform: platform ?? previous.identity.platform,
        ),
        network: previous.network.copyWith(
          connectBaseUrl: nextNode.network.connectBaseUrl,
          host: nextNode.network.host,
          port: nextNode.network.port,
        ),
        meta: previous.meta.copyWith(updatedAt: now),
        server: (previous.server ?? const ServerFacet()).copyWith(
          certificateSha256:
              certificateSha256 ?? previous.server?.certificateSha256,
          isTrusted: isTrusted || (previous.server?.isTrusted ?? false),
          trustedHosts: <String>{
            ...previous.server?.trustedHosts ?? const <String>[],
            ...trustedHosts,
          }.toList(growable: false)..sort(),
        ),
      );
    } else {
      servers.add(nextNode);
    }

    await _keyValueStore.saveServerNodes(servers);
  }
}
