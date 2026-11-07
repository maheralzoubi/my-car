import 'dart:async';

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
  static const _locationKey = 'auth_location';

  String? _token;
  String? _userId;
  String? _role;
  String? _name;
  String? _email;
  String? _phone;
  String? _location;

  String? get token => _token;
  String? get userId => _userId;
  String? get role => _role;
  String? get name => _name;
  String? get email => _email;
  String? get phone => _phone;

  /// Free-text location the user entered on the edit-profile screen. The
  /// backend has no field for it, so it only ever lives on this device.
  String? get location => _location;
  bool get isLoggedIn => _token != null;

  final Completer<void> _loaded = Completer<void>();

  /// Completes when the first [load] has finished (even if it failed), i.e.
  /// once [isLoggedIn] reflects the saved session. The splash screen waits on
  /// this to choose between sign-in and the app.
  Future<void> get loaded => _loaded.future;

  /// Whether the first [load] has finished (synchronous form of [loaded]).
  bool get isLoaded => _loaded.isCompleted;

  Future<void> load() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      _userId = await _storage.read(key: _userIdKey);
      _role = await _storage.read(key: _roleKey);
      _name = await _storage.read(key: _nameKey);
      _email = await _storage.read(key: _emailKey);
      _phone = await _storage.read(key: _phoneKey);
      _location = await _storage.read(key: _locationKey);
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
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

  /// Updates the locally cached profile fields of the logged-in user.
  ///
  /// The backend exposes no profile-update endpoint (only login/register),
  /// so this changes what the app shows on this device only — the server
  /// copy is untouched and the next login overwrites name/email/phone with
  /// it. Memory is updated first; returns false (instead of throwing) if
  /// secure storage could not persist the change, in which case it lasts
  /// until the app restarts.
  Future<bool> updateProfile({
    required String name,
    required String email,
    required String phone,
    String? location,
  }) async {
    _name = name;
    _email = email;
    _phone = phone;
    _location = (location == null || location.trim().isEmpty) ? null : location;

    try {
      await Future.wait([
        _storage.write(key: _nameKey, value: name),
        _storage.write(key: _emailKey, value: email),
        _storage.write(key: _phoneKey, value: phone),
        if (_location == null)
          _storage.delete(key: _locationKey)
        else
          _storage.write(key: _locationKey, value: _location),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    _token = null;
    _userId = null;
    _role = null;
    _name = null;
    _email = null;
    _phone = null;
    _location = null;
    await _storage.deleteAll();
  }
}
