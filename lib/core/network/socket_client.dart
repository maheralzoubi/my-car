import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/session.dart';
import 'api_config.dart';

/// Long-lived Socket.IO connection, opened once after login and reused by
/// every repository that needs realtime events (roadside tracking, driver
/// job offers, etc).
class SocketClient {
  SocketClient(this._session);

  final Session _session;
  io.Socket? _socket;

  io.Socket get socket {
    final current = _socket;
    if (current == null) {
      throw StateError('SocketClient.connect() must be called before use');
    }
    return current;
  }

  io.Socket connect() {
    disconnect();
    final socket = io.io(
      ApiConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': _session.token})
          .disableAutoConnect()
          .build(),
    );
    socket.connect();
    _socket = socket;
    return socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
