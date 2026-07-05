/// 文件输入：ServerDiscoveryRepository、KeyValueStore、UnifiedNodeStore
/// 文件职责：管理服务器选择页面的状态，包括已保存服务器和搜索发现的服务器
/// 文件对外接口：ServerSelectionCubit
/// 文件包含：ServerSelectionCubit
import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/trusted_server_store.dart';
import '../../../../core/node/unified_node.dart';
import '../../../../core/node/unified_node_store.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../domain/repositories/server_discovery_repository.dart';
import 'server_selection_state.dart';

typedef ServerOnlineProbe = Future<bool> Function(String url);
typedef TrustedServerRecordsLoader =
    Future<List<TrustedServerRecord>> Function();

class ServerSelectionCubit extends Cubit<ServerSelectionState> {
  static const Duration defaultScanDuration = Duration(seconds: 3);
  static const Duration _onlineCheckTimeout = Duration(milliseconds: 1500);

  ServerSelectionCubit({
    required ServerDiscoveryRepository discoveryRepository,
    required KeyValueStore keyValueStore,
    required UnifiedNodeStore unifiedNodeStore,
    Duration scanDuration = defaultScanDuration,
    ServerOnlineProbe? onlineProbe,
    TrustedServerRecordsLoader? trustedServerRecordsLoader,
  }) : _discoveryRepository = discoveryRepository,
       _keyValueStore = keyValueStore,
       _unifiedNodeStore = unifiedNodeStore,
       _scanDuration = scanDuration,
       _onlineProbe = onlineProbe ?? _defaultOnlineProbe,
       _trustedServerRecordsLoader = trustedServerRecordsLoader,
       super(const ServerSelectionState());

  final ServerDiscoveryRepository _discoveryRepository;
  final KeyValueStore _keyValueStore;
  final UnifiedNodeStore _unifiedNodeStore;
  final Duration _scanDuration;
  final ServerOnlineProbe _onlineProbe;
  final TrustedServerRecordsLoader? _trustedServerRecordsLoader;
  StreamSubscription<List<UnifiedNode>>? _discoverySubscription;
  Timer? _scanTimer;
  int _scanSessionId = 0;
  int _onlineCheckSessionId = 0;
  Set<String> _pendingProbeUrls = <String>{};

  Future<void> loadSavedServers() async {
    _unifiedNodeStore.applySavedServers(_keyValueStore.getServerNodes());
    await _applyTrustedServers();
    emit(
      state.copyWith(
        savedServers: _unifiedNodeStore.savedServers,
        discoveredServers: _unifiedNodeStore.discoveredServers,
        serverOnlineStatus: _buildServerOnlineStatus(
          _unifiedNodeStore.savedServers,
        ),
        checkingOnline: false,
      ),
    );
    if (state.savedServers.isNotEmpty) {
      unawaited(checkServersOnline(state.savedServers));
    }
  }

  Future<void> checkServersOnline(List<UnifiedNode> servers) async {
    if (isClosed) {
      return;
    }

    final sessionId = ++_onlineCheckSessionId;
    final urls = servers
        .map((server) => server.network.connectBaseUrl)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet();
    _pendingProbeUrls = urls;
    emit(
      state.copyWith(
        serverOnlineStatus: _buildServerOnlineStatus(
          _unifiedNodeStore.savedServers,
        ),
        checkingOnline: urls.isNotEmpty,
      ),
    );

    await Future.wait(
      urls.map((url) async {
        final isOnline = await _onlineProbe(url);
        _setServerStatus(url, isOnline, sessionId: sessionId);
      }),
    );
  }

  void _setServerStatus(String url, bool isOnline, {required int sessionId}) {
    if (isClosed || !_isCurrentOnlineCheck(sessionId)) {
      return;
    }
    _pendingProbeUrls.remove(url);
    _unifiedNodeStore.setServerReachability(
      serverUrl: url,
      reachable: isOnline,
    );
    emit(
      state.copyWith(
        savedServers: _unifiedNodeStore.savedServers,
        discoveredServers: _unifiedNodeStore.discoveredServers,
        serverOnlineStatus: _buildServerOnlineStatus(
          _unifiedNodeStore.savedServers,
        ),
        checkingOnline: _pendingProbeUrls.isNotEmpty,
      ),
    );
  }

  Future<void> startScan() async {
    await _cancelActiveScan(updateState: false);
    if (isClosed) {
      return;
    }

    final sessionId = ++_scanSessionId;
    emit(
      state.copyWith(
        isScanning: true,
        hasCompletedScan: false,
        discoveredServers: _unifiedNodeStore.discoveredServers,
        errorMessage: null,
        scanNoticeMessage: null,
      ),
    );
    if (state.savedServers.isNotEmpty) {
      unawaited(checkServersOnline(state.savedServers));
    }
    _scanTimer = Timer(_scanDuration, () {
      unawaited(_completeScan(sessionId));
    });

    try {
      final stream = _discoveryRepository.discoverServers();
      _discoverySubscription = stream.listen(
        (servers) {
          if (!_isCurrentScan(sessionId) || isClosed) {
            return;
          }
          _unifiedNodeStore.applyDiscoveredServers(servers);
          _markDiscoveredSavedServersOnline(
            _unifiedNodeStore.discoveredServers,
          );
          emit(
            state.copyWith(
              discoveredServers: _unifiedNodeStore.discoveredServers,
              savedServers: _unifiedNodeStore.savedServers,
              serverOnlineStatus: _buildServerOnlineStatus(
                _unifiedNodeStore.savedServers,
              ),
              isScanning: true,
              errorMessage: null,
              scanNoticeMessage: null,
            ),
          );
        },
        onError: (Object error, StackTrace _) {
          unawaited(_failScan(sessionId, error.toString()));
        },
      );
    } catch (e) {
      await _failScan(sessionId, e.toString());
    }
  }

