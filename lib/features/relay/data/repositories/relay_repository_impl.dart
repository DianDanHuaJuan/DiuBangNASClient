import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../core/device/device_file_service.dart';
import '../../../../core/device/local_media_picker.dart';
import '../../../../core/device/media_storage_service.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/relay_peer_history_page.dart';
import '../../domain/entities/relay_transfer_entity.dart';
import '../../domain/relay_transfer_upload.dart';
import '../../domain/relay_thumbnail_paths.dart';
import '../../domain/repositories/relay_repository.dart';
import '../../application/services/relay_thumbnail_generator.dart';
import '../datasources/relay_remote_data_source.dart';
import '../datasources/relay_webdav_transport_client.dart';
import '../../debug/relay_diagnostic_log.dart';

class RelayRepositoryImpl implements RelayRepository {
  RelayRepositoryImpl({
    required RelayRemoteDataSource remoteDataSource,
    required RelayWebdavTransportClient transportClient,
    required DeviceFileService deviceFileService,
    required MediaStorageService mediaStorageService,
    RelayThumbnailGenerator? thumbnailGenerator,
  }) : _remoteDataSource = remoteDataSource,
       _transportClient = transportClient,
       _deviceFileService = deviceFileService,
       _mediaStorageService = mediaStorageService,
       _thumbnailGenerator = thumbnailGenerator ?? const RelayThumbnailGenerator();

  final RelayRemoteDataSource _remoteDataSource;
  final RelayWebdavTransportClient _transportClient;
  final DeviceFileService _deviceFileService;
  final MediaStorageService _mediaStorageService;
  final RelayThumbnailGenerator _thumbnailGenerator;

  @override
  Future<AppResult<List<RelayTransferEntity>>> loadHistory() async {
    try {
      final transfers = await _remoteDataSource.loadHistory();
      transfers.sort(
        (left, right) => right.updatedAt.compareTo(left.updatedAt),
      );
      return Success(List.unmodifiable(transfers));
    } catch (error) {
      return Failure(
        _failureFromError(error, fallbackCode: 'RELAY_HISTORY_FAILED'),
      );
    }
  }

