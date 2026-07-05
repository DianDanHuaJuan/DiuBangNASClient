/// 文件输入：敏感信息键值对
/// 文件职责：安全存取用户名、密码等敏感数据，使用加密存储
/// 文件对外接口：SecureStore
/// 文件包含：SecureStore
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  final FlutterSecureStorage _storage;

  SecureStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  static String _usernameKey(String serverUrl) => 'nas_username_$serverUrl';
  static String _passwordKey(String serverUrl) => 'nas_password_$serverUrl';

  Future<void> saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _usernameKey(serverUrl), value: username);
    await _storage.write(key: _passwordKey(serverUrl), value: password);
  }

  Future<Map<String, String>?> loadCredentials({
    required String serverUrl,
  }) async {
    final username = await _storage.read(key: _usernameKey(serverUrl));
    final password = await _storage.read(key: _passwordKey(serverUrl));
    if (username == null || password == null) return null;
    return {'username': username, 'password': password};
  }

  Future<void> clearCredentials({required String serverUrl}) async {
    await _storage.delete(key: _usernameKey(serverUrl));
    await _storage.delete(key: _passwordKey(serverUrl));
  }

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
