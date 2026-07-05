/// 文件输入：SecureStore、serverId、DeviceSessionDto
/// 文件职责：按 serverId 安全存取设备 access/refresh token
/// 文件对外接口：DeviceTokenStore
/// 文件包含：DeviceTokenStore
import 'dart:convert';

import '../device/device_session_dto.dart';
import 'secure_store.dart';

class DeviceTokenStore {
  DeviceTokenStore({required SecureStore secureStore})
    : _secureStore = secureStore;

  final SecureStore _secureStore;

  static String storageKey(String serverId) => 'device_session_$serverId';

  Future<void> saveSession({
    required String serverId,
    required DeviceSessionDto session,
  }) async {
    final normalizedServerId = serverId.trim();
    if (normalizedServerId.isEmpty) {
      return;
    }
    await _secureStore.write(
      storageKey(normalizedServerId),
      jsonEncode(session.toJson()),
    );
  }

  Future<DeviceSessionDto?> loadSession({required String serverId}) async {
    final normalizedServerId = serverId.trim();
    if (normalizedServerId.isEmpty) {
      return null;
    }
    final raw = await _secureStore.read(storageKey(normalizedServerId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return DeviceSessionDto.fromJson(decoded);
  }

  Future<void> clearSession({required String serverId}) async {
    final normalizedServerId = serverId.trim();
    if (normalizedServerId.isEmpty) {
      return;
    }
    await _secureStore.delete(storageKey(normalizedServerId));
  }
}
