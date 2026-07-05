/// 文件输入：WebSocket 地址、请求头、连接开关、事件监听器
/// 文件职责：为后续实时能力预留统一连接客户端
/// 文件对外接口：AppWebSocketClient
/// 文件包含：AppWebSocketClient
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

typedef WebSocketMessageCallback = void Function(Map<String, dynamic> message);

typedef VoidCallback = void Function();

abstract interface class RealtimeSocketClient {
  bool get isConnected;
  bool get isConnecting;

  Future<void> connect();
  Future<void> sendEnvelope({
    required String type,
    required Map<String, dynamic> payload,
  });
  Future<void> disconnect();
}

class AppWebSocketClient implements RealtimeSocketClient {
  IOWebSocketChannel? _socket;
  final String url;
  final Map<String, Object>? headers;
  final WebSocketMessageCallback? onMessage;
  final VoidCallback? onDisconnected;
  final void Function(String error)? onError;
  final HttpClient? customClient;
  final IOWebSocketChannel Function(
    String url, {
    Map<String, Object>? headers,
    HttpClient? customClient,
  })? channelFactory;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _didManualDisconnect = false;
  StreamSubscription? _subscription;

  AppWebSocketClient({
    required this.url,
    this.headers,
    this.onMessage,
    this.onDisconnected,
    this.onError,
    this.customClient,
    this.channelFactory,
  });

  @override
  bool get isConnected => _isConnected;

  @override
  bool get isConnecting => _isConnecting;

  IOWebSocketChannel _createChannel() {
    final factory = channelFactory;
    if (factory != null) {
      return factory(url, headers: headers, customClient: customClient);
    }
    return IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: headers,
      customClient: customClient,
    );
  }

  @override
  Future<void> connect() async {
    if (_isConnecting || _isConnected) return;

    _isConnecting = true;
    _didManualDisconnect = false;
    try {
      final socket = _createChannel();
      await socket.ready;
      _socket = socket;
      _isConnected = true;
      _isConnecting = false;
      _listenToMessages(socket);
    } catch (e) {
      _isConnecting = false;
      onError?.call(e.toString());
      rethrow;
    }
  }

  void _listenToMessages(IOWebSocketChannel socket) {
    _subscription = socket.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          onMessage?.call(data);
        } catch (_) {}
      },
      onError: (e) {
        onError?.call(e.toString());
        _handleDisconnect();
      },
      onDone: () {
        _handleDisconnect();
      },
    );
  }

  void _handleDisconnect() {
    if (!_isConnected && !_isConnecting) {
      return;
    }
    _isConnected = false;
    _isConnecting = false;
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    if (!_didManualDisconnect) {
      onDisconnected?.call();
    }
  }

  @override
  Future<void> sendEnvelope({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (!_isConnected || _socket == null) return;
    final message = jsonEncode({'type': type, 'payload': payload});
    _socket?.sink.add(message);
  }

  @override
  Future<void> disconnect() async {
    _didManualDisconnect = true;
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    _isConnected = false;
    _isConnecting = false;
    await socket?.sink.close();
  }
}
