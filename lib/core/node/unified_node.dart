import '../auth/root_info.dart';
import 'server_display_name_resolver.dart';

enum NodeKind { server, client }

enum NodeRelation { self, current, saved, discovered, peer, managed }

enum PresenceStatus { offline, connecting, online }

enum NodeAdminState { active, disabled, deleted }

class UnifiedNode {
  const UnifiedNode({
    required this.nodeId,
    required this.kind,
    required this.identity,
    required this.network,
    required this.presence,
    required this.runtime,
    required this.management,
    required this.meta,
    this.relations = const <NodeRelation>{},
    this.client,
    this.server,
  });

  factory UnifiedNode.savedServer({
    required String serverUrl,
    String? serverId,
    String? displayName,
    String? platform,
    String? certificateSha256,
    List<String> trustedHosts = const <String>[],
    bool isTrusted = false,
    DateTime? updatedAt,
  }) {
    final uri = Uri.tryParse(serverUrl);
    final now = updatedAt ?? DateTime.now().toUtc();
    return UnifiedNode(
      nodeId: (serverId?.trim().isNotEmpty ?? false)
          ? 'server:${serverId!.trim()}'
          : 'server-url:${serverUrl.trim()}',
      kind: NodeKind.server,
      relations: const <NodeRelation>{NodeRelation.saved},
      identity: NodeIdentity(
        displayName: (displayName?.trim().isNotEmpty ?? false)
            ? displayName!.trim()
            : '已保存服务器',
        serverId: serverId?.trim().isEmpty ?? true ? null : serverId!.trim(),
        platform: platform?.trim().isEmpty ?? true ? null : platform!.trim(),
      ),
      network: NodeNetwork(
        connectBaseUrl: serverUrl,
        host: uri?.host,
        port: uri?.hasPort == true ? uri!.port : null,
      ),
      presence: const NodePresence(),
      runtime: const NodeRuntime(),
      management: const NodeManagement(),
      meta: NodeMeta(updatedAt: now, updatedFrom: const {'saved'}),
      server: ServerFacet(
        certificateSha256: certificateSha256?.trim().isEmpty ?? true
            ? null
            : certificateSha256!.trim(),
        isTrusted: isTrusted,
        trustedHosts: trustedHosts,
      ),
    );
  }

  factory UnifiedNode.discoveredServer({
    required String name,
    required String host,
    required int port,
    required String serviceType,
    String? serverId,
    String? caSha256,
    String? scheme,
    String? baseUrl,
    String? hostLabel,
    String? platform,
    DateTime? discoveredAt,
  }) {
    final protocol = _resolveDiscoveredProtocol(
      serviceType: serviceType,
      scheme: scheme,
    );
    final connectBaseUrl = (baseUrl?.trim().isNotEmpty ?? false)
        ? baseUrl!.trim()
        : '$protocol://$host:$port';
    final now = discoveredAt ?? DateTime.now().toUtc();
    return UnifiedNode(
      nodeId: (serverId?.trim().isNotEmpty ?? false)
          ? 'server:${serverId!.trim()}'
          : 'server-url:$connectBaseUrl',
      kind: NodeKind.server,
      relations: const <NodeRelation>{NodeRelation.discovered},
      identity: NodeIdentity(
        displayName: ServerDisplayNameResolver.resolve(
          mdnsServiceName: name,
        ),
        serverId: serverId?.trim().isEmpty ?? true ? null : serverId!.trim(),
        platform: platform?.trim().isEmpty ?? true ? null : platform!.trim(),
      ),
      network: NodeNetwork(
        connectBaseUrl: connectBaseUrl,
        host: host,
        port: port,
        reachable: true,
        reachableCheckedAt: now,
      ),
      presence: const NodePresence(status: PresenceStatus.online),
      runtime: const NodeRuntime(status: 'online'),
      management: const NodeManagement(),
      meta: NodeMeta(updatedAt: now, updatedFrom: const {'discovery'}),
      server: ServerFacet(
        certificateSha256: caSha256?.trim().isEmpty ?? true ? null : caSha256,
        trustedHosts: <String>[host],
      ),
    );
  }

