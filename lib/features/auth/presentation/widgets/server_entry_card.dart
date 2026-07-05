/// 文件输入：服务器名称、说明文案、点击事件
/// 文件职责：显示服务器条目卡片，供服务器列表与搜索结果复用
/// 文件对外接口：ServerEntryCard
/// 文件包含：ServerEntryCard
import 'package:flutter/material.dart';

class ServerEntryCard extends StatelessWidget {
  final String title;
  final String primaryText;
  final String? secondaryText;
  final VoidCallback? onTap;
  final bool highlighted;
  final IconData? leadingIcon;
  final String? statusLabel;
  final bool? isOnline;
  final bool isAutoLoggingIn;
  final int? badgeCount;

  const ServerEntryCard({
    super.key,
    required this.title,
    required this.primaryText,
    this.secondaryText,
    this.onTap,
    this.highlighted = false,
    this.leadingIcon,
    this.statusLabel,
    this.isOnline,
    this.isAutoLoggingIn = false,
    this.badgeCount,
  });

  bool get _isOffline => isOnline == false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveHighlighted = _isOffline ? false : highlighted;
    final titleColor = _isOffline
        ? const Color(0xFF9E9E9E)
        : (highlighted
              ? const Color(0xFF1A1A1A)
              : theme.textTheme.titleMedium?.color ?? Colors.black87);
    final primaryColor = _isOffline
        ? const Color(0xFFB0B0B0)
        : const Color(0xFF6D6C6A);
    final secondaryColor = _isOffline
        ? const Color(0xFFBDBDBD)
        : const Color(0xFF9C9B99);

    final cardBackgroundColor = () {
      if (isOnline == null) {
        return Colors.white;
      }
      if (_isOffline) {
        return const Color(0xFFF0F0F0);
      }
      return const Color(0xFFE8F5E9);
    }();

    final inlineLabels = <Widget>[];
    if (isAutoLoggingIn) {
      inlineLabels.add(const SizedBox(width: 4));
      inlineLabels.add(
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isOffline) {
      inlineLabels.add(const SizedBox(width: 4));
      inlineLabels.add(
        SizedBox(
          width: 58,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '离线',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: const Color(0xFF9E9E9E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final ipRowLabels = <Widget>[];
    if (!isAutoLoggingIn && statusLabel != null && statusLabel!.isNotEmpty) {
      ipRowLabels.add(const SizedBox(width: 4));
      ipRowLabels.add(
        SizedBox(
          width: 58,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: effectiveHighlighted
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLabel!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final unreadCount = badgeCount ?? 0;
    if (unreadCount > 0) {
      inlineLabels.add(const SizedBox(width: 6));
      inlineLabels.add(
        Badge(
          label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
          isLabelVisible: true,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF3D8A5A), width: 1.5),
      ),
      child: Material(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 18, 18, 18),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: effectiveHighlighted
                          ? Colors.white.withValues(alpha: 0.72)
                          : (_isOffline
                                ? const Color(0xFFE0E0E0)
                                : theme.colorScheme.secondary),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      leadingIcon,
                      color: _isOffline
                          ? const Color(0xFFBDBDBD)
                          : theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...inlineLabels,
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              primaryText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 15,
                                color: primaryColor,
                              ),
                            ),
                          ),
                          ...ipRowLabels,
                        ],
                      ),
                      if (secondaryText != null &&
                          secondaryText!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          secondaryText!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: secondaryColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
