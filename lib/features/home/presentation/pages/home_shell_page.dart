import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/node/device_display_extensions.dart';
import '../../../../core/node/unified_node_store.dart';
import '../../../../core/realtime/realtime_connection_state.dart';
import '../../../../core/realtime/realtime_session_service.dart';
import '../../../../core/runtime/runtime_build_info.dart';
import '../../../../core/session/server_availability_controller.dart';
import '../../../../core/session/runtime_session_recovery_service.dart';
import '../../../../core/use_case/no_params.dart';
import '../../../../core/widgets/offline_resource_gate.dart';
import '../../../backup/presentation/cubit/backup_cubit.dart';
import '../../../dashboard/presentation/cubit/dashboard_cubit.dart';
import '../../../dashboard/presentation/cubit/dashboard_state.dart';
import '../../../dashboard/presentation/pages/dashboard_page.dart';
import '../../../files/presentation/cubit/file_browser_cubit.dart';
import '../../../files/presentation/cubit/file_browser_state.dart';
import '../../../files/presentation/pages/file_browser_page.dart';
import '../../../relay/presentation/cubit/relay_cubit.dart';
import '../../../relay/presentation/cubit/relay_state.dart';
import '../../../relay/presentation/pages/relay_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';
import '../../../transfer/presentation/cubit/transfer_state.dart';

class HomeShellPage extends StatefulWidget {
  final bool shouldRestoreSession;
  final DashboardCubit? dashboardCubit;
  final FileBrowserCubit? fileBrowserCubit;
  final BackupCubit? backupCubit;
  final TransferCubit? transferCubit;

