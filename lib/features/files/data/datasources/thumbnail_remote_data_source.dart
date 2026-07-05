/// 文件输入：API 客户端、路径列表、缩略图类型
/// 文件职责：调用批量缩略图 API，解析 multipart 响应
/// 文件对外接口：ThumbnailRemoteDataSource
/// 文件包含：ThumbnailRemoteDataSource
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../../core/network/nas_api_client.dart';
import '../../../../core/error/app_exception.dart';
import '../../domain/entities/thumbnail_item_entity.dart';
import '../models/batch_thumbnail_response_dto.dart';
import '../models/thumbnail_batch_response.dart';

class ThumbnailRemoteDataSource {
  final NasApiClient _apiClient;
  static const int maxBatchSize = 5;

  ThumbnailRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient;

  Future<ThumbnailBatchResponse> fetchBatchThumbnails({
    required List<String> paths,
    String type = 'grid',
  }) async {
    if (paths.isEmpty) {
      return const ThumbnailBatchResponse(items: [], failedPaths: []);
    }

    if (paths.length > maxBatchSize) {
      throw AppException(
        code: 'BATCH_SIZE_EXCEEDED',
        message: 'Batch size exceeds maximum of $maxBatchSize',
      );
    }

    final response = await _apiClient.postBytes(
      '/api/v1/thumbnails/batch',
      data: {'paths': paths, 'type': type},
    );

    return _parseMultipartResponse(response, paths);
  }

  ThumbnailBatchResponse _parseMultipartResponse(
    Response<List<int>?> response,
    List<String> originalPaths,
  ) {
    final contentType = response.headers.value('content-type');
    if (contentType == null || !contentType.contains('multipart/mixed')) {
      throw AppException(
        code: 'INVALID_RESPONSE',
        message: 'Expected multipart/mixed response',
      );
    }

    final boundaryMatch = RegExp(r'boundary=([^\s;]+)').firstMatch(contentType);
    final boundary = boundaryMatch?.group(1);

    if (boundary == null) {
      throw AppException(
        code: 'INVALID_RESPONSE',
        message: 'Cannot find boundary in content-type',
      );
    }

    final data = response.data;
    if (data == null) {
      throw AppException(
        code: 'INVALID_RESPONSE',
        message: 'Response data is null',
      );
    }

    return _parseMultipartBytes(Uint8List.fromList(data), boundary, originalPaths);
  }

  ThumbnailBatchResponse _parseMultipartBytes(
    Uint8List rawBytes,
    String boundary,
    List<String> originalPaths,
  ) {
    final results = <ThumbnailItemEntity>[];
    final failedPaths = <String>[];
    final boundaryBytes = utf8.encode('--$boundary');
    final headerEndMarker = utf8.encode('\r\n\r\n');

    final parts = _splitByBoundary(rawBytes, boundaryBytes);

    BatchThumbnailResponseDto? indexInfo;
    final thumbnailDataMap = <int, Uint8List>{};
    final contentTypeMap = <int, String>{};

    for (final part in parts) {
      final headerEndIndex = _findSequence(part, headerEndMarker);
      if (headerEndIndex == -1) continue;

      final headerBytes = part.sublist(0, headerEndIndex);
      final bodyBytes = part.sublist(headerEndIndex + 4);
      final headers = utf8.decode(headerBytes, allowMalformed: true);

      final contentTypeMatch = RegExp(
        r'Content-Type:\s*([^\r\n]+)',
        caseSensitive: false,
      ).firstMatch(headers);
      final partContentType =
          contentTypeMatch?.group(1)?.trim() ?? 'application/octet-stream';

      final indexMatch = RegExp(
        r'X-Thumbnail-Index:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(headers);

      if (partContentType.contains('application/json')) {
        try {
          final jsonStr = utf8.decode(bodyBytes, allowMalformed: true);
          final jsonStart = jsonStr.indexOf('{');
          final jsonEnd = jsonStr.lastIndexOf('}');
          if (jsonStart != -1 && jsonEnd != -1) {
            final json =
                jsonDecode(jsonStr.substring(jsonStart, jsonEnd + 1))
                    as Map<String, dynamic>;
            indexInfo = BatchThumbnailResponseDto.fromJson(json);
          }
        } catch (_) {}
      } else if (partContentType.startsWith('image/') && indexMatch != null) {
        final index = int.parse(indexMatch.group(1)!);
        thumbnailDataMap[index] = bodyBytes;
        contentTypeMap[index] = partContentType;
      }
    }

    if (indexInfo != null) {
      for (final result in indexInfo.thumbnails) {
        if (result.success && thumbnailDataMap.containsKey(result.index)) {
          results.add(
            ThumbnailItemEntity(
              path: result.path,
              data: thumbnailDataMap[result.index]!,
              contentType: contentTypeMap[result.index] ?? 'image/jpeg',
              size: result.size ?? thumbnailDataMap[result.index]!.length,
            ),
          );
        } else if (!result.success) {
          failedPaths.add(result.path);
        }
      }
    } else {
      failedPaths.addAll(originalPaths);
    }

    return ThumbnailBatchResponse(items: results, failedPaths: failedPaths);
  }

  List<Uint8List> _splitByBoundary(Uint8List data, List<int> boundary) {
    final parts = <Uint8List>[];
    var start = 0;

    while (start < data.length) {
      final index = _findSequence(data, boundary, start);
      if (index == -1) break;

      if (start > 0) {
        parts.add(data.sublist(start, index));
      }

      start = index + boundary.length;

      if (start + 1 < data.length &&
          data[start] == 0x2D &&
          data[start + 1] == 0x2D) {
        break;
      }

      while (start < data.length &&
          (data[start] == 0x0D || data[start] == 0x0A)) {
        start++;
      }
    }

    return parts;
  }

  int _findSequence(Uint8List data, List<int> sequence, [int start = 0]) {
    for (var i = start; i <= data.length - sequence.length; i++) {
      var found = true;
      for (var j = 0; j < sequence.length; j++) {
        if (data[i + j] != sequence[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }
}
