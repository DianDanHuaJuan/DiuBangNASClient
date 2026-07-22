import 'dart:async';

import 'dart:io';

import '../node/realtime_presence_client_dto.dart';
import '../session/current_session.dart';
import '../session/server_availability_controller.dart';
import 'app_websocket_client.dart';
import 'realtime_connection_state.dart';

typedef RealtimeSocketClientFactory =
    RealtimeSocketClient Function({
      required String url,
      Map<String, Object>? headers,
      HttpClient? customClient,
      WebSocketMessageCallback? onMessage,
      VoidCallback? onDisconnected,
      void Function(String error)? onError,
    });
typedef RealtimeSessionRecoveryHandler = Future<bool> Function();

class RealtimeSessionService {
  RealtimeSessionService({
    required CurrentSession currentSession,
    Future<String> Function()? clientIdProvider,
    Future<String> Function()? clientNameProvider,
    Future<String> Function()? deviceIdProvider,
    Future<String> Function()? deviceNameProvider,
    Future<String?> Function()? clientPlatformProvider,
    Future<String?> Function()? clientBrandProvider,
    Future<String?> Function()? clientModelProvider,
    Future<String?> Function()? clientAppVersionProvider,
    Future<String?> Function(String serverUrl)? clientRouteIpProvider,
    Future<String?> Function()? presenceLabelProvider,
    Future<String?> Function()? avatarUpdatedAtProvider,
    RealtimeSocketClientFactory? clientFactory,
    HttpClient Function(String url)? websocketHttpClientFactory,
    RealtimeSessionRecoveryHandler? sessionRecoveryHandler,
    ServerAvailabilityController? serverAvailabilityController,
    Future<void> Function()? onSessionRecovered,
    Duration reconnectDelay = const Duration(seconds: 5),
  }) : _currentSession = currentSession,
       _deviceIdProvider = deviceIdProvider ?? clientIdProvider!,
       _deviceNameProvider = deviceNameProvider ?? clientNameProvider!,
       _clientPlatformProvider = clientPlatformProvider,
       _clientBrandProvider = clientBrandProvider,
       _clientModelProvider = clientModelProvider,
       _clientAppVersionProvider = clientAppVersionProvider,
       _clientRouteIpProvider = clientRouteIpProvider,
       _presenceLabelProvider = presenceLabelProvider,
       _avatarUpdatedAtProvider = avatarUpdatedAtProvider,
       _clientFactory = clientFactory ?? _defaultClientFactory,
       _websocketHttpClientFactory = websocketHttpClientFactory,
       _sessionRecoveryHandler = sessionRecoveryHandler,
       _serverAvailabilityController = serverAvailabilityController,
       _onSessionRecovered = onSessionRecovered,
       _reconnectDelay = reconnectDelay;

  final CurrentSession _currentSession;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _deviceNameProvider;
  final Future<String?> Function()? _clientPlatformProvider;
  final Future<String?> Function()? _clientBrandProvider;
  final Future<String?> Function()? _clientModelProvider;
  final Future<String?> Function()? _clientAppVersionProvider;
  final Future<String?> Function(String serverUrl)? _clientRouteIpProvider;
  final Future<String?> Function()? _presenceLabelProvider;
  final Future<String?> Function()? _avatarUpdatedAtProvider;
  final RealtimeSocketClientFactory _clientFactory;
  final HttpClient Function(String url)? _websocketHttpClientFactory;
  final RealtimeSessionRecoveryHandler? _sessionRecoveryHandler;
  final ServerAvailabilityController? _serverAvailabilityController;
  final Future<void> Function()? _onSessionRecovered;
  final Duration _reconnectDelay;
  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();

  RealtimeSocketClient? _client;
  Timer? _heartbeatTimer;
  Timer? _heartbeatWatchdogTimer;
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  bool _suppressDisconnectHandler = false;
  bool _disposed = false;
  int _heartbeatTimeoutSec = 45;
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.idle;
  void Function(Map<String, dynamic> dashboardPayload)? _dashboardListener;
  void Function(List<RealtimePresenceClientDto> clients, {Set<String>? enrolledDeviceIds})?
      _presenceListener;
  void Function(String type, Map<String, dynamic> payload)? _transferListener;
  void Function(List<dynamic> pendingTransfers)? _relaySnapshotListener;

