/// 文件输入：文件类型、文件数据
/// 文件职责：通过 MethodChannel 将媒体文件保存到系统公共目录
/// 文件对外接口：MediaStorageService
/// 文件包含：MediaStorageService
import 'package:flutter/services.dart';

enum MediaFileType { image, video, document }

class MediaStorageService {
  static const _channel = MethodChannel('com.nasclient/media_storage');

  static const int memoryThresholdBytes = 100 * 1024 * 1024;

  Future<String?> saveToPublicStorage({
    required String fileName,
    required Uint8List data,
    required MediaFileType fileType,
  }) async {
    try {
      final fileTypeString = switch (fileType) {
        MediaFileType.image => 'image',
        MediaFileType.video => 'video',
        MediaFileType.document => 'document',
      };

      final result = await _channel.invokeMethod<String>(
        'saveToPublicStorage',
        {'fileName': fileName, 'data': data, 'fileType': fileTypeString},
      );

      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to save file to public storage: ${e.message}');
    }
  }

  Future<String?> saveFileToPublicStorage({
    required String fileName,
    required String filePath,
    required MediaFileType fileType,
  }) async {
    try {
      final fileTypeString = switch (fileType) {
        MediaFileType.image => 'image',
        MediaFileType.video => 'video',
        MediaFileType.document => 'document',
      };

      final result = await _channel.invokeMethod<String>(
        'saveFileToPublicStorage',
        {
          'fileName': fileName,
          'filePath': filePath,
          'fileType': fileTypeString,
        },
      );

      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to save file to public storage: ${e.message}');
    }
  }

  MediaFileType getFileTypeFromExtension(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    const imageExtensions = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'heic',
      'heif',
      'raw',
      'tiff',
    ];
    const videoExtensions = [
      'mp4',
      'mkv',
      'avi',
      'mov',
      'wmv',
      'webm',
      '3gp',
      'flv',
      'm4v',
    ];

    if (imageExtensions.contains(extension)) {
      return MediaFileType.image;
    } else if (videoExtensions.contains(extension)) {
      return MediaFileType.video;
    } else {
      return MediaFileType.document;
    }
  }

  bool shouldUseMemory(int fileSizeBytes) {
    return fileSizeBytes <= memoryThresholdBytes;
  }

  Future<Uint8List?> readContentUriBytes(String uri) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'readContentUri',
        {'uri': uri},
      );
      return result;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> deleteContentUri(String uri) async {
    try {
      final result = await _channel.invokeMethod<int>(
        'deleteContentUri',
        {'uri': uri},
      );
      return (result ?? 0) > 0;
    } on PlatformException {
      return false;
    }
  }
}
