import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/session.dart';
import 'api_config.dart';

/// Builds a (not yet connected) Socket.IO socket for [url] with [options].
/// Defaults to `io.io`; tests inject a fake so nothing touches the network.
typedef SocketFactory =
    io.Socket Function(String url, Map<String, dynamic> options);

io.Socket _defaultSocketFactory(String url, Map<String, dynamic> options) =>
    io.io(url, options);

/// Long-lived Socket.IO connection, opened once after login and reused by
/// every repository that needs realtime events (roadside tracking, driver
/// job offers, etc).
///
/// Every [connect] disposes the previous socket (which also drops all of its
/// listeners) and builds a brand-new one that authenticates with the
/// session's *current* token. Listeners registered on the old socket are not
/// carried over — callers must re-subscribe on [socket] after a reconnect.
class SocketClient {
  SocketClient(this._session, {SocketFactory? socketFactory, String? baseUrl})
    : _socketFactory = socketFactory ?? _defaultSocketFactory,
      _baseUrl = baseUrl;

  final Session _session;
  final SocketFactory _socketFactory;
  final String? _baseUrl;
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
    final socket = _socketFactory(
      _baseUrl ?? ApiConfig.baseUrl,
      buildOptions(_session.token),
    );
    socket.connect();
    _socket = socket;
    return socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  /// Handshake options for a socket authenticating with [token].
  ///
  /// `forceNew` is essential: without it `io.io` reuses the Manager cached
  /// for this host *and* the Socket already registered for the `/`
  /// namespace — even after `dispose()` — so a reconnect after
  /// logout/login would silently hand back the old socket still carrying
  /// the previous user's token.
  @visibleForTesting
  static Map<String, dynamic> buildOptions(String? token) => io.OptionBuilder()
      .setTransports(['websocket'])
      .setAuth({'token': token})
      .disableAutoConnect()
      .enableForceNew()
      .build();
}