  Future<void> stopScan() async {
    _scanSessionId += 1;
    await _cancelActiveScan(updateState: !isClosed);
  }

  Future<void> refresh() async {
    await loadSavedServers();
  }

  void setAutoLoggingIn(String? url) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(autoLoggingInUrl: url));
  }

  @override
  Future<void> close() async {
    _onlineCheckSessionId += 1;
    _pendingProbeUrls = <String>{};
    await stopScan();
    return super.close();
  }

  bool _isCurrentScan(int sessionId) => _scanSessionId == sessionId;
  bool _isCurrentOnlineCheck(int sessionId) =>
      _onlineCheckSessionId == sessionId;

  void _markDiscoveredSavedServersOnline(List<UnifiedNode> discoveredServers) {
    final savedUrls = state.savedServers
        .map((server) => server.network.connectBaseUrl)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (savedUrls.isEmpty) {
      return;
    }

    for (final discovered in discoveredServers) {
      for (final savedUrl in savedUrls) {
        if (_matchesSavedServerUrl(savedUrl, discovered)) {
          _unifiedNodeStore.setServerReachability(
            serverUrl: savedUrl,
            reachable: true,
          );
          _pendingProbeUrls.remove(savedUrl);
        }
      }
    }
  }

  bool _matchesSavedServerUrl(String savedUrl, UnifiedNode server) {
    if (savedUrl == server.network.connectBaseUrl) {
      return true;
    }

    final uri = Uri.tryParse(savedUrl);
    final host = server.network.host;
    if (uri == null || uri.host.isEmpty || host == null || host.isEmpty) {
      return false;
    }

    final savedPort = uri.hasPort
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    final serverPort = server.network.port ?? savedPort;
    return uri.host == host && savedPort == serverPort;
  }

  Future<void> _completeScan(int sessionId) async {
    if (!_isCurrentScan(sessionId)) {
      return;
    }

    final hasResults = state.discoveredServers.isNotEmpty;
    await _cancelActiveScan(updateState: false);
    if (!_isCurrentScan(sessionId) || isClosed) {
      return;
    }

    emit(
      state.copyWith(
        isScanning: false,
        hasCompletedScan: true,
        errorMessage: null,
        scanNoticeMessage: hasResults ? null : '未发现任何服务器',
        scanNoticeVersion: hasResults
            ? state.scanNoticeVersion
            : state.scanNoticeVersion + 1,
      ),
    );
  }

  Future<void> _failScan(int sessionId, String message) async {
    if (!_isCurrentScan(sessionId)) {
      return;
    }

    await _cancelActiveScan(updateState: false);
    if (!_isCurrentScan(sessionId) || isClosed) {
      return;
    }

    emit(
      state.copyWith(
        isScanning: false,
        hasCompletedScan: true,
        errorMessage: message,
        scanNoticeMessage: null,
      ),
    );
  }

  Future<void> _cancelActiveScan({required bool updateState}) async {
    final wasScanning = state.isScanning;
    final hadTimer = _scanTimer != null;
    _scanTimer?.cancel();
    _scanTimer = null;

    final subscription = _discoverySubscription;
    _discoverySubscription = null;
    await subscription?.cancel();
    final hadActiveScan = wasScanning || hadTimer || subscription != null;
    if (hadActiveScan) {
      _discoveryRepository.stopDiscovery();
    }

    if (updateState && wasScanning && !isClosed) {
      emit(
        state.copyWith(
          isScanning: false,
          errorMessage: null,
          scanNoticeMessage: null,
        ),
      );
    }
  }

  Future<void> _applyTrustedServers() async {
    final loader = _trustedServerRecordsLoader;
    if (loader == null) {
      return;
    }
    final records = await loader();
    _unifiedNodeStore.applyTrustedServers(records);
  }

  Map<String, bool> _buildServerOnlineStatus(List<UnifiedNode> servers) {
    final result = <String, bool>{};
    for (final server in servers) {
      final url = server.network.connectBaseUrl;
      if (url == null || url.isEmpty) {
        continue;
      }
      result[url] = server.network.reachable ?? false;
    }
    return result;
  }

  static Future<bool> probeServerOnline(String url) => _defaultOnlineProbe(url);

  static Future<bool> _defaultOnlineProbe(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) {
        return false;
      }

      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        uri.host,
        port,
        timeout: _onlineCheckTimeout,
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