  factory UnifiedNode.peerPlaceholder({
    required String clientId,
    String? label,
    String? deviceName,
    DateTime? updatedAt,
  }) {
    final now = updatedAt ?? DateTime.now().toUtc();
    return UnifiedNode(
      nodeId: 'client-runtime:${clientId.trim()}',
      kind: NodeKind.client,
      relations: const <NodeRelation>{NodeRelation.peer},
      identity: NodeIdentity(
        displayName: label?.trim().isNotEmpty == true
            ? label!.trim()
            : clientId.trim(),
        clientId: clientId.trim(),
        label: label?.trim().isEmpty ?? true ? null : label!.trim(),
        deviceName: deviceName?.trim().isEmpty ?? true
            ? null
            : deviceName!.trim(),
      ),
      network: const NodeNetwork(),
      presence: const NodePresence(status: PresenceStatus.offline),
      runtime: const NodeRuntime(),
      management: const NodeManagement(),
      meta: NodeMeta(updatedAt: now, updatedFrom: const {'relay-history'}),
      client: const ClientFacet(),
    );
  }

  factory UnifiedNode.cachedPeerIdentity({
    required String clientId,
    String? accountId,
    String? displayName,
    String? label,
    String? deviceName,
    String? platform,
    String? brand,
    String? model,
    String? appVersion,
    String? reportedRouteIp,
    String? observedRemoteIp,
    DateTime? updatedAt,
  }) {
    final now = updatedAt ?? DateTime.now().toUtc();
    final normalizedClientId = clientId.trim();
    return UnifiedNode(
      nodeId: 'client-runtime:$normalizedClientId',
      kind: NodeKind.client,
      relations: const <NodeRelation>{NodeRelation.peer},
      identity: NodeIdentity(
        displayName: displayName?.trim().isNotEmpty == true
            ? displayName!.trim()
            : normalizedClientId,
        accountId: accountId?.trim().isEmpty ?? true ? null : accountId!.trim(),
        clientId: normalizedClientId,
        label: label?.trim().isEmpty ?? true ? null : label!.trim(),
        deviceName: deviceName?.trim().isEmpty ?? true
            ? null
            : deviceName!.trim(),
        platform: platform?.trim().isEmpty ?? true ? null : platform!.trim(),
        brand: brand?.trim().isEmpty ?? true ? null : brand!.trim(),
        manufacturer: brand?.trim().isEmpty ?? true ? null : brand!.trim(),
        model: model?.trim().isEmpty ?? true ? null : model!.trim(),
        appVersion: appVersion?.trim().isEmpty ?? true
            ? null
            : appVersion!.trim(),
      ),
      network: NodeNetwork(
        reportedRouteIp: reportedRouteIp?.trim().isEmpty ?? true
            ? null
            : reportedRouteIp!.trim(),
        observedRemoteIp: observedRemoteIp?.trim().isEmpty ?? true
            ? null
            : observedRemoteIp!.trim(),
      ),
      presence: const NodePresence(status: PresenceStatus.offline),
      runtime: const NodeRuntime(),
      management: const NodeManagement(),
      meta: NodeMeta(updatedAt: now, updatedFrom: const {'peer-cache'}),
      client: const ClientFacet(),
    );
  }

  final String nodeId;
  final NodeKind kind;
  final Set<NodeRelation> relations;
  final NodeIdentity identity;
  final NodeNetwork network;
  final NodePresence presence;
  final NodeRuntime runtime;
  final NodeManagement management;
  final NodeMeta meta;
  final ClientFacet? client;
  final ServerFacet? server;

  Map<String, dynamic> toSavedServerJson() {
    return {
      'nodeId': nodeId,
      'displayName': identity.displayName,
      'serverId': identity.serverId,
      'platform': identity.platform,
      'connectBaseUrl': network.connectBaseUrl,
      'host': network.host,
      'port': network.port,
      'reachable': network.reachable,
      'reachableCheckedAt': network.reachableCheckedAt?.toIso8601String(),
      'status': runtime.status,
      'updatedAt': meta.updatedAt.toIso8601String(),
      'updatedFrom': meta.updatedFrom.toList(growable: false),
      'certificateSha256': server?.certificateSha256,
      'isTrusted': server?.isTrusted ?? false,
      'trustedHosts': server?.trustedHosts ?? const <String>[],
    };
  }

