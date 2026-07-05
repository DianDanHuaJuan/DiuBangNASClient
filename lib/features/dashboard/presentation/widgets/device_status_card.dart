/// 文件输入：设备名称、型号、状态、运行时长
/// 文件职责：显示 NAS 设备状态卡片
/// 文件对外接口：DeviceStatusCard
/// 文件包含：DeviceStatusCard
import 'package:flutter/material.dart';

class DeviceStatusCard extends StatelessWidget {
  final String deviceName;
  final String model;
  final String status;
  final String uptime;

  const DeviceStatusCard({
    super.key,
    required this.deviceName,
    required this.model,
    required this.status,
    required this.uptime,
  });

  Color _getStatusColor() {
    switch (status.toLowerCase()) {
      case 'online':
      case 'running':
        return const Color(0xFF3D8A5A);
      case 'offline':
        return const Color(0xFFB64848);
      case 'warning':
        return const Color(0xFFD08A31);
      default:
        return const Color(0xFF8B867C);
    }
  }

  String _localizeStatus() {
    switch (status.toLowerCase()) {
      case 'online':
      case 'running':
        return '在线';
      case 'offline':
        return '离线';
      case 'warning':
        return '告警';
      default:
        return status.isEmpty ? '未知' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.dns_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName.isEmpty ? 'NAS 设备' : deviceName,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.isEmpty ? '未知型号' : model,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: const Color(0xFF6D6C6A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _localizeStatus(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: '运行时长',
                  value: uptime.isEmpty ? '--' : uptime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  label: '状态',
                  value: _localizeStatus(),
                  valueColor: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoTile({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
