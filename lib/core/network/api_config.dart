import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  ApiConfig._();

  /// Override at build/run time with:
  /// flutter run --dart-define=API_BASE_URL=http://192.168.1.50:3000
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:3000';
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }
}
