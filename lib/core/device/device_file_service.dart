/// 文件输入：本地设备文件路径、导入导出流、缓存目录
/// 文件职责：统一处理设备侧文件读写，提供文件选择和流式读写能力
/// 文件对外接口：DeviceFileService
/// 文件包含：DeviceFileService
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DeviceFileService {
  Future<String?> pickFile() async {
    final files = await pickUploadFiles();
    if (files.isEmpty) {
      return null;
    }
    return files.first;
  }

  Future<List<String>?> pickMultipleFiles() async {
    final files = await pickUploadFiles();
    if (files.isEmpty) {
      return null;
    }
    return files;
  }

  Future<List<String>> pickUploadFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      dialogTitle: '选择要上传的资源',
    );
    if (result == null || result.files.isEmpty) {
      return [];
    }
    return result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();
  }

  Future<String?> pickDirectory() async {
    return await FilePicker.platform.getDirectoryPath();
  }

  Future<Stream<List<int>>> readFileAsStream(String path) async {
    final file = File(path);
    return file.openRead();
  }

  Future<Uint8List> readFileAsBytes(String path) async {
    final file = File(path);
    return await file.readAsBytes();
  }

  Future<String> readFileAsString(String path) async {
    final file = File(path);
    return await file.readAsString();
  }

  Future<void> writeFile(String path, Uint8List bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes);
  }

  Future<void> writeFileFromStream(
    String path,
    Stream<List<int>> stream,
  ) async {
    final file = File(path);
    final sink = file.openWrite();
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    await sink.close();
  }

  Future<int> getFileSize(String path) async {
    final file = File(path);
    return await file.length();
  }

  Future<String> getFileName(String path) async {
    return p.basename(path);
  }

  Future<String> getAppCacheDirectory() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  Future<String> getAppDocumentsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<bool> fileExists(String path) async {
    return await File(path).exists();
  }

  Future<bool> directoryExists(String path) async {
    return await Directory(path).exists();
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<List<String>> listFiles(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];
    return await dir.list().map((e) => e.path).toList();
  }

  Future<List<String>> listFilesRecursive(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final results = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        results.add(entity.path);
      }
    }
    results.sort();
    return results;
  }
}