  Map<String, dynamic> toPeerIdentityJson() {
    return {
      'nodeId': nodeId,
      'displayName': identity.displayName,
      'accountId': identity.accountId,
      'clientId': identity.clientId,
      'label': identity.label,
      'deviceName': identity.deviceName,
      'platform': identity.platform,
      'brand': identity.brand,
      'model': identity.model,
      'appVersion': identity.appVersion,
      'reportedRouteIp': network.reportedRouteIp,
      'observedRemoteIp': network.observedRemoteIp,
      'updatedAt': meta.updatedAt.toIso8601String(),
    };
  }

  factory UnifiedNode.fromSavedServerJson(Map<String, dynamic> json) {
    final connectBaseUrl = json['connectBaseUrl'] as String? ?? '';
    final host = json['host'] as String?;
    final portValue = json['port'];
    final updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    )?.toUtc();
    final reachableCheckedAt = DateTime.tryParse(
      json['reachableCheckedAt'] as String? ?? '',
    )?.toUtc();
    final trustedHostsValue = json['trustedHosts'];
    final trustedHosts = trustedHostsValue is List
        ? trustedHostsValue
              .map((item) => item.toString())
              .toList(growable: false)
        : const <String>[];
    final updatedFromValue = json['updatedFrom'];
    final updatedFrom = updatedFromValue is List
        ? updatedFromValue.map((item) => item.toString()).toSet()
        : const <String>{'saved'};
    return UnifiedNode(
      nodeId:
          json['nodeId'] as String? ??
          ((json['serverId'] as String?)?.trim().isNotEmpty == true
              ? 'server:${(json['serverId'] as String).trim()}'
              : 'server-url:$connectBaseUrl'),
      kind: NodeKind.server,
      relations: const <NodeRelation>{NodeRelation.saved},
      identity: NodeIdentity(
        displayName: json['displayName'] as String? ?? '已保存服务器',
        serverId: json['serverId'] as String?,
        platform: json['platform'] as String?,
      ),
      network: NodeNetwork(
        connectBaseUrl: connectBaseUrl.isEmpty ? null : connectBaseUrl,
        host: host,
        port: portValue is int
            ? portValue
            : (portValue is num ? portValue.toInt() : null),
        reachable: json['reachable'] as bool?,
        reachableCheckedAt: reachableCheckedAt,
      ),
      presence: NodePresence(
        status: _presenceFromString(json['status'] as String?),
      ),
      runtime: NodeRuntime(status: json['status'] as String?),
      management: const NodeManagement(),
      meta: NodeMeta(
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        updatedFrom: updatedFrom,
      ),
      server: ServerFacet(
        certificateSha256: json['certificateSha256'] as String?,
        isTrusted: json['isTrusted'] as bool? ?? false,
        trustedHosts: trustedHosts,
      ),
    );
  }

  factory UnifiedNode.fromPeerIdentityJson(Map<String, dynamic> json) {
    final clientId = (json['clientId'] as String? ?? '').trim();
    final updatedAt = DateTime.tryParse(
      json['updatedAt'] as String? ?? '',
    )?.toUtc();
    return UnifiedNode.cachedPeerIdentity(
      clientId: clientId,
      accountId: json['accountId'] as String?,
      displayName: json['displayName'] as String?,
      label: json['label'] as String?,
      deviceName: json['deviceName'] as String?,
      platform: json['platform'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      appVersion: json['appVersion'] as String?,
      reportedRouteIp: json['reportedRouteIp'] as String?,
      observedRemoteIp: json['observedRemoteIp'] as String?,
      updatedAt: updatedAt,
    );
  }

  UnifiedNode copyWith({
    String? nodeId,
    NodeKind? kind,
    Set<NodeRelation>? relations,
    NodeIdentity? identity,
    NodeNetwork? network,
    NodePresence? presence,
    NodeRuntime? runtime,
    NodeManagement? management,
    NodeMeta? meta,
    Object? client = _sentinel,
    Object? server = _sentinel,
  }) {
    return UnifiedNode(
      nodeId: nodeId ?? this.nodeId,
      kind: kind ?? this.kind,
      relations: relations ?? this.relations,
      identity: identity ?? this.identity,
      network: network ?? this.network,
      presence: presence ?? this.presence,
      runtime: runtime ?? this.runtime,
      management: management ?? this.management,
      meta: meta ?? this.meta,
      client: client == _sentinel ? this.client : client as ClientFacet?,
      server: server == _sentinel ? this.server : server as ServerFacet?,
    );
  }
}

