import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/auth/session.dart';
import 'package:mycar/core/network/api_client.dart';
import 'package:mycar/core/network/api_config.dart';
import 'package:mycar/core/network/socket_client.dart';

import 'helpers/network_fakes.dart';

void main() {
  tearDown(() => ApiConfig.baseUrlOverride = null);

  group('ApiConfig.resolveBaseUrl', () {
    test('defaults to the deployed backend over HTTPS', () {
      expect(ApiConfig.resolveBaseUrl(dartDefine: ''), ApiConfig.defaultBaseUrl);
      expect(Uri.parse(ApiConfig.defaultBaseUrl).scheme, 'https');
    });

    test('--dart-define=API_BASE_URL beats the default', () {
      expect(ApiConfig.resolveBaseUrl(dartDefine: 'http://10.0.2.2:3000'), 'http://10.0.2.2:3000');
    });

    test('test override beats --dart-define', () {
      expect(
        ApiConfig.resolveBaseUrl(testOverride: testBaseUrl, dartDefine: 'http://10.0.2.2:3000'),
        testBaseUrl,
      );
    });

    test('an empty test override is ignored', () {
      expect(ApiConfig.resolveBaseUrl(testOverride: '', dartDefine: ''), ApiConfig.defaultBaseUrl);
    });
  });

  group('ApiConfig.baseUrlOverride', () {
    test('test runs (no dart-define) use the default until overridden', () {
      expect(ApiConfig.baseUrl, ApiConfig.defaultBaseUrl);
    });

    test('override is picked up by baseUrl and reset by null', () {
      ApiConfig.baseUrlOverride = testBaseUrl;
      expect(ApiConfig.baseUrl, testBaseUrl);
      ApiConfig.baseUrlOverride = null;
      expect(ApiConfig.baseUrl, ApiConfig.defaultBaseUrl);
    });

    test('ApiClient and SocketClient built after an override target it', () {
      ApiConfig.baseUrlOverride = testBaseUrl;
      final session = Session(FakeSecureStorage());
      expect(ApiClient(session).dio.options.baseUrl, testBaseUrl);

      final sockets = FakeSocketFactory();
      SocketClient(session, socketFactory: sockets.call).connect();
      expect(sockets.last.url, testBaseUrl);
    });

    test('explicit constructor baseUrl beats the global override', () {
      ApiConfig.baseUrlOverride = 'https://other.invalid';
      final session = Session(FakeSecureStorage());
      expect(ApiClient(session, baseUrl: testBaseUrl).dio.options.baseUrl, testBaseUrl);

      final sockets = FakeSocketFactory();
      SocketClient(session, socketFactory: sockets.call, baseUrl: testBaseUrl).connect();
      expect(sockets.last.url, testBaseUrl);
    });
  });
}
