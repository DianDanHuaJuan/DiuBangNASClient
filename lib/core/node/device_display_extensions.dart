import 'device_display_resolver.dart';
import 'unified_node.dart';

extension UnifiedNodeDisplay on UnifiedNode {
  String get publicDisplayName {
    if (kind == NodeKind.server) {
      return identity.displayName;
    }
    return DeviceDisplayResolver.publicDisplayName(
      alias: identity.label,
      hardwareName: identity.deviceName,
      brand: identity.brand,
      model: identity.model,
      platform: identity.platform,
      fallback: identity.clientId ?? identity.deviceId ?? nodeId,
    );
  }

  String? get disambiguationSubtitle {
    if (kind == NodeKind.server) {
      return null;
    }
    return DeviceDisplayResolver.disambiguationSubtitle(
      hardwareName: identity.deviceName,
      deviceId: identity.deviceId ?? identity.clientId,
      reportedRouteIp: network.reportedRouteIp,
    );
  }
}
