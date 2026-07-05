/// 文件输入：选中的分类、分类切换回调
/// 文件职责：显示文件分类快捷入口（照片/视频/文档/其他）
/// 文件对外接口：FileCategoryFilter
/// 文件包含：FileCategoryFilter
import 'package:flutter/material.dart';
import '../../domain/entities/file_category.dart';

class FileCategoryFilter extends StatelessWidget {
  final FileCategory selectedCategory;
  final ValueChanged<FileCategory> onCategoryChanged;

  const FileCategoryFilter({
    super.key,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: FileCategory.values.map((category) {
        final isSelected = category == selectedCategory;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: category != FileCategory.values.last ? 12 : 0,
            ),
            child: _CategoryChip(
              category: category,
              isSelected: isSelected,
              onTap: () => onCategoryChanged(category),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final FileCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  IconData get _icon {
    switch (category) {
      case FileCategory.photo:
        return Icons.photo_outlined;
      case FileCategory.video:
        return Icons.videocam_outlined;
      case FileCategory.document:
        return Icons.description_outlined;
      case FileCategory.other:
        return Icons.folder_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : const Color(0xFFE0E0E0),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _icon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFF6D6C6A),
              ),
              const SizedBox(height: 4),
              Text(
                category.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : const Color(0xFF6D6C6A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
