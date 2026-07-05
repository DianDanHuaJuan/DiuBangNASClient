import 'dart:convert';

import '../storage/secure_store.dart';

class TrustedServerRecord {
  const TrustedServerRecord({
    required this.serverId,
    required this.serverName,
    required this.caSha256,
    required this.rootCaPem,
    this.leafSha256,
    required this.lastBaseUrl,
    required this.hosts,
  });

  final String serverId;
  final String serverName;
  final String caSha256;
  final String rootCaPem;
  final String? leafSha256;
  final String lastBaseUrl;
  final List<String> hosts;

  factory TrustedServerRecord.fromJson(Map<String, dynamic> json) {
    final hostsValue = json['hosts'];
    final hosts = hostsValue is List
        ? hostsValue.map((item) => item.toString()).toList()
        : const <String>[];
    return TrustedServerRecord(
      serverId: json['serverId'] as String? ?? '',
      serverName: json['serverName'] as String? ?? '',
      caSha256: json['caSha256'] as String? ?? '',
      rootCaPem: json['rootCaPem'] as String? ?? '',
      leafSha256: json['leafSha256'] as String?,
      lastBaseUrl: json['lastBaseUrl'] as String? ?? '',
      hosts: hosts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'serverName': serverName,
      'caSha256': caSha256,
      'rootCaPem': rootCaPem,
      'leafSha256': leafSha256,
      'lastBaseUrl': lastBaseUrl,
      'hosts': hosts,
    };
  }

  TrustedServerRecord copyWith({
    String? serverName,
    String? caSha256,
    String? rootCaPem,
    String? leafSha256,
    String? lastBaseUrl,
    List<String>? hosts,
  }) {
    return TrustedServerRecord(
      serverId: serverId,
      serverName: serverName ?? this.serverName,
      caSha256: caSha256 ?? this.caSha256,
      rootCaPem: rootCaPem ?? this.rootCaPem,
      leafSha256: leafSha256 ?? this.leafSha256,
      lastBaseUrl: lastBaseUrl ?? this.lastBaseUrl,
      hosts: hosts ?? this.hosts,
    );
  }
}

class TrustedServerStore {
  TrustedServerStore({required SecureStore secureStore})
    : _secureStore = secureStore;

  static const _storageKey = 'trusted_server_records_v1';

  final SecureStore _secureStore;
  bool _initialized = false;
  List<TrustedServerRecord> _records = const [];

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final raw = await _secureStore.read(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      _records = const [];
      _initialized = true;
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      _records = const [];
      _initialized = true;
      return;
    }
    _records = decoded
        .whereType<Map>()
        .map(
          (item) =>
              TrustedServerRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    _initialized = true;
  }

  TrustedServerRecord? findByServerUrl(String serverUrl) {
    if (!_initialized) {
      return null;
    }
    final host = _tryReadHost(serverUrl);
    if (host == null) {
      return null;
    }
    for (final record in _records) {
      if (record.hosts.contains(host)) {
        return record;
      }
    }
    return null;
  }

  TrustedServerRecord? findByServerId(String serverId) {
    if (!_initialized) {
      return null;
    }
    for (final record in _records) {
      if (record.serverId == serverId) {
        return record;
      }
    }
    return null;
  }

  Future<List<TrustedServerRecord>> listRecords() async {
    await initialize();
    return List<TrustedServerRecord>.from(_records);
  }

  Future<void> trustServer({
    required String serverId,
    String serverName = '',
    required String baseUrl,
    required String rootCaPem,
    required String caSha256,
    String? leafSha256,
  }) async {
    await initialize();
    final host = _tryReadHost(baseUrl);
    final normalizedHosts = <String>{
      ?host,
      ...?findByServerId(serverId)?.hosts,
    }.toList()..sort();
    final existingIndex = _records.indexWhere(
      (record) => record.serverId == serverId,
    );
    final updatedRecord = TrustedServerRecord(
      serverId: serverId,
      serverName: serverName,
      caSha256: caSha256,
      rootCaPem: rootCaPem,
      leafSha256: leafSha256,
      lastBaseUrl: baseUrl,
      hosts: normalizedHosts,
    );
    if (existingIndex == -1) {
      _records = [..._records, updatedRecord];
    } else {
      final next = [..._records];
      next[existingIndex] = updatedRecord;
      _records = next;
    }
    await _persist();
  }

  Future<void> clear() async {
    _records = const [];
    _initialized = true;
    await _secureStore.delete(_storageKey);
  }

  Future<void> _persist() async {
    final payload = jsonEncode(
      _records.map((record) => record.toJson()).toList(),
    );
    await _secureStore.write(_storageKey, payload);
  }

  String? _tryReadHost(String serverUrl) {
    final uri = Uri.tryParse(serverUrl.trim());
    final host = uri?.host.trim().toLowerCase();
    if (host == null || host.isEmpty) {
      return null;
    }
    return host;
  }
}