class NodeIdentity {
  const NodeIdentity({
    required this.displayName,
    this.serverId,
    this.accountId,
    this.clientId,
    this.deviceId,
    this.username,
    this.label,
    this.deviceName,
    this.platform,
    this.brand,
    this.manufacturer,
    this.model,
    this.systemVersion,
    this.appVersion,
  });

  final String displayName;
  final String? serverId;
  final String? accountId;
  final String? clientId;
  final String? deviceId;
  final String? username;
  final String? label;
  final String? deviceName;
  final String? platform;
  final String? brand;
  final String? manufacturer;
  final String? model;
  final String? systemVersion;
  final String? appVersion;

  NodeIdentity copyWith({
    String? displayName,
    Object? serverId = _sentinel,
    Object? accountId = _sentinel,
    Object? clientId = _sentinel,
    Object? deviceId = _sentinel,
    Object? username = _sentinel,
    Object? label = _sentinel,
    Object? deviceName = _sentinel,
    Object? platform = _sentinel,
    Object? brand = _sentinel,
    Object? manufacturer = _sentinel,
    Object? model = _sentinel,
    Object? systemVersion = _sentinel,
    Object? appVersion = _sentinel,
  }) {
    return NodeIdentity(
      displayName: displayName ?? this.displayName,
      serverId: serverId == _sentinel ? this.serverId : serverId as String?,
      accountId: accountId == _sentinel ? this.accountId : accountId as String?,
      clientId: clientId == _sentinel ? this.clientId : clientId as String?,
      deviceId: deviceId == _sentinel ? this.deviceId : deviceId as String?,
      username: username == _sentinel ? this.username : username as String?,
      label: label == _sentinel ? this.label : label as String?,
      deviceName: deviceName == _sentinel
          ? this.deviceName
          : deviceName as String?,
      platform: platform == _sentinel ? this.platform : platform as String?,
      brand: brand == _sentinel ? this.brand : brand as String?,
      manufacturer: manufacturer == _sentinel
          ? this.manufacturer
          : manufacturer as String?,
      model: model == _sentinel ? this.model : model as String?,
      systemVersion: systemVersion == _sentinel
          ? this.systemVersion
          : systemVersion as String?,
      appVersion: appVersion == _sentinel
          ? this.appVersion
          : appVersion as String?,
    );
  }
}

class NodeNetwork {
  const NodeNetwork({
    this.connectBaseUrl,
    this.host,
    this.port,
    this.serverLanIp,
    this.reportedRouteIp,
    this.observedRemoteIp,
    this.reachable,
    this.reachableCheckedAt,
  });

  final String? connectBaseUrl;
  final String? host;
  final int? port;
  final String? serverLanIp;
  final String? reportedRouteIp;
  final String? observedRemoteIp;
  final bool? reachable;
  final DateTime? reachableCheckedAt;

  NodeNetwork copyWith({
    Object? connectBaseUrl = _sentinel,
    Object? host = _sentinel,
    Object? port = _sentinel,
    Object? serverLanIp = _sentinel,
    Object? reportedRouteIp = _sentinel,
    Object? observedRemoteIp = _sentinel,
    Object? reachable = _sentinel,
    Object? reachableCheckedAt = _sentinel,
  }) {
    return NodeNetwork(
      connectBaseUrl: connectBaseUrl == _sentinel
          ? this.connectBaseUrl
          : connectBaseUrl as String?,
      host: host == _sentinel ? this.host : host as String?,
      port: port == _sentinel ? this.port : port as int?,
      serverLanIp: serverLanIp == _sentinel
          ? this.serverLanIp
          : serverLanIp as String?,
      reportedRouteIp: reportedRouteIp == _sentinel
          ? this.reportedRouteIp
          : reportedRouteIp as String?,
      observedRemoteIp: observedRemoteIp == _sentinel
          ? this.observedRemoteIp
          : observedRemoteIp as String?,
      reachable: reachable == _sentinel ? this.reachable : reachable as bool?,
      reachableCheckedAt: reachableCheckedAt == _sentinel
          ? this.reachableCheckedAt
          : reachableCheckedAt as DateTime?,
    );
  }
}

