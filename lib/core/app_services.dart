import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth/api_auth_repository.dart';
import 'auth/auth_repository.dart';
import 'auth/session.dart';
import 'network/api_client.dart';
import 'network/socket_client.dart';
import 'notifications/notification_service.dart';
import '../modules/roadside/data/repositories/api_roadside_repository.dart';
import '../modules/roadside/data/repositories/roadside_repository.dart';

/// Wires the backend-facing singletons (session, HTTP client, socket
/// connection, repositories) once for the whole app.
class AppServices {
  AppServices._();

  static final AppServices instance = AppServices._();

  final Session session = Session(const FlutterSecureStorage());
  late final ApiClient apiClient = ApiClient(session);
  late final SocketClient socketClient = SocketClient(session);
  late final AuthRepository authRepository = ApiAuthRepository(apiClient, session);
  late final RoadsideRepository roadsideRepository =
      ApiRoadsideRepository(apiClient, socketClient);

  Future<void> init() async {
    await session.load();
    if (session.isLoggedIn) {
      socketClient.connect();
      await registerPushNotifications();
    }
  }

  /// Call after login/signup succeeds (and on startup if already logged in).
  /// Safe to call repeatedly — no-ops after the first successful init.
  Future<void> registerPushNotifications() async {
    await NotificationService.instance.init(
      onToken: (token) async {
        try {
          await apiClient.dio.post('/users/me/fcm-token', data: {'token': token});
        } catch (_) {
          // Non-fatal — live updates still work over Socket.IO while open.
        }
      },
    );
  }

  Future<void> logout() async {
    socketClient.disconnect();
    await authRepository.logout();
  }
}
