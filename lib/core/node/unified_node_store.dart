import 'dart:async';

import '../auth/root_info.dart';
import '../network/nas_network_access_policy.dart';
import '../network/trusted_server_store.dart';
import '../session/current_session.dart';
import '../session/server_availability_controller.dart';
import 'device_display_resolver.dart';
import 'realtime_presence_client_dto.dart';
import 'server_display_name_policy.dart';
import 'unified_node.dart';

class UnifiedNodeStore implements SessionStateBinding {
  final Map<String, UnifiedNode> _byNodeId = <String, UnifiedNode>{};
  final StreamController<int> _controller = StreamController<int>.broadcast(
    sync: true,
  );

  AuthStateSnapshot _authState = const AuthStateSnapshot();
  NavigationStateSnapshot _navigationState = const NavigationStateSnapshot();
  SessionContextState _sessionContext = const SessionContextState();
  int _revision = 0;

  Stream<int> get stream => _controller.stream;
  int get revision => _revision;
  @override
  AuthStateSnapshot get authState => _authState;
  @override
  NavigationStateSnapshot get navigationState => _navigationState;
  @override
  SessionContextState get sessionContext => _sessionContext;

  Iterable<UnifiedNode> get nodes => _byNodeId.values.toList(growable: false);

  @override
  UnifiedNode? get selfClient {
    final nodeId = _sessionContext.selfClientNodeId;
    return nodeId == null ? null : _byNodeId[nodeId];
  }

  @override
  UnifiedNode? get currentServer {
    final nodeId = _sessionContext.currentServerNodeId;
    return nodeId == null ? null : _byNodeId[nodeId];
  }

  List<UnifiedNode> get peerClients {
    final selfNodeId = _sessionContext.selfClientNodeId;
    final clients =
        _byNodeId.values
            .where(
              (node) =>
                  node.kind == NodeKind.client &&
                  node.nodeId != selfNodeId &&
                  !node.relations.contains(NodeRelation.self),
            )
            .toList(growable: false)
          ..sort((left, right) {
            return DeviceDisplayResolver.publicDisplayName(
              alias: left.identity.label,
              hardwareName: left.identity.deviceName,
              brand: left.identity.brand,
              model: left.identity.model,
              platform: left.identity.platform,
              fallback: left.identity.clientId ?? left.nodeId,
            ).compareTo(
              DeviceDisplayResolver.publicDisplayName(
                alias: right.identity.label,
                hardwareName: right.identity.deviceName,
                brand: right.identity.brand,
                model: right.identity.model,
                platform: right.identity.platform,
                fallback: right.identity.clientId ?? right.nodeId,
              ),
            );
          });
    return clients;
  }

  List<UnifiedNode> get peerIdentityCacheEntries {
    final peers = <UnifiedNode>[];
    for (final node in _byNodeId.values) {
      if (node.kind != NodeKind.client ||
          !node.relations.contains(NodeRelation.peer) ||
          !_shouldPersistPeerIdentity(node)) {
        continue;
      }
      final clientId = node.identity.clientId?.trim() ?? '';
      if (clientId.isEmpty) {
        continue;
      }
      peers.add(
        UnifiedNode.cachedPeerIdentity(
          clientId: clientId,
          accountId: node.identity.accountId,
          displayName: node.identity.displayName,
          label: DeviceDisplayResolver.sanitizeAlias(node.identity.label),
          deviceName: DeviceDisplayResolver.sanitizeAlias(node.identity.deviceName),
          platform: node.identity.platform,
          brand: node.identity.brand,
          model: node.identity.model,
          appVersion: node.identity.appVersion,
          reportedRouteIp: node.network.reportedRouteIp,
          observedRemoteIp: node.network.observedRemoteIp,
          updatedAt: node.meta.updatedAt,
        ),
      );
    }
    peers.sort(
      (left, right) => right.meta.updatedAt.compareTo(left.meta.updatedAt),
    );
    return List<UnifiedNode>.unmodifiable(peers);
  }

  List<UnifiedNode> get savedServers {
    final servers =
        _byNodeId.values
            .where((node) => node.relations.contains(NodeRelation.saved))
            .toList(growable: false)
          ..sort(
            (left, right) =>
                right.meta.updatedAt.compareTo(left.meta.updatedAt),
          );
    return servers;
  }

