import 'dart:io';

typedef RouteProbeSocketConnector =
    Future<RouteProbeSocket> Function({
      required String host,
      required int port,
      required Duration timeout,
    });

abstract interface class RouteProbeSocket {
  InternetAddress get localAddress;

  InternetAddress get remoteAddress;

  void close();
}

class ClientRouteIpService {
  ClientRouteIpService({
    RouteProbeSocketConnector? socketConnector,
    Duration timeout = const Duration(seconds: 2),
  }) : _socketConnector = socketConnector ?? _defaultSocketConnector,
       _timeout = timeout;

  final RouteProbeSocketConnector _socketConnector;
  final Duration _timeout;

  Future<String?> resolveRouteIpForBaseUrl(String baseUrl) async {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) {
      return null;
    }
    return resolveRouteIp(uri);
  }

  Future<String?> resolveRouteIp(Uri serverUri) async {
    final host = serverUri.host.trim();
    if (host.isEmpty) {
      return null;
    }

    final probedRouteIp = await _probeRouteIp(serverUri, host: host);
    if (probedRouteIp != null) {
      return probedRouteIp;
    }
    return _resolveFromNetworkInterfaces(host);
  }

  Future<String?> _probeRouteIp(Uri serverUri, {required String host}) async {
    try {
      final socket = await _socketConnector(
        host: host,
        port: _resolvePort(serverUri),
        timeout: _timeout,
      );
      final localAddress = _normalizeIp(socket.localAddress.address);
      final remoteAddress = _normalizeIp(socket.remoteAddress.address);
      socket.close();
      if (!_isUsableRouteIp(
        localAddress,
        serverHost: host,
        remoteHost: remoteAddress,
      )) {
        return null;
      }
      return localAddress;
    } catch (_) {
      return null;
    }
  }

  static Future<RouteProbeSocket> _defaultSocketConnector({
    required String host,
    required int port,
    required Duration timeout,
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    return _SocketRouteProbe(socket);
  }

  int _resolvePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    switch (uri.scheme.toLowerCase()) {
      case 'https':
      case 'wss':
        return 443;
      default:
        return 80;
    }
  }

  Future<String?> _resolveFromNetworkInterfaces(String serverHost) async {
    final serverAddress = InternetAddress.tryParse(serverHost);
    if (serverAddress == null ||
        serverAddress.type != InternetAddressType.IPv4) {
      return null;
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final candidate = _normalizeIp(address.address);
          if (!_isUsableRouteIp(
            candidate,
            serverHost: serverHost,
            remoteHost: serverHost,
          )) {
            continue;
          }
          if (_sharesIpv4LanSubnet(candidate, serverHost)) {
            return candidate;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static bool _isUsableRouteIp(
    String routeIp, {
    required String serverHost,
    required String remoteHost,
  }) {
    final normalized = routeIp.trim();
    if (normalized.isEmpty ||
        normalized == '0.0.0.0' ||
        normalized == '127.0.0.1' ||
        normalized == '::1') {
      return false;
    }
    final normalizedServerHost = serverHost.trim();
    if (normalizedServerHost.isNotEmpty && normalized == normalizedServerHost) {
      return false;
    }
    if (normalized == remoteHost.trim()) {
      return false;
    }
    return true;
  }

  static bool _sharesIpv4LanSubnet(String left, String right) {
    final leftParts = left.split('.');
    final rightParts = right.split('.');
    if (leftParts.length != 4 || rightParts.length != 4) {
      return false;
    }
    return leftParts[0] == rightParts[0] &&
        leftParts[1] == rightParts[1] &&
        leftParts[2] == rightParts[2];
  }

  String _normalizeIp(String rawAddress) {
    final normalized = rawAddress.trim();
    if (normalized.startsWith('::ffff:')) {
      return normalized.substring(7);
    }
    return normalized;
  }
}

class _SocketRouteProbe implements RouteProbeSocket {
  _SocketRouteProbe(this._socket);

  final Socket _socket;

  @override
  InternetAddress get localAddress => _socket.address;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  void close() {
    _socket.destroy();
  }
}
