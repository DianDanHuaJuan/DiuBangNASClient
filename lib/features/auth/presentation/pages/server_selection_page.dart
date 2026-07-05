/// 文件输入：路由上下文、ServerSelectionCubit
/// 文件职责：显示服务器选择页面，合并已保存服务器和搜索发现的服务器
/// 文件对外接口：ServerSelectionPage
/// 文件包含：ServerSelectionPage
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/node/unified_node.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/network/nas_network_access_policy.dart';
import '../../../../core/use_case/no_params.dart';
import '../widgets/server_entry_card.dart';
import '../cubit/server_selection_cubit.dart';
import '../cubit/server_selection_state.dart';

class ServerSelectionPage extends StatelessWidget {
  const ServerSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = ServerSelectionCubit(
          discoveryRepository: serviceLocator.serverDiscoveryRepository,
          keyValueStore: serviceLocator.keyValueStore,
          unifiedNodeStore: serviceLocator.unifiedNodeStore,
          trustedServerRecordsLoader:
              serviceLocator.trustedServerStore.listRecords,
        );
        unawaited(
          cubit.loadSavedServers().then((_) => cubit.startScan()),
        );
        return cubit;
      },
      child: BlocListener<ServerSelectionCubit, ServerSelectionState>(
        listenWhen: (previous, current) =>
            previous.scanNoticeVersion != current.scanNoticeVersion &&
            current.scanNoticeMessage != null,
        listener: (context, state) {
          final message = state.scanNoticeMessage;
          if (message == null || message.trim().isEmpty) {
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(SnackBar(content: Text(message)));
        },
        child: const _ServerSelectionView(),
      ),
    );
  }
}

