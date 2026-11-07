import 'package:flutter/foundation.dart';

class ApiConfig {
  ApiConfig._();

  /// The deployed backend. Used unless overridden below.
  static const String defaultBaseUrl =
      'https://mycar-backend-r5p3.onrender.com';

  /// Override at build/run time with:
  /// flutter run --dart-define=API_BASE_URL=http://192.168.1.50:3000
  static const String _dartDefine = String.fromEnvironment('API_BASE_URL');

  static String? _testOverride;

  /// Points every [ApiClient]/[SocketClient] built afterwards at [url]
  /// (e.g. a local fake server). Pass null to restore the default. Tests
  /// that set this must reset it in `tearDown`.
  @visibleForTesting
  static set baseUrlOverride(String? url) => _testOverride = url;

  static String get baseUrl =>
      resolveBaseUrl(testOverride: _testOverride, dartDefine: _dartDefine);

  /// Precedence: test override > `--dart-define=API_BASE_URL` > [defaultBaseUrl].
  @visibleForTesting
  static String resolveBaseUrl({
    String? testOverride,
    String dartDefine = _dartDefine,
  }) {
    if (testOverride != null && testOverride.isNotEmpty) return testOverride;
    if (dartDefine.isNotEmpty) return dartDefine;
    return defaultBaseUrl;
  }
}
