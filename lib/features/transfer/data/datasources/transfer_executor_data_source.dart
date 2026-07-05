/// 文件输入：文件协议客户端、任务参数
/// 文件职责：执行实际上传/下载任务，支持进度回调和任务控制
/// 文件对外接口：TransferExecutorDataSource
/// 文件包含：TransferExecutorDataSource
import 'dart:async';
import 'dart:io';

import '../../../../core/network/progress_callback_throttler.dart';
import '../../../../core/path/nas_path.dart';
import '../../../../core/protocol/file_protocol_client.dart';
import '../../../../core/protocol/path_download_capable_file_protocol_client.dart';
import '../../../../core/protocol/upload_contract.dart';
import '../../../../core/transfer/client_transfer_tuning.dart';

class TransferExecutorDataSource {
  final FileProtocolClient _protocolClient;
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, bool> _pausedTasks = {};

  TransferExecutorDataSource({required FileProtocolClient protocolClient})
    : _protocolClient = protocolClient;

  Future<void> download({
    required String taskId,
    required NasPath remotePath,
    required String localPath,
    Function(int, int)? onProgress,
    Function()? onComplete,
    Function(String)? onError,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      final file = File(localPath);
      final parentDir = file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      int totalSize = await _protocolClient.getFileSize(remotePath);
      final progressThrottler = ProgressCallbackThrottler();

      if (_protocolClient is PathDownloadCapableFileProtocolClient) {
        final pathDownloadClient =
            _protocolClient as PathDownloadCapableFileProtocolClient;
        try {
          await pathDownloadClient.downloadToPath(
            sourcePath: remotePath,
            savePath: localPath,
            expectedSize: totalSize,
            onProgress: (received) {
              if (_pausedTasks[taskId] == true || cancelToken.isCancelled) {
                return;
              }
              progressThrottler.report(
                received,
                totalBytes: totalSize,
                onProgress: onProgress,
              );
            },
            shouldCancel: () =>
                _pausedTasks[taskId] == true || cancelToken.isCancelled,
          );
        } on PathDownloadCancelledException {
          return;
        }

        progressThrottler.complete(
          transferredBytes: totalSize,
          totalBytes: totalSize,
          onProgress: onProgress,
        );
        _cancelTokens.remove(taskId);
        _pausedTasks.remove(taskId);
        onComplete?.call();
        return;
      }

      final stream = await _protocolClient.download(sourcePath: remotePath);

      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in stream) {
        if (_pausedTasks[taskId] == true) {
          await sink.close();
          return;
        }
        if (cancelToken.isCancelled) {
          await sink.close();
          await file.delete();
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        progressThrottler.report(
          received,
          totalBytes: totalSize,
          onProgress: onProgress,
        );
      }

      await sink.close();
      progressThrottler.complete(
        transferredBytes: totalSize > 0 ? totalSize : received,
        totalBytes: totalSize > 0 ? totalSize : received,
        onProgress: onProgress,
      );
      _cancelTokens.remove(taskId);
      _pausedTasks.remove(taskId);
      onComplete?.call();
    } catch (e) {
      _cancelTokens.remove(taskId);
      _pausedTasks.remove(taskId);
      onError?.call(e.toString());
    }
  }

  Future<void> upload({
    required String taskId,
    required String localPath,
    required NasPath remotePath,
    UploadConflictPolicy conflictPolicy = UploadConflictPolicy.fail,
    Map<String, String>? uploadHeaders,
    Function(int)? onProgress,
    Function(UploadResult result)? onComplete,
    Function(Object error)? onError,
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw Exception('Local file not found: $localPath');
      }

      final stream = ClientTransferTuning.bufferUploadStream(file.openRead());
      final size = await file.length();
      final progressThrottler = ClientTransferTuning.uploadProgressThrottler();

      final result = await _protocolClient.upload(
        targetPath: remotePath,
        sourceStream: stream,
        totalSize: size,
        conflictPolicy: conflictPolicy,
        extraHeaders: uploadHeaders,
        onProgress: (sent) {
          if (_pausedTasks[taskId] == true) return;
          if (cancelToken.isCancelled) return;
          progressThrottler.reportValue(
            sent,
            totalBytes: size,
            onProgress: onProgress,
          );
        },
      );

      progressThrottler.completeValue(
        transferredBytes: size,
        onProgress: onProgress,
      );
      _cancelTokens.remove(taskId);
      _pausedTasks.remove(taskId);
      onComplete?.call(result);
    } catch (e) {
      _cancelTokens.remove(taskId);
      _pausedTasks.remove(taskId);
      onError?.call(e);
    }
  }

  void cancel(String taskId) {
    _cancelTokens[taskId]?.cancel();
    _cancelTokens.remove(taskId);
    _pausedTasks.remove(taskId);
  }

  void pause(String taskId) {
    _pausedTasks[taskId] = true;
  }

  void resume(String taskId) {
    _pausedTasks.remove(taskId);
  }

  bool isPaused(String taskId) {
    return _pausedTasks[taskId] == true;
  }

  bool isCancelled(String taskId) {
    return _cancelTokens[taskId]?.isCancelled ?? false;
  }
}

class CancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}
