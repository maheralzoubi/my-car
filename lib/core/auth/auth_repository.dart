abstract class AuthRepository {
  Future<void> login(String email, String password);

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String phone,
  });

  Future<void> logout();
}
