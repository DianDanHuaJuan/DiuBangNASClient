import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/device_file_service.dart';
import 'package:nasclient/features/files/application/params/build_file_browser_download_path_params.dart';
import 'package:nasclient/features/files/application/use_cases/build_file_browser_download_path_use_case.dart';
import 'package:path/path.dart' as p;

class _FakeDeviceFileService extends DeviceFileService {
  @override
  Future<String> getAppDocumentsDirectory() async => p.join('tmp', 'nasclient-docs');
}

void main() {
  group('BuildFileBrowserDownloadPathUseCase', () {
    late BuildFileBrowserDownloadPathUseCase useCase;

    setUp(() {
      useCase = BuildFileBrowserDownloadPathUseCase(
        deviceFileService: _FakeDeviceFileService(),
      );
    });

    test('builds absolute path under nasclient_downloads with sanitized name', () async {
      final path = await useCase.call(
        const BuildFileBrowserDownloadPathParams(fileName: 'report.pdf'),
      );

      expect(path, contains('nasclient_downloads'));
      expect(p.basename(path), 'report.pdf');
      expect(path, endsWith(p.join('nasclient_downloads', 'report.pdf')));
    });

    test('sanitizes invalid filename characters', () async {
      final path = await useCase.call(
        const BuildFileBrowserDownloadPathParams(fileName: 'bad:name?.apk'),
      );

      expect(p.basename(path), 'bad_name_.apk');
    });
  });
}
