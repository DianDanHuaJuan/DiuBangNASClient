import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/auth/root_info.dart';
import 'package:nasclient/core/network/trusted_server_store.dart';
import 'package:nasclient/core/node/realtime_presence_client_dto.dart';
import 'package:nasclient/core/node/device_display_extensions.dart';
import 'package:nasclient/core/node/unified_node.dart';
import 'package:nasclient/core/node/unified_node_store.dart';
import 'package:nasclient/core/session/current_session.dart';
import 'package:nasclient/core/session/server_availability_controller.dart';

void main() {
  group('UnifiedNodeStore', () {
    test('hydrates current server and self client from current session', () {
      final store = UnifiedNodeStore();
      final session = _buildSession();

      store.applyCurrentSession(session);

      expect(store.currentServer?.identity.serverId, 'server-1');
      expect(store.currentServer?.server?.serverVersion, '1.0.0');
      expect(
        store.currentServer?.network.connectBaseUrl,
        'https://nas.local:9443',
      );
      expect(store.selfClient?.identity.clientId, 'tablet-01');
      expect(store.authState.accountId, 'acct-1');
      expect(store.navigationState.rootId, 'fs');
      expect(store.sessionContext.currentServerNodeId, 'server:server-1');
      expect(store.sessionContext.selfClientNodeId, 'client-account:acct-1');
    });

    test(
      'updates peer nodes from presence snapshot and marks missing peers offline',
      () {
        final store = UnifiedNodeStore();
        store.applyCurrentSession(_buildSession());

        store.applyPresenceSnapshot(<RealtimePresenceClientDto>[
          RealtimePresenceClientDto.fromJson({
            'accountId': 'acct-phone-01',
            'clientId': 'phone-01',
            'label': 'Phone 01',
            'role': 'client',
            'deviceName': 'Xiaomi 14',
            'platform': 'android',
            'brand': 'Xiaomi',
            'model': '14',
            'reportedRouteIp': '192.168.1.25',
            'status': 'online',
            'connectedAt': '2026-04-12T10:00:00.000Z',
            'lastSeenAt': '2026-04-12T10:05:00.000Z',
          }),
        ]);

        final phone = store.findPeerClientByClientId('phone-01');
        expect(phone, isNotNull);
        expect(phone!.identity.displayName, 'Phone 01');
        expect(phone.network.reportedRouteIp, '192.168.1.25');
        expect(phone.presence.status, PresenceStatus.online);

        store.applyPresenceSnapshot(const <RealtimePresenceClientDto>[]);

        final offlinePhone = store.findPeerClientByClientId('phone-01');
        expect(offlinePhone, isNotNull);
        expect(offlinePhone!.presence.status, PresenceStatus.offline);
      },
    );

    test(
      'ensurePeerClient does not infer alias from relay placeholder metadata',
      () {
        final store = UnifiedNodeStore();
        store.applyCurrentSession(_buildSession());
        store.ensurePeerClient(clientId: 'phone-01');

        store.applyPresenceSnapshot(<RealtimePresenceClientDto>[
          RealtimePresenceClientDto.fromJson({
            'accountId': 'acct-phone-01',
            'clientId': 'phone-01',
            'label': '扫码接入1234',
            'deviceName': '扫码接入1234',
            'platform': 'ios',
            'status': 'online',
          }),
        ]);

        final peers = store.peerClients;
        expect(peers, hasLength(1));
        expect(peers.first.nodeId, 'client-runtime:phone-01');
        expect(peers.first.publicDisplayName, 'iOS设备');
      },
    );

    test('relay ensurePeerClient alone keeps clientId fallback display name', () {
      final store = UnifiedNodeStore();
      store.applyCurrentSession(_buildSession());

      store.ensurePeerClient(clientId: 'android_install_01');

      final peers = store.peerClients;
      expect(peers, hasLength(1));
      expect(peers.first.publicDisplayName, '伙伴设备');
    });

    test('applyPeerProfiles updates alias without relay senderLabel', () {
      final store = UnifiedNodeStore();
      store.applyCurrentSession(_buildSession());
      store.ensurePeerClient(clientId: 'phone-01');

      store.applyPeerProfiles(const <PeerProfileSnapshot>[
        PeerProfileSnapshot(
          deviceId: 'phone-01',
          label: '客厅平板',
          deviceName: 'Xiaomi Pad',
        ),
      ]);

      final phone = store.findPeerClientByClientId('phone-01');
      expect(phone, isNotNull);
      expect(phone!.identity.label, '客厅平板');
      expect(phone.publicDisplayName, '客厅平板');
    });

    test(
      'hydrates cached peer identity and reuses it for offline peer cards',
      () {
        final store = UnifiedNodeStore();
        store.applyCurrentSession(_buildSession());
        store.applyCachedPeerClients(<UnifiedNode>[
          UnifiedNode.cachedPeerIdentity(
            clientId: 'phone-01',
            accountId: 'acct-phone-01',
            displayName: 'Xiaomi 14',
            label: 'Xiaomi 14',
            deviceName: 'Xiaomi 14',
            platform: 'android',
            brand: 'Xiaomi',
            model: '14',
            reportedRouteIp: '192.168.1.25',
            updatedAt: DateTime.utc(2026, 5, 21, 10),
          ),
        ]);

        store.ensurePeerClient(clientId: 'phone-01');
        store.applyPresenceSnapshot(const <RealtimePresenceClientDto>[]);

        final phone = store.findPeerClientByClientId('phone-01');
        expect(phone, isNotNull);
        expect(phone!.publicDisplayName, 'Xiaomi 14');
        expect(phone.network.reportedRouteIp, '192.168.1.25');
        expect(phone.presence.status, PresenceStatus.offline);
      },
    );

    test('drops reported route ip when it matches current server lan ip', () {
      final store = UnifiedNodeStore();
      store.applyCurrentSession(_buildSession());
      store.applyCurrentServerRuntime(
        serverLanIp: '192.168.1.10',
        serverStatus: 'online',
      );

      store.applyPresenceSnapshot(<RealtimePresenceClientDto>[
        RealtimePresenceClientDto.fromJson({
          'clientId': 'phone-01',
          'deviceName': 'Xiaomi 14',
          'platform': 'android',
          'reportedRouteIp': '192.168.1.10',
          'observedRemoteIp': '192.168.1.25',
          'status': 'online',
        }),
      ]);

      final phone = store.findPeerClientByClientId('phone-01');
      expect(phone, isNotNull);
      expect(phone!.network.reportedRouteIp, isNull);
      expect(phone.network.observedRemoteIp, '192.168.1.25');
    });

    test('applies server availability and dashboard runtime fields', () {
      final store = UnifiedNodeStore();
      store.applyCurrentSession(_buildSession());

      store.applyServerAvailabilityStatus(ServerAvailabilityStatus.online);
      store.applyCurrentServerRuntime(
        serverLanIp: '192.168.1.10',
        serverStatus: 'online',
        brand: 'QingMao',
        model: 'MiniNAS X1',
        storageTotal: 1000,
        storageUsed: 250,
        storageAvailable: 750,
        batteryLevel: 3,
        batteryPercent: 80,
        isCharging: true,
      );

      final server = store.currentServer;
      expect(server, isNotNull);
      expect(server!.presence.status, PresenceStatus.online);
      expect(server.identity.brand, 'QingMao');
      expect(server.identity.model, 'MiniNAS X1');
      expect(server.network.serverLanIp, '192.168.1.10');
      expect(server.runtime.storageUsed, 250);
      expect(server.runtime.batteryPercent, 80);
    });

    test('merges saved discovered and trusted server data into one node', () {
      final store = UnifiedNodeStore();

      store.applySavedServers(<UnifiedNode>[
        UnifiedNode.savedServer(
          serverUrl: 'https://nas.local:9443',
          displayName: 'MiniNAS',
          updatedAt: DateTime.utc(2026, 5, 17, 10),
        ),
      ]);
      store.applyDiscoveredServers(<UnifiedNode>[
        UnifiedNode.discoveredServer(
          serverId: 'server-1',
          name: 'MiniNAS',
          host: 'nas.local',
          port: 9443,
          platform: 'windows',
          serviceType: '_https._tcp.',
          caSha256: 'sha256-1',
        ),
      ]);
      store.applyTrustedServers(const <TrustedServerRecord>[
        TrustedServerRecord(
          serverId: 'server-1',
          serverName: 'MiniNAS',
          caSha256: 'sha256-1',
          rootCaPem: 'pem',
          lastBaseUrl: 'https://nas.local:9443',
          hosts: <String>['nas.local', '192.168.1.10'],
        ),
      ]);

      final saved = store.savedServers;
      final discovered = store.discoveredServers;
      expect(saved, hasLength(1));
      expect(discovered, hasLength(1));
      expect(identical(saved.first, discovered.first), isTrue);
      expect(saved.first.identity.serverId, 'server-1');
      expect(saved.first.identity.platform, 'windows');
      expect(saved.first.server?.isTrusted, isTrue);
      expect(saved.first.server?.certificateSha256, 'sha256-1');
      expect(saved.first.server?.trustedHosts, contains('192.168.1.10'));
    });

    test(
      'keeps discovered platform when saved server history lacks platform',
      () {
        final store = UnifiedNodeStore();

        store.applyDiscoveredServers(<UnifiedNode>[
          UnifiedNode.discoveredServer(
            serverId: 'server-1',
            name: 'MiniNAS',
            host: 'nas.local',
            port: 9443,
            platform: 'windows',
            serviceType: '_https._tcp.',
          ),
        ]);
        store.applySavedServers(<UnifiedNode>[
          UnifiedNode.savedServer(
            serverUrl: 'https://nas.local:9443',
            serverId: 'server-1',
            displayName: 'MiniNAS',
            updatedAt: DateTime.utc(2026, 5, 17, 10),
          ),
        ]);

        expect(store.savedServers, hasLength(1));
        expect(store.savedServers.first.identity.platform, 'windows');
      },
    );

    test('scan discovery does not overwrite saved server display name', () {
      final store = UnifiedNodeStore();

      store.applySavedServers(<UnifiedNode>[
        UnifiedNode.savedServer(
          serverUrl: 'https://192.168.1.10:9443',
          serverId: 'server-1',
          displayName: '家庭 NAS',
          updatedAt: DateTime.utc(2026, 5, 17, 10),
        ),
      ]);
      store.applyDiscoveredServers(<UnifiedNode>[
        UnifiedNode.discoveredServer(
          serverId: 'server-1',
          name: 'nas-123456',
          host: '192.168.1.10',
          port: 9443,
          hostLabel: 'nas-123456',
          serviceType: '_https._tcp.',
        ),
      ]);

      expect(store.savedServers, hasLength(1));
      expect(store.savedServers.first.identity.displayName, '家庭 NAS');
      expect(store.discoveredServers.first.identity.displayName, '家庭 NAS');
    });

    test('discovery preserves saved mDNS service name over scan', () {
      final store = UnifiedNodeStore();

      store.applySavedServers(<UnifiedNode>[
        UnifiedNode.savedServer(
          serverUrl: 'https://192.168.1.10:9443',
          serverId: 'server-1',
          displayName: 'nas-123456',
          updatedAt: DateTime.utc(2026, 5, 17, 10),
        ),
      ]);
      store.applyDiscoveredServers(<UnifiedNode>[
        UnifiedNode.discoveredServer(
          serverId: 'server-1',
          name: '家庭 NAS',
          host: '192.168.1.10',
          port: 9443,
          serviceType: '_https._tcp.',
        ),
      ]);

      expect(store.savedServers, hasLength(1));
      expect(store.savedServers.first.identity.displayName, 'nas-123456');
    });

    test('discovered server uses mDNS serviceName such as DESKTOP hostnames', () {
      final node = UnifiedNode.discoveredServer(
        name: 'DESKTOP-ABC123',
        host: '192.168.1.10',
        port: 9443,
        serviceType: '_webdavs._tcp.',
      );

      expect(node.identity.displayName, 'DESKTOP-ABC123');
    });

    test('scan discovery does not overwrite current server display name', () {
      final store = UnifiedNodeStore();
      store.applyCurrentSession(_buildSession());

      store.applyDiscoveredServers(<UnifiedNode>[
        UnifiedNode.discoveredServer(
          serverId: 'server-1',
          name: 'nas-123456',
          host: 'nas.local',
          port: 9443,
          hostLabel: 'nas-123456',
          serviceType: '_https._tcp.',
        ),
      ]);

      expect(store.currentServer, isNotNull);
      expect(store.currentServer!.identity.displayName, 'MiniNAS');
    });

    test('matches current server through trusted host aliases', () {
      final store = UnifiedNodeStore();
      store.applyCurrentSession(_buildSession());
      store.applyTrustedServers(const <TrustedServerRecord>[
        TrustedServerRecord(
          serverId: 'server-1',
          serverName: 'MiniNAS',
          caSha256: 'sha256-1',
          rootCaPem: 'pem',
          lastBaseUrl: 'https://nas.local:9443',
          hosts: <String>['nas.local', '192.168.1.10'],
        ),
      ]);

      final tappedServer = UnifiedNode.savedServer(
        serverUrl: 'https://192.168.1.10:9443',
        serverId: 'server-1',
        displayName: 'MiniNAS',
        updatedAt: DateTime.utc(2026, 5, 21, 10),
      );

      expect(store.isCurrentServerNode(tappedServer), isTrue);
    });
  });
}

CurrentSession _buildSession() {
  final session = CurrentSession();
  session.clear();
  session.set(
    serverId: 'server-1',
    serverName: 'MiniNAS',
    serverVersion: '1.0.0',
    serverStatus: 'online',
    serverPlatform: 'windows',
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
    roots: const <RootInfo>[
      RootInfo(
        id: 'fs',
        name: 'NAS',
        path: '/fs',
        type: 'local',
        writable: true,
      ),
    ],
    capabilities: const <String, dynamic>{
      'relay': {'enabled': true},
    },
  );
  return session;
}
