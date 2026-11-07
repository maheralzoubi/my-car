import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/auth/session.dart';
import 'package:mycar/core/network/api_client.dart';
import 'package:mycar/core/network/api_exception.dart';

import 'helpers/network_fakes.dart';

void main() {
  late FakeSecureStorage storage;
  late Session session;
  late RecordingAdapter http;
  late ApiClient client;

  Future<void> login(String token) => session.save(
        token: token,
        userId: 'u1',
        role: 'customer',
        name: 'Maher',
        email: 'm@example.com',
        phone: '+966500000000',
      );

  setUp(() {
    storage = FakeSecureStorage();
    session = Session(storage);
    http = RecordingAdapter();
    client = ApiClient(session, baseUrl: testBaseUrl, httpClientAdapter: http);
  });

  group('construction', () {
    test('uses the injected base URL and transport', () async {
      await client.dio.get('/ping');
      expect(http.requests.single.uri.toString(), '$testBaseUrl/ping');
    });

    test('every timeout is bounded', () {
      final o = client.dio.options;
      expect(o.connectTimeout, ApiClient.timeout);
      expect(o.sendTimeout, ApiClient.timeout);
      expect(o.receiveTimeout, ApiClient.timeout);
      expect(ApiClient.timeout, greaterThan(Duration.zero));
    });
  });

  group('auth interceptor', () {
    test('no Authorization header while logged out', () async {
      await client.dio.get('/ping');
      expect(http.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('sends Bearer <token> while logged in', () async {
      await login('tok-1');
      await client.dio.get('/ping');
      expect(http.requests.single.headers['Authorization'], 'Bearer tok-1');
    });

    test('token is read per request: login, re-login and logout apply immediately', () async {
      await client.dio.get('/a');
      await login('tok-1');
      await client.dio.get('/b');
      await login('tok-2');
      await client.dio.get('/c');
      await session.clear();
      await client.dio.get('/d');

      final auth = http.requests.map((r) => r.headers['Authorization']).toList();
      expect(auth, [null, 'Bearer tok-1', 'Bearer tok-2', null]);
    });

    test('token restored from secure storage on startup is sent', () async {
      final restored = Session(FakeSecureStorage({'auth_token': 'persisted'}));
      await restored.load();
      final c = ApiClient(restored, baseUrl: testBaseUrl, httpClientAdapter: http);
      await c.dio.post('/x', data: {'a': 1});
      expect(http.requests.single.headers['Authorization'], 'Bearer persisted');
    });

    test('is not sent to absolute URLs on other origins', () async {
      await login('tok-1');
      await client.dio.get('https://cdn.example.invalid/photo.jpg');
      await client.dio.get('http://api.mycar.invalid/downgraded'); // same host, other scheme
      await client.dio.get('https://api.mycar.invalid:8443/other-port');
      for (final r in http.requests) {
        expect(r.headers.containsKey('Authorization'), isFalse, reason: r.uri.toString());
      }
    });

    test('is sent to absolute URLs on the API origin', () async {
      await login('tok-1');
      await client.dio.get('$testBaseUrl/users/me');
      expect(http.requests.single.headers['Authorization'], 'Bearer tok-1');
    });

    test('Authorization never appears in the DioException message', () async {
      await login('secret-token');
      http.handler = (_) => RecordingAdapter.json(500);
      try {
        await client.dio.get('/boom');
        fail('expected a DioException');
      } on DioException catch (e) {
        expect(e.toString(), isNot(contains('secret-token')));
        expect(mapDioException(e).toString(), isNot(contains('secret-token')));
      }
    });
  });

  group('401 behavior (documented: no refresh, no auto-logout)', () {
    test('401 surfaces as ApiException(statusCode: 401) and the token is kept', () async {
      await login('expired');
      http.handler = (_) => RecordingAdapter.json(401, {'statusCode': 401, 'message': 'Unauthorized'});

      final error = await client.dio.get('/service-requests/history').then<Object?>(
            (_) => null,
            onError: (Object e) => mapDioException(e as DioException),
          );

      expect(error, isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401));
      expect((error! as ApiException).message, 'Unauthorized');
      expect(http.requests, hasLength(1), reason: 'no retry / refresh request');
      expect(session.token, 'expired');
      expect(session.isLoggedIn, isTrue);
      expect(storage.values['auth_token'], 'expired');
      expect(storage.calls, isNot(contains('deleteAll')));
    });

    test('401 without a body still maps to a user-facing message', () async {
      await login('expired');
      http.handler = (_) => RecordingAdapter.json(401);
      try {
        await client.dio.get('/x');
        fail('expected a DioException');
      } on DioException catch (e) {
        final mapped = mapDioException(e);
        expect(mapped.statusCode, 401);
        expect(mapped.message, 'Authentication failed. Please log in again.');
      }
    });
  });

  group('end-to-end error mapping through the client', () {
    Future<ApiException> failWith(FakeHandler handler) async {
      http.handler = handler;
      try {
        await client.dio.get('/x');
      } on DioException catch (e) {
        return mapDioException(e);
      }
      throw StateError('request unexpectedly succeeded');
    }

    test('transport connection error', () async {
      final e = await failWith((o) => throw DioException.connectionError(requestOptions: o, reason: 'lookup failed'));
      expect(e.message, contains('Could not reach the server'));
      expect(e.statusCode, isNull);
    });

    test('non-Dio transport failure is wrapped, not leaked', () async {
      final e = await failWith((_) => throw const FormatException('raw socket junk'));
      expect(e.message, 'Something went wrong. Please try again.');
    });

    test('HTML error page from a proxy (non-JSON body) gets a friendly message', () async {
      final e = await failWith((_) => ResponseBody.fromString(
            '<html>Bad gateway</html>',
            502,
            headers: {
              Headers.contentTypeHeader: ['text/html'],
            },
          ));
      expect(e.statusCode, 502);
      expect(e.message, 'The server is having trouble right now. Please try again shortly.');
    });
  });
}