  @override
  Future<AppResult<RelayPeerHistoryPage>> loadPeerHistory({
    required String peerClientId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    try {
      final page = await _remoteDataSource.loadPeerHistory(
        peerClientId: peerClientId,
        limit: limit,
        beforeCreatedAt: beforeCreatedAt,
      );
      final transfers = List<RelayTransferEntity>.from(page.transfers)
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      return Success(
        RelayPeerHistoryPage(
          transfers: List.unmodifiable(transfers),
          hasMore: page.hasMore,
        ),
      );
    } catch (error) {
      return Failure(
        _failureFromError(error, fallbackCode: 'RELAY_PEER_HISTORY_FAILED'),
      );
    }
  }

  @override
  Future<AppResult<RelayTransferEntity>> sendFile({
    required String receiverClientId,
    required String localPath,
    String? mimeType,
    void Function(RelayTransferEntity transfer)? onTransferCreated,
    void Function(RelayTransferEntity transfer, int sentBytes, int totalBytes)?
        onUploadProgress,
  }) async {
    try {
      final fileName = await _deviceFileService.getFileName(localPath);
      final fileSize = await _deviceFileService.getFileSize(localPath);
      final effectiveMimeType =
          mimeType ?? guessMimeTypeFromFileName(fileName);
      final createdTransfer = await _remoteDataSource.createTransfer(
        targetClientIds: <String>[receiverClientId],
        fileName: fileName,
        fileSize: fileSize,
        mimeType: effectiveMimeType,
      );
      final uploadPath = _requireUploadPath(createdTransfer);
      var transfer = mergeRelayTransferTransport(
        createdTransfer,
        createdTransfer,
      );
      onTransferCreated?.call(transfer);

      final thumbnailLocalPath = await _thumbnailGenerator.generate(
        localPath: localPath,
        transferId: transfer.transferId,
        mimeType: effectiveMimeType,
      );
      if (thumbnailLocalPath != null) {
        final thumbnailUploadPath =
            transfer.transport?.thumbnailUpload?.path.trim();
        if (thumbnailUploadPath != null && thumbnailUploadPath.isNotEmpty) {
          try {
            await _transportClient.uploadThumbnail(
              relayPath: thumbnailUploadPath,
              thumbnailPath: thumbnailLocalPath,
            );
          } catch (_) {
            // Thumbnail upload is best-effort; payload upload may still succeed
          }
        }
      } else {
        final isVideo =
            (effectiveMimeType ?? '').toLowerCase().startsWith('video/');
        if (isVideo && kDebugMode) {
          debugPrint(
            '[RelayThumb] SEND-NO-THUMB transfer=${transfer.transferId} '
            'mime=$effectiveMimeType — video thumbnail generation returned null',
          );
        }
      }

      final uploadedTransfer = await _transportClient.uploadFile(
        relayPath: uploadPath,
        localPath: localPath,
        onSendProgress: onUploadProgress == null
            ? null
            : (sent, total) {
                final totalBytes = total > 0 ? total : fileSize;
                onUploadProgress(
                  relayTransferWithUploadBytes(transfer, sent),
                  sent,
                  totalBytes,
                );
              },
      );
      transfer = mergeRelayTransferTransport(
        createdTransfer,
        uploadedTransfer,
      );

      return Success(transfer);
    } catch (error) {
      return Failure(
        _failureFromError(error, fallbackCode: 'RELAY_SEND_FAILED'),
      );
    }
  }

  @override
  Future<AppResult<RelayTransferEntity>> cancelTransfer({
    required String transferId,
  }) async {
    try {
      final transfer = await _remoteDataSource.cancelTransfer(
        transferId: transferId,
      );
      return Success(transfer);
    } catch (error) {
      return Failure(
        _failureFromError(error, fallbackCode: 'RELAY_CANCEL_FAILED'),
      );
    }
  }

  @override
  Future<AppResult<RelayTransferEntity>> retryTransfer({
    required String transferId,
  }) async {
    try {
      final transfer = await _remoteDataSource.retryTransfer(
        transferId: transferId,
      );
      return Success(transfer);
    } catch (error) {
      return Failure(
        _failureFromError(error, fallbackCode: 'RELAY_RETRY_FAILED'),
      );
    }
  }

  @override
  Future<AppResult<RelayDownloadResult>> downloadTransfer({
    required RelayTransferEntity transfer,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    relayDiag(
      'download_start',
      fields: <String, Object?>{
        'transferId': transfer.transferId,
        'status': transfer.status.name,
        'cleanupState': transfer.artifact.cleanupState.name,
        'tempPath': transfer.artifact.tempPath,
        'sealedPath': transfer.artifact.sealedPath,
        'fileSize': transfer.fileSize,
      },
    );
    final tempPath = await _buildTempDownloadPath(transfer);
    try {
      await _transportClient.downloadToPath(
        relayPath: _requireDownloadPath(transfer),
        savePath: tempPath,
        expectedSize: transfer.fileSize,
        supportsRange: transfer.transport?.download.supportsRange ?? false,
        onReceiveProgress: onProgress,
      );
      relayDiag(
        'download_payload_ok',
        fields: <String, Object?>{
          'transferId': transfer.transferId,
          'savePath': tempPath,
        },
      );
      try {
        await _remoteDataSource.acknowledgeDownloadCompleted(
          transferId: transfer.transferId,
        );
        relayDiag(
          'download_ack_ok',
          fields: <String, Object?>{'transferId': transfer.transferId},
        );
      } catch (error) {
        relayDiag(
          'download_ack_fail',
          fields: <String, Object?>{
            'transferId': transfer.transferId,
            'error': '$error',
          },
        );
      }
      final publicUri = await _saveToPublicStorage(
        localPath: tempPath,
        fileName: transfer.fileName,
      );
      await _deleteIfExists(tempPath);
      relayDiag(
        'download_complete',
        fields: <String, Object?>{
          'transferId': transfer.transferId,
          'publicUri': publicUri,
        },
      );
      return Success(
        RelayDownloadResult(
          fileName: transfer.fileName,
          publicUri: publicUri,
          localPath: publicUri,
        ),
      );
    } catch (error) {
      relayDiag(
        'download_fail',
        fields: <String, Object?>{
          'transferId': transfer.transferId,
          'error': '$error',
          if (error is DioException) 'statusCode': error.response?.statusCode,
          if (error is DioException) 'responseData': '${error.response?.data}',
        },
      );
      await _deleteIfExists(tempPath);
      return Failure(
        _failureFromError(error, fallbackCode: 'RELAY_DOWNLOAD_FAILED'),
      );
    }
  }

  @override
  Future<AppResult<String?>> downloadThumbnail({
    required String thumbnailPath,
    required String savePath,
  }) async {
    try {
      await _transportClient.downloadToPath(
        relayPath: thumbnailPath,
        savePath: savePath,
        expectedSize: 0,
        supportsRange: false,
      );
      if (!await _hasNonEmptyFile(savePath)) {
        await _deleteIfExists(savePath);
        return const Success(null);
      }
      return Success(savePath);
    } catch (error) {
      await _deleteIfExists(savePath);
      return const Success(null);
    }
  }

  @override
  Future<AppResult<String?>> downloadThumbnailForTransfer({
    required RelayTransferEntity transfer,
    required String savePath,
  }) async {
    if (!relayTransferCanFetchRemoteThumbnail(transfer)) {
      return const Success(null);
    }

    final apiBytes = await _remoteDataSource.downloadRelayThumbnailBytes(
      transferId: transfer.transferId,
    );
    if (apiBytes != null && apiBytes.isNotEmpty) {
      await File(savePath).writeAsBytes(apiBytes);
      if (kDebugMode) {
        debugPrint(
          '[RelayThumb] RECV-THUMB-DL transfer=${transfer.transferId} '
          'bytes=${apiBytes.length} path=$savePath',
        );
      }
      return Success(savePath);
    }

    final webdavPath = transfer.transport?.thumbnailDownload?.path.trim();
    if (webdavPath == null || webdavPath.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[RelayThumb] RECV-NO-PATH transfer=${transfer.transferId} '
          'status=${transfer.status.name} — no thumbnail download path in transport',
        );
      }
      return const Success(null);
    }

    final result = await downloadThumbnail(
      thumbnailPath: webdavPath,
      savePath: savePath,
    );
    if (result.isSuccess && result.dataOrNull != null) {
      return result;
    }

    if (kDebugMode) {
      debugPrint(
        '[RelayThumb] RECV-THUMB-FAIL transfer=${transfer.transferId} '
        'status=${transfer.status.name} path=$webdavPath',
      );
    }
    return const Success(null);
  }

