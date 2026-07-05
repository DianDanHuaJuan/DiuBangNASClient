/// 文件输入：选中的顶级目录、根目录列表、切换回调
/// 文件职责：切换 /fs 和 /library 两个顶级目录
/// 文件对外接口：TopDirSwitcher
/// 文件包含：TopDirSwitcher
import 'package:flutter/material.dart';

class TopDirSwitcher extends StatelessWidget {
  final String selectedRootId;
  final ValueChanged<String> onRootChanged;

  const TopDirSwitcher({
    super.key,
    required this.selectedRootId,
    required this.onRootChanged,
  });

  static const List<_RootOption> _options = [
    _RootOption(id: 'fs', label: '/fs', name: '共享目录'),
    _RootOption(id: 'library', label: '/library', name: '原机目录'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: _options.map((option) {
          final isSelected = option.id == selectedRootId;
          return Padding(
            padding: EdgeInsets.only(right: option != _options.last ? 8 : 0),
            child: GestureDetector(
              onTap: () => onRootChanged(option.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFFE0E0E0),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${option.label} ${option.name}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF6D6C6A),
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RootOption {
  final String id;
  final String label;
  final String name;

  const _RootOption({
    required this.id,
    required this.label,
    required this.name,
  });
}
