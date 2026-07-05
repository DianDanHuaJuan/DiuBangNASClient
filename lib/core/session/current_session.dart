/// 文件输入：登录/恢复得到的会话字段，或统一节点快照绑定
/// 文件职责：兼容旧链路读取入口，但运行时 server/client/session 导航信息统一代理到节点快照
/// 文件对外接口：CurrentSession, SessionStateBinding
/// 文件包含：CurrentSession, SessionStateBinding
import 'dart:convert';

import '../auth/root_info.dart';
import '../node/unified_node.dart';

abstract class SessionStateBinding {
  AuthStateSnapshot get authState;
  NavigationStateSnapshot get navigationState;
  SessionContextState get sessionContext;
  UnifiedNode? get currentServer;
  UnifiedNode? get selfClient;

  void applySessionData({
    required String serverId,
    required String serverName,
    required String serverVersion,
    required String serverStatus,
    String? serverPlatform,
    required String serverUrl,
    String? username,
    String? password,
    required String protocol,
    required String rootId,
    required String rootName,
    String? accountId,
    String? role,
    String? clientId,
    String? deviceId,
    String? sessionId,
    String? accessToken,
    DateTime? expiresAt,
    List<RootInfo>? roots,
    Map<String, dynamic>? webdavConfig,
    Map<String, dynamic>? capabilities,
  });

  void updateNavigationSelection({
    required String rootId,
    required String rootName,
  });

  void clearSessionState();
}

class CurrentSession {
  static final CurrentSession _instance = CurrentSession._internal();
  factory CurrentSession() => _instance;
  CurrentSession._internal();

  SessionStateBinding? _binding;
  String? _serverId;
  String? _serverName;
  String? _serverVersion;
  String? _serverPlatform;
  String? _serverStatus;
  String? _serverUrl;
  String? _accountId;
  String? _role;
  String? _deviceId;
  String? _sessionId;
  String? _accessToken;
  DateTime? _expiresAt;
  String? _username;
  String? _password;
  String? _protocol;
  String? _rootId;
  String? _rootName;
  List<RootInfo> _roots = [];
  Map<String, dynamic>? _webdavConfig;
  Map<String, dynamic>? _capabilities;
  bool _isInitialized = false;

  void bindState(SessionStateBinding binding) {
    _binding = binding;
  }

  void unbindState(SessionStateBinding binding) {
    if (identical(_binding, binding)) {
      _binding = null;
    }
  }

  UnifiedNode? get _boundCurrentServer => _binding?.currentServer;
  UnifiedNode? get _boundSelfClient => _binding?.selfClient;
  AuthStateSnapshot? get _boundAuthState => _binding?.authState;
  NavigationStateSnapshot? get _boundNavigationState =>
      _binding?.navigationState;

