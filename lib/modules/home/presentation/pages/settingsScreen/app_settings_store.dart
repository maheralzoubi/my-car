import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Snapshot of the user's settings-screen preferences.
class AppSettings {
  const AppSettings({
    this.notifications = true,
    this.autoScan = false,
    this.darkMode = true,
    this.soundEffects = true,
    this.units = 'Metric',
  });

  final bool notifications;
  final bool autoScan;
  final bool darkMode;
  final bool soundEffects;

  /// 'Metric' or 'Imperial'.
  final String units;
}

/// Persists the settings-screen preferences in the same secure storage the
/// [Session] uses, so they are per-account: logout (`Session.clear`, which
/// wipes the store) resets them along with the session.
///
/// Every call degrades to the defaults when storage is unavailable rather
/// than throwing — a preference must never break the settings screen.
class AppSettingsStore {
  AppSettingsStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const notificationsKey = 'pref_notifications';
  static const autoScanKey = 'pref_auto_scan';
  static const darkModeKey = 'pref_dark_mode';
  static const soundEffectsKey = 'pref_sound_effects';
  static const unitsKey = 'pref_units';

  /// 'light' | 'dark' | 'system' — read and written by [ThemeController].
  static const themeModeKey = 'pref_theme_mode';

  Future<String?> readThemeMode() async {
    try {
      return await _storage.read(key: themeModeKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeThemeMode(String value) => _write(themeModeKey, value);

  Future<AppSettings> load() async {
    const d = AppSettings();
    try {
      final values = await Future.wait([
        _storage.read(key: notificationsKey),
        _storage.read(key: autoScanKey),
        _storage.read(key: darkModeKey),
        _storage.read(key: soundEffectsKey),
        _storage.read(key: unitsKey),
      ]);
      bool flag(String? v, bool fallback) => v == null ? fallback : v == 'true';
      final units = values[4];
      return AppSettings(
        notifications: flag(values[0], d.notifications),
        autoScan: flag(values[1], d.autoScan),
        darkMode: flag(values[2], d.darkMode),
        soundEffects: flag(values[3], d.soundEffects),
        units: units == 'Imperial' || units == 'Metric' ? units! : d.units,
      );
    } catch (_) {
      return d;
    }
  }

  Future<void> setBool(String key, bool value) => _write(key, '$value');

  Future<void> setUnits(String units) => _write(unitsKey, units);

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Keeps the in-screen value; it just won't survive a restart.
    }
  }
}
