import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/auth/session.dart';
import 'package:mycar/core/network/api_config.dart';
import 'package:mycar/core/network/socket_client.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'helpers/network_fakes.dart';

void main() {
  late Session session;
  late FakeSocketFactory sockets;
  late SocketClient client;

  Future<void> login(String token) => session.save(
        token: token,
        userId: 'u1',
        role: 'customer',
        name: 'Maher',
        email: 'm@example.com',
        phone: '+966500000000',
      );

  setUp(() {
    session = Session(FakeSecureStorage());
    sockets = FakeSocketFactory();
    client = SocketClient(session, socketFactory: sockets.call, baseUrl: testBaseUrl);
  });

  group('connect', () {
    test('socket getter throws before connect()', () {
      expect(() => client.socket, throwsStateError);
      expect(sockets.created, isEmpty, reason: 'nothing is built lazily');
    });

    test('builds one socket against the base URL and connects it', () async {
      await login('tok-1');
      final socket = client.connect();

      expect(sockets.created, hasLength(1));
      expect(identical(socket, sockets.last), isTrue);
      expect(identical(client.socket, socket), isTrue);
      expect(sockets.last.url, testBaseUrl);
      expect(sockets.last.connectCalls, 1);
    });

    test('auth handshake carries the current session token', () async {
      await login('tok-1');
      client.connect();
      expect(sockets.last.handshakeAuth, {'token': 'tok-1'});
    });

    test('handshake options: websocket only, manual connect, never reuse a cached manager', () async {
      await login('tok-1');
      client.connect();
      final o = sockets.last.options;
      expect(o['transports'], ['websocket']);
      expect(o['autoConnect'], isFalse);
      expect(o['forceNew'], isTrue);
    });

    test('token is not leaked into the query string', () async {
      await login('tok-1');
      client.connect();
      expect(sockets.last.options['query'], anyOf(isNull, isNot(contains('tok-1'))));
      expect(sockets.last.url, isNot(contains('tok-1')));
    });

    test('default base URL comes from ApiConfig', () {
      final c = SocketClient(session, socketFactory: sockets.call);
      c.connect();
      expect(sockets.last.url, ApiConfig.baseUrl);
    });
  });

  group('reconnect', () {
    test('disposes the previous socket and authenticates the new one with the fresh token', () async {
      await login('tok-A');
      final first = client.connect() as FakeSocket;

      await session.clear();
      await login('tok-B');
      final second = client.connect() as FakeSocket;

      expect(identical(first, second), isFalse);
      expect(first.disposeCalls, 1);
      expect(second.disposed, isFalse);
      expect(first.handshakeAuth, {'token': 'tok-A'});
      expect(second.handshakeAuth, {'token': 'tok-B'});
      expect(identical(client.socket, second), isTrue);
    });

    test('listeners on the old socket are dropped, not carried over', () async {
      await login('tok-A');
      final first = client.connect() as FakeSocket;
      var calls = 0;
      first.on('status-changed', (_) => calls++);

      final second = client.connect() as FakeSocket;

      expect(first.totalHandlers, 0, reason: 'dispose() clears listeners');
      expect(second.totalHandlers, 0, reason: 'subscribers must re-register on the new socket');
      first.serverEmit('status-changed', {});
      second.serverEmit('status-changed', {});
      expect(calls, 0);
    });

    test('repeated connects never leave more than one live socket', () async {
      await login('tok');
      for (var i = 0; i < 5; i++) {
        client.connect();
      }
      final live = sockets.created.where((s) => !s.disposed);
      expect(live, hasLength(1));
      expect(identical(live.single, client.socket), isTrue);
    });
  });

  group('disconnect', () {
    test('disposes the socket, drops its listeners and resets the getter', () async {
      await login('tok');
      final socket = client.connect() as FakeSocket;
      socket.on('driver-location-update', (_) {});

      client.disconnect();

      expect(socket.disposeCalls, 1);
      expect(socket.totalHandlers, 0);
      expect(() => client.socket, throwsStateError);
    });

    test('is idempotent and safe before connect()', () async {
      client.disconnect();
      await login('tok');
      final socket = client.connect() as FakeSocket;
      client.disconnect();
      client.disconnect();
      expect(socket.disposeCalls, 1);
    });

    test('logout then login connects with the new token', () async {
      await login('tok-A');
      client.connect();
      client.disconnect();
      await session.clear();
      await login('tok-B');
      client.connect();
      expect(sockets.last.handshakeAuth, {'token': 'tok-B'});
    });
  });

  group('event subscription cleanup', () {
    test('on/off pairs leave no handlers behind', () async {
      await login('tok');
      final socket = client.connect() as FakeSocket;
      void handler(dynamic _) {}
      socket
        ..on('driver-assigned', handler)
        ..on('status-changed', handler);
      expect(socket.totalHandlers, 2);
      socket
        ..off('driver-assigned', handler)
        ..off('status-changed', handler);
      expect(socket.totalHandlers, 0);
    });
  });

  group('real socket_io_client (no network: autoConnect is off and connect() is never called)', () {
    // Regression for the io.io() cache: without forceNew it returns the very
    // same Socket for the same host/namespace — even after dispose() — so
    // the second login would handshake with the first user's token.
    const url = 'https://sockets.mycar.invalid';

    test('each build yields a distinct socket with its own token', () {
      final a = io.io(url, SocketClient.buildOptions('tok-A'));
      a.dispose();
      final b = io.io(url, SocketClient.buildOptions('tok-B'));
      addTearDown(b.dispose);

      expect(identical(a, b), isFalse);
      expect(a.auth, {'token': 'tok-A'});
      expect(b.auth, {'token': 'tok-B'});
      expect(b.connected, isFalse);
    });

    test('without forceNew the library hands back the stale socket (why the flag matters)', () {
      Map<String, dynamic> cachedOptions(String token) =>
          io.OptionBuilder().setTransports(['websocket']).setAuth({'token': token}).disableAutoConnect().build();
      const cacheUrl = 'https://cache-demo.mycar.invalid';
      final a = io.io(cacheUrl, cachedOptions('tok-A'));
      a.dispose();
      final b = io.io(cacheUrl, cachedOptions('tok-B'));
      addTearDown(b.dispose);

      expect(identical(a, b), isTrue);
      expect(b.auth, {'token': 'tok-A'});
    });
  });
}