  String? get serverId => _boundCurrentServer?.identity.serverId ?? _serverId;
  String? get serverName =>
      _boundCurrentServer?.identity.displayName ?? _serverName;
  String? get serverVersion =>
      _boundCurrentServer?.server?.serverVersion ?? _serverVersion;
  String? get serverPlatform =>
      _boundCurrentServer?.identity.platform ?? _serverPlatform;
  String? get serverStatus =>
      _boundCurrentServer?.runtime.status ?? _serverStatus;
  String? get serverUrl =>
      _boundCurrentServer?.network.connectBaseUrl ?? _serverUrl;
  String? get accountId =>
      _boundAuthState?.accountId ??
      _boundSelfClient?.identity.accountId ??
      _accountId;
  String? get role =>
      _boundAuthState?.role ?? _boundSelfClient?.client?.role ?? _role;
  String? get deviceId =>
      _boundAuthState?.deviceId ??
      _boundSelfClient?.identity.deviceId ??
      _deviceId;
  String? get clientId => deviceId;
  String? get sessionId =>
      _boundAuthState?.sessionId ??
      _boundCurrentServer?.presence.sessionId ??
      _sessionId;
  String? get accessToken => _boundAuthState?.accessToken ?? _accessToken;
  DateTime? get expiresAt => _boundAuthState?.expiresAt ?? _expiresAt;
  String? get username =>
      _boundAuthState?.username ??
      _boundSelfClient?.identity.username ??
      _username;
  String? get password => _boundAuthState?.password ?? _password;
  String? get protocol =>
      _boundNavigationState?.protocol ??
      _boundCurrentServer?.server?.protocol ??
      _protocol;
  String? get rootId => _boundNavigationState?.rootId ?? _rootId;
  String? get rootName => _boundNavigationState?.rootName ?? _rootName;
  List<RootInfo> get roots => _boundNavigationState?.roots ?? _roots;
  Map<String, dynamic>? get webdavConfig =>
      _boundNavigationState?.webdavConfig ??
      _boundCurrentServer?.server?.webdavConfig ??
      _webdavConfig;
  Map<String, dynamic>? get capabilities =>
      _boundCurrentServer?.server?.capabilities ?? _capabilities;
  Map<String, dynamic>? get relayCapability {
    final relay = capabilities?['relay'];
    if (relay is Map<String, dynamic>) {
      return relay;
    }
    if (relay is Map) {
      return relay.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  bool get isInitialized => _binding != null || _isInitialized;
  bool get isDeviceSession => role?.trim().toLowerCase() == 'device';
  bool get hasSession =>
      (serverId?.trim().isNotEmpty ?? false) &&
      (accessToken?.isNotEmpty ?? false);

  RootInfo? get currentRoot {
    final activeRootId = rootId;
    if (activeRootId == null) {
      return null;
    }
    return getRootById(activeRootId);
  }

  RootInfo? getRootById(String id) {
    try {
      return roots.firstWhere((root) => root.id == id);
    } catch (_) {
      return null;
    }
  }

  List<RootInfo> get writableRoots =>
      roots.where((root) => root.writable).toList(growable: false);

  List<RootInfo> get mediaRoots =>
      roots.where((root) => root.isMediastore).toList(growable: false);

  void set({
    required String serverId,
    required String serverName,
    required String serverVersion,
    required String serverStatus,
    String? serverPlatform,
    required String serverUrl,
    String? username,
    String? password,
    required String protocol,
    required String rootId,
    required String rootName,
    String? accountId,
    String? role,
    String? clientId,
    String? deviceId,
    String? sessionId,
    String? accessToken,
    DateTime? expiresAt,
    List<RootInfo>? roots,
    Map<String, dynamic>? webdavConfig,
    Map<String, dynamic>? capabilities,
  }) {
    _serverId = serverId;
    _serverName = serverName;
    _serverVersion = serverVersion;
    _serverPlatform = serverPlatform;
    _serverStatus = serverStatus;
    _serverUrl = serverUrl;
    _accountId = accountId;
    _role = role;
    _deviceId = deviceId ?? clientId;
    _sessionId = sessionId;
    _accessToken = accessToken;
    _expiresAt = expiresAt;
    _username = username;
    _password = password;
    _protocol = protocol;
    _rootId = rootId;
    _rootName = rootName;
    _roots = roots ?? const <RootInfo>[];
    _webdavConfig = webdavConfig;
    _capabilities = capabilities;
    _isInitialized = true;

    _binding?.applySessionData(
      serverId: serverId,
      serverName: serverName,
      serverVersion: serverVersion,
      serverStatus: serverStatus,
      serverPlatform: serverPlatform,
      serverUrl: serverUrl,
      username: username,
      password: password,
      protocol: protocol,
      rootId: rootId,
      rootName: rootName,
      accountId: accountId,
      role: role,
      clientId: clientId,
      deviceId: deviceId ?? clientId,
      sessionId: sessionId,
      accessToken: accessToken,
      expiresAt: expiresAt,
      roots: roots,
      webdavConfig: webdavConfig,
      capabilities: capabilities,
    );
  }

  void switchRoot(String rootId) {
    final root = getRootById(rootId);
    if (root == null) {
      return;
    }
    _rootId = root.id;
    _rootName = root.name;
    _binding?.updateNavigationSelection(rootId: root.id, rootName: root.name);
  }

  void clear() {
    _serverId = null;
    _serverName = null;
    _serverVersion = null;
    _serverPlatform = null;
    _serverStatus = null;
    _serverUrl = null;
    _accountId = null;
    _role = null;
    _deviceId = null;
    _sessionId = null;
    _accessToken = null;
    _expiresAt = null;
    _username = null;
    _password = null;
    _protocol = null;
    _rootId = null;
    _rootName = null;
    _roots = const <RootInfo>[];
    _webdavConfig = null;
    _capabilities = null;
    _isInitialized = false;
    _binding?.clearSessionState();
  }

  bool get hasDashboardCapability => capabilities?['dashboard'] == true;
  bool get hasPreviewCapability => capabilities?['preview'] != null;
  bool get hasRelayCapability => relayCapability?['enabled'] == true;
  bool get hasWebsocketCapability =>
      capabilities?['realtime']?['websocket'] == true;

  String get realtimeEndpointPath {
    final endpoint = capabilities?['realtime']?['endpoint'];
    if (endpoint is String && endpoint.trim().isNotEmpty) {
      return endpoint;
    }
    return '/api/v1/realtime/ws';
  }

  int get realtimeHeartbeatIntervalSec {
    final interval = _readRealtimeInt('heartbeatIntervalSec');
    return interval != null && interval > 0 ? interval : 15;
  }

  int get realtimeHeartbeatTimeoutSec {
    final timeout = _readRealtimeInt('heartbeatTimeoutSec');
    return timeout != null && timeout > 0 ? timeout : 45;
  }

  bool get hasImagePreview => capabilities?['preview']?['image'] == true;
  bool get hasVideoPreview => capabilities?['preview']?['video'] == true;
  bool get hasProgressiveVideo =>
      capabilities?['preview']?['progressive'] == true;

  String? get webdavBaseUrl {
    final config = webdavConfig;
    if (config == null) {
      return null;
    }
    return config['baseUrl'] as String?;
  }

  String? get authHeader {
    final currentAccessToken = accessToken;
    if (currentAccessToken != null && currentAccessToken.isNotEmpty) {
      return 'Bearer $currentAccessToken';
    }
    if (isDeviceSession) {
      return null;
    }
    final currentUsername = username;
    final currentPassword = password;
    if (currentUsername == null || currentPassword == null) {
      return null;
    }
    final credentials = '$currentUsername:$currentPassword';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  int? _readRealtimeInt(String key) {
    final value = capabilities?['realtime']?[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}
