import 'package:flutter_test/flutter_test.dart';
import 'package:nasclient/core/session/server_availability_controller.dart';

void main() {
  group('ServerAvailabilityController', () {
    test('suppresses offline gate during initial connection grace', () {
      final controller = ServerAvailabilityController()
        ..startMonitoring(
          initialStatus: ServerAvailabilityStatus.offline,
          awaitingInitialConnection: true,
        );

      expect(controller.shouldShowOfflineGate, isFalse);

      controller.markOnline();
      expect(controller.shouldShowOfflineGate, isFalse);

      controller.markOffline();
      expect(controller.shouldShowOfflineGate, isTrue);
    });

    test('shows offline gate after initial grace expires', () async {
      final controller = ServerAvailabilityController()
        ..startMonitoring(
          initialStatus: ServerAvailabilityStatus.offline,
          awaitingInitialConnection: true,
        );

      expect(controller.shouldShowOfflineGate, isFalse);

      await Future<void>.delayed(
        ServerAvailabilityController.initialConnectionGracePeriod +
            const Duration(milliseconds: 20),
      );

      expect(controller.shouldShowOfflineGate, isTrue);
      controller.dispose();
    });
  });
}