class NodePresence {
  const NodePresence({
    this.status = PresenceStatus.offline,
    this.connectionId,
    this.sessionId,
    this.connectedAt,
    this.lastHeartbeatAt,
    this.lastSeenAt,
  });

  final PresenceStatus status;
  final String? connectionId;
  final String? sessionId;
  final DateTime? connectedAt;
  final DateTime? lastHeartbeatAt;
  final DateTime? lastSeenAt;

  NodePresence copyWith({
    PresenceStatus? status,
    Object? connectionId = _sentinel,
    Object? sessionId = _sentinel,
    Object? connectedAt = _sentinel,
    Object? lastHeartbeatAt = _sentinel,
    Object? lastSeenAt = _sentinel,
  }) {
    return NodePresence(
      status: status ?? this.status,
      connectionId: connectionId == _sentinel
          ? this.connectionId
          : connectionId as String?,
      sessionId: sessionId == _sentinel ? this.sessionId : sessionId as String?,
      connectedAt: connectedAt == _sentinel
          ? this.connectedAt
          : connectedAt as DateTime?,
      lastHeartbeatAt: lastHeartbeatAt == _sentinel
          ? this.lastHeartbeatAt
          : lastHeartbeatAt as DateTime?,
      lastSeenAt: lastSeenAt == _sentinel
          ? this.lastSeenAt
          : lastSeenAt as DateTime?,
    );
  }
}

class NodeRuntime {
  const NodeRuntime({
    this.status,
    this.uptimeSeconds,
    this.batteryLevel,
    this.batteryPercent,
    this.isCharging,
    this.storageTotal,
    this.storageUsed,
    this.storageAvailable,
  });

  final String? status;
  final int? uptimeSeconds;
  final int? batteryLevel;
  final double? batteryPercent;
  final bool? isCharging;
  final int? storageTotal;
  final int? storageUsed;
  final int? storageAvailable;

  NodeRuntime copyWith({
    Object? status = _sentinel,
    Object? uptimeSeconds = _sentinel,
    Object? batteryLevel = _sentinel,
    Object? batteryPercent = _sentinel,
    Object? isCharging = _sentinel,
    Object? storageTotal = _sentinel,
    Object? storageUsed = _sentinel,
    Object? storageAvailable = _sentinel,
  }) {
    return NodeRuntime(
      status: status == _sentinel ? this.status : status as String?,
      uptimeSeconds: uptimeSeconds == _sentinel
          ? this.uptimeSeconds
          : uptimeSeconds as int?,
      batteryLevel: batteryLevel == _sentinel
          ? this.batteryLevel
          : batteryLevel as int?,
      batteryPercent: batteryPercent == _sentinel
          ? this.batteryPercent
          : batteryPercent as double?,
      isCharging: isCharging == _sentinel
          ? this.isCharging
          : isCharging as bool?,
      storageTotal: storageTotal == _sentinel
          ? this.storageTotal
          : storageTotal as int?,
      storageUsed: storageUsed == _sentinel
          ? this.storageUsed
          : storageUsed as int?,
      storageAvailable: storageAvailable == _sentinel
          ? this.storageAvailable
          : storageAvailable as int?,
    );
  }
}

class NodeManagement {
  const NodeManagement({
    this.adminState = NodeAdminState.active,
    this.allowedActions = const <String>{},
  });

  final NodeAdminState adminState;
  final Set<String> allowedActions;

  NodeManagement copyWith({
    NodeAdminState? adminState,
    Set<String>? allowedActions,
  }) {
    return NodeManagement(
      adminState: adminState ?? this.adminState,
      allowedActions: allowedActions ?? this.allowedActions,
    );
  }
}

class NodeMeta {
  const NodeMeta({
    required this.updatedAt,
    this.updatedFrom = const <String>{},
    this.revision = 0,
  });

  final DateTime updatedAt;
  final Set<String> updatedFrom;
  final int revision;

  NodeMeta copyWith({
    DateTime? updatedAt,
    Set<String>? updatedFrom,
    int? revision,
  }) {
    return NodeMeta(
      updatedAt: updatedAt ?? this.updatedAt,
      updatedFrom: updatedFrom ?? this.updatedFrom,
      revision: revision ?? this.revision,
    );
  }
}

