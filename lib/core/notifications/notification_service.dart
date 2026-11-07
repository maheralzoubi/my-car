import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Must be a top-level (or static) function — the background isolate that
/// invokes this has no access to any app state built up in `main()`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Wires Firebase Cloud Messaging + local notification display for this
/// device. Safe to call `init` even if no Firebase project is configured yet
/// (google-services.json missing) — callers should treat failures as
/// non-fatal, since Socket.IO-based live updates still work while the app is
/// foregrounded/connected.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _jobsChannel = AndroidNotificationChannel(
    'roadside_updates',
    'Roadside Assistance Updates',
    description: 'Driver assignment and job status updates',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Requests notification permission, registers the FCM token with the
  /// backend via [onToken], and shows a local notification for any message
  /// that arrives while the app is in the foreground (FCM does not surface
  /// those automatically the way it does for background/terminated states).
  Future<void> init({
    required Future<void> Function(String token) onToken,
  }) async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _localNotifications.initialize(
        // iOS settings are mandatory — without them initialize() throws on iOS
        // and the rest of push setup (permission, token) is skipped.
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_jobsChannel);

      // Listeners first: a slow permission answer or token fetch below must
      // not delay foreground messages or token refreshes.
      FirebaseMessaging.instance.onTokenRefresh.listen(onToken);
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      await FirebaseMessaging.instance.requestPermission();

      // getToken needs the network and Google Play services and can hang on
      // a weak connection or a phone without Play services. That is fine:
      // nothing waits for this method (startup and sign-in run it in the
      // background), and onTokenRefresh delivers a token later.
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await onToken(token);
    } catch (_) {
      // No google-services.json configured yet (or permission denied) —
      // push notifications stay off; Socket.IO updates still work while
      // the app is foregrounded/connected.
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'roadside_updates',
          'Roadside Assistance Updates',
          channelDescription: 'Driver assignment and job status updates',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }
}
