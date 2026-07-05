import 'package:flutter/material.dart';

import '../../domain/entities/file_entry_entity.dart';

class NonPreviewFileIconStyle {
  final Color backgroundColor;
  final Color iconColor;
  final IconData iconData;

  const NonPreviewFileIconStyle({
    required this.backgroundColor,
    required this.iconColor,
    required this.iconData,
  });
}

NonPreviewFileIconStyle resolveNonPreviewFileIconStyle(FileEntryEntity file) {
  switch (file.extension.toLowerCase()) {
    // PDF
    case 'pdf':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF4ECE7),
        iconColor: Color(0xFFB5664C),
        iconData: Icons.picture_as_pdf,
      );
    // Word
    case 'doc':
    case 'docx':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF4ECE7),
        iconColor: Color(0xFFB5664C),
        iconData: Icons.article,
      );
    // Excel / CSV
    case 'xls':
    case 'xlsx':
    case 'csv':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF4ECE7),
        iconColor: Color(0xFFB5664C),
        iconData: Icons.grid_on,
      );
    // PowerPoint
    case 'ppt':
    case 'pptx':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF4ECE7),
        iconColor: Color(0xFFB5664C),
        iconData: Icons.slideshow,
      );
    // 音频
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'aac':
    case 'ogg':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.audio_file,
      );
    // 压缩包
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.folder_zip,
      );
    // 文本
    case 'txt':
    case 'md':
    case 'log':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.text_snippet,
      );
    // 代码
    case 'dart':
    case 'js':
    case 'ts':
    case 'jsx':
    case 'tsx':
    case 'py':
    case 'java':
    case 'kt':
    case 'swift':
    case 'c':
    case 'cpp':
    case 'h':
    case 'go':
    case 'rs':
    case 'rb':
    case 'php':
    case 'html':
    case 'css':
    case 'json':
    case 'xml':
    case 'yaml':
    case 'yml':
    case 'sh':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.code,
      );
    // 可执行文件
    case 'apk':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.android,
      );
    case 'exe':
    case 'msi':
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.terminal,
      );
    default:
      return const NonPreviewFileIconStyle(
        backgroundColor: Color(0xFFF2F1EE),
        iconColor: Color(0xFF7C7974),
        iconData: Icons.insert_drive_file,
      );
  }
}

String formatNonPreviewFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class NonPreviewFileIconPlaceholder extends StatelessWidget {
  final NonPreviewFileIconStyle style;
  final double? progress;
  final bool showProgressRing;

  const NonPreviewFileIconPlaceholder({
    super.key,
    required this.style,
    this.progress,
    this.showProgressRing = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: style.backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Icon(style.iconData, size: 32, color: style.iconColor),
    );

    if (!showProgressRing) {
      return icon;
    }

    final clampedProgress = (progress ?? 0).clamp(0.0, 1.0);

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: clampedProgress,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              backgroundColor: const Color(0xFFE8E6E1),
              color: const Color(0xFF3D8A5A),
            ),
          ),
          icon,
        ],
      ),
    );
  }
}
