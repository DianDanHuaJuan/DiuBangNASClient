/// 文件输入：API 客户端、NAS 路径
/// 文件职责：获取预览信息，调用 /api/v1/preview/meta
/// 文件对外接口：PreviewRemoteDataSource
/// 文件包含：PreviewRemoteDataSource
import '../../../../core/network/nas_api_client.dart';
import '../../../../core/path/nas_path.dart';
import '../models/preview_item_dto.dart';

class PreviewRemoteDataSource {
  final NasApiClient _apiClient;

  PreviewRemoteDataSource({required NasApiClient apiClient})
    : _apiClient = apiClient;

  Future<PreviewItemDto> loadPreview(NasPath path) async {
    final apiPath = path.toApiPath();
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/preview/meta',
      queryParameters: {'path': apiPath},
    );
    return PreviewItemDto.fromJson(response);
  }
}
