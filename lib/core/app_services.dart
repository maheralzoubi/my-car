import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth/api_auth_repository.dart';
import 'auth/auth_repository.dart';
import 'auth/profile_photo_store.dart';
import 'auth/session.dart';
import 'network/api_client.dart';
import 'network/socket_client.dart';
import 'notifications/notification_service.dart';
import 'theme/theme_controller.dart';
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
  late final AuthRepository authRepository = ApiAuthRepository(
    apiClient,
    session,
  );
  late final RoadsideRepository roadsideRepository = ApiRoadsideRepository(
    apiClient,
    socketClient,
  );

  /// Settings-screen preferences (same secure storage as [session]).
  late final AppSettingsStore settings = AppSettingsStore();

  /// App-wide Light / Dark / System choice, persisted in [settings].
  late final ThemeController theme = ThemeController(
    read: settings.readThemeMode,
    write: settings.writeThemeMode,
  );

  /// The user's on-device profile picture (no backend avatar endpoint).
  final ProfilePhotoStore profilePhoto = ProfilePhotoStore();

  Future<void>? _ready;

  /// Completes once the saved theme, session and profile photo are loaded.
  /// Loading starts on first access and runs once; it never throws.
  ///
  /// main() calls [start] and draws the first frame right away — nothing
  /// here may block startup. The session loads first; the splash screen
  /// waits for `session.loaded` (not for all of this) before it decides
  /// between sign-in and the app. Push registration is NOT awaited: it can
  /// wait on a permission dialog or the network, so it runs in the
  /// background.
  Future<void> get ready => _ready ??= _load();

  /// Kicks off [ready] without waiting for it.
  void start() => unawaited(ready);

  /// Same as [ready] (kept for existing callers).
  Future<void> init() => ready;

  Future<void> _load() async {
    // Session first: the splash is waiting on it.
    try {
      await session.load();
    } catch (_) {
      // Unreadable storage = signed out; the user can sign in again.
    }
    for (final step in <Future<void> Function()>[
      theme.load,
      profilePhoto.load,
    ]) {
      try {
        await step();
      } catch (_) {
        // A storage failure must not stop the app from starting; the
        // affected preference just falls back to its default.
      }
    }
    if (session.isLoggedIn) {
      socketClient.connect();
      unawaited(registerPushNotifications());
    }
  }

  /// Call after login/signup succeeds (and on startup if already logged in).
  /// Safe to call repeatedly — no-ops after the first successful init.
  Future<void> registerPushNotifications() async {
    await NotificationService.instance.init(
      onToken: (token) async {
        try {
          await apiClient.dio.post(
            '/users/me/fcm-token',
            data: {'token': token},
          );
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
    // Logout wipes secure storage (per-account preferences). The Light / Dark
    // / System choice is a device preference, so write it back.
    if (theme.value != ThemeMode.system) {
      await settings.writeThemeMode(theme.value.name);
    }
  }
}
