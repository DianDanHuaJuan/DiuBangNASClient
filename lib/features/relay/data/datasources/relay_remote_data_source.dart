import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/nas_api_client.dart';
import '../../domain/entities/relay_peer_history_page.dart';
import '../../domain/entities/relay_transfer_entity.dart';
import '../../debug/relay_diagnostic_log.dart';
import '../models/relay_transfer_dto.dart';

class RelayRemoteDataSource {
  RelayRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient;

  final NasApiClient _apiClient;

  Future<List<RelayTransferEntity>> loadHistory() async {
    relayDiag('api_loadHistory_start');
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/relay/transfers/history',
    );
    final transfers = RelayTransferDto.requireEnvelopeTransfers(response);
    relayDiag(
      'api_loadHistory_response',
      fields: <String, Object?>{'rawCount': transfers.length},
    );
    return RelayTransferDto.parseTransferList(
      transfers,
      context: 'loadHistory',
    );
  }

  Future<RelayPeerHistoryPage> loadPeerHistory({
    required String peerClientId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    relayDiag(
      'api_loadPeerHistory_start',
      fields: <String, Object?>{
        'peerClientId': peerClientId,
        'limit': limit,
        'before': beforeCreatedAt?.toUtc().toIso8601String(),
      },
    );
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/relay/transfers/history',
      queryParameters: <String, dynamic>{
        'peerClientId': peerClientId,
        'limit': limit,
        if (beforeCreatedAt != null)
          'before': beforeCreatedAt.toUtc().toIso8601String(),
      },
    );
    final page = RelayTransferDto.requirePeerHistoryPage(response);
    relayDiag(
      'api_loadPeerHistory_ok',
      fields: <String, Object?>{
        'peerClientId': peerClientId,
        'count': page.transfers.length,
        'hasMore': page.hasMore,
      },
    );
    return page;
  }

  Future<RelayTransferEntity> createTransfer({
    required List<String> targetClientIds,
    required String fileName,
    required int fileSize,
    String? mimeType,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/relay/transfers',
      data: <String, dynamic>{
        'targetClientIds': targetClientIds,
        'fileName': fileName,
        'fileSize': fileSize,
        if (mimeType != null && mimeType.trim().isNotEmpty)
          'mimeType': mimeType,
      },
    );
    return RelayTransferDto.fromJson(
      RelayTransferDto.requireEnvelopeTransfer(response),
    );
  }

  Future<RelayTransferEntity> cancelTransfer({
    required String transferId,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/relay/transfers/$transferId/cancel',
    );
    return RelayTransferDto.fromJson(
      RelayTransferDto.requireEnvelopeTransfer(response),
    );
  }

  Future<RelayTransferEntity> retryTransfer({
    required String transferId,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/relay/transfers/$transferId/retry',
    );
    return RelayTransferDto.fromJson(
      RelayTransferDto.requireEnvelopeTransfer(response),
    );
  }

  Future<RelayTransferEntity> acknowledgeDownloadCompleted({
    required String transferId,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/relay/transfers/$transferId/download-complete',
      data: const <String, dynamic>{},
    );
    return RelayTransferDto.parseEnvelopeTransfer(
      response,
      context: 'ackDownloadCompleted',
    );
  }

  Future<Uint8List?> downloadRelayThumbnailBytes({
    required String transferId,
  }) async {
    final path = '/api/v1/relay/transfers/$transferId/thumbnail';
    try {
      final response = await _apiClient.dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        return null;
      }
      return Uint8List.fromList(data);
    } catch (error) {
      return null;
    }
  }
}