  static RealtimeSocketClient _defaultClientFactory({
    required String url,
    Map<String, Object>? headers,
    HttpClient? customClient,
    WebSocketMessageCallback? onMessage,
    VoidCallback? onDisconnected,
    void Function(String error)? onError,
  }) {
    return AppWebSocketClient(
      url: url,
      headers: headers,
      customClient: customClient,
      onMessage: onMessage,
      onDisconnected: onDisconnected,
      onError: onError,
    );
  }

  bool get isConnected => _status.isConnected;

  Stream<RealtimeConnectionStatus> get statusStream => _statusController.stream;

  RealtimeConnectionStatus get currentStatus => _status;

  void setDashboardListener(
    void Function(Map<String, dynamic> dashboardPayload)? listener,
  ) {
    _dashboardListener = listener;
  }

  void clearDashboardListener() {
    _dashboardListener = null;
  }

  void setPresenceListener(
    void Function(
      List<RealtimePresenceClientDto> clients, {
      Set<String>? enrolledDeviceIds,
    })?
    listener,
  ) {
    _presenceListener = listener;
  }

  void clearPresenceListener() {
    _presenceListener = null;
  }

  void setTransferListener(
    void Function(String type, Map<String, dynamic> payload)? listener,
  ) {
    _transferListener = listener;
  }

  void clearTransferListener() {
    _transferListener = null;
  }

  void setRelaySnapshotListener(
    void Function(List<dynamic> pendingTransfers)? listener,
  ) {
    _relaySnapshotListener = listener;
  }

  void clearRelaySnapshotListener() {
    _relaySnapshotListener = null;
  }

