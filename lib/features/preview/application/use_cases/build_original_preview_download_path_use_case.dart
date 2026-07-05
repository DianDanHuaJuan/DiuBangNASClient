/// 文件输入：DeviceFileService、BuildOriginalPreviewDownloadPathParams
/// 文件职责：生成预览原图下载的本地缓存路径
/// 文件对外接口：BuildOriginalPreviewDownloadPathUseCase
/// 文件包含：BuildOriginalPreviewDownloadPathUseCase
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/device/device_file_service.dart';
import '../../../../core/use_case/use_case.dart';
import '../params/build_original_preview_download_path_params.dart';

/// 输入：DeviceFileService、BuildOriginalPreviewDownloadPathParams。
/// 职责：为原图下载统一生成稳定的本地缓存目标路径。
/// 对外接口：`call(params) -> Future<String>`。
class BuildOriginalPreviewDownloadPathUseCase
    implements UseCase<String, BuildOriginalPreviewDownloadPathParams> {
  final DeviceFileService _deviceFileService;

  BuildOriginalPreviewDownloadPathUseCase({
    required DeviceFileService deviceFileService,
  }) : _deviceFileService = deviceFileService;

  @override
  Future<String> call(BuildOriginalPreviewDownloadPathParams params) async {
    final cacheDirectory = await _deviceFileService.getAppCacheDirectory();
    final originalsDirectoryPath = p.join(
      cacheDirectory,
      'nasclient_original_previews',
    );
    final originalsDirectory = Directory(originalsDirectoryPath);
    if (!await originalsDirectory.exists()) {
      await originalsDirectory.create(recursive: true);
    }

    final sanitizedRemotePath = params.remotePath.replaceAll(
      RegExp(r'[\\/:*?"<>|]+'),
      '_',
    );
    return p.join(
      originalsDirectoryPath,
      '${params.rootId}_$sanitizedRemotePath',
    );
  }
}