class ClientFacet {
  const ClientFacet({
    this.role,
    this.credentialStatus,
    this.credentialVersion,
    this.boundDeviceId,
    this.boundDeviceName,
    this.boundAt,
    this.createdAt,
    this.lastUsedAt,
    this.lastBoundAt,
    this.avatarUpdatedAt,
  });

  final String? role;
  final String? credentialStatus;
  final String? credentialVersion;
  final String? boundDeviceId;
  final String? boundDeviceName;
  final DateTime? boundAt;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? lastBoundAt;
  final DateTime? avatarUpdatedAt;

  ClientFacet copyWith({
    Object? role = _sentinel,
    Object? credentialStatus = _sentinel,
    Object? credentialVersion = _sentinel,
    Object? boundDeviceId = _sentinel,
    Object? boundDeviceName = _sentinel,
    Object? boundAt = _sentinel,
    Object? createdAt = _sentinel,
    Object? lastUsedAt = _sentinel,
    Object? lastBoundAt = _sentinel,
    Object? avatarUpdatedAt = _sentinel,
  }) {
    return ClientFacet(
      role: role == _sentinel ? this.role : role as String?,
      credentialStatus: credentialStatus == _sentinel
          ? this.credentialStatus
          : credentialStatus as String?,
      credentialVersion: credentialVersion == _sentinel
          ? this.credentialVersion
          : credentialVersion as String?,
      boundDeviceId: boundDeviceId == _sentinel
          ? this.boundDeviceId
          : boundDeviceId as String?,
      boundDeviceName: boundDeviceName == _sentinel
          ? this.boundDeviceName
          : boundDeviceName as String?,
      boundAt: boundAt == _sentinel ? this.boundAt : boundAt as DateTime?,
      createdAt: createdAt == _sentinel
          ? this.createdAt
          : createdAt as DateTime?,
      lastUsedAt: lastUsedAt == _sentinel
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
      lastBoundAt: lastBoundAt == _sentinel
          ? this.lastBoundAt
          : lastBoundAt as DateTime?,
      avatarUpdatedAt: avatarUpdatedAt == _sentinel
          ? this.avatarUpdatedAt
          : avatarUpdatedAt as DateTime?,
    );
  }
}

class ServerFacet {
  const ServerFacet({
    this.serverVersion,
    this.protocol,
    this.capabilities,
    this.roots = const <RootInfo>[],
    this.webdavConfig,
    this.certificateSha256,
    this.isTrusted = false,
    this.trustedHosts = const <String>[],
  });

  final String? serverVersion;
  final String? protocol;
  final Map<String, dynamic>? capabilities;
  final List<RootInfo> roots;
  final Map<String, dynamic>? webdavConfig;
  final String? certificateSha256;
  final bool isTrusted;
  final List<String> trustedHosts;

  ServerFacet copyWith({
    Object? serverVersion = _sentinel,
    Object? protocol = _sentinel,
    Object? capabilities = _sentinel,
    List<RootInfo>? roots,
    Object? webdavConfig = _sentinel,
    Object? certificateSha256 = _sentinel,
    bool? isTrusted,
    List<String>? trustedHosts,
  }) {
    return ServerFacet(
      serverVersion: serverVersion == _sentinel
          ? this.serverVersion
          : serverVersion as String?,
      protocol: protocol == _sentinel ? this.protocol : protocol as String?,
      capabilities: capabilities == _sentinel
          ? this.capabilities
          : capabilities as Map<String, dynamic>?,
      roots: roots ?? this.roots,
      webdavConfig: webdavConfig == _sentinel
          ? this.webdavConfig
          : webdavConfig as Map<String, dynamic>?,
      certificateSha256: certificateSha256 == _sentinel
          ? this.certificateSha256
          : certificateSha256 as String?,
      isTrusted: isTrusted ?? this.isTrusted,
      trustedHosts: trustedHosts ?? this.trustedHosts,
    );
  }
}

class AuthStateSnapshot {
  const AuthStateSnapshot({
    this.accountId,
    this.role,
    this.clientId,
    this.deviceId,
    this.sessionId,
    this.accessToken,
    this.expiresAt,
    this.username,
    this.password,
  });

