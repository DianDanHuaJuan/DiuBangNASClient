/// 文件输入：当前路径、当前顶级目录、导航回调、顶级目录切换回调
/// 文件职责：显示顶级目录切换和路径面包屑导航
/// 文件对外接口：PathBreadcrumb
/// 文件包含：PathBreadcrumb
import 'package:flutter/material.dart';

class PathBreadcrumb extends StatelessWidget {
  final String path;
  final String currentRootId;
  final VoidCallback? onRootTap;
  final Function(String)? onSegmentTap;
  final ValueChanged<String>? onTopDirChanged;
  final bool showRootToggle;

  const PathBreadcrumb({
    super.key,
    required this.path,
    required this.currentRootId,
    this.onRootTap,
    this.onSegmentTap,
    this.onTopDirChanged,
    this.showRootToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    final segments = path == '/'
        ? <String>[]
        : path.split('/').where((segment) => segment.isNotEmpty).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (showRootToggle)
            _TopDirToggle(
              selectedRootId: currentRootId,
              onChanged: onTopDirChanged,
            ),
          if (showRootToggle && segments.isNotEmpty) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 4),
          ],
          for (var i = 0; i < segments.length; i++) ...[
            _BreadcrumbChip(
              label: segments[i],
              highlighted: i == segments.length - 1,
              onTap: onSegmentTap != null
                  ? () => onSegmentTap!(segments[i])
                  : null,
            ),
            if (i < segments.length - 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TopDirToggle extends StatelessWidget {
  final String selectedRootId;
  final ValueChanged<String>? onChanged;

  const _TopDirToggle({required this.selectedRootId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleItem(
            label: '共享',
            isSelected: selectedRootId == 'fs',
            onTap: onChanged != null ? () => onChanged!('fs') : null,
            isFirst: true,
          ),
          _ToggleItem(
            label: '原机',
            isSelected: selectedRootId == 'library',
            onTap: onChanged != null ? () => onChanged!('library') : null,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;

  const _ToggleItem({
    required this.label,
    required this.isSelected,
    this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(16) : Radius.zero,
            right: isLast ? const Radius.circular(16) : Radius.zero,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : const Color(0xFF6D6C6A),
          ),
        ),
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  final String label;
  final bool highlighted;
  final VoidCallback? onTap;

  const _BreadcrumbChip({
    required this.label,
    required this.highlighted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? theme.colorScheme.secondary
              : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: highlighted
              ? null
              : Border.all(color: const Color(0xFFE7E3DA)),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: highlighted
                ? theme.colorScheme.primary
                : const Color(0xFF6D6C6A),
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
