/// 文件输入：存储总量、已用、可用、服务器名称
/// 文件职责：显示 NAS 存储概览卡片
/// 文件对外接口：StorageOverviewCard
/// 文件包含：StorageOverviewCard
import 'dart:math' as math;
import 'package:flutter/material.dart';

class StorageOverviewCard extends StatelessWidget {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final String title;
  final String subtitle;

  const StorageOverviewCard({
    super.key,
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    this.title = '家庭NAS',
    this.subtitle = '',
  });

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes < 1024 * 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usagePercent = totalBytes > 0 ? usedBytes / totalBytes : 0.0;

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
              Icon(
                Icons.menu_rounded,
                color: theme.textTheme.bodySmall?.color,
                size: 20,
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.sync_outlined,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: CustomPaint(
                  painter: _UsagePiePainter(
                    percent: usagePercent,
                    accentColor: theme.colorScheme.primary,
                    backgroundColor: const Color(0xFFE0DED8),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '家庭NAS' : title,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '已用: ${_formatBytes(usedBytes)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '剩余: ${_formatBytes(availableBytes)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: const Color(0xFF6D6C6A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: usagePercent.clamp(0.0, 1.0),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '总容量 ${_formatBytes(totalBytes)} · 已使用 ${(usagePercent * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _UsagePiePainter extends CustomPainter {
  final double percent;
  final Color accentColor;
  final Color backgroundColor;

  const _UsagePiePainter({
    required this.percent,
    required this.accentColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final safePercent = percent.clamp(0.0, 1.0);

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    final foregroundPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    canvas.drawOval(rect, backgroundPaint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * safePercent,
      true,
      foregroundPaint,
    );
    canvas.drawCircle(
      rect.center,
      size.width * 0.22,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _UsagePiePainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
