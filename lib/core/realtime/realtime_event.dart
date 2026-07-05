/// 文件输入：实时事件类型、事件负载
/// 文件职责：统一表达实时消息对象，用于 WebSocket 事件传递
/// 文件对外接口：RealtimeEvent
/// 文件包含：RealtimeEvent, RealtimeEventType
enum RealtimeEventType {
  relayCreated,
  relayUpdated,
  transferUpdated,
  connectionStatus,
  unknown;

  static RealtimeEventType fromString(String value) {
    switch (value) {
      case 'relay.created':
        return RealtimeEventType.relayCreated;
      case 'relay.updated':
        return RealtimeEventType.relayUpdated;
      case 'transfer.updated':
        return RealtimeEventType.transferUpdated;
      case 'connection.status':
        return RealtimeEventType.connectionStatus;
      default:
        return RealtimeEventType.unknown;
    }
  }

  String get value {
    switch (this) {
      case RealtimeEventType.relayCreated:
        return 'relay.created';
      case RealtimeEventType.relayUpdated:
        return 'relay.updated';
      case RealtimeEventType.transferUpdated:
        return 'transfer.updated';
      case RealtimeEventType.connectionStatus:
        return 'connection.status';
      case RealtimeEventType.unknown:
        return 'unknown';
    }
  }
}

class RealtimeEvent {
  final RealtimeEventType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const RealtimeEvent({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final typeString = json['event'] as String? ?? '';
    return RealtimeEvent(
      type: RealtimeEventType.fromString(typeString),
      data: json['data'] as Map<String, dynamic>? ?? {},
      timestamp: DateTime.now(),
    );
  }

  String? get recordId => data['recordId'] as String?;
  String? get taskId => data['taskId'] as String?;
  String? get status => data['status'] as String?;
}
