import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth/api_auth_repository.dart';
import 'auth/auth_repository.dart';
import 'auth/profile_photo_store.dart';
import 'auth/session.dart';
import 'network/api_client.dart';
import 'network/socket_client.dart';
import 'notifications/notification_service.dart';
import '../modules/roadside/data/repositories/api_roadside_repository.dart';
import '../modules/roadside/data/repositories/roadside_repository.dart';
import '../modules/home/presentation/pages/settingsScreen/app_settings_store.dart';

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

  /// Settings-screen preferences (same secure storage as [session]).
  late final AppSettingsStore settings = AppSettingsStore();

  /// The user's on-device profile picture (no backend avatar endpoint).
  final ProfilePhotoStore profilePhoto = ProfilePhotoStore();

  Future<void> init() async {
    await session.load();
    await profilePhoto.load();
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

  /// Ends the session: drops the live socket, then wipes the token, the
  /// cached profile and the per-account preferences (all in secure storage,
  /// cleared by [Session.clear]) plus the on-device profile photo.
  ///
  /// Not undone server-side: the backend has no logout or FCM-token removal
  /// endpoint, so the issued JWT stays valid until it expires and push
  /// notifications keep targeting this device until another login replaces
  /// the token.
  Future<void> logout() async {
    socketClient.disconnect();
    // The photo disappears from memory at once; its on-disk copy is removed
    // in the background so a slow prefs write never holds up the logout.
    unawaited(profilePhoto.clear());
    await authRepository.logout();
  }
}