  const HomeShellPage({
    super.key,
    this.shouldRestoreSession = false,
    this.dashboardCubit,
    this.fileBrowserCubit,
    this.backupCubit,
    this.transferCubit,
  });

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage>
    with WidgetsBindingObserver {
  DashboardCubit? _dashboardCubit;
  FileBrowserCubit? _fileBrowserCubit;
  BackupCubit? _backupCubit;
  TransferCubit? _transferCubit;
  RelayCubit? _relayCubit;
  RealtimeSessionService? _realtimeSessionService;
  RuntimeSessionRecoveryService? _runtimeSessionRecoveryService;
  ServerAvailabilityController? _serverAvailabilityController;
  UnifiedNodeStore? _unifiedNodeStore;
  StreamSubscription<RealtimeConnectionStatus>? _realtimeStatusSubscription;
  StreamSubscription<ServerAvailabilityStatus>? _serverAvailabilitySubscription;
  StreamSubscription<DashboardState>? _dashboardStateSubscription;
  StreamSubscription<int>? _nodeStoreSubscription;
  Timer? _peerIdentityPersistTimer;

  int _selectedIndex = 0;
  bool _shellReady = false;
  DateTime? _lastIncomingRelaySnackAt;
  bool _dashboardLoaded = false;
  bool _fileBrowserLoaded = false;
  bool _transferTasksLoaded = false;
  bool _relayHistoryLoaded = false;
  bool _deferredStartupScheduled = false;
  Set<String>? _lastSyncedEnrolledDeviceIds;
  ServerAvailabilityStatus _currentServerAvailabilityStatus =
      ServerAvailabilityStatus.offline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.shouldRestoreSession &&
        !serviceLocator.currentSession.hasSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_restoreStartupSession());
      });
      return;
    }

    _initializeShell();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_realtimeStatusSubscription?.cancel());
    unawaited(_serverAvailabilitySubscription?.cancel());
    unawaited(_dashboardStateSubscription?.cancel());
    unawaited(_nodeStoreSubscription?.cancel());
    _peerIdentityPersistTimer?.cancel();
    unawaited(_persistPeerIdentityCache());
    _realtimeSessionService?.clearDashboardListener();
    _realtimeSessionService?.clearPresenceListener();
    _realtimeSessionService?.clearTransferListener();
    unawaited(_realtimeSessionService?.dispose());
    _serverAvailabilityController?.stopMonitoring();
    _dashboardCubit?.close();
    _fileBrowserCubit?.close();
    _backupCubit?.close();
    _relayCubit?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_realtimeSessionService?.handleForegroundResume());
    }
  }

  Future<void> _restoreStartupSession() async {
    final result = await serviceLocator.restoreSessionUseCase.call(NoParams());
    if (!mounted) {
      return;
    }

    result.when(
      success: (_) async {
        final serverUrl = serviceLocator.currentSession.serverUrl;
        if (serverUrl != null && serverUrl.isNotEmpty) {
          await serviceLocator.setBaseUrl(serverUrl);
        }
        _initializeShell(notify: true);
      },
      failure: (_) {
        context.go(RouteNames.serverList);
      },
    );
  }

  void _initializeShell({bool notify = false}) {
    if (_shellReady) {
      return;
    }

    _runtimeSessionRecoveryService =
        serviceLocator.runtimeSessionRecoveryService;
    _serverAvailabilityController = serviceLocator.serverAvailabilityController;
    _unifiedNodeStore = serviceLocator.unifiedNodeStore;
    _unifiedNodeStore!.applyServerAvailabilityStatus(
      _serverAvailabilityController!.currentStatus,
    );
    _nodeStoreSubscription = _unifiedNodeStore!.stream.listen((_) {
      _schedulePeerIdentityCachePersist();
    });
    unawaited(_hydrateTrustedServers());
    _dashboardCubit =
        widget.dashboardCubit ??
        DashboardCubit(
          loadDashboardUseCase: serviceLocator.loadDashboardUseCase,
          unifiedNodeStore: _unifiedNodeStore!,
        );
    _backupCubit = widget.backupCubit ?? serviceLocator.backupCubit;
    _transferCubit = widget.transferCubit ?? serviceLocator.transferCubit;
    _relayCubit = RelayCubit(
      relayRepository: serviceLocator.relayRepository,
      deviceFileService: serviceLocator.deviceFileService,
      unifiedNodeStore: _unifiedNodeStore!,
      relayPreviewCache: serviceLocator.relayPreviewCache,
      userProfileStore: serviceLocator.userProfileStore,
      relayUnreadStore: serviceLocator.relayUnreadStore,
      deviceProfileSyncService: serviceLocator.deviceProfileSyncService,
    );
    _fileBrowserCubit =
        widget.fileBrowserCubit ??
        FileBrowserCubit(
          listDirectoryUseCase: serviceLocator.listDirectoryUseCase,
          createFolderUseCase: serviceLocator.createFolderUseCase,
          deleteFileUseCase: serviceLocator.deleteFileUseCase,
          batchDeleteUseCase: serviceLocator.batchDeleteUseCase,
          loadVisibleThumbnailsUseCase:
              serviceLocator.loadVisibleThumbnailsUseCase,
          getCachedThumbnailUseCase: serviceLocator.getCachedThumbnailUseCase,
          switchFileRootUseCase: serviceLocator.switchFileRootUseCase,
          isRootWritableUseCase: serviceLocator.isRootWritableUseCase,
        );
    _realtimeSessionService = RealtimeSessionService(
      currentSession: serviceLocator.currentSession,
      deviceIdProvider: serviceLocator.clientIdentityService.getDeviceId,
      deviceNameProvider: serviceLocator.clientIdentityService.getDeviceName,
      presenceLabelProvider: () async =>
          serviceLocator.deviceIdentityService.resolvePresenceLabel(),
      avatarUpdatedAtProvider: () async {
        final updatedAt = serviceLocator.userProfileStore.avatarUpdatedAt;
        return updatedAt?.toUtc().toIso8601String();
      },
      clientPlatformProvider:
          serviceLocator.clientIdentityService.getDeviceType,
      clientBrandProvider: serviceLocator.clientIdentityService.getDeviceBrand,
      clientModelProvider: serviceLocator.clientIdentityService.getDeviceModel,
      clientAppVersionProvider: () async => RuntimeBuildInfo.appVersion,
      clientRouteIpProvider:
          serviceLocator.clientRouteIpService.resolveRouteIpForBaseUrl,
      websocketHttpClientFactory: (url) {
        return serviceLocator.trustedServerHttpClientFactory.createHttpClient(
          baseUrl: url,
        );
      },
      sessionRecoveryHandler: _runtimeSessionRecoveryService!.recoverSession,
      serverAvailabilityController: _serverAvailabilityController,
      onSessionRecovered: _handleSessionRecovered,
    );
    serviceLocator.deviceIdentityService.bindRealtimeHelloRefresher(
      () => _realtimeSessionService!.refreshHello(),
    );

    _dashboardCubit!.applyRealtimeConnectionStatus(
      _realtimeSessionService!.currentStatus,
    );
    _dashboardCubit!.applyServerAvailabilityStatus(
      _serverAvailabilityController!.currentStatus,
    );
    _currentServerAvailabilityStatus =
        _serverAvailabilityController!.currentStatus;

    _realtimeStatusSubscription = _realtimeSessionService!.statusStream.listen((
      status,
    ) {
      _dashboardCubit!.applyRealtimeConnectionStatus(status);
      if (status == RealtimeConnectionStatus.connected) {
        unawaited(_syncDeviceRosterFromServer());
      }
    });
    _serverAvailabilitySubscription = _serverAvailabilityController!
        .statusStream
        .listen(_handleServerAvailabilityChanged);
    _dashboardStateSubscription = _dashboardCubit!.stream.listen((state) {
      if (state is DashboardLoaded) {
        _dashboardLoaded = true;
      }
      if (state is! DashboardLoaded) {
        return;
      }
      _unifiedNodeStore?.applyCurrentServerRuntime(
        serverLanIp: state.localIp,
        serverStatus: state.serverStatus,
        brand: state.deviceBrand,
        model: state.deviceModel,
        storageTotal: state.storageTotal,
        storageUsed: state.storageUsed,
        storageAvailable: state.storageAvailable,
        batteryLevel: state.batteryLevel,
        batteryPercent: state.batteryPercent,
        isCharging: state.isCharging,
      );
    });
    _realtimeSessionService!.setDashboardListener(
      _dashboardCubit!.applyRealtimeDashboardPayload,
    );
    _realtimeSessionService!.setPresenceListener((
      clients, {
      enrolledDeviceIds,
    }) {
      final previousEnrolled = _unifiedNodeStore!.enrolledDeviceIds;
      _unifiedNodeStore!.applyPresenceSnapshot(
        clients,
        enrolledDeviceIds: enrolledDeviceIds,
      );
      if (enrolledDeviceIds != null &&
          !_sameStringSet(previousEnrolled, enrolledDeviceIds) &&
          !_sameStringSet(_lastSyncedEnrolledDeviceIds, enrolledDeviceIds)) {
        unawaited(_syncDeviceRosterFromServer());
      }
    });
    _realtimeSessionService!.setTransferListener(_handleTransferEvent);
    _realtimeSessionService!.setRelaySnapshotListener(
      _relayCubit!.ingestSnapshotTransferMaps,
    );
    unawaited(_primeLocalClientNodeIdentity());

    _shellReady = true;
    _scheduleDeferredStartup();

    if (notify && mounted) {
      setState(() {});
    }
  }

  Future<void> _syncDeviceRosterFromServer() async {
    try {
      await serviceLocator.deviceProfileSyncService.syncServerRoster();
      _lastSyncedEnrolledDeviceIds = _unifiedNodeStore?.enrolledDeviceIds;
    } catch (_) {
      // Keep the local copy; next connect/change will retry.
    }
  }

  bool _sameStringSet(Set<String>? left, Set<String>? right) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    if (left.length != right.length) {
      return false;
    }
    return left.containsAll(right);
  }

  void _scheduleDeferredStartup() {
    if (_deferredStartupScheduled) {
      return;
    }
    _deferredStartupScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shellReady) {
        return;
      }

      _serverAvailabilityController?.startMonitoring(
        initialStatus: ServerAvailabilityStatus.offline,
        awaitingInitialConnection: true,
      );
      _dashboardCubit?.applyServerAvailabilityStatus(
        _serverAvailabilityController?.currentStatus ??
            ServerAvailabilityStatus.offline,
      );
      unawaited(_realtimeSessionService?.connect());
      unawaited(_scheduleInitialDashboardLoad());
    });
  }

  Future<void> _scheduleInitialDashboardLoad() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted || _dashboardLoaded) {
      return;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_dashboardCubit?.hasLoadedDashboard ?? false) {
        _dashboardLoaded = true;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (!mounted || _dashboardLoaded) {
      return;
    }
    if (_dashboardCubit?.hasLoadedDashboard ?? false) {
      _dashboardLoaded = true;
      return;
    }

    _ensureDashboardLoaded();
  }

  void _ensureDashboardLoaded() {
    if (_dashboardLoaded) {
      return;
    }
    _dashboardLoaded = true;
    unawaited(_dashboardCubit?.loadDashboard());
  }

  void _ensureTransferTasksLoaded() {
    if (_transferTasksLoaded) {
      return;
    }
    _transferTasksLoaded = true;
    unawaited(_transferCubit?.loadTasks());
  }

  void _ensureRelayHistoryLoaded() {
    if (_relayHistoryLoaded) {
      return;
    }
    _relayHistoryLoaded = true;
    unawaited(_relayCubit?.loadHistory());
  }

  Future<void> _handleSessionRecovered() async {
    unawaited(_hydrateTrustedServers());
    unawaited(_primeLocalClientNodeIdentity());
    await _refreshRecoveredViews();
  }

  void _handleServerAvailabilityChanged(ServerAvailabilityStatus status) {
    final previousStatus = _currentServerAvailabilityStatus;
    _currentServerAvailabilityStatus = status;
    _dashboardCubit?.applyServerAvailabilityStatus(status);
    _unifiedNodeStore?.applyServerAvailabilityStatus(status);
    if (previousStatus == ServerAvailabilityStatus.offline &&
        status == ServerAvailabilityStatus.online) {
      unawaited(_refreshRecoveredViews());
    }
  }

  Future<void> _primeLocalClientNodeIdentity() async {
    final nodeStore = _unifiedNodeStore;
    if (nodeStore == null) {
      return;
    }
    final identityService = serviceLocator.clientIdentityService;
    final sessionDeviceId = serviceLocator.currentSession.deviceId?.trim();
    final deviceId =
        sessionDeviceId != null && sessionDeviceId.isNotEmpty
            ? sessionDeviceId
            : await identityService.getDeviceId();
    final deviceDetails = await identityService.getDeviceDetails();
    nodeStore.applyLocalClientIdentity(
      deviceId: deviceId,
      deviceName: deviceDetails.name,
      platform: deviceDetails.type,
      brand: deviceDetails.brand,
      model: deviceDetails.model,
      appVersion: RuntimeBuildInfo.appVersion,
      label: serviceLocator.userProfileStore.displayAlias,
    );
    unawaited(serviceLocator.deviceIdentityService.syncFromServer());
  }

  Future<void> _hydrateTrustedServers() async {
    final nodeStore = _unifiedNodeStore;
    if (nodeStore == null) {
      return;
    }
    final records = await serviceLocator.trustedServerStore.listRecords();
    nodeStore.applyTrustedServers(records);
  }

  Future<void> _refreshRecoveredViews() async {
    if (!mounted || !_shellReady) {
      return;
    }

    if (_dashboardLoaded) {
      await _dashboardCubit?.loadDashboard(force: true);
    }
    if (!mounted) {
      return;
    }

    final fileBrowserCubit = _fileBrowserCubit;
    final fileState = fileBrowserCubit?.state;
    if (fileState is FileBrowserLoaded) {
      if (!(fileBrowserCubit?.canSkipDirectoryRefreshOnReconnect() ?? false)) {
        await fileBrowserCubit?.refreshDirectoryEntries(fileState.currentPath);
      }
    } else if (_fileBrowserLoaded) {
      await fileBrowserCubit?.loadRoot();
    }

    if (!mounted) {
      return;
    }

    if (_relayHistoryLoaded) {
      await _relayCubit?.refreshHistory();
    }
  }

  Future<void> _retryOfflineAccess() async {
    await _realtimeSessionService?.reconnectNow();
  }

  void _onBackPressed(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出应用'),
        content: const Text('确定要退出应用吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              if (Platform.isAndroid) {
                SystemNavigator.pop();
                return;
              }
              exit(0);
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  void _schedulePeerIdentityCachePersist() {
    _peerIdentityPersistTimer?.cancel();
    _peerIdentityPersistTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistPeerIdentityCache());
    });
  }

  Future<void> _persistPeerIdentityCache() async {
    final nodeStore = _unifiedNodeStore;
    if (nodeStore == null) {
      return;
    }
    await serviceLocator.keyValueStore.savePeerNodes(
      nodeStore.peerIdentityCacheEntries,
    );
  }

  void _onSelectTab(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (!_shellReady) {
      return;
    }

    if (index == 0) {
      _ensureDashboardLoaded();
      return;
    }

    if (index == 1) {
      _ensureTransferTasksLoaded();
      if (!_fileBrowserLoaded) {
        _fileBrowserLoaded = true;
        unawaited(_fileBrowserCubit?.loadRoot());
      }
      return;
    }

    if (index == 2) {
      _ensureRelayHistoryLoaded();
    }
  }

  void _handleTransferEvent(String type, Map<String, dynamic> payload) {
    final relayCubit = _relayCubit;
    if (relayCubit == null) {
      return;
    }

    relayCubit.applyTransferEvent(type, payload);
    if (type != 'transfer.created' && type != 'transfer.ready') {
      return;
    }
    if (!mounted) {
      return;
    }

    final selfClientId = relayCubit.currentClientId;
    if (selfClientId == null) {
      return;
    }

    final rawTransfer = payload['transfer'];
    if (rawTransfer is! Map) {
      return;
    }

    final senderClientId = rawTransfer['senderClientId']?.toString().trim();
    if (senderClientId == null || senderClientId.isEmpty) {
      return;
    }

    final targets = rawTransfer['targets'];
    final isReceiver = targets is List &&
        targets.any((target) {
          if (target is! Map) {
            return false;
          }
          return target['receiverClientId']?.toString().trim() == selfClientId;
        });
    if (!isReceiver) {
      return;
    }

    if (_selectedIndex == 2 &&
        relayCubit.state.activePeerClientId == senderClientId) {
      return;
    }

    final now = DateTime.now();
    if (_lastIncomingRelaySnackAt != null &&
        now.difference(_lastIncomingRelaySnackAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastIncomingRelaySnackAt = now;

    final senderLabel =
        rawTransfer['senderLabel']?.toString().trim() ??
        relayCubit.peerById(senderClientId)?.publicDisplayName ??
        senderClientId;
    final fileName = rawTransfer['fileName']?.toString().trim();
    final message = fileName == null || fileName.isEmpty
        ? '收到来自 $senderLabel 的文件'
        : '收到来自 $senderLabel 的文件：$fileName';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_shellReady) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider<DashboardCubit>.value(value: _dashboardCubit!),
        BlocProvider<FileBrowserCubit>.value(value: _fileBrowserCubit!),
        BlocProvider<BackupCubit>.value(value: _backupCubit!),
        BlocProvider<TransferCubit>.value(value: _transferCubit!),
        BlocProvider<RelayCubit>.value(value: _relayCubit!),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<TransferCubit, TransferState>(
            listener: (context, state) {
              if (state is TransferLoaded) {
                _backupCubit?.syncTrackedTasks(state.tasks);
              }
            },
          ),
        ],
        child: RepositoryProvider<RealtimeSessionService>.value(
          value: _realtimeSessionService!,
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              _onBackPressed(context);
            },
            child: Stack(
              children: [
                Scaffold(
                  extendBody: true,
                  body: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      const DashboardPage(),
                      const FileBrowserPage(bottomPadding: 126),
                      const RelayPage(),
                      const SettingsPage(),
                    ],
                  ),
                  bottomNavigationBar: BlocBuilder<RelayCubit, RelayState>(
                    builder: (context, relayState) {
                      return _BottomNavigationBar(
                        selectedIndex: _selectedIndex,
                        deviceTabUnread: relayState.totalUnread,
                        onSelect: _onSelectTab,
                      );
                    },
                  ),
                ),
                OfflineResourceGate(
                  controller: _serverAvailabilityController!,
                  onReconnect: _retryOfflineAccess,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final int deviceTabUnread;
  final ValueChanged<int> onSelect;

  const _BottomNavigationBar({
    required this.selectedIndex,
    required this.deviceTabUnread,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavigationItem(
            icon: Icons.dns_outlined,
            label: '概览',
            selected: selectedIndex == 0,
            onTap: () => onSelect(0),
          ),
          _NavigationItem(
            icon: Icons.inventory_2_outlined,
            label: '文件',
            selected: selectedIndex == 1,
            onTap: () => onSelect(1),
          ),
          _NavigationItem(
            icon: Icons.devices_outlined,
            label: '设备',
            selected: selectedIndex == 2,
            badgeCount: deviceTabUnread,
            onTap: () => onSelect(2),
          ),
          _NavigationItem(
            icon: Icons.settings_outlined,
            label: '设置',
            selected: selectedIndex == 3,
            onTap: () => onSelect(3),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.badgeCount = 0,
    required this.onTap,
  });

  String get _badgeLabel {
    if (badgeCount <= 0) {
      return '';
    }
    if (badgeCount > 99) {
      return '99+';
    }
    return '$badgeCount';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.textTheme.bodySmall?.color ?? const Color(0xFF9C9B99);
    final iconWidget = Icon(icon, color: color, size: 23);
    final badgeLabel = _badgeLabel;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            badgeLabel.isEmpty
                ? iconWidget
                : Badge(
                    label: Text(badgeLabel),
                    isLabelVisible: true,
                    child: iconWidget,
                  ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
