/// 文件输入：DeviceFileService、BuildFileBrowserDownloadPathParams
/// 文件职责：为文件浏览器下载生成稳定的本地暂存路径
/// 文件对外接口：BuildFileBrowserDownloadPathUseCase
/// 文件包含：BuildFileBrowserDownloadPathUseCase
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/device/device_file_service.dart';
import '../../../../core/use_case/use_case.dart';
import '../params/build_file_browser_download_path_params.dart';

class BuildFileBrowserDownloadPathUseCase
    implements UseCase<String, BuildFileBrowserDownloadPathParams> {
  final DeviceFileService _deviceFileService;

  BuildFileBrowserDownloadPathUseCase({
    required DeviceFileService deviceFileService,
  }) : _deviceFileService = deviceFileService;

  @override
  Future<String> call(BuildFileBrowserDownloadPathParams params) async {
    final documentsDirectory =
        await _deviceFileService.getAppDocumentsDirectory();
    final downloadsDirectoryPath = p.join(
      documentsDirectory,
      'nasclient_downloads',
    );
    final downloadsDirectory = Directory(downloadsDirectoryPath);
    if (!await downloadsDirectory.exists()) {
      await downloadsDirectory.create(recursive: true);
    }

    final sanitizedFileName = p.basename(
      params.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_'),
    );
    return p.join(downloadsDirectoryPath, sanitizedFileName);
  }
}
