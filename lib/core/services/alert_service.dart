import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'obd_service.dart';

// ── Alert model ───────────────────────────────────────────────────────────────

class OBDAlert {
  final String id;
  final String title;
  final String message;
  final AlertSeverity severity;
  final DateTime triggeredAt;

  const OBDAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.triggeredAt,
  });
}

enum AlertSeverity { warning, critical }

// ── Service ───────────────────────────────────────────────────────────────────

class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<OBDLiveData>? _sub;

  // Cooldown: each alert id cannot fire again within this duration.
  final Map<String, DateTime> _lastFired = {};
  static const Duration _cooldown = Duration(seconds: 30);

  // In-app alert stream — the dashboard listens to this.
  final StreamController<OBDAlert> _alertStream =
      StreamController<OBDAlert>.broadcast();
  Stream<OBDAlert> get alerts => _alertStream.stream;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: android),
    );

    // Create high-priority notification channel (Android 8+).
    const channel = AndroidNotificationChannel(
      'obd_critical',
      'OBD Vehicle Alerts',
      description: 'Critical alerts from your OBD-II connection',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void startMonitoring() {
    _sub?.cancel();
    _sub = OBDService.instance.liveDataStream.listen(_evaluate);
  }

  void stopMonitoring() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stopMonitoring();
    _alertStream.close();
    _player.dispose();
  }

  // ── Evaluation — runs on every OBD poll (~3 s) ───────────────────────────

  void _evaluate(OBDLiveData d) {
    // ── Critical thresholds ───────────────────────────────────────────────
    _check(
      id: 'overheat',
      condition: d.coolantTempC != null && d.coolantTempC! >= 108,
      title: '🌡️ Engine Overheating!',
      message: 'Coolant ${d.coolantTempC?.toStringAsFixed(0)}°C — Pull over safely',
      severity: AlertSeverity.critical,
    );

    _check(
      id: 'oil_overheat',
      condition: d.oilTempC != null && d.oilTempC! >= 135,
      title: '🛢️ Oil Temperature Critical!',
      message: 'Oil temp ${d.oilTempC?.toStringAsFixed(0)}°C — Stop engine soon',
      severity: AlertSeverity.critical,
    );

    _check(
      id: 'battery',
      condition: d.batteryVoltage != null && d.batteryVoltage! < 11.0,
      title: '🔋 Battery / Charging Failure!',
      message: '${d.batteryVoltage?.toStringAsFixed(1)} V — Charging system fault',
      severity: AlertSeverity.critical,
    );

    _check(
      id: 'overrev',
      condition: d.rpm != null && d.rpm! > 6500,
      title: '⚠️ Engine Over-Rev!',
      message: '${d.rpm?.toStringAsFixed(0)} RPM — Reduce throttle',
      severity: AlertSeverity.warning,
      cooldown: const Duration(seconds: 10),
    );

    _check(
      id: 'knock_retard',
      condition: d.timingAdvanceDeg != null && d.timingAdvanceDeg! < -8,
      title: '⚡ Knock Detected!',
      message: 'Timing retarded to ${d.timingAdvanceDeg?.toStringAsFixed(1)}° — Possible bad fuel',
      severity: AlertSeverity.warning,
    );

    _check(
      id: 'low_fuel',
      condition: d.fuelLevelPct != null && d.fuelLevelPct! <= 8,
      title: '⛽ Low Fuel',
      message: '${d.fuelLevelPct?.toStringAsFixed(0)}% remaining — Refuel soon',
      severity: AlertSeverity.warning,
      cooldown: const Duration(minutes: 5),
    );

    _check(
      id: 'intake_heat',
      condition: d.intakeAirTempC != null && d.intakeAirTempC! > 65,
      title: '💨 Intake Heat Soak',
      message: 'Air temp ${d.intakeAirTempC?.toStringAsFixed(0)}°C — Possible intercooler issue',
      severity: AlertSeverity.warning,
    );
  }

  // ── Core alert logic ──────────────────────────────────────────────────────

  Future<void> _check({
    required String id,
    required bool condition,
    required String title,
    required String message,
    required AlertSeverity severity,
    Duration? cooldown,
  }) async {
    if (!condition) {
      if (!_isCritical(id)) { _lastFired.remove(id); }
      return;
    }

    final effective = cooldown ?? _cooldown;
    final last = _lastFired[id];
    if (last != null && DateTime.now().difference(last) < effective) {
      return;
    }

    _lastFired[id] = DateTime.now();

    final alert = OBDAlert(
      id: id,
      title: title,
      message: message,
      severity: severity,
      triggeredAt: DateTime.now(),
    );

    // Broadcast to in-app listeners (dashboard overlay).
    _alertStream.add(alert);

    // Play sound + vibration.
    await _playAlertSound(severity);

    // Push system notification (visible even when screen is locked).
    await _showNotification(alert);
  }

  bool _isCritical(String id) =>
      id == 'overheat' || id == 'oil_overheat' || id == 'battery';

  // ── Sound ─────────────────────────────────────────────────────────────────

  Future<void> _playAlertSound(AlertSeverity severity) async {
    try {
      // Vibration pattern: critical = long buzz, warning = short buzz.
      if (severity == AlertSeverity.critical) {
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }

      // Play the bundled alert tone.
      await _player.stop();
      await _player.play(
        AssetSource('sounds/alert.mp3'),
        volume: 1.0,
      );
    } catch (_) {
      // Silently ignore audio errors — alert is shown visually anyway.
    }
  }

  // ── System notification ───────────────────────────────────────────────────

  Future<void> _showNotification(OBDAlert alert) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'obd_critical',
        'OBD Vehicle Alerts',
        channelDescription: 'Critical alerts from your OBD-II connection',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: alert.severity == AlertSeverity.critical
            ? Int64List.fromList([0, 500, 200, 500, 200, 500])
            : Int64List.fromList([0, 300]),
        icon: '@mipmap/ic_launcher',
        color: alert.severity == AlertSeverity.critical
            ? const Color(0xFFFF1744)
            : const Color(0xFFFF6B35),
      ),
    );
    await _notif.show(alert.id.hashCode, alert.title, alert.message, details);
  }
}
