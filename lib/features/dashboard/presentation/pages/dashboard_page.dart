/// 文件输入：DashboardCubit 状态
/// 文件职责：显示设备概览页面，按照 ClientUI07.pen 设计稿实现
/// 文件对外接口：DashboardPage
/// 文件包含：DashboardPage
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/service_locator.dart';
import '../../../../app/router/route_names.dart';
import '../../../../core/realtime/realtime_connection_state.dart';
import '../../../../core/realtime/realtime_session_service.dart';
import '../cubit/dashboard_cubit.dart';
import '../cubit/dashboard_state.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentServer = serviceLocator.unifiedNodeStore.currentServer;
    final queryParameters = <String, String>{
      if ((currentServer?.network.connectBaseUrl ?? '').isNotEmpty)
        'serverUrl': currentServer!.network.connectBaseUrl!,
      if ((currentServer?.identity.displayName ?? '').isNotEmpty)
        'serverName': currentServer!.identity.displayName,
    };
    final loginLocation = Uri(
      path: RouteNames.login,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 150,
        leading: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go(loginLocation),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 24,
                  color: Color(0xFF6D6C6A),
                ),
                const SizedBox(width: 2),
                Text(
                  '返回登录页',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6D6C6A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          if (state is DashboardLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is DashboardError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 54,
                      color: Color(0xFFB64848),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '设备概览加载失败',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: () =>
                          context.read<DashboardCubit>().loadDashboard(force: true),
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state is DashboardLoaded) {
            final realtimeService = context.read<RealtimeSessionService>();
            return RefreshIndicator(
              onRefresh: () => context.read<DashboardCubit>().loadDashboard(force: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusBadge(
                          label: _realtimeStatusLabel(
                            state.realtimeConnectionStatus,
                            serverName: serviceLocator
                                .unifiedNodeStore
                                .currentServer
                                ?.identity
                                .displayName,
                          ),
                          color: _realtimeStatusColor(
                            state.realtimeConnectionStatus,
                          ),
                        ),
                        if (state.canManualReconnect || state.isConnecting)
                          OutlinedButton.icon(
                            onPressed: state.isConnecting
                                ? null
                                : () async {
                                    await realtimeService.reconnectNow();
                                    if (!context.mounted) return;
                                    if (!realtimeService.isConnected) {
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          const SnackBar(
                                            content: Text('连接服务器失败，请检查网络或服务器状态'),
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                    }
                                  },
                            icon: state.isConnecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: Text(
                              state.isConnecting
                                  ? '正在连接...'
                                  : state.realtimeConnectionStatus ==
                                          RealtimeConnectionStatus.reconnecting
                                      ? '立即重试'
                                      : '重新连接',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _DeviceInfoCard(
                      serverName: state.serverName,
                      brand: state.deviceBrand,
                      model: state.deviceModel,
                      batteryPercent: state.batteryPercent,
                      isCharging: state.isCharging,
                      localIp: state.localIp,
                    ),
                    const SizedBox(height: 16),
                    _StorageStatusCard(
                      totalBytes: state.storageTotal,
                      usedBytes: state.storageUsed,
                      availableBytes: state.storageAvailable,
                    ),
                  ],
                ),
              ),
            );
          }
          return Center(
            child: TextButton(
              onPressed: () => context.read<DashboardCubit>().loadDashboard(force: true),
              child: const Text('加载设备概览'),
            ),
          );
        },
      ),
    );
  }
}

String _realtimeStatusLabel(
  RealtimeConnectionStatus status, {
  String? serverName,
}) {
  switch (status) {
    case RealtimeConnectionStatus.connected:
      final prefix = serverName != null && serverName.isNotEmpty
          ? serverName
          : '实时';
      return '$prefix已连接';
    case RealtimeConnectionStatus.connecting:
      return '实时连接中';
    case RealtimeConnectionStatus.reconnecting:
      return '实时重连中';
    case RealtimeConnectionStatus.disconnected:
      return '实时已断开';
    case RealtimeConnectionStatus.idle:
      return '实时待启动';
  }
}

Color _realtimeStatusColor(RealtimeConnectionStatus status) {
  switch (status) {
    case RealtimeConnectionStatus.connected:
      return const Color(0xFF3D8A5A);
    case RealtimeConnectionStatus.connecting:
    case RealtimeConnectionStatus.reconnecting:
      return const Color(0xFFD08A31);
    case RealtimeConnectionStatus.disconnected:
      return const Color(0xFFB64848);
    case RealtimeConnectionStatus.idle:
      return const Color(0xFF8B867C);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final String serverName;
  final String brand;
  final String model;
  final double batteryPercent;
  final bool isCharging;
  final String localIp;

  const _DeviceInfoCard({
    required this.serverName,
    required this.brand,
    required this.model,
    required this.batteryPercent,
    required this.isCharging,
    required this.localIp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4F1),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0A000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设备信息',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.dns_outlined,
            label: '服务器名称',
            value: serverName.isNotEmpty ? serverName : '未知',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.branding_watermark_outlined,
            label: '品牌',
            value: brand.isNotEmpty ? brand : '未知',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.phone_android_outlined,
            label: '型号',
            value: model.isNotEmpty ? model : '未知',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.battery_std_outlined,
            label: '电量',
            value: '${batteryPercent.toStringAsFixed(0)}%',
            valueColor: batteryPercent < 20
                ? const Color(0xFFB64848)
                : batteryPercent < 50
                ? const Color(0xFFE8A838)
                : const Color(0xFF3D8A5A),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.power_outlined,
            label: '充电状态',
            value: isCharging ? '充电中' : '未充电',
            valueColor: isCharging
                ? const Color(0xFF3D8A5A)
                : const Color(0xFF8B867C),
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.wifi_outlined,
            label: '局域网IP',
            value: localIp.isNotEmpty ? localIp : '未知',
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF8B867C)),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            color: const Color(0xFF8B867C),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor ?? const Color(0xFF1A1918),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _StorageStatusCard extends StatelessWidget {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;

  const _StorageStatusCard({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
  });

  double get usedPercentage => totalBytes > 0 ? usedBytes / totalBytes : 0;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F4F1),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0A000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '存储状态',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _CircularProgressPainter(
                    progress: usedPercentage,
                    color: const Color(0xFF3D8A5A),
                    backgroundColor: const Color(0xFFE8F3EB),
                  ),
                  child: Center(
                    child: Text(
                      '${(usedPercentage * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D8A5A),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(
                      color: const Color(0xFF3D8A5A),
                      label: '已使用',
                      value: _formatBytes(usedBytes),
                    ),
                    const SizedBox(height: 12),
                    _LegendItem(
                      color: const Color(0xFFE8F3EB),
                      label: '可用空间',
                      value: _formatBytes(availableBytes),
                    ),
                    const SizedBox(height: 12),
                    _LegendItem(
                      color: const Color(0xFF8B867C),
                      label: '总容量',
                      value: _formatBytes(totalBytes),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 13,
            color: const Color(0xFF8B867C),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF1A1918),
          ),
        ),
      ],
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final strokeWidth = 10.0;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, backgroundPaint);

    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
