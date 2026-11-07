import 'package:flutter/material.dart';

/// Holds the app-wide [ThemeMode] (Light / Dark / System). `MaterialApp`
/// listens to it, so changing [value] restyles the whole app immediately.
///
/// Persistence is injected so this stays free of storage details:
/// [load] reads the saved choice at startup, [set] saves every change.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController({
    Future<String?> Function()? read,
    Future<void> Function(String value)? write,
  }) : _read = read,
       _write = write,
       super(ThemeMode.system);

  final Future<String?> Function()? _read;
  final Future<void> Function(String value)? _write;

  /// Restores the saved choice; keeps [ThemeMode.system] if none or on error.
  Future<void> load() async {
    try {
      value = parse(await _read?.call());
    } catch (_) {
      value = ThemeMode.system;
    }
  }

  /// Applies [mode] now and saves it (a failed save keeps the in-app value).
  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await _write?.call(mode.name);
    } catch (_) {}
  }

  static ThemeMode parse(String? raw) => ThemeMode.values.firstWhere(
    (m) => m.name == raw,
    orElse: () => ThemeMode.system,
  );
}
