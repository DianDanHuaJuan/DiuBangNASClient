import '../../../../core/result/app_result.dart';
import '../entities/relay_peer_history_page.dart';
import '../entities/relay_transfer_entity.dart';

abstract interface class RelayRepository {
  Future<AppResult<List<RelayTransferEntity>>> loadHistory();

  Future<AppResult<RelayPeerHistoryPage>> loadPeerHistory({
    required String peerClientId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  });

  Future<AppResult<RelayTransferEntity>> sendFile({
    required String receiverClientId,
    required String localPath,
    String? mimeType,
    void Function(RelayTransferEntity transfer)? onTransferCreated,
    void Function(RelayTransferEntity transfer, int sentBytes, int totalBytes)?
        onUploadProgress,
  });

  Future<AppResult<RelayTransferEntity>> cancelTransfer({
    required String transferId,
  });

  Future<AppResult<RelayTransferEntity>> retryTransfer({
    required String transferId,
  });

  Future<AppResult<RelayDownloadResult>> downloadTransfer({
    required RelayTransferEntity transfer,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  });

  Future<AppResult<String?>> downloadThumbnail({
    required String thumbnailPath,
    required String savePath,
  });

  Future<AppResult<String?>> downloadThumbnailForTransfer({
    required RelayTransferEntity transfer,
    required String savePath,
  });
}
