/// 文件输入：SaveOriginalToPublicStorageUseCase、SaveOriginalToPublicStorageParams
/// 文件职责：验证原图保存到系统公共目录的行为
/// 文件对外接口：main
/// 文件包含：main、_FakeDeviceFileService、_FakeMediaStorageService
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/device/device_file_service.dart';
import 'package:nasclient/core/device/media_storage_service.dart';
import 'package:nasclient/features/preview/application/params/save_original_to_public_storage_params.dart';
import 'package:nasclient/features/preview/application/use_cases/save_original_to_public_storage_use_case.dart';

/// 输入：Flutter test runtime。
/// 职责：验证原图保存逻辑在成功和缺失文件场景下都能返回明确结果。
/// 对外接口：main。
void main() {
  group('SaveOriginalToPublicStorageUseCase', () {
    test('saves small files through in-memory MediaStore flow', () async {
      final deviceFileService = _FakeDeviceFileService(
        exists: true,
        fileSize: 32,
        bytes: Uint8List.fromList(const [1, 2, 3]),
      );
      final mediaStorageService = _FakeMediaStorageService(
        shouldUseMemoryResult: true,
        memorySaveResult: 'content://images/original-1',
      );
      final useCase = SaveOriginalToPublicStorageUseCase(
        deviceFileService: deviceFileService,
        mediaStorageService: mediaStorageService,
      );

      final result = await useCase.call(
        const SaveOriginalToPublicStorageParams(
          localPath: 'C:\\temp\\original.jpg',
          fileName: 'original.jpg',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, 'content://images/original-1');
      expect(mediaStorageService.savedFilePath, isNull);
      expect(
        mediaStorageService.savedBytes,
        Uint8List.fromList(const [1, 2, 3]),
      );
    });

    test('returns failure when downloaded file is missing', () async {
      final useCase = SaveOriginalToPublicStorageUseCase(
        deviceFileService: _FakeDeviceFileService(
          exists: false,
          fileSize: 0,
          bytes: Uint8List(0),
        ),
        mediaStorageService: _FakeMediaStorageService(
          shouldUseMemoryResult: true,
          memorySaveResult: 'content://images/unused',
        ),
      );

      final result = await useCase.call(
        const SaveOriginalToPublicStorageParams(
          localPath: 'C:\\temp\\missing.jpg',
          fileName: 'missing.jpg',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.code, 'PREVIEW_ORIGINAL_MISSING');
    });
  });
}

/// 输入：文件存在性、大小和字节内容。
/// 职责：为原图保存用例测试提供可控的设备文件读取行为。
/// 对外接口：fileExists()、getFileSize()、readFileAsBytes()。
class _FakeDeviceFileService extends DeviceFileService {
  final bool exists;
  final int fileSize;
  final Uint8List bytes;

  _FakeDeviceFileService({
    required this.exists,
    required this.fileSize,
    required this.bytes,
  });

  @override
  Future<bool> fileExists(String path) async {
    return exists;
  }

  @override
  Future<int> getFileSize(String path) async {
    return fileSize;
  }

  @override
  Future<Uint8List> readFileAsBytes(String path) async {
    return bytes;
  }
}

/// 输入：保存策略与预期返回值。
/// 职责：为原图保存用例测试提供可控的公共目录保存行为。
/// 对外接口：shouldUseMemory()、saveToPublicStorage()、saveFileToPublicStorage()。
class _FakeMediaStorageService extends MediaStorageService {
  final bool shouldUseMemoryResult;
  final String memorySaveResult;
  Uint8List? savedBytes;
  String? savedFilePath;

  _FakeMediaStorageService({
    required this.shouldUseMemoryResult,
    required this.memorySaveResult,
  });

  @override
  bool shouldUseMemory(int fileSizeBytes) {
    return shouldUseMemoryResult;
  }

  @override
  Future<String?> saveToPublicStorage({
    required String fileName,
    required Uint8List data,
    required MediaFileType fileType,
  }) async {
    savedBytes = data;
    return memorySaveResult;
  }

  @override
  Future<String?> saveFileToPublicStorage({
    required String fileName,
    required String filePath,
    required MediaFileType fileType,
  }) async {
    savedFilePath = filePath;
    return 'content://files/original-1';
  }
}