  List<UnifiedNode> get discoveredServers {
    final servers =
        _byNodeId.values
            .where((node) => node.relations.contains(NodeRelation.discovered))
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.identity.displayName.compareTo(right.identity.displayName),
          );
    return servers;
  }

  UnifiedNode? findPeerClientByClientId(String clientId) {
    for (final node in peerClients) {
      if (node.identity.clientId == clientId) {
        return node;
      }
    }
    return null;
  }

  UnifiedNode? findServerByUrl(String serverUrl) {
    final normalizedUrl = serverUrl.trim();
    if (normalizedUrl.isEmpty) {
      return null;
    }
    final host = _tryParseUri(normalizedUrl)?.host;
    for (final node in _byNodeId.values) {
      if (node.kind != NodeKind.server) {
        continue;
      }
      if (node.network.connectBaseUrl == normalizedUrl) {
        return node;
      }
      if (host != null && node.server?.trustedHosts.contains(host) == true) {
        return node;
      }
    }
    return null;
  }

  bool isCurrentServerNode(UnifiedNode server) {
    if (server.kind != NodeKind.server) {
      return false;
    }
    final activeServer = currentServer;
    if (activeServer == null) {
      return false;
    }
    return _isSameServerNode(activeServer, server);
  }

  void applySavedServers(List<UnifiedNode> servers) {
    final activeSavedNodeIds = <String>{};
    for (final server in servers) {
      final serverUrl = server.network.connectBaseUrl?.trim() ?? '';
      if (serverUrl.isEmpty) {
        continue;
      }
      final nodeId = _resolveServerNodeId(serverUrl: serverUrl);
      activeSavedNodeIds.add(nodeId);
      final previous = _byNodeId[nodeId];
      final relations = <NodeRelation>{
        ...?previous?.relations,
        NodeRelation.saved,
      };
      _byNodeId[nodeId] =
          (previous ??
                  UnifiedNode(
                    nodeId: nodeId,
                    kind: NodeKind.server,
                    relations: relations,
                    identity: server.identity,
                    network: server.network,
                    presence: server.presence,
                    runtime: server.runtime,
                    management: server.management,
                    meta: server.meta,
                    server: server.server,
                  ))
              .copyWith(
                relations: relations,
                identity: (previous?.identity ?? server.identity).copyWith(
                  displayName: _mergeServerDisplayName(
                    previous: previous,
                    incoming: server.identity.displayName,
                    source: 'saved',
                  ),
                  serverId: server.identity.serverId,
                  platform:
                      server.identity.platform ?? previous?.identity.platform,
                ),
                network: (previous?.network ?? const NodeNetwork()).copyWith(
                  connectBaseUrl: server.network.connectBaseUrl,
                  host: server.network.host,
                  port: server.network.port,
                  reachable: server.network.reachable,
                  reachableCheckedAt: server.network.reachableCheckedAt,
                ),
                presence: (previous?.presence ?? const NodePresence()).copyWith(
                  status: server.presence.status,
                ),
                runtime: (previous?.runtime ?? const NodeRuntime()).copyWith(
                  status: server.runtime.status,
                ),
                meta: _nextMeta(previous?.meta, server.meta.updatedAt, 'saved'),
                server: (previous?.server ?? const ServerFacet()).copyWith(
                  certificateSha256:
                      server.server?.certificateSha256 ??
                      previous?.server?.certificateSha256,
                  isTrusted:
                      server.server?.isTrusted ?? previous?.server?.isTrusted,
                  trustedHosts: _mergeTrustedHostsList(
                    previous?.server?.trustedHosts ?? const <String>[],
                    server.server?.trustedHosts ?? const <String>[],
                  ),
                ),
              );
    }

    for (final entry in _byNodeId.entries.toList(growable: false)) {
      final node = entry.value;
      if (node.kind != NodeKind.server ||
          !node.relations.contains(NodeRelation.saved) ||
          activeSavedNodeIds.contains(node.nodeId)) {
        continue;
      }
      final nextRelations = Set<NodeRelation>.from(node.relations)
        ..remove(NodeRelation.saved);
      if (nextRelations.isEmpty) {
        _byNodeId.remove(entry.key);
      } else {
        _byNodeId[entry.key] = node.copyWith(relations: nextRelations);
      }
    }

    _emit();
  }

  void applyDiscoveredServers(List<UnifiedNode> servers) {
    final activeDiscoveredNodeIds = <String>{};
    for (final server in servers) {
      final nodeId = _resolveServerNodeId(
        serverId: server.identity.serverId,
        serverUrl: server.network.connectBaseUrl,
      );
      activeDiscoveredNodeIds.add(nodeId);
      final previous = _byNodeId[nodeId];
      final relations = <NodeRelation>{
        ...?previous?.relations,
        NodeRelation.discovered,
      };
      _byNodeId[nodeId] =
          (previous ??
                  UnifiedNode(
                    nodeId: nodeId,
                    kind: NodeKind.server,
                    relations: relations,
                    identity: server.identity,
                    network: server.network,
                    presence: server.presence,
                    runtime: server.runtime,
                    management: server.management,
                    meta: server.meta,
                    server: server.server,
                  ))
              .copyWith(
                relations: relations,
                identity: (previous?.identity ?? server.identity).copyWith(
                  displayName: _mergeServerDisplayName(
                    previous: previous,
                    incoming: server.identity.displayName,
                    source: 'discovery',
                  ),
                  serverId:
                      server.identity.serverId ?? previous?.identity.serverId,
                  platform:
                      server.identity.platform ?? previous?.identity.platform,
                ),
                network: (previous?.network ?? const NodeNetwork()).copyWith(
                  connectBaseUrl: server.network.connectBaseUrl,
                  host: server.network.host,
                  port: server.network.port,
                  reachable: server.network.reachable,
                  reachableCheckedAt: server.network.reachableCheckedAt,
                ),
                presence: (previous?.presence ?? const NodePresence()).copyWith(
                  status: server.presence.status,
                ),
                runtime: (previous?.runtime ?? const NodeRuntime()).copyWith(
                  status: server.runtime.status,
                ),
                meta: _nextMeta(
                  previous?.meta,
                  server.meta.updatedAt,
                  'discovery',
                ),
                server: (previous?.server ?? const ServerFacet()).copyWith(
                  certificateSha256:
                      server.server?.certificateSha256 ??
                      previous?.server?.certificateSha256,
                  trustedHosts: _mergeTrustedHostsList(
                    previous?.server?.trustedHosts ?? const <String>[],
                    server.server?.trustedHosts ?? const <String>[],
                  ),
                ),
              );
    }

    for (final entry in _byNodeId.entries.toList(growable: false)) {
      final node = entry.value;
      if (node.kind != NodeKind.server ||
          !node.relations.contains(NodeRelation.discovered) ||
          activeDiscoveredNodeIds.contains(node.nodeId)) {
        continue;
      }
      final nextRelations = Set<NodeRelation>.from(node.relations)
        ..remove(NodeRelation.discovered);
      if (nextRelations.isEmpty) {
        _byNodeId.remove(entry.key);
      } else {
        _byNodeId[entry.key] = node.copyWith(relations: nextRelations);
      }
    }

    _emit();
  }

  void applyTrustedServers(List<TrustedServerRecord> records) {
    final now = DateTime.now().toUtc();
    for (final record in records) {
      final nodeId = _resolveServerNodeId(
        serverId: record.serverId,
        serverUrl: record.lastBaseUrl,
      );
      final previous = _byNodeId[nodeId];
      final relations = <NodeRelation>{
        ...?previous?.relations,
        NodeRelation.saved,
      };
      final uri = _tryParseUri(record.lastBaseUrl);
      _byNodeId[nodeId] =
          (previous ??
                  UnifiedNode(
                    nodeId: nodeId,
                    kind: NodeKind.server,
                    relations: relations,
                    identity: NodeIdentity(
                      displayName: _serverDisplayName(record.serverName),
                      serverId: record.serverId,
                    ),
                    network: NodeNetwork(
                      connectBaseUrl: record.lastBaseUrl,
                      host: uri?.host,
                      port: uri?.hasPort == true ? uri!.port : null,
                    ),
                    presence: const NodePresence(),
                    runtime: const NodeRuntime(),
                    management: const NodeManagement(),
                    meta: NodeMeta(
                      updatedAt: now,
                      updatedFrom: const {'trust'},
                    ),
                    server: const ServerFacet(),
                  ))
              .copyWith(
                relations: relations,
                identity:
                    (previous?.identity ??
                            NodeIdentity(
                              displayName: _serverDisplayName(
                                record.serverName,
                              ),
                            ))
                        .copyWith(
                          displayName: _mergeServerDisplayName(
                            previous: previous,
                            incoming: _serverDisplayName(record.serverName),
                            source: 'trust',
                          ),
                          serverId: record.serverId,
                        ),
                network: (previous?.network ?? const NodeNetwork()).copyWith(
                  connectBaseUrl: record.lastBaseUrl,
                  host: uri?.host,
                  port: uri?.hasPort == true ? uri!.port : null,
                ),
                meta: _nextMeta(previous?.meta, now, 'trust'),
                server: (previous?.server ?? const ServerFacet()).copyWith(
                  certificateSha256: record.caSha256,
                  isTrusted: true,
                  trustedHosts: record.hosts,
                ),
              );
    }
    _emit();
  }

  void setServerReachability({
    required String serverUrl,
    required bool reachable,
  }) {
    final node = findServerByUrl(serverUrl);
    if (node == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    _byNodeId[node.nodeId] = node.copyWith(
      network: node.network.copyWith(
        reachable: reachable,
        reachableCheckedAt: now,
      ),
      presence: node.presence.copyWith(
        status: reachable ? PresenceStatus.online : PresenceStatus.offline,
      ),
      runtime: node.runtime.copyWith(status: reachable ? 'online' : 'offline'),
      meta: _nextMeta(node.meta, now, 'reachability'),
    );
    _emit();
  }

  @override
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
  }) {
    final now = DateTime.now().toUtc();
    final effectiveServerId = serverId.trim();
    final effectiveServerUrl = serverUrl.trim();
    final effectiveProtocol = protocol.trim().isEmpty
        ? 'webdav'
        : protocol.trim();
    final effectiveRootId = rootId.trim();
    final effectiveRootName = rootName.trim();
    final effectiveRoots = List<RootInfo>.from(roots ?? const <RootInfo>[]);
    final serverNodeId = _resolveServerNodeId(
      serverId: effectiveServerId,
      serverUrl: effectiveServerUrl,
    );
    final effectiveRole = role?.trim().toLowerCase() ?? '';
    final selfClientNodeId = _clientNodeId(
      role: effectiveRole,
      accountId: accountId,
      clientId: deviceId ?? clientId,
    );
    _authState = AuthStateSnapshot(
      accountId: effectiveRole == 'device' ? null : accountId,
      role: role,
      clientId: deviceId ?? clientId,
      deviceId: deviceId ?? clientId,
      sessionId: sessionId,
      accessToken: accessToken,
      expiresAt: expiresAt,
      username: effectiveRole == 'device' ? null : username,
      password: effectiveRole == 'device' ? null : password,
    );
    _navigationState = NavigationStateSnapshot(
      protocol: effectiveProtocol,
      rootId: effectiveRootId,
      rootName: effectiveRootName,
      roots: effectiveRoots,
      webdavConfig: _cloneMap(webdavConfig),
    );
    _sessionContext = SessionContextState(
      currentServerNodeId: serverNodeId,
      selfClientNodeId: selfClientNodeId,
    );

    final previousServer = _byNodeId[serverNodeId];
    final serverUri = _tryParseUri(effectiveServerUrl);
    _byNodeId[serverNodeId] =
        (previousServer ??
                UnifiedNode(
                  nodeId: serverNodeId,
                  kind: NodeKind.server,
                  relations: const <NodeRelation>{NodeRelation.current},
                  identity: NodeIdentity(
                    displayName: _serverDisplayName(serverName),
                    serverId: effectiveServerId,
                    platform: serverPlatform,
                  ),
                  network: NodeNetwork(
                    connectBaseUrl: effectiveServerUrl,
                    host: serverUri?.host,
                    port: serverUri?.hasPort == true ? serverUri!.port : null,
                  ),
                  presence: NodePresence(
                    status: _serverPresenceFromStatus(serverStatus),
                    sessionId: sessionId,
                  ),
                  runtime: NodeRuntime(status: serverStatus),
                  management: const NodeManagement(),
                  meta: NodeMeta(
                    updatedAt: now,
                    updatedFrom: const {'session'},
                  ),
                  server: ServerFacet(
                    serverVersion: serverVersion,
                    protocol: effectiveProtocol,
                    capabilities: _cloneMap(capabilities),
                    roots: effectiveRoots,
                    webdavConfig: _cloneMap(webdavConfig),
                  ),
                ))
            .copyWith(
              relations: <NodeRelation>{
                ...?previousServer?.relations,
                NodeRelation.current,
              },
              identity:
                  (previousServer?.identity ??
                          NodeIdentity(
                            displayName: _serverDisplayName(serverName),
                          ))
                      .copyWith(
                        displayName: _mergeServerDisplayName(
                          previous: previousServer,
                          incoming: _serverDisplayName(serverName),
                          source: 'session',
                        ),
                        serverId: effectiveServerId,
                        platform: serverPlatform,
                      ),
              network: (previousServer?.network ?? const NodeNetwork())
                  .copyWith(
                    connectBaseUrl: effectiveServerUrl,
                    host: serverUri?.host,
                    port: serverUri?.hasPort == true ? serverUri!.port : null,
                  ),
              presence: (previousServer?.presence ?? const NodePresence())
                  .copyWith(
                    status: _serverPresenceFromStatus(serverStatus),
                    sessionId: sessionId,
                  ),
              runtime: (previousServer?.runtime ?? const NodeRuntime())
                  .copyWith(status: serverStatus),
              meta: _nextMeta(previousServer?.meta, now, 'session'),
              server: (previousServer?.server ?? const ServerFacet()).copyWith(
                serverVersion: serverVersion,
                protocol: effectiveProtocol,
                capabilities: _cloneMap(capabilities),
                roots: effectiveRoots,
                webdavConfig: _cloneMap(webdavConfig),
              ),
            );

    if (selfClientNodeId != null) {
      final previousClient = _byNodeId[selfClientNodeId];
      final isDeviceSession = effectiveRole == 'device';
      final displayName = isDeviceSession
          ? '当前设备'
          : ((username?.trim().isNotEmpty ?? false)
                ? username!.trim()
                : '当前设备');
      _byNodeId[selfClientNodeId] =
          (previousClient ??
                  UnifiedNode(
                    nodeId: selfClientNodeId,
                    kind: NodeKind.client,
                    relations: const <NodeRelation>{NodeRelation.self},
                    identity: NodeIdentity(
                      displayName: displayName,
                      accountId: isDeviceSession ? null : accountId,
                      clientId: clientId,
                      deviceId: deviceId ?? clientId,
                      username: isDeviceSession ? null : username,
                      label: isDeviceSession ? null : username,
                    ),
                    network: const NodeNetwork(),
                    presence: NodePresence(sessionId: sessionId),
                    runtime: const NodeRuntime(),
                    management: const NodeManagement(),
                    meta: NodeMeta(
                      updatedAt: now,
                      updatedFrom: const {'session'},
                    ),
                    client: ClientFacet(role: role),
                  ))
              .copyWith(
                relations: const <NodeRelation>{NodeRelation.self},
                identity:
                    (previousClient?.identity ??
                            const NodeIdentity(displayName: '当前设备'))
                        .copyWith(
                          displayName: displayName,
                          accountId: isDeviceSession
                              ? null
                              : accountId,
                          clientId: clientId,
                          deviceId: deviceId ?? clientId,
                          username: isDeviceSession ? null : username,
                          label: isDeviceSession
                              ? previousClient?.identity.label
                              : username,
                        ),
                presence: (previousClient?.presence ?? const NodePresence())
                    .copyWith(sessionId: sessionId),
                meta: _nextMeta(previousClient?.meta, now, 'session'),
                client: (previousClient?.client ?? const ClientFacet())
                    .copyWith(role: role),
              );
    }

    _emit();
  }

  @override
  void updateNavigationSelection({
    required String rootId,
    required String rootName,
  }) {
    _navigationState = _navigationState.copyWith(
      rootId: rootId,
      rootName: rootName,
    );
    _emit();
  }

  @override
  void clearSessionState() {
    clear();
  }

  void ensurePeerClient({required String clientId}) {
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) {
      return;
    }
    final nodeId = _resolveClientNodeId(
      accountId: null,
      clientId: normalizedClientId,
    );
    final now = DateTime.now().toUtc();
    final previous = _byNodeId[nodeId];
    if (previous != null) {
      _byNodeId[nodeId] = previous.copyWith(
        relations: <NodeRelation>{...previous.relations, NodeRelation.peer},
        meta: _nextMeta(previous.meta, now, 'relay-peer'),
      );
      _emit();
      return;
    }

    _byNodeId[nodeId] = UnifiedNode.peerPlaceholder(
      clientId: normalizedClientId,
      updatedAt: now,
    );
    _emit();
  }

  void applyPeerProfiles(Iterable<PeerProfileSnapshot> profiles) {
    final now = DateTime.now().toUtc();
    for (final profile in profiles) {
      final clientId = profile.deviceId.trim();
      if (clientId.isEmpty) {
        continue;
      }
      ensurePeerClient(clientId: clientId);
      final nodeId = _resolveClientNodeId(accountId: null, clientId: clientId);
      final previous = _byNodeId[nodeId];
      if (previous == null) {
        continue;
      }
      final sanitizedLabel = DeviceDisplayResolver.sanitizeAlias(profile.label);
      final sanitizedDeviceName = DeviceDisplayResolver.sanitizeAlias(
        profile.deviceName,
      );
      _byNodeId[nodeId] = previous.copyWith(
        identity: previous.identity.copyWith(
          clientId: clientId,
          deviceId: clientId,
          label: sanitizedLabel ?? previous.identity.label,
          deviceName: sanitizedDeviceName ?? previous.identity.deviceName,
          displayName: _bestDisplayName(
            brand: previous.identity.brand,
            model: previous.identity.model,
            deviceName: sanitizedDeviceName ?? previous.identity.deviceName,
            label: sanitizedLabel ?? previous.identity.label,
            platform: previous.identity.platform,
            fallback: previous.identity.clientId ?? clientId,
          ),
        ),
        client: (previous.client ?? const ClientFacet()).copyWith(
          avatarUpdatedAt:
              profile.avatarUpdatedAt ?? previous.client?.avatarUpdatedAt,
        ),
        meta: _nextMeta(previous.meta, now, 'peer-profile'),
      );
    }
    _emit();
  }

  void applyCurrentSession(CurrentSession session) {
    applySessionData(
      serverId: session.serverId ?? '',
      serverName: session.serverName ?? '',
      serverVersion: session.serverVersion ?? '',
      serverStatus: session.serverStatus ?? '',
      serverPlatform: session.serverPlatform,
      serverUrl: session.serverUrl ?? '',
      username: session.username,
      password: session.password,
      protocol: session.protocol ?? 'webdav',
      rootId: session.rootId ?? '',
      rootName: session.rootName ?? '',
      accountId: session.accountId,
      role: session.role,
      clientId: session.clientId,
      deviceId: session.deviceId,
      sessionId: session.sessionId,
      accessToken: session.accessToken,
      expiresAt: session.expiresAt,
      roots: session.roots,
      webdavConfig: session.webdavConfig,
      capabilities: session.capabilities,
    );
  }

  void applyCachedPeerClients(List<UnifiedNode> peers) {
    if (peers.isEmpty) {
      return;
    }
    for (final peer in peers) {
      final clientId = peer.identity.clientId?.trim() ?? '';
      if (clientId.isEmpty) {
        continue;
      }
      final nodeId = _resolveClientNodeId(
        accountId: peer.identity.accountId,
        clientId: clientId,
      );
      final previous = _byNodeId[nodeId];
      final relations = <NodeRelation>{
        ...?previous?.relations,
        NodeRelation.peer,
      };
      final platform = peer.identity.platform ?? previous?.identity.platform;
      final brand = peer.identity.brand ?? previous?.identity.brand;
      final model = peer.identity.model ?? previous?.identity.model;
      final deviceName =
          peer.identity.deviceName ?? previous?.identity.deviceName;
      final label = peer.identity.label ?? previous?.identity.label;
      _byNodeId[nodeId] =
          (previous ??
                  UnifiedNode.cachedPeerIdentity(
                    clientId: clientId,
                    accountId: peer.identity.accountId,
                    displayName: peer.identity.displayName,
                    label: label,
                    deviceName: deviceName,
                    platform: platform,
                    brand: brand,
                    model: model,
                    appVersion: peer.identity.appVersion,
                    reportedRouteIp: peer.network.reportedRouteIp,
                    observedRemoteIp: peer.network.observedRemoteIp,
                    updatedAt: peer.meta.updatedAt,
                  ))
              .copyWith(
                relations: relations,
                identity: (previous?.identity ?? peer.identity).copyWith(
                  displayName: _bestDisplayName(
                    brand: brand,
                    model: model,
                    deviceName: deviceName,
                    label: label,
                    platform: platform,
                    fallback:
                        previous?.identity.displayName ??
                        peer.identity.displayName,
                  ),
                  accountId:
                      peer.identity.accountId ?? previous?.identity.accountId,
                  clientId: clientId,
                  label: _sanitizeDisplayAlias(label),
                  deviceName: _sanitizeDisplayAlias(deviceName),
                  platform: platform,
                  brand: brand,
                  manufacturer: brand ?? previous?.identity.manufacturer,
                  model: model,
                  appVersion:
                      peer.identity.appVersion ?? previous?.identity.appVersion,
                ),
                network: (previous?.network ?? const NodeNetwork()).copyWith(
                  reportedRouteIp:
                      _sanitizePeerReportedRouteIp(peer.network.reportedRouteIp) ??
                      _sanitizePeerReportedRouteIp(
                        previous?.network.reportedRouteIp,
                      ),
                  observedRemoteIp:
                      peer.network.observedRemoteIp ??
                      previous?.network.observedRemoteIp,
                ),
                meta: _nextMeta(
                  previous?.meta,
                  peer.meta.updatedAt,
                  'peer-cache',
                ),
              );
    }
    _emit();
  }

  void applyLocalClientIdentity({
    required String deviceId,
    required String deviceName,
    required String platform,
    String? brand,
    String? model,
    String? appVersion,
    String? label,
  }) {
    final nodeId = _sessionContext.selfClientNodeId;
    if (nodeId == null) {
      return;
    }
    final previous = _byNodeId[nodeId];
    if (previous == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    _byNodeId[nodeId] = previous.copyWith(
      identity: previous.identity.copyWith(
        displayName: _bestDisplayName(
          brand: brand,
          model: model,
          deviceName: deviceName,
          label: label ?? previous.identity.label,
          platform: platform,
          fallback: '当前设备',
        ),
        deviceId: deviceId,
        deviceName: deviceName,
        label: _sanitizeDisplayAlias(label) ?? previous.identity.label,
        platform: platform,
        brand: brand,
        manufacturer: brand,
        model: model,
        appVersion: appVersion,
      ),
      meta: _nextMeta(previous.meta, now, 'identity'),
      client: (previous.client ?? const ClientFacet()).copyWith(
        boundDeviceId: deviceId,
        boundDeviceName: deviceName,
      ),
    );
    _emit();
  }

  void applyLocalClientDisplayAlias(String? label) {
    final nodeId = _sessionContext.selfClientNodeId;
    if (nodeId == null) {
      return;
    }
    final previous = _byNodeId[nodeId];
    if (previous == null) {
      return;
    }
    final sanitizedLabel = _sanitizeDisplayAlias(label);
    final now = DateTime.now().toUtc();
    _byNodeId[nodeId] = previous.copyWith(
      identity: previous.identity.copyWith(
        label: sanitizedLabel,
        displayName: _bestDisplayName(
          brand: previous.identity.brand,
          model: previous.identity.model,
          deviceName: previous.identity.deviceName,
          label: sanitizedLabel,
          platform: previous.identity.platform,
          fallback: previous.identity.displayName,
        ),
      ),
      meta: _nextMeta(previous.meta, now, 'identity'),
    );
    _emit();
  }

  void applyCurrentServerRuntime({
    String? serverLanIp,
    String? serverStatus,
    String? brand,
    String? model,
    int? storageTotal,
    int? storageUsed,
    int? storageAvailable,
    int? batteryLevel,
    double? batteryPercent,
    bool? isCharging,
  }) {
    final nodeId = _sessionContext.currentServerNodeId;
    if (nodeId == null) {
      return;
    }
    final previous = _byNodeId[nodeId];
    if (previous == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    _byNodeId[nodeId] = previous.copyWith(
      identity: previous.identity.copyWith(
        brand: brand ?? previous.identity.brand,
        manufacturer: brand ?? previous.identity.manufacturer,
        model: model ?? previous.identity.model,
      ),
      network: previous.network.copyWith(serverLanIp: serverLanIp),
      presence: previous.presence.copyWith(
        status: serverStatus == null
            ? previous.presence.status
            : _serverPresenceFromStatus(serverStatus),
      ),
      runtime: previous.runtime.copyWith(
        status: serverStatus,
        storageTotal: storageTotal,
        storageUsed: storageUsed,
        storageAvailable: storageAvailable,
        batteryLevel: batteryLevel,
        batteryPercent: batteryPercent,
        isCharging: isCharging,
      ),
      meta: _nextMeta(previous.meta, now, 'dashboard'),
    );
    _emit();
  }

  void applyServerAvailabilityStatus(ServerAvailabilityStatus status) {
    final nodeId = _sessionContext.currentServerNodeId;
    if (nodeId == null) {
      return;
    }
    final previous = _byNodeId[nodeId];
    if (previous == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final runtimeStatus = previous.runtime.status;
    _byNodeId[nodeId] = previous.copyWith(
      presence: previous.presence.copyWith(
        status: status == ServerAvailabilityStatus.online
            ? PresenceStatus.online
            : PresenceStatus.offline,
      ),
      runtime: previous.runtime.copyWith(
        status: status == ServerAvailabilityStatus.offline
            ? 'offline'
            : (runtimeStatus ?? 'online'),
      ),
      meta: _nextMeta(previous.meta, now, 'availability'),
    );
    _emit();
  }

  void applyPresenceSnapshot(List<RealtimePresenceClientDto> clients) {
    final now = DateTime.now().toUtc();
    final selfClientId = _authState.clientId;
    final incomingClientIds = <String>{};
    for (final client in clients) {
      incomingClientIds.add(client.clientId);
      final isSelf = selfClientId != null && client.clientId == selfClientId;
      final nodeId = _resolveClientNodeId(
        accountId: client.accountId,
        clientId: client.clientId,
      );
      final previous = _byNodeId[nodeId];
      final relations = <NodeRelation>{
        if (isSelf) NodeRelation.self else NodeRelation.peer,
        ...?previous?.relations.where(
          (relation) =>
              relation == NodeRelation.managed ||
              relation == NodeRelation.saved ||
              relation == NodeRelation.discovered,
        ),
      };
      _byNodeId[nodeId] =
          (previous ??
                  UnifiedNode(
                    nodeId: nodeId,
                    kind: NodeKind.client,
                    relations: relations,
                    identity: NodeIdentity(
                      displayName: _bestDisplayName(
                        brand: client.brand,
                        model: client.model,
                        deviceName: client.deviceName,
                        label: client.label,
                        platform: client.platform,
                        fallback: client.clientId,
                      ),
                      accountId: client.accountId,
                      clientId: client.clientId,
                      label: client.label,
                      deviceName: client.deviceName,
                      platform: client.platform,
                      brand: client.brand,
                      manufacturer: client.brand,
                      model: client.model,
                      appVersion: client.appVersion,
                    ),
                    network: NodeNetwork(
                      reportedRouteIp: _sanitizePeerReportedRouteIp(
                        client.reportedRouteIp,
                      ),
                      observedRemoteIp: client.observedRemoteIp,
                    ),
                    presence: NodePresence(
                      status: _presenceStatus(client.status),
                      connectionId: client.connectionId,
                      sessionId: client.sessionId,
                      connectedAt: client.connectedAt,
                      lastSeenAt: client.lastSeenAt,
                      lastHeartbeatAt: client.lastSeenAt,
                    ),
                    runtime: const NodeRuntime(),
                    management: const NodeManagement(),
                    meta: NodeMeta(
                      updatedAt: now,
                      updatedFrom: const {'presence'},
                    ),
                    client: ClientFacet(
                      role: client.role,
                      avatarUpdatedAt: client.avatarUpdatedAt,
                    ),
                  ))
              .copyWith(
                relations: relations,
                identity:
                    (previous?.identity ??
                            NodeIdentity(displayName: client.clientId))
                        .copyWith(
                          displayName: _bestDisplayName(
                            brand: client.brand ?? previous?.identity.brand,
                            model: client.model ?? previous?.identity.model,
                            deviceName:
                                client.deviceName ??
                                previous?.identity.deviceName,
                            label: client.label ?? previous?.identity.label,
                            platform:
                                client.platform ?? previous?.identity.platform,
                            fallback:
                                previous?.identity.displayName ??
                                client.clientId,
                          ),
                          accountId:
                              client.accountId ?? previous?.identity.accountId,
                          clientId: client.clientId,
                          label: client.label ?? previous?.identity.label,
                          deviceName:
                              client.deviceName ??
                              previous?.identity.deviceName,
                          platform:
                              client.platform ?? previous?.identity.platform,
                          brand: client.brand ?? previous?.identity.brand,
                          manufacturer:
                              client.brand ?? previous?.identity.manufacturer,
                          model: client.model ?? previous?.identity.model,
                          appVersion:
                              client.appVersion ??
                              previous?.identity.appVersion,
                        ),
                network: (previous?.network ?? const NodeNetwork()).copyWith(
                  reportedRouteIp:
                      _sanitizePeerReportedRouteIp(client.reportedRouteIp) ??
                      _sanitizePeerReportedRouteIp(
                        previous?.network.reportedRouteIp,
                      ),
                  observedRemoteIp:
                      client.observedRemoteIp ??
                      previous?.network.observedRemoteIp,
                ),
                presence: (previous?.presence ?? const NodePresence()).copyWith(
                  status: _presenceStatus(client.status),
                  connectionId: client.connectionId,
                  sessionId: client.sessionId,
                  connectedAt: client.connectedAt,
                  lastSeenAt: client.lastSeenAt,
                  lastHeartbeatAt: client.lastSeenAt,
                ),
                meta: _nextMeta(previous?.meta, now, 'presence'),
                client: (previous?.client ?? const ClientFacet()).copyWith(
                  role: client.role ?? previous?.client?.role,
                  avatarUpdatedAt:
                      client.avatarUpdatedAt ?? previous?.client?.avatarUpdatedAt,
                ),
              );

      if (isSelf) {
        _sessionContext = _sessionContext.copyWith(selfClientNodeId: nodeId);
      }
    }

    for (final entry in _byNodeId.entries.toList(growable: false)) {
      final node = entry.value;
      if (node.kind != NodeKind.client) {
        continue;
      }
      final clientId = node.identity.clientId;
      if (clientId == null || incomingClientIds.contains(clientId)) {
        continue;
      }
      if (node.nodeId == _sessionContext.selfClientNodeId) {
        continue;
      }
      if (!node.relations.contains(NodeRelation.peer)) {
        continue;
      }
      _byNodeId[entry.key] = node.copyWith(
        presence: node.presence.copyWith(
          status: PresenceStatus.offline,
          connectionId: null,
          sessionId: null,
        ),
        meta: _nextMeta(node.meta, now, 'presence'),
      );
    }

    _emit();
  }

  void clear() {
    _byNodeId.clear();
    _authState = const AuthStateSnapshot();
    _navigationState = const NavigationStateSnapshot();
    _sessionContext = const SessionContextState();
    _emit();
  }

  String _resolveClientNodeId({
    required String? accountId,
    required String clientId,
  }) {
    final normalizedAccountId = accountId?.trim() ?? '';
    final normalizedClientId = clientId.trim();
    String? accountMatchNodeId;
    for (final entry in _byNodeId.entries) {
      final node = entry.value;
      if (node.kind != NodeKind.client) {
        continue;
      }
      if (node.identity.clientId == normalizedClientId) {
        return entry.key;
      }
      if (accountMatchNodeId == null &&
          normalizedAccountId.isNotEmpty &&
          node.identity.accountId == normalizedAccountId) {
        accountMatchNodeId = entry.key;
      }
    }
    if (accountMatchNodeId != null) {
      return accountMatchNodeId;
    }
    if (normalizedAccountId.isNotEmpty) {
      return 'client-account:$normalizedAccountId';
    }
    return 'client-runtime:$normalizedClientId';
  }

  String? _clientNodeId({
    required String role,
    required String? accountId,
    required String? clientId,
  }) {
    final normalizedRole = role.trim().toLowerCase();
    final normalizedClientId = clientId?.trim() ?? '';
    if (normalizedRole == 'device' && normalizedClientId.isNotEmpty) {
      return 'client-device:$normalizedClientId';
    }
    final normalizedAccountId = accountId?.trim() ?? '';
    if (normalizedAccountId.isNotEmpty) {
      return 'client-account:$normalizedAccountId';
    }
    if (normalizedClientId.isNotEmpty) {
      return 'client-runtime:$normalizedClientId';
    }
    return null;
  }

  Uri? _tryParseUri(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return null;
    }
    return Uri.tryParse(rawUrl);
  }

  bool _isSameServerNode(UnifiedNode left, UnifiedNode right) {
    final leftServerId = left.identity.serverId?.trim() ?? '';
    final rightServerId = right.identity.serverId?.trim() ?? '';
    if (leftServerId.isNotEmpty &&
        rightServerId.isNotEmpty &&
        leftServerId == rightServerId) {
      return true;
    }

    final leftUrl = _normalizedServerUrlForMatch(left.network.connectBaseUrl);
    final rightUrl = _normalizedServerUrlForMatch(right.network.connectBaseUrl);
    if (leftUrl.isNotEmpty && rightUrl.isNotEmpty && leftUrl == rightUrl) {
      return true;
    }

    final leftHosts = _serverHostsForMatch(left);
    final rightHosts = _serverHostsForMatch(right);
    if (leftHosts.isEmpty || rightHosts.isEmpty) {
      return false;
    }
    return leftHosts.any(rightHosts.contains);
  }

  String _normalizedServerUrlForMatch(String? rawUrl) {
    final trimmed = rawUrl?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    try {
      return NasNetworkAccessPolicy.normalizeServerUrl(trimmed);
    } on Exception {
      return trimmed;
    }
  }

  Set<String> _serverHostsForMatch(UnifiedNode server) {
    final hosts = <String>{};
    final directHost = server.network.host?.trim().toLowerCase() ?? '';
    if (directHost.isNotEmpty) {
      hosts.add(directHost);
    }
    final baseUrlHost =
        _tryParseUri(
          server.network.connectBaseUrl,
        )?.host.trim().toLowerCase() ??
        '';
    if (baseUrlHost.isNotEmpty) {
      hosts.add(baseUrlHost);
    }
    for (final host in server.server?.trustedHosts ?? const <String>[]) {
      final normalizedHost = host.trim().toLowerCase();
      if (normalizedHost.isNotEmpty) {
        hosts.add(normalizedHost);
      }
    }
    return hosts;
  }

  String _serverDisplayName(String? rawName) {
    final trimmed = rawName?.trim() ?? '';
    return trimmed.isEmpty ? '当前服务器' : trimmed;
  }

  String _mergeServerDisplayName({
    required UnifiedNode? previous,
    required String? incoming,
    required String source,
  }) {
    final previousName = previous?.identity.displayName.trim();
    final incomingName = incoming?.trim();
    final incomingUsable =
        ServerDisplayNamePolicy.isUsableDisplayName(incomingName);
    final previousUsable =
        ServerDisplayNamePolicy.isUsableDisplayName(previousName);

    if (source == 'session') {
      if (incomingUsable) {
        return _serverDisplayName(incomingName);
      }
      if (previousUsable) {
        return _serverDisplayName(previousName);
      }
      return _serverDisplayName(incomingName ?? previousName);
    }

    if (source == 'discovery') {
      if (_hasStableServerName(previous) && previousUsable) {
        return _serverDisplayName(previousName);
      }
      if (incomingUsable) {
        return _serverDisplayName(incomingName);
      }
      return _serverDisplayName(previousName);
    }

    // saved / trust
    if (incomingUsable) {
      return _serverDisplayName(incomingName);
    }
    if (previousUsable) {
      return _serverDisplayName(previousName);
    }
    return _serverDisplayName(incomingName ?? previousName);
  }

  bool _hasStableServerName(UnifiedNode? node) {
    if (node == null) {
      return false;
    }
    if (node.relations.contains(NodeRelation.current) ||
        node.relations.contains(NodeRelation.saved) ||
        node.server?.isTrusted == true) {
      return true;
    }
    return false;
  }

  String _bestDisplayName({
    String? brand,
    String? model,
    String? deviceName,
    String? label,
    String? platform,
    required String fallback,
  }) {
    return DeviceDisplayResolver.publicDisplayName(
      alias: label,
      hardwareName: deviceName,
      brand: brand,
      model: model,
      platform: platform,
      fallback: fallback,
    );
  }

  String? _sanitizeDisplayAlias(String? rawValue) {
    return DeviceDisplayResolver.sanitizeAlias(rawValue);
  }

  bool _shouldPersistPeerIdentity(UnifiedNode node) {
    if ((node.identity.brand?.trim().isNotEmpty ?? false) ||
        (node.identity.model?.trim().isNotEmpty ?? false) ||
        (node.identity.platform?.trim().isNotEmpty ?? false)) {
      return true;
    }
    if (DeviceDisplayResolver.sanitizeAlias(node.identity.deviceName) != null ||
        DeviceDisplayResolver.sanitizeAlias(node.identity.label) != null) {
      return true;
    }
    if ((node.network.reportedRouteIp?.trim().isNotEmpty ?? false) ||
        (node.network.observedRemoteIp?.trim().isNotEmpty ?? false)) {
      return true;
    }
    return false;
  }

  PresenceStatus _serverPresenceFromStatus(String? status) {
    final normalized = status?.trim().toLowerCase() ?? '';
    if (normalized == 'online') {
      return PresenceStatus.online;
    }
    if (normalized == 'connecting') {
      return PresenceStatus.connecting;
    }
    return PresenceStatus.offline;
  }

  PresenceStatus _presenceStatus(String? status) {
    switch (status?.trim().toLowerCase()) {
      case 'online':
        return PresenceStatus.online;
      case 'connecting':
        return PresenceStatus.connecting;
      default:
        return PresenceStatus.offline;
    }
  }

  String? _sanitizePeerReportedRouteIp(String? reportedRouteIp) {
    final normalized = reportedRouteIp?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    final server = currentServer;
    if (server == null) {
      return normalized;
    }
    final serverLanIp = server.network.serverLanIp?.trim() ?? '';
    if (serverLanIp.isNotEmpty && normalized == serverLanIp) {
      return null;
    }
    final connectUrl = server.network.connectBaseUrl?.trim() ?? '';
    if (connectUrl.isNotEmpty) {
      final host = Uri.tryParse(connectUrl)?.host.trim() ?? '';
      if (host.isNotEmpty && normalized == host) {
        return null;
      }
    }
    return normalized;
  }

  Map<String, dynamic>? _cloneMap(Map<String, dynamic>? rawValue) {
    if (rawValue == null) {
      return null;
    }
    return Map<String, dynamic>.from(rawValue);
  }

  NodeMeta _nextMeta(NodeMeta? previous, DateTime updatedAt, String source) {
    return NodeMeta(
      updatedAt: updatedAt,
      updatedFrom: <String>{...?previous?.updatedFrom, source},
      revision: (previous?.revision ?? 0) + 1,
    );
  }

  void _emit() {
    _revision += 1;
    if (!_controller.isClosed) {
      _controller.add(_revision);
    }
  }

  String _resolveServerNodeId({String? serverId, String? serverUrl}) {
    final normalizedServerId = serverId?.trim() ?? '';
    final normalizedUrl = serverUrl?.trim() ?? '';
    final uri = normalizedUrl.isEmpty ? null : _tryParseUri(normalizedUrl);
    final targetHost = uri?.host;
    final targetPort = uri == null
        ? null
        : (uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80));
    if (normalizedServerId.isNotEmpty) {
      for (final entry in _byNodeId.entries) {
        if (entry.value.identity.serverId == normalizedServerId) {
          return entry.key;
        }
      }
    }
    if (normalizedUrl.isNotEmpty) {
      for (final entry in _byNodeId.entries) {
        if (entry.value.kind == NodeKind.server &&
            entry.value.network.connectBaseUrl == normalizedUrl) {
          return entry.key;
        }
      }
    }
    if (targetHost != null && targetHost.isNotEmpty && targetPort != null) {
      for (final entry in _byNodeId.entries) {
        final node = entry.value;
        if (node.kind != NodeKind.server) {
          continue;
        }
        final nodeHost = node.network.host;
        final nodePort = node.network.port;
        if (nodeHost == targetHost && nodePort == targetPort) {
          return entry.key;
        }
      }
    }
    if (normalizedServerId.isNotEmpty) {
      return 'server:$normalizedServerId';
    }
    if (normalizedUrl.isNotEmpty) {
      return 'server-url:$normalizedUrl';
    }
    return 'server-runtime:unknown';
  }

  List<String> _mergeTrustedHostsList(
    List<String> existing,
    List<String> incoming,
  ) {
    return <String>{...existing, ...incoming}.toList(growable: false)..sort();
  }
}
