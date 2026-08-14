import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'auth_repository.dart';
import 'session.dart';

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
      await _persist(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
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
      await _persist(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> logout() => _session.clear();

  Future<void> _persist(Map<String, dynamic> data) async {
    final user = data['user'] as Map<String, dynamic>;
    await _session.save(
      token: data['accessToken'] as String,
      userId: user['id'] as String,
      role: _role,
      name: user['name'] as String,
      email: user['email'] as String,
      phone: user['phone'] as String,
    );
  }
}
