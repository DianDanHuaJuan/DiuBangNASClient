/// 文件输入：DeviceFileService、MediaStorageService、SaveOriginalToPublicStorageParams
/// 文件职责：将已下载的原图保存到系统公共目录
/// 文件对外接口：SaveOriginalToPublicStorageUseCase
/// 文件包含：SaveOriginalToPublicStorageUseCase
import '../../../../core/device/device_file_service.dart';
import '../../../../core/device/media_storage_service.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/use_case.dart';
import '../params/save_original_to_public_storage_params.dart';

/// 输入：DeviceFileService、MediaStorageService、SaveOriginalToPublicStorageParams。
/// 职责：统一处理原图落盘到系统公共目录的保存策略和失败返回。
/// 对外接口：`call(params) -> Future<AppResult<String>>`。
class SaveOriginalToPublicStorageUseCase
    implements UseCase<AppResult<String>, SaveOriginalToPublicStorageParams> {
  final DeviceFileService _deviceFileService;
  final MediaStorageService _mediaStorageService;

  SaveOriginalToPublicStorageUseCase({
    required DeviceFileService deviceFileService,
    required MediaStorageService mediaStorageService,
  }) : _deviceFileService = deviceFileService,
       _mediaStorageService = mediaStorageService;

  @override
  Future<AppResult<String>> call(
    SaveOriginalToPublicStorageParams params,
  ) async {
    try {
      final exists = await _deviceFileService.fileExists(params.localPath);
      if (!exists) {
        return Failure(
          AppFailure.fromException(
            code: 'PREVIEW_ORIGINAL_MISSING',
            message: 'Downloaded original file not found: ${params.localPath}',
          ),
        );
      }

      final fileSize = await _deviceFileService.getFileSize(params.localPath);
      final fileType = _mediaStorageService.getFileTypeFromExtension(
        params.fileName,
      );

      String? publicUri;
      if (_mediaStorageService.shouldUseMemory(fileSize)) {
        final bytes = await _deviceFileService.readFileAsBytes(
          params.localPath,
        );
        publicUri = await _mediaStorageService.saveToPublicStorage(
          fileName: params.fileName,
          data: bytes,
          fileType: fileType,
        );
      } else {
        publicUri = await _mediaStorageService.saveFileToPublicStorage(
          fileName: params.fileName,
          filePath: params.localPath,
          fileType: fileType,
        );
      }

      if (publicUri == null || publicUri.isEmpty) {
        return Failure(
          AppFailure.fromException(
            code: 'SAVE_ORIGINAL_EMPTY_URI',
            message: 'Saving original to public storage returned empty uri.',
          ),
        );
      }

      return Success(publicUri);
    } catch (error) {
      return Failure(
        AppFailure.fromException(
          code: 'SAVE_ORIGINAL_FAILED',
          message: 'Failed to save original to public storage: $error',
        ),
      );
    }
  }
}
