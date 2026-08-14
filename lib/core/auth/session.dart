import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the current logged-in user's auth token and profile in memory,
/// persisted to secure storage so it survives app restarts.
class Session {
  Session(this._storage);

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _roleKey = 'auth_role';
  static const _nameKey = 'auth_name';
  static const _emailKey = 'auth_email';
  static const _phoneKey = 'auth_phone';

  String? _token;
  String? _userId;
  String? _role;
  String? _name;
  String? _email;
  String? _phone;

  String? get token => _token;
  String? get userId => _userId;
  String? get role => _role;
  String? get name => _name;
  String? get email => _email;
  String? get phone => _phone;
  bool get isLoggedIn => _token != null;

  Future<void> load() async {
    _token = await _storage.read(key: _tokenKey);
    _userId = await _storage.read(key: _userIdKey);
    _role = await _storage.read(key: _roleKey);
    _name = await _storage.read(key: _nameKey);
    _email = await _storage.read(key: _emailKey);
    _phone = await _storage.read(key: _phoneKey);
  }

  Future<void> save({
    required String token,
    required String userId,
    required String role,
    required String name,
    required String email,
    required String phone,
  }) async {
    _token = token;
    _userId = userId;
    _role = role;
    _name = name;
    _email = email;
    _phone = phone;

    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _userIdKey, value: userId),
      _storage.write(key: _roleKey, value: role),
      _storage.write(key: _nameKey, value: name),
      _storage.write(key: _emailKey, value: email),
      _storage.write(key: _phoneKey, value: phone),
    ]);
  }

  Future<void> clear() async {
    _token = null;
    _userId = null;
    _role = null;
    _name = null;
    _email = null;
    _phone = null;
    await _storage.deleteAll();
  }
}
