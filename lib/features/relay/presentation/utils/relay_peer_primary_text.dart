import '../../../../core/node/device_display_resolver.dart';
import '../../../../core/node/unified_node.dart';

Map<String, int> buildRelayPeerObservedRemoteIpUsage(
  Iterable<UnifiedNode> peers,
) {
  final usage = <String, int>{};
  for (final peer in peers) {
    final observedRemoteIp = peer.network.observedRemoteIp?.trim() ?? '';
    if (observedRemoteIp.isEmpty) {
      continue;
    }
    usage.update(observedRemoteIp, (count) => count + 1, ifAbsent: () => 1);
  }
  return usage;
}

Map<String, int> buildRelayPeerReportedRouteIpUsage(
  Iterable<UnifiedNode> peers,
) {
  final usage = <String, int>{};
  for (final peer in peers) {
    final reportedRouteIp = peer.network.reportedRouteIp?.trim() ?? '';
    if (reportedRouteIp.isEmpty) {
      continue;
    }
    usage.update(reportedRouteIp, (count) => count + 1, ifAbsent: () => 1);
  }
  return usage;
}

bool isUsablePeerReportedRouteIp(
  String reportedRouteIp, {
  required String? serverIp,
  required Map<String, int> reportedRouteIpUsage,
}) {
  if (reportedRouteIp.isEmpty) {
    return false;
  }
  final normalizedServerIp = serverIp?.trim() ?? '';
  if (normalizedServerIp.isNotEmpty && reportedRouteIp == normalizedServerIp) {
    return false;
  }
  return reportedRouteIpUsage[reportedRouteIp] == 1;
}

String buildRelayPeerPrimaryText(
  UnifiedNode peer, {
  required String? serverIp,
  required Map<String, int> observedRemoteIpUsage,
  required Map<String, int> reportedRouteIpUsage,
}) {
  final observedRemoteIp = peer.network.observedRemoteIp?.trim() ?? '';
  if (observedRemoteIp.isNotEmpty &&
      observedRemoteIpUsage[observedRemoteIp] == 1) {
    return 'IP: $observedRemoteIp';
  }

  final reportedRouteIp = peer.network.reportedRouteIp?.trim() ?? '';
  if (isUsablePeerReportedRouteIp(
    reportedRouteIp,
    serverIp: serverIp,
    reportedRouteIpUsage: reportedRouteIpUsage,
  )) {
    return 'IP: $reportedRouteIp';
  }

  final fallback =
      DeviceDisplayResolver.disambiguationSubtitle(
        hardwareName: peer.identity.deviceName,
        deviceId: peer.identity.deviceId ?? peer.identity.clientId,
      )?.trim() ??
      '';
  if (fallback.isNotEmpty) {
    return fallback;
  }
  return 'ID: 未知';
}