  Future<bool> _hasNonEmptyFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    return await file.length() > 0;
  }

  Future<String> _buildTempDownloadPath(RelayTransferEntity transfer) async {
    final cacheDir = await _deviceFileService.getAppCacheDirectory();
    final relayDir = Directory(p.join(cacheDir, 'relay_downloads'));
    if (!await relayDir.exists()) {
      await relayDir.create(recursive: true);
    }
    final safeFileName = p.basename(transfer.fileName);
    return p.join(relayDir.path, '${transfer.transferId}_$safeFileName');
  }

  Future<String> _saveToPublicStorage({
    required String localPath,
    required String fileName,
  }) async {
    final fileSize = await _deviceFileService.getFileSize(localPath);
    final fileType = _mediaStorageService.getFileTypeFromExtension(fileName);

    String? publicUri;
    if (_mediaStorageService.shouldUseMemory(fileSize)) {
      final bytes = await _deviceFileService.readFileAsBytes(localPath);
      publicUri = await _mediaStorageService.saveToPublicStorage(
        fileName: fileName,
        data: bytes,
        fileType: fileType,
      );
    } else {
      publicUri = await _mediaStorageService.saveFileToPublicStorage(
        fileName: fileName,
        filePath: localPath,
        fileType: fileType,
      );
    }

    if (publicUri == null || publicUri.trim().isEmpty) {
      throw const AppException(
        code: 'RELAY_DOWNLOAD_SAVE_FAILED',
        message:
            'Saving relay download to public storage returned an empty uri',
      );
    }
    return publicUri;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  AppFailure _failureFromError(Object error, {required String fallbackCode}) {
    if (error is AppException) {
      return AppFailure.fromException(code: error.code, message: error.message);
    }
    if (error is DioException && error.response?.statusCode == 409) {
      return AppFailure.fromException(
        code: 'RELAY_DOWNLOAD_NOT_READY',
        message: '文件尚未发送完成，请稍后再试',
      );
    }
    return AppFailure.fromException(code: fallbackCode, message: '$error');
  }

  String _requireUploadPath(RelayTransferEntity transfer) {
    final path = transfer.transport?.upload.path;
    if (path == null || path.trim().isEmpty) {
      throw const AppException(
        code: 'RELAY_TRANSPORT_UNAVAILABLE',
        message: 'Relay upload path is missing from the server response',
      );
    }
    return path;
  }

  String _requireDownloadPath(RelayTransferEntity transfer) {
    final path = transfer.transport?.download.path;
    if (path == null || path.trim().isEmpty) {
      throw const AppException(
        code: 'RELAY_TRANSPORT_UNAVAILABLE',
        message: 'Relay download path is missing from the server response',
      );
    }
    return path;
  }
}
