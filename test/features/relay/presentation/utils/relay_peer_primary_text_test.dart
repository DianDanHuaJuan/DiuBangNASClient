import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/unified_node.dart';
import 'package:nasclient/features/relay/presentation/utils/relay_peer_primary_text.dart';

void main() {
  group('buildRelayPeerPrimaryText', () {
    test('prefers unique observed remote ip over reported route ip', () {
      final peer = UnifiedNode.cachedPeerIdentity(
        clientId: 'phone-01',
        deviceName: 'Xiaomi 14',
        reportedRouteIp: '192.168.1.25',
        observedRemoteIp: '203.0.113.10',
      );

      expect(
        buildRelayPeerPrimaryText(
          peer,
          serverIp: '192.168.1.10',
          observedRemoteIpUsage: buildRelayPeerObservedRemoteIpUsage(
            <UnifiedNode>[peer],
          ),
          reportedRouteIpUsage: buildRelayPeerReportedRouteIpUsage(
            <UnifiedNode>[peer],
          ),
        ),
        'IP: 203.0.113.10',
      );
    });

    test('shows unique reported route ip when observed remote ip is absent', () {
      final peer = UnifiedNode.cachedPeerIdentity(
        clientId: 'phone-01',
        reportedRouteIp: '192.168.1.25',
      );

      expect(
        buildRelayPeerPrimaryText(
          peer,
          serverIp: '192.168.1.10',
          observedRemoteIpUsage: buildRelayPeerObservedRemoteIpUsage(
            <UnifiedNode>[peer],
          ),
          reportedRouteIpUsage: buildRelayPeerReportedRouteIpUsage(
            <UnifiedNode>[peer],
          ),
        ),
        'IP: 192.168.1.25',
      );
    });

    test('falls back when reported route ip equals server ip', () {
      final peer = UnifiedNode.cachedPeerIdentity(
        clientId: 'phone-01',
        deviceName: 'Xiaomi 14',
        reportedRouteIp: '192.168.1.10',
        observedRemoteIp: '192.168.1.25',
      );

      expect(
        buildRelayPeerPrimaryText(
          peer,
          serverIp: '192.168.1.10',
          observedRemoteIpUsage: buildRelayPeerObservedRemoteIpUsage(
            <UnifiedNode>[peer],
          ),
          reportedRouteIpUsage: buildRelayPeerReportedRouteIpUsage(
            <UnifiedNode>[peer],
          ),
        ),
        'IP: 192.168.1.25',
      );
    });

    test('falls back when observed remote ip is shared by multiple peers', () {
      final phone = UnifiedNode.cachedPeerIdentity(
        clientId: 'phone-01',
        deviceName: 'Xiaomi 14',
        observedRemoteIp: '203.0.113.10',
      );
      final tablet = UnifiedNode.cachedPeerIdentity(
        clientId: 'tablet-01',
        deviceName: 'iPad Pro',
        observedRemoteIp: '203.0.113.10',
      );
      final peers = <UnifiedNode>[phone, tablet];
      final observedUsage = buildRelayPeerObservedRemoteIpUsage(peers);
      final reportedUsage = buildRelayPeerReportedRouteIpUsage(peers);

      expect(
        buildRelayPeerPrimaryText(
          phone,
          serverIp: '192.168.1.10',
          observedRemoteIpUsage: observedUsage,
          reportedRouteIpUsage: reportedUsage,
        ),
        'Xiaomi 14',
      );
      expect(
        buildRelayPeerPrimaryText(
          tablet,
          serverIp: '192.168.1.10',
          observedRemoteIpUsage: observedUsage,
          reportedRouteIpUsage: reportedUsage,
        ),
        'iPad Pro',
      );
    });

    test('falls back when reported route ip is shared by multiple peers', () {
      final phone = UnifiedNode.cachedPeerIdentity(
        clientId: 'phone-01',
        deviceName: 'Xiaomi 14',
        reportedRouteIp: '192.168.1.25',
      );
      final tablet = UnifiedNode.cachedPeerIdentity(
        clientId: 'tablet-01',
        deviceName: 'iPad Pro',
        reportedRouteIp: '192.168.1.25',
      );
      final peers = <UnifiedNode>[phone, tablet];
      final observedUsage = buildRelayPeerObservedRemoteIpUsage(peers);
      final reportedUsage = buildRelayPeerReportedRouteIpUsage(peers);

      expect(
        buildRelayPeerPrimaryText(
          phone,
          serverIp: '192.168.1.10',
          observedRemoteIpUsage: observedUsage,
          reportedRouteIpUsage: reportedUsage,
        ),
        'Xiaomi 14',
      );
    });
  });
}