  Future<void> connect({
    RealtimeConnectionStatus targetStatus = RealtimeConnectionStatus.connecting,
    bool allowSessionRecovery = true,
  }) async {
    if (_disposed) {
      return;
    }

    _manualDisconnect = false;
    _reconnectTimer?.cancel();

    final accessToken = _currentSession.accessToken;
    final sessionId = _currentSession.sessionId;
    final serverUrl = _currentSession.serverUrl;
    if (!_currentSession.hasWebsocketCapability ||
        accessToken == null ||
        accessToken.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty ||
        serverUrl == null ||
        serverUrl.isEmpty) {
      return;
    }

    final existingClient = _client;
    if (existingClient != null &&
        (existingClient.isConnected || existingClient.isConnecting)) {
      return;
    }

    _updateStatus(targetStatus);
    final websocketUrl = _buildWebsocketUrl(serverUrl);
    final customClient =
        _websocketHttpClientFactory == null ||
            !websocketUrl.startsWith('wss://')
        ? null
        : _websocketHttpClientFactory(websocketUrl);
    final client = _clientFactory(
      url: websocketUrl,
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_currentSession.deviceId?.trim().isNotEmpty ?? false)
          'X-NAS-Device-Id': _currentSession.deviceId!.trim(),
      },
      customClient: customClient,
      onMessage: _handleMessage,
      onDisconnected: _handleDisconnected,
      onError: (_) {},
    );

    _client = client;
    try {
      await client.connect();
      await _sendHello();
    } catch (_) {
      _client = null;
      await _handleConnectFailure(
        targetStatus: targetStatus,
        allowSessionRecovery: allowSessionRecovery,
      );
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelHeartbeatWatchdog();

    final client = _client;
    _client = null;
    _updateStatus(RealtimeConnectionStatus.disconnected);
    await client?.disconnect();
  }

  Future<void> reconnectNow() async {
    if (_disposed) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelHeartbeatWatchdog();

    final client = _client;
    if (client != null) {
      _manualDisconnect = true;
      _client = null;
      await client.disconnect();
      _manualDisconnect = false;
    }

    await connect(targetStatus: RealtimeConnectionStatus.connecting);
  }

  Future<void> handleForegroundResume() async {
    if (_disposed) {
      return;
    }

    final client = _client;
    if (client != null && client.isConnected) {
      await _sendHeartbeat();
      return;
    }

    if (client != null && client.isConnecting) {
      return;
    }

    await reconnectNow();
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _statusController.close();
  }

  Future<void> refreshHello() => _sendHello();

  Future<void> _sendHello() async {
    final client = _client;
    final sessionId = _currentSession.sessionId;
    if (client == null || sessionId == null) {
      return;
    }

    final deviceId = _currentSession.deviceId?.trim().isNotEmpty == true
        ? _currentSession.deviceId!
        : await _deviceIdProvider();
    final deviceName = await _deviceNameProvider();
    final platform = await _clientPlatformProvider?.call();
    final brand = await _clientBrandProvider?.call();
    final model = await _clientModelProvider?.call();
    final appVersion = await _clientAppVersionProvider?.call();
    final serverUrl = _currentSession.serverUrl;
    final reportedRouteIp = serverUrl == null
        ? null
        : await _clientRouteIpProvider?.call(serverUrl);
    final payload = <String, Object>{
      'sessionId': sessionId,
      'deviceId': deviceId,
      'deviceName': deviceName,
    };
    final trimmedPlatform = platform?.trim() ?? '';
    if (trimmedPlatform.isNotEmpty) {
      payload['platform'] = trimmedPlatform;
    }
    final trimmedBrand = brand?.trim() ?? '';
    if (trimmedBrand.isNotEmpty) {
      payload['brand'] = trimmedBrand;
    }
    final trimmedModel = model?.trim() ?? '';
    if (trimmedModel.isNotEmpty) {
      payload['model'] = trimmedModel;
    }
    final trimmedAppVersion = appVersion?.trim() ?? '';
    if (trimmedAppVersion.isNotEmpty) {
      payload['appVersion'] = trimmedAppVersion;
    }
    final trimmedReportedRouteIp = reportedRouteIp?.trim() ?? '';
    if (trimmedReportedRouteIp.isNotEmpty) {
      payload['reportedRouteIp'] = trimmedReportedRouteIp;
    }
    final label = await _presenceLabelProvider?.call();
    final trimmedLabel = label?.trim() ?? '';
    if (trimmedLabel.isNotEmpty) {
      payload['label'] = trimmedLabel;
    }
    final avatarUpdatedAt = await _avatarUpdatedAtProvider?.call();
    final trimmedAvatarUpdatedAt = avatarUpdatedAt?.trim() ?? '';
    if (trimmedAvatarUpdatedAt.isNotEmpty) {
      payload['avatarUpdatedAt'] = trimmedAvatarUpdatedAt;
    }

    await client.sendEnvelope(type: 'hello', payload: payload);
  }

  Future<void> _sendHeartbeat() async {
    final client = _client;
    final sessionId = _currentSession.sessionId;
    if (client == null || sessionId == null || !client.isConnected) {
      return;
    }

    await client.sendEnvelope(
      type: 'heartbeat',
      payload: {'sessionId': sessionId},
    );
  }

  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    final payload = _readMap(message['payload']);

    switch (type) {
      case 'hello.ack':
        _handleHelloAck(payload);
        return;
      case 'heartbeat.ack':
        _serverAvailabilityController?.markOnline();
        _resetHeartbeatWatchdog();
        return;
      case 'server.state.changed':
        final server = _readMap(payload?['server']);
        if (server?['status'] != 'online') {
          _serverAvailabilityController?.markOffline();
          unawaited(disconnect());
        }
        return;
      case 'dashboard.updated':
        if (payload != null) {
          _dashboardListener?.call(payload);
        }
        return;
      case 'presence.changed':
        _handlePresencePayload(payload);
        return;
      case 'session.revoked':
        unawaited(_handleSessionRevoked(payload));
        return;
      case 'connection.replaced':
        unawaited(disconnect());
        return;
      case 'transfer.created':
      case 'transfer.upload.progress':
      case 'transfer.ready':
      case 'transfer.download.progress':
      case 'transfer.completed':
      case 'transfer.failed':
      case 'transfer.cancelled':
        if (payload != null) {
          _transferListener?.call(type!, payload);
        }
        return;
      default:
        return;
    }
  }

  void _handleHelloAck(Map<String, dynamic>? payload) {
    if (payload == null) {
      return;
    }

    final heartbeatIntervalSec =
        _readInt(payload['heartbeatIntervalSec']) ??
        _currentSession.realtimeHeartbeatIntervalSec;
    final heartbeatTimeoutSec =
        _readInt(payload['heartbeatTimeoutSec']) ??
        _currentSession.realtimeHeartbeatTimeoutSec;
    _heartbeatTimeoutSec = heartbeatTimeoutSec;
    _heartbeatTimer?.cancel();
    _serverAvailabilityController?.markOnline();
    _updateStatus(RealtimeConnectionStatus.connected);
    _resetHeartbeatWatchdog();
    _heartbeatTimer = Timer.periodic(Duration(seconds: heartbeatIntervalSec), (
      _,
    ) {
      unawaited(_sendHeartbeat());
    });

    final snapshot = _readMap(payload['snapshot']);
    final dashboard = snapshot == null ? null : _readMap(snapshot['dashboard']);
    final presence = snapshot == null ? null : _readMap(snapshot['presence']);
    final relay = snapshot == null ? null : _readMap(snapshot['relay']);
    if (dashboard != null) {
      _dashboardListener?.call(dashboard);
    }
    _handlePresencePayload(presence);
    final pendingTransfers = relay?['pendingTransfers'];
    if (pendingTransfers is List && pendingTransfers.isNotEmpty) {
      _relaySnapshotListener?.call(pendingTransfers);
    }
  }

  void _handleDisconnected() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelHeartbeatWatchdog();
    _serverAvailabilityController?.markOffline();

    if (_manualDisconnect || _disposed || _suppressDisconnectHandler) {
      return;
    }

    _client = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _disposed) {
      return;
    }

    _updateStatus(RealtimeConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      unawaited(connect(targetStatus: RealtimeConnectionStatus.reconnecting));
    });
  }

  Future<void> _handleConnectFailure({
    required RealtimeConnectionStatus targetStatus,
    required bool allowSessionRecovery,
  }) async {
    _serverAvailabilityController?.markOffline();
    if (allowSessionRecovery) {
      final recovered = await _recoverSession();
      if (recovered) {
        await connect(targetStatus: targetStatus, allowSessionRecovery: false);
        return;
      }
    }
    _scheduleReconnect();
  }

  Future<void> _handleSessionRevoked(Map<String, dynamic>? payload) async {
    final code = payload == null ? null : payload['code'] as String?;
    final shouldRecover =
        code == null ||
        code == 'AUTH_INVALID' ||
        code == 'AUTH_EXPIRED' ||
        code == 'AUTH_REVOKED';
    if (shouldRecover) {
      final recovered = await _recoverSession();
      if (recovered) {
        await reconnectNow();
        return;
      }
    }

    await disconnect();
  }

  Future<bool> _recoverSession() async {
    final recoveryHandler = _sessionRecoveryHandler;
    if (recoveryHandler == null) {
      return false;
    }

    final recovered = await recoveryHandler();
    if (recovered) {
      await _onSessionRecovered?.call();
    }
    return recovered;
  }

  String _buildWebsocketUrl(String serverUrl) {
    final uri = Uri.parse(serverUrl);
    final path = _currentSession.realtimeEndpointPath;
    return uri
        .replace(
          scheme: uri.scheme == 'https' ? 'wss' : 'ws',
          path: path.startsWith('/') ? path : '/$path',
          query: null,
          fragment: null,
        )
        .toString();
  }

  Map<String, dynamic>? _readMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  void _handlePresencePayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      return;
    }
    _presenceListener?.call(
      _readPresenceClients(payload['clients']),
      enrolledDeviceIds: _readStringIdSet(payload['enrolledDeviceIds']),
    );
  }

  Set<String>? _readStringIdSet(Object? value) {
    if (value is! List) {
      return null;
    }
    final ids = <String>{};
    for (final item in value) {
      final id = '$item'.trim();
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    return Set<String>.unmodifiable(ids);
  }

  List<RealtimePresenceClientDto> _readPresenceClients(Object? value) {
    if (value is! List) {
      return const <RealtimePresenceClientDto>[];
    }
    final items = <RealtimePresenceClientDto>[];
    for (final item in value) {
      final mapped = _readMap(item);
      if (mapped != null) {
        try {
          items.add(RealtimePresenceClientDto.fromJson(mapped));
        } on FormatException {
          continue;
        }
      }
    }
    return List.unmodifiable(items);
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  void _updateStatus(RealtimeConnectionStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _cancelHeartbeatWatchdog() {
    _heartbeatWatchdogTimer?.cancel();
    _heartbeatWatchdogTimer = null;
  }

  void _resetHeartbeatWatchdog() {
    _cancelHeartbeatWatchdog();
    if (_disposed || _manualDisconnect) {
      return;
    }
    _heartbeatWatchdogTimer = Timer(Duration(seconds: _heartbeatTimeoutSec), () {
      _handleHeartbeatWatchdogTimeout();
    });
  }

  void _handleHeartbeatWatchdogTimeout() {
    if (_disposed || _manualDisconnect) {
      return;
    }
    _cancelHeartbeatWatchdog();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _serverAvailabilityController?.markOffline();
    final client = _client;
    _client = null;
    _updateStatus(RealtimeConnectionStatus.reconnecting);
    if (client != null) {
      unawaited(_tearDownClient(client));
    }
    _scheduleReconnect();
  }

  Future<void> _tearDownClient(RealtimeSocketClient client) async {
    _suppressDisconnectHandler = true;
    try {
      await client.disconnect();
    } finally {
      _suppressDisconnectHandler = false;
    }
  }
}
