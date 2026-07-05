/// 文件职责：表达服务器选择页面的状态
/// 文件对外接口：ServerSelectionState
/// 文件包含：ServerSelectionState
import '../../../../core/node/unified_node.dart';

const _serverSelectionStateUnset = Object();

class ServerSelectionState {
  final List<UnifiedNode> savedServers;
  final List<UnifiedNode> discoveredServers;
  final bool isScanning;
  final bool hasCompletedScan;
  final String? errorMessage;
  final String? scanNoticeMessage;
  final int scanNoticeVersion;
  final Map<String, bool> serverOnlineStatus;
  final bool checkingOnline;
  final String? autoLoggingInUrl;

  const ServerSelectionState({
    this.savedServers = const [],
    this.discoveredServers = const [],
    this.isScanning = false,
    this.hasCompletedScan = false,
    this.errorMessage,
    this.scanNoticeMessage,
    this.scanNoticeVersion = 0,
    this.serverOnlineStatus = const {},
    this.checkingOnline = false,
    this.autoLoggingInUrl,
  });

  ServerSelectionState copyWith({
    List<UnifiedNode>? savedServers,
    List<UnifiedNode>? discoveredServers,
    bool? isScanning,
    bool? hasCompletedScan,
    Object? errorMessage = _serverSelectionStateUnset,
    Object? scanNoticeMessage = _serverSelectionStateUnset,
    int? scanNoticeVersion,
    Map<String, bool>? serverOnlineStatus,
    bool? checkingOnline,
    Object? autoLoggingInUrl = _serverSelectionStateUnset,
  }) {
    return ServerSelectionState(
      savedServers: savedServers ?? this.savedServers,
      discoveredServers: discoveredServers ?? this.discoveredServers,
      isScanning: isScanning ?? this.isScanning,
      hasCompletedScan: hasCompletedScan ?? this.hasCompletedScan,
      errorMessage: identical(errorMessage, _serverSelectionStateUnset)
          ? this.errorMessage
          : errorMessage as String?,
      scanNoticeMessage:
          identical(scanNoticeMessage, _serverSelectionStateUnset)
          ? this.scanNoticeMessage
          : scanNoticeMessage as String?,
      scanNoticeVersion: scanNoticeVersion ?? this.scanNoticeVersion,
      serverOnlineStatus: serverOnlineStatus ?? this.serverOnlineStatus,
      checkingOnline: checkingOnline ?? this.checkingOnline,
      autoLoggingInUrl: identical(autoLoggingInUrl, _serverSelectionStateUnset)
          ? this.autoLoggingInUrl
          : autoLoggingInUrl as String?,
    );
  }
}