class _ServerSelectionView extends StatelessWidget {
  const _ServerSelectionView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<ServerSelectionCubit, ServerSelectionState>(
      listenWhen: (previous, current) =>
          !previous.hasCompletedScan && current.hasCompletedScan,
      listener: (context, state) {
        unawaited(_tryAutoConnectLastServer(context, state));
      },
      child: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '文件服务器',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 34),
              ),
              const SizedBox(height: 8),
              Text(
                '选择或添加你的服务器',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 14,
                  color: const Color(0xFF6D6C6A),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: BlocBuilder<ServerSelectionCubit, ServerSelectionState>(
                  builder: (context, state) {
                    final allServers = <Widget>[];

                    final savedNodeIds = state.savedServers
                        .map((server) => server.nodeId)
                        .toSet();

                    for (final server in state.savedServers) {
                      final url = server.network.connectBaseUrl ?? '';
                      final isOnline = state.serverOnlineStatus[url];
                      final isAutoLoggingIn = state.autoLoggingInUrl == url;
                      allServers.add(
                        ServerEntryCard(
                          title: server.identity.displayName,
                          primaryText: 'IP: ${_serverPrimaryText(server)}',
                          secondaryText: _formatTimestampWithLabel(
                            server.meta.updatedAt.toIso8601String(),
                          ),
                          statusLabel: '已保存',
                          leadingIcon:
                              _platformIcon(server.identity.platform) ??
                              Icons.dns_outlined,
                          isOnline: isOnline,
                          isAutoLoggingIn: isAutoLoggingIn,
                          onTap: () => _tapSavedServer(
                            context,
                            server: server,
                            isOnline: isOnline,
                          ),
                        ),
                      );
                      allServers.add(const SizedBox(height: 12));
                    }

                    for (final server in state.discoveredServers) {
                      if (savedNodeIds.contains(server.nodeId)) {
                        continue;
                      }
                      final connectBaseUrl =
                          server.network.connectBaseUrl ?? '';
                      allServers.add(
                        ServerEntryCard(
                          title: server.identity.displayName,
                          primaryText: 'IP: ${_serverPrimaryText(server)}',
                          highlighted: true,
                          leadingIcon:
                              _platformIcon(server.identity.platform) ??
                              Icons.dns_outlined,
                          statusLabel: server.server?.isTrusted == true
                              ? '已信任'
                              : '新发现',
                          onTap: () => _openLocation(
                            context,
                            Uri(
                              path: RouteNames.login,
                              queryParameters: {
                                'serverUrl': connectBaseUrl,
                                'serverName': server.identity.displayName,
                                if ((server.identity.serverId ?? '').isNotEmpty)
                                  'serverId': server.identity.serverId!,
                                if ((server.server?.certificateSha256 ?? '')
                                    .isNotEmpty)
                                  'caSha256': server.server!.certificateSha256!,
                              },
                            ).toString(),
                          ),
                        ),
                      );
                      allServers.add(const SizedBox(height: 12));
                    }

                    if (allServers.isEmpty) {
                      if (state.isScanning) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              state.errorMessage != null
                                  ? '搜索失败: ${state.errorMessage}'
                                  : state.hasCompletedScan
                                  ? '未发现任何服务器'
                                  : '暂无保存的服务器',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView(children: allServers);
                  },
                ),
              ),
              const SizedBox(height: 20),
              BlocBuilder<ServerSelectionCubit, ServerSelectionState>(
                builder: (context, state) {
                  return ElevatedButton.icon(
                    onPressed: () {
                      context.read<ServerSelectionCubit>().startScan();
                    },
                    icon: state.isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(state.isScanning ? '扫描中...' : '扫描局域网'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  IconData? _platformIcon(String? platform) {
    switch (_normalizedPlatform(platform)) {
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.desktop_windows_rounded;
      case 'linux':
        return Icons.computer_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      default:
        return null;
    }
  }

  String _normalizedPlatform(String? platform) {
    final normalized = platform?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.contains('android')) {
      return 'android';
    }
    if (normalized == 'ios' ||
        normalized.contains('iphone') ||
        normalized.contains('ipad')) {
      return 'ios';
    }
    if (normalized.contains('windows') || normalized == 'win32') {
      return 'windows';
    }
    if (normalized.contains('mac') || normalized == 'darwin') {
      return 'macos';
    }
    if (normalized.contains('linux')) {
      return 'linux';
    }
    return normalized;
  }

  String _buildLoginLocation({
    required String serverUrl,
    required String serverName,
    String? serverId,
    String? caSha256,
  }) {
    return Uri(
      path: RouteNames.login,
      queryParameters: {
        'serverUrl': serverUrl,
        'serverName': serverName,
        if ((serverId ?? '').isNotEmpty) 'serverId': serverId!,
        if ((caSha256 ?? '').isNotEmpty) 'caSha256': caSha256!,
      },
    ).toString();
  }

  String _formatTimestampWithLabel(String? isoString) {
    final formatted = _formatTimestamp(isoString);
    if (formatted.isEmpty) {
      return '';
    }
    return '上次连接：$formatted';
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) {
      return '';
    }
    final dateTime = DateTime.tryParse(isoString);
    if (dateTime == null) {
      return isoString;
    }
    final y = (dateTime.year % 100).toString().padLeft(2, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $hour:$minute';
  }

  void _openLocation(BuildContext context, String location) {
    unawaited(context.read<ServerSelectionCubit>().stopScan());
    context.go(location);
  }

  Future<void> _tryAutoConnectLastServer(
    BuildContext context,
    ServerSelectionState state,
  ) async {
    final cubit = context.read<ServerSelectionCubit>();
    if (cubit.state.autoLoggingInUrl != null) {
      return;
    }

    final lastUrl =
        serviceLocator.keyValueStore.getLastServerUrl()?.trim() ?? '';
    if (lastUrl.isEmpty) {
      return;
    }

    final normalizedLastUrl = NasNetworkAccessPolicy.normalizeServerUrl(lastUrl);
    UnifiedNode? target;
    for (final server in state.savedServers) {
      final url = server.network.connectBaseUrl?.trim() ?? '';
      if (url.isEmpty) {
        continue;
      }
      if (NasNetworkAccessPolicy.normalizeServerUrl(url) == normalizedLastUrl) {
        target = server;
        break;
      }
    }
    if (target == null) {
      return;
    }

    final serverUrl = target.network.connectBaseUrl ?? '';
    if (state.serverOnlineStatus[serverUrl] != true) {
      return;
    }

    await _tryAutoLoginOrNavigate(context, server: target);
  }

  void _tapSavedServer(
    BuildContext context, {
    required UnifiedNode server,
    required bool? isOnline,
  }) {
    if (isOnline == false) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('当前探测未连通，继续尝试连接')));
    }

    unawaited(_tryAutoLoginOrNavigate(context, server: server));
  }

  Future<void> _tryAutoLoginOrNavigate(
    BuildContext context, {
    required UnifiedNode server,
  }) async {
    final cubit = context.read<ServerSelectionCubit>();
    if (cubit.state.autoLoggingInUrl != null) {
      return;
    }

    final rawUrl = server.network.connectBaseUrl ?? '';
    if (rawUrl.isEmpty) {
      return;
    }
    final name = server.identity.displayName;
    final url = rawUrl;

    cubit.setAutoLoggingIn(url);

    final normalizedUrl = NasNetworkAccessPolicy.normalizeServerUrl(url);
    if (serviceLocator.currentSession.hasSession &&
        serviceLocator.unifiedNodeStore.isCurrentServerNode(server)) {
      await serviceLocator.keyValueStore.saveLastServerUrl(normalizedUrl);
      cubit.setAutoLoggingIn(null);
      if (!context.mounted) {
        return;
      }
      await serviceLocator.setBaseUrl(normalizedUrl);
      _openLocation(context, RouteNames.home);
      return;
    }

    final savedSession = await serviceLocator.authLocalDataSource.loadSession();
    final serverId = server.identity.serverId?.trim() ?? '';
    final hasMatchingSession =
        savedSession != null &&
        savedSession.serverUrl.trim() == normalizedUrl &&
        (serverId.isEmpty || savedSession.serverId.trim() == serverId);
    if (!hasMatchingSession) {
      cubit.setAutoLoggingIn(null);
      _openLocation(
        context,
        _buildLoginLocation(
          serverUrl: url,
          serverName: name,
          serverId: server.identity.serverId,
          caSha256: server.server?.certificateSha256,
        ),
      );
      return;
    }

    try {
      final result = await serviceLocator.restoreSessionUseCase.call(
        const NoParams(),
      );

      cubit.setAutoLoggingIn(null);

      if (!context.mounted) {
        return;
      }

      if (result.isSuccess) {
        await serviceLocator.setBaseUrl(normalizedUrl);
        _openLocation(context, RouteNames.home);
      } else {
        _openLocation(
          context,
          _buildLoginLocation(
            serverUrl: url,
            serverName: name,
            serverId: server.identity.serverId,
            caSha256: server.server?.certificateSha256,
          ),
        );
      }
    } on AppException {
      cubit.setAutoLoggingIn(null);
      if (context.mounted) {
        _openLocation(
          context,
          _buildLoginLocation(
            serverUrl: url,
            serverName: name,
            serverId: server.identity.serverId,
            caSha256: server.server?.certificateSha256,
          ),
        );
      }
    } catch (_) {
      cubit.setAutoLoggingIn(null);
      if (context.mounted) {
        _openLocation(
          context,
          _buildLoginLocation(
            serverUrl: url,
            serverName: name,
            serverId: server.identity.serverId,
            caSha256: server.server?.certificateSha256,
          ),
        );
      }
    }
  }

  String _serverPrimaryText(UnifiedNode server) {
    final serverLanIp = server.network.serverLanIp?.trim() ?? '';
    if (serverLanIp.isNotEmpty) {
      return serverLanIp;
    }
    final url = server.network.connectBaseUrl ?? '';
    if (url.isEmpty) {
      final host = server.network.host ?? '';
      final port = server.network.port;
      if (host.isEmpty) {
        return '未知';
      }
      return port == null ? host : '$host:$port';
    }
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return url;
      if (uri.hasPort) return '${uri.host}:${uri.port}';
      return uri.host;
    } catch (_) {
      return url;
    }
  }
}