  final String? accountId;
  final String? role;
  final String? clientId;
  final String? deviceId;
  final String? sessionId;
  final String? accessToken;
  final DateTime? expiresAt;
  final String? username;
  final String? password;

  AuthStateSnapshot copyWith({
    Object? accountId = _sentinel,
    Object? role = _sentinel,
    Object? clientId = _sentinel,
    Object? deviceId = _sentinel,
    Object? sessionId = _sentinel,
    Object? accessToken = _sentinel,
    Object? expiresAt = _sentinel,
    Object? username = _sentinel,
    Object? password = _sentinel,
  }) {
    return AuthStateSnapshot(
      accountId: accountId == _sentinel ? this.accountId : accountId as String?,
      role: role == _sentinel ? this.role : role as String?,
      clientId: clientId == _sentinel ? this.clientId : clientId as String?,
      deviceId: deviceId == _sentinel ? this.deviceId : deviceId as String?,
      sessionId: sessionId == _sentinel ? this.sessionId : sessionId as String?,
      accessToken: accessToken == _sentinel
          ? this.accessToken
          : accessToken as String?,
      expiresAt: expiresAt == _sentinel
          ? this.expiresAt
          : expiresAt as DateTime?,
      username: username == _sentinel ? this.username : username as String?,
      password: password == _sentinel ? this.password : password as String?,
    );
  }
}

class NavigationStateSnapshot {
  const NavigationStateSnapshot({
    this.protocol,
    this.rootId,
    this.rootName,
    this.roots = const <RootInfo>[],
    this.webdavConfig,
  });

  final String? protocol;
  final String? rootId;
  final String? rootName;
  final List<RootInfo> roots;
  final Map<String, dynamic>? webdavConfig;

  NavigationStateSnapshot copyWith({
    Object? protocol = _sentinel,
    Object? rootId = _sentinel,
    Object? rootName = _sentinel,
    List<RootInfo>? roots,
    Object? webdavConfig = _sentinel,
  }) {
    return NavigationStateSnapshot(
      protocol: protocol == _sentinel ? this.protocol : protocol as String?,
      rootId: rootId == _sentinel ? this.rootId : rootId as String?,
      rootName: rootName == _sentinel ? this.rootName : rootName as String?,
      roots: roots ?? this.roots,
      webdavConfig: webdavConfig == _sentinel
          ? this.webdavConfig
          : webdavConfig as Map<String, dynamic>?,
    );
  }
}

class SessionContextState {
  const SessionContextState({this.currentServerNodeId, this.selfClientNodeId});

  final String? currentServerNodeId;
  final String? selfClientNodeId;

  SessionContextState copyWith({
    Object? currentServerNodeId = _sentinel,
    Object? selfClientNodeId = _sentinel,
  }) {
    return SessionContextState(
      currentServerNodeId: currentServerNodeId == _sentinel
          ? this.currentServerNodeId
          : currentServerNodeId as String?,
      selfClientNodeId: selfClientNodeId == _sentinel
          ? this.selfClientNodeId
          : selfClientNodeId as String?,
    );
  }
}

const Object _sentinel = Object();

String _resolveDiscoveredProtocol({
  required String serviceType,
  required String? scheme,
}) {
  final normalizedScheme = scheme?.trim().toLowerCase();
  if (normalizedScheme == 'https' || normalizedScheme == 'http') {
    return normalizedScheme!;
  }
  if (serviceType.contains('_webdavs.')) {
    return 'https';
  }
  if (serviceType.contains('webdav')) {
    return 'http';
  }
  return 'http';
}

PresenceStatus _presenceFromString(String? status) {
  switch (status?.trim().toLowerCase()) {
    case 'online':
      return PresenceStatus.online;
    case 'connecting':
      return PresenceStatus.connecting;
    default:
      return PresenceStatus.offline;
  }
}

class PeerProfileSnapshot {
  const PeerProfileSnapshot({
    required this.deviceId,
    this.label,
    this.deviceName,
    this.platform,
    this.brand,
    this.model,
    this.displayName,
    this.avatarUpdatedAt,
    this.online,
  });

  final String deviceId;
  final String? label;
  final String? deviceName;
  final String? platform;
  final String? brand;
  final String? model;
  final String? displayName;
  final DateTime? avatarUpdatedAt;
  final bool? online;
}
