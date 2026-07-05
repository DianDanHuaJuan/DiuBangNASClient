import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../core/node/device_display_extensions.dart';
import '../../../../core/node/unified_node.dart';
import '../../../transfer/presentation/cubit/transfer_cubit.dart';
import '../cubit/relay_cubit.dart';
import '../cubit/relay_state.dart';
import '../utils/relay_peer_primary_text.dart';
import '../widgets/relay_record_list.dart';
import 'device_chat_page.dart';
import 'server_transfer_chat_page.dart';

class RelayPage extends StatelessWidget {
  const RelayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final relayCubit = context.read<RelayCubit>();
    final nodeStore = serviceLocator.unifiedNodeStore;
    return SafeArea(
      child: BlocBuilder<RelayCubit, RelayState>(
        builder: (context, state) {
          final currentClientId = relayCubit.currentClientId;
          final peers = relayCubit.peers;
          final serverNode = nodeStore.currentServer;
          final serverIp = _resolveServerIp(serverNode);
          final observedRemoteIpUsage = buildRelayPeerObservedRemoteIpUsage(
            peers,
          );
          final reportedRouteIpUsage = buildRelayPeerReportedRouteIpUsage(
            peers,
          );
          final summaries = <RelayDeviceSummary>[
            _buildServerSummary(serverNode: serverNode),
            ...peers.map((peer) {
              final peerClientId = peer.identity.clientId ?? peer.nodeId;
              final unreadCount = state.unreadForPeer(peerClientId);
              final secondaryText = _buildClientSecondaryText(
                peer: peer,
                state: state,
                currentClientId: currentClientId,
                unreadCount: unreadCount,
              );
              return RelayDeviceSummary(
                clientId: peerClientId,
                name: peer.publicDisplayName,
                primaryText: buildRelayPeerPrimaryText(
                  peer,
                  serverIp: serverIp,
                  observedRemoteIpUsage: observedRemoteIpUsage,
                  reportedRouteIpUsage: reportedRouteIpUsage,
                ),
                secondaryText: secondaryText,
                online: peer.presence.status == PresenceStatus.online,
                tagLabel: '客户端',
                leadingIcon: _clientPlatformIcon(peer),
                unreadCount: unreadCount,
              );
            }),
          ];

          return RefreshIndicator(
            onRefresh: relayCubit.refreshHistory,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 112),
              children: [
                Text(
                  '伙伴设备',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 24),
                if (!relayCubit.hasRelayConfiguration)
                  const _RelayNoticeCard(
                    icon: Icons.info_outline_rounded,
                    title: '当前服务器未声明 Relay 能力',
                    message: '请先用已实现 Relay API 的 NASServer 版本登录，再进入联调。',
                    backgroundColor: Color(0xFFFFF5E5),
                    foregroundColor: Color(0xFF8A5A00),
                  )
                else if (!relayCubit.isRelayEnabled)
                  const _RelayNoticeCard(
                    icon: Icons.science_outlined,
                    title: 'Relay 仍处于联调阶段',
                    message: '服务端当前仍将 relay.enabled 标记为 false，这里保留调试入口，方便直接联调。',
                    backgroundColor: Color(0xFFEAF2FF),
                    foregroundColor: Color(0xFF375B9E),
                  ),
                if (state.errorMessage != null &&
                    state.errorMessage!.trim().isNotEmpty)
                  _RelayNoticeCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Relay 历史加载失败',
                    message: state.errorMessage!,
                    backgroundColor: const Color(0xFFFFE9E9),
                    foregroundColor: const Color(0xFFB64848),
                  ),
                RelayRecordList(
                  devices: summaries,
                  onTap: (device) {
                    if (device.isServer) {
                      final transferCubit = context.read<TransferCubit>();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BlocProvider<TransferCubit>.value(
                            value: transferCubit,
                            child: const ServerTransferChatPage(),
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BlocProvider.value(
                          value: relayCubit,
                          child: DeviceChatPage(peerClientId: device.clientId),
                        ),
                      ),
                    );
                  },
                ),
                if (state.isLoading &&
                    !relayCubit.hasPeers &&
                    !state.hasTransfers)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  RelayDeviceSummary _buildServerSummary({required UnifiedNode? serverNode}) {
    final serverName = serverNode?.identity.displayName ?? '当前服务器';
    final serverVersion = serverNode?.server?.serverVersion;
    final serverPlatform = serverNode?.identity.platform;
    final serverAddress =
        serverNode?.network.serverLanIp ??
        _hostDisplay(serverNode?.network.connectBaseUrl);
    final isOnline = serverNode?.presence.status == PresenceStatus.online;
    return RelayDeviceSummary(
      clientId:
          serverNode?.identity.serverId ?? serverNode?.nodeId ?? '_server',
      name: serverName,
      primaryText: 'IP: ${serverAddress.isEmpty ? '未知' : serverAddress}',
      secondaryText: _joinNonEmpty(<String?>[
        isOnline ? '当前连接服务器' : '当前服务器离线',
        serverPlatform,
        serverVersion,
      ]),
      online: isOnline,
      isServer: true,
      tagLabel: '服务器',
      leadingIcon: _platformIcon(serverPlatform) ?? Icons.dns_outlined,
      isInteractive: false,
    );
  }

  String _buildClientSecondaryText({
    required UnifiedNode peer,
    required RelayState state,
    required String? currentClientId,
    required int unreadCount,
  }) {
    final lastActivity = peer.presence.lastSeenAt ?? peer.meta.updatedAt;
    final base = '上次连接：${_formatTimestamp(lastActivity)}';
    if (unreadCount <= 0) {
      return base;
    }
    return '$base · $unreadCount 条新文件';
  }

  String? _resolveServerIp(UnifiedNode? serverNode) {
    final serverLanIp = serverNode?.network.serverLanIp?.trim() ?? '';
    if (serverLanIp.isNotEmpty) {
      return serverLanIp;
    }
    final host = _hostDisplay(serverNode?.network.connectBaseUrl);
    return host.isEmpty ? null : host;
  }

  String _hostDisplay(String? url) {
    if (url == null || url.trim().isEmpty) {
      return '';
    }
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        return url;
      }
      if (uri.hasPort) {
        return '${uri.host}:${uri.port}';
      }
      return uri.host;
    } catch (_) {
      return url;
    }
  }

  IconData? _platformIcon(String? platform) {
    switch (_normalizedPlatform(platform)) {
      case 'android':
        return Icons.android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.window_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.computer_rounded;
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

  IconData _clientPlatformIcon(UnifiedNode peer) {
    return _platformIcon(peer.identity.platform) ?? Icons.devices_rounded;
  }

  String _joinNonEmpty(List<String?> values) {
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');
  }
}

class _RelayNoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;

  const _RelayNoticeCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foregroundColor,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  final yy = (local.year % 100).toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$yy/$month/$day $hour:$minute';
}
