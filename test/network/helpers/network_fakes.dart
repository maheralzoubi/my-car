import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// A base URL that can never resolve (`.invalid` is reserved by RFC 2606),
/// so even a bug that bypassed the fakes could not reach a real server.
const testBaseUrl = 'https://api.mycar.invalid';

// ─────────────────────────────────────────────────────────────────────────────
// Secure storage.
// ─────────────────────────────────────────────────────────────────────────────

/// In-memory [FlutterSecureStorage]; records every call so tests can assert
/// what was persisted/wiped without a platform channel.
class FakeSecureStorage implements FlutterSecureStorage {
  FakeSecureStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;
  final List<String> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    final key = invocation.namedArguments[#key] as String?;
    if (name == #read) {
      calls.add('read:$key');
      return Future<String?>.value(values[key]);
    }
    if (name == #write) {
      calls.add('write:$key');
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        values.remove(key);
      } else {
        values[key!] = value;
      }
      return Future<void>.value();
    }
    if (name == #delete) {
      calls.add('delete:$key');
      values.remove(key);
      return Future<void>.value();
    }
    if (name == #deleteAll) {
      calls.add('deleteAll');
      values.clear();
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP transport.
// ─────────────────────────────────────────────────────────────────────────────

typedef FakeHandler = FutureOr<ResponseBody> Function(RequestOptions options);

/// Dio transport that never leaves the process. Every request is recorded;
/// [handler] decides the reply (default: 200 `{}`), and may throw to simulate
/// transport failures.
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter([FakeHandler? handler]) : handler = handler ?? ((_) => json(200, const {}));

  FakeHandler handler;
  final List<RequestOptions> requests = [];

  static ResponseBody json(int status, [Object? body]) => ResponseBody.fromString(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Socket.IO.
// ─────────────────────────────────────────────────────────────────────────────

/// Stands in for a Socket.IO socket: records the lifecycle calls
/// [SocketClient] makes and keeps a real listener registry, cleared on
/// [dispose] exactly like the real `Socket.dispose()` does.
class FakeSocket implements io.Socket {
  FakeSocket(this.url, this.options);

  final String url;
  final Map<String, dynamic> options;

  int connectCalls = 0;
  int disposeCalls = 0;
  final Map<String, List<dynamic Function(dynamic)>> handlers = {};

  bool get disposed => disposeCalls > 0;

  /// The `auth` payload the real client would send in its CONNECT packet.
  Object? get handshakeAuth => options['auth'];

  int get totalHandlers => handlers.values.fold(0, (sum, l) => sum + l.length);

  @override
  io.Socket connect() {
    connectCalls++;
    return this;
  }

  @override
  void dispose() {
    disposeCalls++;
    handlers.clear();
  }

  @override
  void on(String event, dynamic Function(dynamic) handler) {
    handlers.putIfAbsent(event, () => []).add(handler);
  }

  @override
  void off(String event, [dynamic Function(dynamic)? handler]) {
    if (handler == null) {
      handlers.remove(event);
    } else {
      handlers[event]?.remove(handler);
      if (handlers[event]?.isEmpty ?? false) handlers.remove(event);
    }
  }

  void serverEmit(String event, Object? data) {
    for (final h in List.of(handlers[event] ?? const <dynamic Function(dynamic)>[])) {
      h(data);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('FakeSocket: ${invocation.memberName} not faked');
}

/// A `SocketFactory` that hands out [FakeSocket]s and remembers each one.
class FakeSocketFactory {
  final List<FakeSocket> created = [];

  FakeSocket get last => created.last;

  io.Socket call(String url, Map<String, dynamic> options) {
    final socket = FakeSocket(url, options);
    created.add(socket);
    return socket;
  }
}
