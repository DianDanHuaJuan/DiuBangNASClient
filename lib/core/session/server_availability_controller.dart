import 'dart:async';

enum ServerAvailabilityStatus { online, offline }

class ServerAvailabilityController {
  static const Duration initialConnectionGracePeriod = Duration(seconds: 5);

  final StreamController<ServerAvailabilityStatus> _controller =
      StreamController<ServerAvailabilityStatus>.broadcast();

  ServerAvailabilityStatus _currentStatus = ServerAvailabilityStatus.offline;
  bool _isMonitoring = false;
  bool _awaitingInitialConnection = false;
  bool _initialConnectionGraceExpired = false;
  bool _hasEverBeenOnline = false;
  Timer? _initialConnectionGraceTimer;

  Stream<ServerAvailabilityStatus> get statusStream => _controller.stream;

  ServerAvailabilityStatus get currentStatus => _currentStatus;
  bool get isMonitoring => _isMonitoring;

  bool get shouldShowOfflineGate {
    if (!_isMonitoring || _currentStatus != ServerAvailabilityStatus.offline) {
      return false;
    }
    if (_awaitingInitialConnection &&
        !_initialConnectionGraceExpired &&
        !_hasEverBeenOnline) {
      return false;
    }
    return true;
  }

  void startMonitoring({
    ServerAvailabilityStatus initialStatus = ServerAvailabilityStatus.online,
    bool awaitingInitialConnection = false,
  }) {
    _isMonitoring = true;
    _awaitingInitialConnection = awaitingInitialConnection;
    _initialConnectionGraceExpired = !awaitingInitialConnection;
    _hasEverBeenOnline = initialStatus == ServerAvailabilityStatus.online;
    _cancelInitialConnectionGraceTimer();
    if (awaitingInitialConnection) {
      _initialConnectionGraceTimer = Timer(
        initialConnectionGracePeriod,
        _handleInitialConnectionGraceExpired,
      );
    }
    _update(initialStatus, force: true);
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _awaitingInitialConnection = false;
    _initialConnectionGraceExpired = false;
    _hasEverBeenOnline = false;
    _cancelInitialConnectionGraceTimer();
    _update(ServerAvailabilityStatus.offline, force: true);
  }

  void markOnline() {
    if (!_isMonitoring) {
      return;
    }
    _hasEverBeenOnline = true;
    _awaitingInitialConnection = false;
    _initialConnectionGraceExpired = true;
    _cancelInitialConnectionGraceTimer();
    _update(ServerAvailabilityStatus.online);
  }

  void markOffline() {
    if (!_isMonitoring) {
      return;
    }
    _update(ServerAvailabilityStatus.offline);
  }

  void _handleInitialConnectionGraceExpired() {
    if (!_isMonitoring || !_awaitingInitialConnection || _hasEverBeenOnline) {
      return;
    }
    _initialConnectionGraceExpired = true;
    _notifyGateVisibilityChanged();
  }

  void _cancelInitialConnectionGraceTimer() {
    _initialConnectionGraceTimer?.cancel();
    _initialConnectionGraceTimer = null;
  }

  void _notifyGateVisibilityChanged() {
    if (!_controller.isClosed) {
      _controller.add(_currentStatus);
    }
  }

  void _update(ServerAvailabilityStatus status, {bool force = false}) {
    if (!force && _currentStatus == status) {
      return;
    }
    _currentStatus = status;
    if (!_controller.isClosed) {
      _controller.add(status);
    }
  }

  void dispose() {
    _cancelInitialConnectionGraceTimer();
    _controller.close();
  }
}
