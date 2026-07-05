enum RealtimeConnectionStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
}

extension RealtimeConnectionStatusX on RealtimeConnectionStatus {
  bool get isConnected => this == RealtimeConnectionStatus.connected;

  bool get allowsManualReconnect =>
      this == RealtimeConnectionStatus.reconnecting ||
      this == RealtimeConnectionStatus.disconnected;
}
