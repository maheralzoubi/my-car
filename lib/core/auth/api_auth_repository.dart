import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'auth_repository.dart';
import 'session.dart';

/// An [ApiException] raised by the auth flow when there is no server-provided
/// message to show. [l10nKey] names the localized text for the UI (the
/// inherited English [message] stays as the developer-facing fallback).
class AuthException extends ApiException {
  AuthException(super.message, {required this.l10nKey, super.statusCode});

  final String l10nKey;
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._apiClient, this._session);

  final ApiClient _apiClient;
  final Session _session;
  static const _role = 'customer';

  @override
  Future<void> login(String email, String password) async {
    try {
      final response = await _apiClient.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
        'role': _role,
      });
      await _persist(response.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      final response = await _apiClient.dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'role': _role,
        'name': name,
        'phone': phone,
      });
      await _persist(response.data);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<void> logout() => _session.clear();

  /// Validates the `{accessToken, user: {id, name, email, phone}}` body before
  /// touching the session, so a malformed reply surfaces as an
  /// [ApiException] (which the UI handles) instead of a [TypeError].
  Future<void> _persist(Object? data) async {
    final body = data is Map ? data : null;
    final user = body?['user'];
    final token = body?['accessToken'];
    if (user is! Map || token is! String || token.isEmpty) {
      throw _badResponse();
    }
    final id = user['id'];
    final name = user['name'];
    final email = user['email'];
    final phone = user['phone'];
    if (id is! String || name is! String || email is! String) {
      throw _badResponse();
    }
    await _session.save(
      token: token,
      userId: id,
      role: _role,
      name: name,
      email: email,
      // Optional on the backend schema; never fail a login over it.
      phone: phone is String ? phone : '',
    );
  }

  static AuthException _badResponse() => AuthException(
        'Unexpected response from the server. Please try again.',
        l10nKey: 'auth_err_bad_response',
      );

  /// A NestJS error `message` from the server wins (shown as-is, like
  /// [mapDioException]); every other failure gets a localizable key.
  static ApiException _mapError(DioException e) {
    final mapped = mapDioException(e);
    if (_hasBackendMessage(e.response?.data)) return mapped;
    return AuthException(
      mapped.message,
      l10nKey: _l10nKeyFor(e),
      statusCode: mapped.statusCode,
    );
  }

  static bool _hasBackendMessage(Object? data) {
    if (data is! Map) return false;
    final raw = data['message'];
    if (raw == null) return false;
    final message = raw is List ? raw.join(', ') : raw.toString();
    return message.trim().isNotEmpty;
  }

  static String _l10nKeyFor(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'auth_err_timeout';
      case DioExceptionType.connectionError:
        return 'auth_err_offline';
      case DioExceptionType.badCertificate:
        return 'auth_err_tls';
      case DioExceptionType.cancel:
        return 'auth_err_cancelled';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 401) return 'auth_err_unauthorized';
        if (status == 403) return 'auth_err_forbidden';
        if (status == 404) return 'auth_err_not_found';
        if (status != null && status >= 500) return 'auth_err_server';
        return 'auth_err_generic';
      default:
        return 'auth_err_generic';
    }
  }
}
