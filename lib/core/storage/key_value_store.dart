/// 文件输入：普通轻量配置键值对
/// 文件职责：存取应用级轻量配置，如服务器地址、上次连接信息等
/// 文件对外接口：KeyValueStore
/// 文件包含：KeyValueStore
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../node/unified_node.dart';

class KeyValueStore {
  final SharedPreferences _prefs;

  KeyValueStore._internal(this._prefs);

  factory KeyValueStore({required SharedPreferences prefs}) {
    return KeyValueStore._internal(prefs);
  }

  static const _keyLastServerUrl = 'last_server_url';
  static const _keyLastRootId = 'last_root_id';
  static const _keyTransferConcurrency = 'transfer_concurrency';
  static const _keyServerList = 'server_list';
  static const _keyPeerIdentityList = 'peer_identity_list';

  Future<void> saveLastServerInfo({
    required String serverUrl,
    required String rootId,
  }) async {
    await saveLastServerUrl(serverUrl);
    await _prefs.setString(_keyLastRootId, rootId);
  }

  Future<void> saveLastServerUrl(String serverUrl) async {
    await _prefs.setString(_keyLastServerUrl, serverUrl);
  }

  String? getLastServerUrl() {
    return _prefs.getString(_keyLastServerUrl);
  }

  bool hasLastServer() {
    return _prefs.containsKey(_keyLastServerUrl);
  }

  String? getLastRootId() {
    return _prefs.getString(_keyLastRootId);
  }

  Future<void> setTransferConcurrency(int value) async {
    await _prefs.setInt(_keyTransferConcurrency, value);
  }

  int getTransferConcurrency() {
    return _prefs.getInt(_keyTransferConcurrency) ?? 3;
  }

  Future<void> saveServerNodes(List<UnifiedNode> servers) async {
    final jsonString = jsonEncode(
      servers
          .map((server) => server.toSavedServerJson())
          .toList(growable: false),
    );
    await _prefs.setString(_keyServerList, jsonString);
  }

  List<UnifiedNode> getServerNodes() {
    final jsonString = _prefs.getString(_keyServerList);
    if (jsonString == null || jsonString.trim().isEmpty) {
      return const <UnifiedNode>[];
    }
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      return const <UnifiedNode>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => UnifiedNode.fromSavedServerJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
  }

  Future<void> savePeerNodes(List<UnifiedNode> peers) async {
    final jsonString = jsonEncode(
      peers.map((peer) => peer.toPeerIdentityJson()).toList(growable: false),
    );
    await _prefs.setString(_keyPeerIdentityList, jsonString);
  }

  List<UnifiedNode> getPeerNodes() {
    final jsonString = _prefs.getString(_keyPeerIdentityList);
    if (jsonString == null || jsonString.trim().isEmpty) {
      return const <UnifiedNode>[];
    }
    final decoded = jsonDecode(jsonString);
    if (decoded is! List) {
      return const <UnifiedNode>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => UnifiedNode.fromPeerIdentityJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .where((peer) => (peer.identity.clientId ?? '').isNotEmpty)
        .toList(growable: false);
  }

  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  String? getString(String key) {
    return _prefs.getString(key);
  }

  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  int? getInt(String key) {
    return _prefs.getInt(key);
  }

  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  Future<void> clear() async {
    await _prefs.clear();
  }
}
