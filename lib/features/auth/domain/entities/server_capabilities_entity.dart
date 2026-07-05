/// 文件输入：dashboard、preview、relay 能力开关
/// 文件职责：表达服务器能力矩阵实体
/// 文件对外接口：ServerCapabilitiesEntity
/// 文件包含：ServerCapabilitiesEntity
class ServerCapabilitiesEntity {
  final bool dashboard;
  final Map<String, dynamic>? preview;
  final Map<String, dynamic>? relay;
  final Map<String, dynamic>? realtime;

  const ServerCapabilitiesEntity({
    this.dashboard = false,
    this.preview,
    this.relay,
    this.realtime,
  });

  bool get hasDashboard => dashboard;
  bool get hasPreview => preview != null;
  bool get hasRelay => relay?['enabled'] == true;
  bool get hasWebsocket => realtime?['websocket'] == true;
  bool get hasImagePreview => preview?['image'] == true;
  bool get hasVideoPreview => preview?['video'] == true;
  bool get hasProgressiveVideo => preview?['progressive'] == true;
}
