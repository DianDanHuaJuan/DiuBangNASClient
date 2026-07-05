/// 文件输入：BuildOriginalPreviewDownloadPathUseCase、BuildOriginalPreviewDownloadPathParams
/// 文件职责：验证原图下载缓存路径构建逻辑
/// 文件对外接口：main
/// 文件包含：main、_FakeDeviceFileService
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:nasclient/core/device/device_file_service.dart';
import 'package:nasclient/features/preview/application/params/build_original_preview_download_path_params.dart';
import 'package:nasclient/features/preview/application/use_cases/build_original_preview_download_path_use_case.dart';

/// 输入：Flutter test runtime。
/// 职责：验证原图缓存路径会稳定落在专用目录并对远端路径做安全替换。
/// 对外接口：main。
void main() {
  group('BuildOriginalPreviewDownloadPathUseCase', () {
    test(
      'creates stable cache path under dedicated preview directory',
      () async {
        final tempDirectory = await Directory.systemTemp.createTemp(
          'nasclient-preview-path-',
        );
        addTearDown(() async {
          if (tempDirectory.existsSync()) {
            await tempDirectory.delete(recursive: true);
          }
        });

        final useCase = BuildOriginalPreviewDownloadPathUseCase(
          deviceFileService: _FakeDeviceFileService(tempDirectory.path),
        );

        final result = await useCase.call(
          const BuildOriginalPreviewDownloadPathParams(
            rootId: 'library',
            remotePath: '/albums/2026/test:file?.jpg',
          ),
        );

        expect(p.basename(result), 'library__albums_2026_test_file_.jpg');
        expect(Directory(p.dirname(result)).existsSync(), isTrue);
        expect(
          p.dirname(result),
          p.join(tempDirectory.path, 'nasclient_original_previews'),
        );
      },
    );
  });
}

/// 输入：缓存目录路径。
/// 职责：为路径构建测试提供可控的应用缓存目录。
/// 对外接口：getAppCacheDirectory()。
class _FakeDeviceFileService extends DeviceFileService {
  final String cacheDirectory;

  _FakeDeviceFileService(this.cacheDirectory);

  @override
  Future<String> getAppCacheDirectory() async {
    return cacheDirectory;
  }
}
