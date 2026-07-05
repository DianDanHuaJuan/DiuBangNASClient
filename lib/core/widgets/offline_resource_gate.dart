import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/service_locator.dart';
import '../../app/router/route_names.dart';
import '../session/server_availability_controller.dart';

class OfflineResourceGate extends StatefulWidget {
  const OfflineResourceGate({
    super.key,
    required this.controller,
    required this.onReconnect,
  });

  final ServerAvailabilityController controller;
  final Future<void> Function() onReconnect;

  @override
  State<OfflineResourceGate> createState() => _OfflineResourceGateState();
}

class _OfflineResourceGateState extends State<OfflineResourceGate> {
  bool _isReconnecting = false;
  String? _errorMessage;

  Future<void> _handleReconnect() async {
    if (_isReconnecting) return;
    setState(() {
      _isReconnecting = true;
      _errorMessage = null;
    });
    try {
      await widget.onReconnect();
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      if (widget.controller.currentStatus != ServerAvailabilityStatus.online) {
        setState(() {
          _isReconnecting = false;
          _errorMessage = '连接服务器失败，请检查网络或服务器状态';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
          _errorMessage = '连接服务器失败，请检查网络或服务器状态';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServerAvailabilityStatus>(
      initialData: widget.controller.currentStatus,
      stream: widget.controller.statusStream,
      builder: (context, snapshot) {
        if (!widget.controller.isMonitoring ||
            !widget.controller.shouldShowOfflineGate) {
          if ((_isReconnecting || _errorMessage != null) && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _isReconnecting = false;
                  _errorMessage = null;
                });
              }
            });
          }
          return const SizedBox.shrink();
        }

        return Positioned.fill(
          child: Material(
            color: const Color(0xD9000000),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              size: 54,
                              color: Color(0xFFB64848),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '服务器当前离线',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '已限制继续访问离线服务器资源。你可以先尝试重新连接，或者返回登录页 / 搜索页。',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFF6D6C6A)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isReconnecting ? null : _handleReconnect,
                                icon: _isReconnecting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                                label: Text(
                                  _isReconnecting ? '正在连接...' : '重新连接',
                                ),
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _errorMessage!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFB64848),
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isReconnecting
                                        ? null
                                        : () => context.go(
                                          _buildLoginLocation(),
                                        ),
                                icon: const Icon(Icons.login_rounded),
                                label: const Text('返回登录页'),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed:
                                  _isReconnecting
                                      ? null
                                      : () =>
                                          context.go(RouteNames.serverList),
                              child: const Text('返回搜索页'),
                            ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildLoginLocation() {
    final currentServer = serviceLocator.unifiedNodeStore.currentServer;
    final queryParameters = <String, String>{
      if ((currentServer?.network.connectBaseUrl ?? '').isNotEmpty)
        'serverUrl': currentServer!.network.connectBaseUrl!,
      if ((currentServer?.identity.displayName ?? '').isNotEmpty)
        'serverName': currentServer!.identity.displayName,
      if ((currentServer?.identity.serverId ?? '').isNotEmpty)
        'serverId': currentServer!.identity.serverId!,
      if ((currentServer?.server?.certificateSha256 ?? '').isNotEmpty)
        'caSha256': currentServer!.server!.certificateSha256!,
    };
    return Uri(
      path: RouteNames.login,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }
}
