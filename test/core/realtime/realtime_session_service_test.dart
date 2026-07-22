import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/realtime_presence_client_dto.dart';
import 'package:nasclient/core/realtime/app_websocket_client.dart';
import 'package:nasclient/core/realtime/realtime_connection_state.dart';
import 'package:nasclient/core/realtime/realtime_session_service.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/core/session/server_availability_controller.dart';
import 'package:nasclient/core/auth/root_info.dart';

void main() {
  group('RealtimeSessionService', () {
    test(
      'connects with bearer auth, sends hello, and applies dashboard snapshot',
      () async {
        final session = CurrentSession();
        session.clear();
        session.set(
          serverId: 'server-1',
          serverName: 'MiniNAS',
          serverVersion: '1.0.0',
          serverStatus: 'online',
          serverUrl: 'https://nas.local:9443',
          username: 'client-user',
          password: '',
          protocol: 'webdav',
          rootId: 'fs',
          rootName: 'NAS',
          accountId: 'acct-1',
          role: 'client',
          clientId: 'tablet-01',
          sessionId: 'sess-1',
          accessToken: 'access-token-1',
          roots: const [
            RootInfo(
              id: 'fs',
              name: 'NAS',
              path: '/fs',
              type: 'local',
              writable: true,
            ),
          ],
          capabilities: const {
            'realtime': {
              'websocket': true,
              'endpoint': '/api/v1/realtime/ws',
              'heartbeatIntervalSec': 1,
              'heartbeatTimeoutSec': 3,
            },
          },
        );

        late _FakeRealtimeSocketClient fakeClient;
        Map<String, dynamic>? dashboardPayload;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          clientPlatformProvider: () async => 'android',
          clientBrandProvider: () async => 'Google',
          clientModelProvider: () async => 'Pixel 7',
          clientAppVersionProvider: () async => '1.0.0',
          clientRouteIpProvider: (_) async => '192.168.1.25',
          reconnectDelay: const Duration(milliseconds: 50),
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                fakeClient = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                return fakeClient;
              },
        );
        addTearDown(service.dispose);
        final connectionStates = <RealtimeConnectionStatus>[];
        final statusSubscription = service.statusStream.listen(
          connectionStates.add,
        );
        addTearDown(statusSubscription.cancel);

        service.setDashboardListener((payload) {
          dashboardPayload = payload;
        });

        await service.connect();

        expect(fakeClient.url, 'wss://nas.local:9443/api/v1/realtime/ws');
        expect(fakeClient.headers?['Authorization'], 'Bearer access-token-1');
        expect(fakeClient.sentMessages, hasLength(1));
        expect(fakeClient.sentMessages.first['type'], 'hello');
        expect(fakeClient.sentMessages.first['payload']['sessionId'], 'sess-1');
        expect(
          fakeClient.sentMessages.first['payload']['deviceId'],
          'tablet-01',
        );
        expect(fakeClient.sentMessages.first['payload']['platform'], 'android');
        expect(fakeClient.sentMessages.first['payload']['brand'], 'Google');
        expect(fakeClient.sentMessages.first['payload']['model'], 'Pixel 7');
        expect(fakeClient.sentMessages.first['payload']['appVersion'], '1.0.0');
        expect(
          fakeClient.sentMessages.first['payload']['reportedRouteIp'],
          '192.168.1.25',
        );

        fakeClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 1,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(dashboardPayload?['network']['localIp'], '192.168.1.10');
        expect(service.currentStatus, RealtimeConnectionStatus.connected);
        expect(
          connectionStates,
          containsAllInOrder([
            RealtimeConnectionStatus.connecting,
            RealtimeConnectionStatus.connected,
          ]),
        );

        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(
          fakeClient.sentMessages.any(
            (message) => message['type'] == 'heartbeat',
          ),
          isTrue,
        );
      },
    );

    test(
      'keeps the same websocket after short background and resumes with a heartbeat',
      () async {
        final session = _buildSession();
        late _FakeRealtimeSocketClient fakeClient;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                fakeClient = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                return fakeClient;
              },
        );
        addTearDown(service.dispose);

        await service.connect();
        fakeClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 15,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final initialConnectCalls = fakeClient.connectCalls;
        final initialMessageCount = fakeClient.sentMessages.length;
        await service.handleForegroundResume();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(fakeClient.connectCalls, initialConnectCalls);
        expect(fakeClient.sentMessages.length, initialMessageCount + 1);
        expect(fakeClient.sentMessages.last['type'], 'heartbeat');
        expect(service.currentStatus, RealtimeConnectionStatus.connected);
      },
    );

    test(
      'drives online and offline availability from websocket events',
      () async {
        final session = _buildSession();
        final availabilityController = ServerAvailabilityController()
          ..startMonitoring(initialStatus: ServerAvailabilityStatus.offline);
        late _FakeRealtimeSocketClient fakeClient;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          serverAvailabilityController: availabilityController,
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                fakeClient = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                return fakeClient;
              },
        );
        addTearDown(service.dispose);

        await service.connect();
        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.offline,
        );

        fakeClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 15,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.online,
        );

        fakeClient.simulateUnexpectedDisconnect();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.offline,
        );
      },
    );

    test(
      'forwards dashboard.updated and disconnects when session is revoked',
      () async {
        final session = _buildSession();

        late _FakeRealtimeSocketClient fakeClient;
        Map<String, dynamic>? dashboardPayload;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                fakeClient = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                return fakeClient;
              },
        );
        addTearDown(service.dispose);

        service.setDashboardListener((payload) {
          dashboardPayload = payload;
        });

        await service.connect();
        fakeClient.emitMessage({
          'type': 'dashboard.updated',
          'payload': _dashboardSummaryPayload(),
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(dashboardPayload?['server']['status'], 'online');

        fakeClient.emitMessage({
          'type': 'session.revoked',
          'payload': {'code': 'AUTH_REVOKED'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fakeClient.disconnectCalls, 1);
        expect(service.currentStatus, RealtimeConnectionStatus.disconnected);
      },
    );

    test(
      'marks offline when server.state.changed reports offline status',
      () async {
        final session = _buildSession();
        final availabilityController = ServerAvailabilityController()
          ..startMonitoring(initialStatus: ServerAvailabilityStatus.offline);
        late _FakeRealtimeSocketClient fakeClient;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          serverAvailabilityController: availabilityController,
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                fakeClient = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                return fakeClient;
              },
        );
        addTearDown(service.dispose);

        await service.connect();
        fakeClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 15,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.online,
        );

        fakeClient.emitMessage({
          'type': 'server.state.changed',
          'payload': {
            'server': {'status': 'offline'},
            'reason': 'server_stopping',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.offline,
        );
        expect(fakeClient.disconnectCalls, 1);
        expect(service.currentStatus, RealtimeConnectionStatus.disconnected);
      },
    );

    test(
      'marks offline when heartbeat acknowledgements stop arriving',
      () async {
        final session = _buildSession();
        final availabilityController = ServerAvailabilityController()
          ..startMonitoring(initialStatus: ServerAvailabilityStatus.offline);
        late _FakeRealtimeSocketClient fakeClient;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          serverAvailabilityController: availabilityController,
          reconnectDelay: const Duration(milliseconds: 50),
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                fakeClient = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                return fakeClient;
              },
        );
        addTearDown(service.dispose);

        await service.connect();
        fakeClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 15,
            'heartbeatTimeoutSec': 1,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.online,
        );

        await Future<void>.delayed(const Duration(milliseconds: 1200));
        expect(
          availabilityController.currentStatus,
          ServerAvailabilityStatus.offline,
        );
        expect(service.currentStatus, RealtimeConnectionStatus.reconnecting);
      },
    );

    test(
      'reconnects immediately on resume after an unexpected disconnect',
      () async {
        final session = _buildSession();
        final clients = <_FakeRealtimeSocketClient>[];
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          reconnectDelay: const Duration(seconds: 10),
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                final client = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                clients.add(client);
                return client;
              },
        );
        addTearDown(service.dispose);

        await service.connect();
        final firstClient = clients.single;
        firstClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 15,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        firstClient.simulateUnexpectedDisconnect();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(service.currentStatus, RealtimeConnectionStatus.reconnecting);

        await service.handleForegroundResume();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(clients, hasLength(2));
        expect(clients.first.connectCalls, 1);
        expect(clients.last.connectCalls, 1);
        expect(clients.last.sentMessages.last['type'], 'hello');
        expect(service.currentStatus, RealtimeConnectionStatus.connecting);
      },
    );

    test(
      'recovers the runtime session and reconnects after session revocation',
      () async {
        final session = _buildSession();
        final clients = <_FakeRealtimeSocketClient>[];
        var recoveryCalls = 0;
        var recoveredCallbacks = 0;
        final service = RealtimeSessionService(
          currentSession: session,
          clientIdProvider: () async => 'device-1',
          clientNameProvider: () async => 'Pixel 7',
          sessionRecoveryHandler: () async {
            recoveryCalls += 1;
            session.set(
              serverId: 'server-1',
              serverName: 'MiniNAS',
              serverVersion: '1.0.0',
              serverStatus: 'online',
              serverUrl: 'https://nas.local:9443',
              username: 'client-user',
              password: '',
              protocol: 'webdav',
              rootId: 'fs',
              rootName: 'NAS',
              accountId: 'acct-1',
              role: 'client',
              clientId: 'tablet-01',
              sessionId: 'sess-2',
              accessToken: 'access-token-2',
              roots: const [
                RootInfo(
                  id: 'fs',
                  name: 'NAS',
                  path: '/fs',
                  type: 'local',
                  writable: true,
                ),
              ],
              capabilities: const {
                'realtime': {
                  'websocket': true,
                  'endpoint': '/api/v1/realtime/ws',
                  'heartbeatIntervalSec': 15,
                  'heartbeatTimeoutSec': 45,
                },
              },
            );
            return true;
          },
          onSessionRecovered: () async {
            recoveredCallbacks += 1;
          },
          clientFactory:
              ({
                required String url,
                Map<String, Object>? headers,
                HttpClient? customClient,
                WebSocketMessageCallback? onMessage,
                VoidCallback? onDisconnected,
                void Function(String error)? onError,
              }) {
                final client = _FakeRealtimeSocketClient(
                  url: url,
                  headers: headers,
                  onMessage: onMessage,
                  onDisconnected: onDisconnected,
                  onError: onError,
                );
                clients.add(client);
                return client;
              },
        );
        addTearDown(service.dispose);

        await service.connect();
        final firstClient = clients.single;
        firstClient.emitMessage({
          'type': 'hello.ack',
          'payload': {
            'heartbeatIntervalSec': 15,
            'snapshot': {'dashboard': _dashboardSummaryPayload()},
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        firstClient.emitMessage({
          'type': 'session.revoked',
          'payload': {'code': 'AUTH_REVOKED'},
        });
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(recoveryCalls, 1);
        expect(recoveredCallbacks, 1);
        expect(clients, hasLength(2));
        expect(clients.last.headers?['Authorization'], 'Bearer access-token-2');
        expect(
          clients.last.sentMessages.last['payload']['sessionId'],
          'sess-2',
        );
        expect(service.currentStatus, RealtimeConnectionStatus.connecting);
      },
    );

    test('forwards presence snapshots and transfer events', () async {
      final session = _buildSession();
      late _FakeRealtimeSocketClient fakeClient;
      List<RealtimePresenceClientDto> presenceClients =
          const <RealtimePresenceClientDto>[];
      String? transferType;
      Map<String, dynamic>? transferPayload;
      final service = RealtimeSessionService(
        currentSession: session,
        clientIdProvider: () async => 'device-1',
        clientNameProvider: () async => 'Pixel 7',
        clientFactory:
            ({
              required String url,
              Map<String, Object>? headers,
              HttpClient? customClient,
              WebSocketMessageCallback? onMessage,
              VoidCallback? onDisconnected,
              void Function(String error)? onError,
            }) {
              fakeClient = _FakeRealtimeSocketClient(
                url: url,
                headers: headers,
                onMessage: onMessage,
                onDisconnected: onDisconnected,
                onError: onError,
              );
              return fakeClient;
            },
      );
      addTearDown(service.dispose);

      service.setPresenceListener((clients, {enrolledDeviceIds}) {
        presenceClients = clients;
      });
      service.setTransferListener((type, payload) {
        transferType = type;
        transferPayload = payload;
      });

      await service.connect();
      fakeClient.emitMessage({
        'type': 'hello.ack',
        'payload': {
          'heartbeatIntervalSec': 15,
          'snapshot': {
            'dashboard': _dashboardSummaryPayload(),
            'presence': {
              'clients': [
                _presenceClientPayload(clientId: 'phone-01', label: 'Phone 01'),
              ],
            },
          },
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(presenceClients, hasLength(1));
      expect(presenceClients.single.clientId, 'phone-01');

      fakeClient.emitMessage({
        'type': 'presence.changed',
        'payload': {
          'clients': [
            _presenceClientPayload(clientId: 'phone-01', label: 'Phone 01'),
            _presenceClientPayload(clientId: 'laptop-02', label: 'Laptop 02'),
          ],
        },
      });
      fakeClient.emitMessage({
        'type': 'transfer.ready',
        'payload': {'transfer': _relayTransferPayload()},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(presenceClients, hasLength(2));
      expect(transferType, 'transfer.ready');
      expect(
        (transferPayload?['transfer'] as Map<String, dynamic>)['transferId'],
        'relay-1',
      );
    });
  });
}

CurrentSession _buildSession({
  String sessionId = 'sess-1',
  String accessToken = 'access-token-1',
}) {
  final session = CurrentSession();
  session.clear();
  session.set(
    serverId: 'server-1',
    serverName: 'MiniNAS',
    serverVersion: '1.0.0',
    serverStatus: 'online',
    serverUrl: 'https://nas.local:9443',
    username: 'client-user',
    password: '',
    protocol: 'webdav',
    rootId: 'fs',
    rootName: 'NAS',
    accountId: 'acct-1',
    role: 'client',
    clientId: 'tablet-01',
    sessionId: sessionId,
    accessToken: accessToken,
    roots: const [
      RootInfo(
        id: 'fs',
        name: 'NAS',
        path: '/fs',
        type: 'local',
        writable: true,
      ),
    ],
    capabilities: const {
      'realtime': {
        'websocket': true,
        'endpoint': '/api/v1/realtime/ws',
        'heartbeatIntervalSec': 15,
        'heartbeatTimeoutSec': 45,
      },
    },
  );
  return session;
}

Map<String, dynamic> _dashboardSummaryPayload() {
  return {
    'device': {
      'deviceId': 'device-1',
      'model': 'Pixel 7',
      'brand': 'google',
      'systemVersion': '14',
      'batteryLevel': 2,
      'batteryPercent': 88.5,
      'isCharging': true,
    },
    'system': {
      'storage': {
        'totalBytes': 128000,
        'usedBytes': 64000,
        'freeBytes': 64000,
        'usagePercent': 50.0,
      },
      'uptime': 120,
    },
    'network': {'localIp': '192.168.1.10', 'port': 8080},
    'server': {'status': 'online'},
    'updatedAt': '2024-04-01T12:00:00Z',
  };
}

Map<String, dynamic> _presenceClientPayload({
  required String clientId,
  required String label,
}) {
  return {
    'connectionId': 'conn-$clientId',
    'sessionId': 'sess-$clientId',
    'accountId': 'acct-$clientId',
    'role': 'client',
    'clientId': clientId,
    'label': label,
    'deviceName': label,
    'status': 'online',
    'connectedAt': '2026-04-12T10:00:00.000Z',
    'lastSeenAt': '2026-04-12T10:05:00.000Z',
  };
}

Map<String, dynamic> _relayTransferPayload({
  String transferId = 'relay-1',
  String status = 'ready',
}) {
  return {
    'transferId': transferId,
    'senderAccountId': 'acct-1',
    'senderLabel': 'Phone 01',
    'senderClientId': 'phone-01',
    'targetCount': 1,
    'fileName': 'demo.txt',
    'fileSize': 128,
    'checksumAlgorithm': 'sha256',
    'chunkSize': 1048576,
    'storageMode': 'store_on_nas',
    'status': status,
    'createdAt': '2026-04-12T10:00:00.000Z',
    'updatedAt': '2026-04-12T10:01:00.000Z',
    'expiresAt': '2026-04-15T10:00:00.000Z',
    'targets': [
      {
        'transferId': transferId,
        'receiverClientId': 'tablet-01',
        'deliveryState': status == 'completed' ? 'completed' : 'ready',
        'updatedAt': '2026-04-12T10:01:00.000Z',
      },
    ],
    'artifact': {
      'transferId': transferId,
      'tempPath': 'D:\\relay\\$transferId.part',
      'chunkCount': 1,
      'receivedBytes': 128,
      'isSealed': status != 'uploading',
      'cleanupState': status == 'uploading' ? 'pending' : 'sealed',
      'updatedAt': '2026-04-12T10:01:00.000Z',
    },
  };
}

class _FakeRealtimeSocketClient implements RealtimeSocketClient {
  _FakeRealtimeSocketClient({
    required this.url,
    required this.headers,
    this.onMessage,
    this.onDisconnected,
    this.onError,
  });

  final String url;
  final Map<String, Object>? headers;
  final WebSocketMessageCallback? onMessage;
  final VoidCallback? onDisconnected;
  final void Function(String error)? onError;

  final List<Map<String, dynamic>> sentMessages = <Map<String, dynamic>>[];
  int disconnectCalls = 0;
  int connectCalls = 0;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  bool get isConnected => _isConnected;

  @override
  bool get isConnecting => _isConnecting;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    _isConnecting = true;
    _isConnected = true;
    _isConnecting = false;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    _isConnected = false;
    onDisconnected?.call();
  }

  void emitMessage(Map<String, dynamic> message) {
    onMessage?.call(message);
  }

  void simulateUnexpectedDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    onDisconnected?.call();
  }

  @override
  Future<void> sendEnvelope({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    sentMessages.add({'type': type, 'payload': payload});
  }
}
