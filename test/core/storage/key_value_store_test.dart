import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/node/unified_node.dart';
import 'package:nasclient/core/storage/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('saves and restores cached peer identity nodes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = KeyValueStore(prefs: prefs);

    await store.savePeerNodes(<UnifiedNode>[
      UnifiedNode.cachedPeerIdentity(
        clientId: 'phone-01',
        accountId: 'acct-phone-01',
        displayName: 'Xiaomi 14',
        label: 'Xiaomi 14',
        deviceName: 'Xiaomi 14',
        platform: 'android',
        brand: 'Xiaomi',
        model: '14',
        reportedRouteIp: '192.168.1.25',
        updatedAt: DateTime.utc(2026, 5, 21, 10),
      ),
    ]);

    final peers = store.getPeerNodes();
    expect(peers, hasLength(1));
    expect(peers.first.identity.clientId, 'phone-01');
    expect(peers.first.identity.platform, 'android');
    expect(peers.first.identity.brand, 'Xiaomi');
    expect(peers.first.identity.model, '14');
    expect(peers.first.network.reportedRouteIp, '192.168.1.25');
  });
}
