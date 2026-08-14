class ApiConfig {
  ApiConfig._();

  /// Override at build/run time with:
  /// flutter run --dart-define=API_BASE_URL=http://192.168.1.50:3000
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    return 'https://mycar-backend-r5p3.onrender.com';
  }
}
