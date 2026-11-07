import 'package:flutter/foundation.dart';

import 'obd_adapter.dart';

/// Accumulates trip statistics and drive score by sampling live OBD data.
class TripService {
  TripService._();
  static final TripService instance = TripService._();

  /// Time source for trip timing and sample intervals. Tests replace it with
  /// a fake clock so interval-dependent rules can be exercised exactly.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool      _running     = false;
  DateTime? _startTime;
  DateTime? _lastSample;

  double _distanceKm     = 0;
  double _sumSpeedKmh    = 0;
  int    _movingSamples  = 0;
  double _estimatedFuelL = 0;

  // ── Drive score tracking ──────────────────────────────────────────────────
  int    _hardAccelEvents  = 0;  // speed jumped > 15 km/h in one 3-s window
  int    _overRevEvents    = 0;  // RPM > 5 500 on consecutive samples
  double _highSpeedSecs    = 0;  // seconds driven > 120 km/h
  double _prevSpeedKmh     = 0;
  double _prevRpm          = 0;

  // ── Public API ────────────────────────────────────────────────────────────

  bool   get isRunning   => _running;
  double get distanceKm  => _distanceKm;
  double get fuelUsedL   => _estimatedFuelL;

  Duration get elapsed =>
      _running && _startTime != null
          ? clock().difference(_startTime!)
          : Duration.zero;

  double get avgSpeedKmh =>
      _movingSamples > 0 ? _sumSpeedKmh / _movingSamples : 0;

  double get fuelEfficiencyL100km =>
      _distanceKm > 0.5 ? (_estimatedFuelL * 100) / _distanceKm : 0;

  // ── Drive score ───────────────────────────────────────────────────────────

  /// 0–100. Deductions for hard acceleration, over-rev, sustained high speed.
  int get driveScore {
    int score = 100;
    score -= (_hardAccelEvents * 4).clamp(0, 30);
    score -= (_overRevEvents * 2).clamp(0, 20);
    score -= (_highSpeedSecs / 15).round().clamp(0, 20);
    return score.clamp(0, 100);
  }

  String get driveScoreLabel {
    final s = driveScore;
    if (s >= 85) return 'Eco 🌿';
    if (s >= 65) return 'Normal';
    if (s >= 45) return 'Sporty';
    return 'Aggressive 🔥';
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start() {
    _running          = true;
    _startTime        = clock();
    _lastSample       = _startTime;
    _distanceKm       = 0;
    _sumSpeedKmh      = 0;
    _movingSamples    = 0;
    _estimatedFuelL   = 0;
    _hardAccelEvents  = 0;
    _overRevEvents    = 0;
    _highSpeedSecs    = 0;
    _prevSpeedKmh     = 0;
    _prevRpm          = 0;
  }

  void stop()  => _running = false;

  void reset() {
    _distanceKm       = 0;
    _sumSpeedKmh      = 0;
    _movingSamples    = 0;
    _estimatedFuelL   = 0;
    _hardAccelEvents  = 0;
    _overRevEvents    = 0;
    _highSpeedSecs    = 0;
    _prevSpeedKmh     = 0;
    _prevRpm          = 0;
    _startTime        = clock();
    _lastSample       = _startTime;
  }

  // ── Sample processing ─────────────────────────────────────────────────────

  void addSample(OBDLiveData data) {
    if (!_running) return;

    final now  = clock();
    final dtSec = _lastSample != null
        ? now.difference(_lastSample!).inMilliseconds / 1000.0
        : 0.0;
    _lastSample = now;

    final speed = data.speedKmh ?? 0;
    final rpm   = data.rpm ?? 0;

    // An interval that can't be integrated (duplicate timestamp, or a gap
    // > 10 s such as polling paused for a DTC read) adds nothing, but the
    // reading still becomes the baseline for the next sample — otherwise the
    // first poll after the gap is compared against a pre-gap reading and can
    // score a phantom hard acceleration or "sustained" over-rev.
    if (dtSec <= 0 || dtSec > 10) {
      _prevSpeedKmh = speed;
      _prevRpm      = rpm;
      return;
    }
    final load  = (data.engineLoad ?? 30) / 100.0;

    // Distance
    _distanceKm += speed * dtSec / 3600.0;

    // Average speed
    if (speed > 2) {
      _sumSpeedKmh += speed;
      _movingSamples++;
    }

    // Fuel estimate — nothing burns when the ECU reports the engine stopped
    // (ignition on / engine off, start-stop, hybrid EV mode).
    final engineOff = data.rpm != null && data.rpm! <= 0;
    if (engineOff) {
      // Engine stopped — no fuel burned.
    } else if (speed > 0) {
      final adjustedL100km = 8.0 * (0.4 + 0.6 * load);
      _estimatedFuelL += adjustedL100km * (speed * dtSec / 3600.0) / 100.0;
    } else if (load > 0.1) {
      _estimatedFuelL += 0.5 * dtSec / 3600.0;
    }

    // ── Drive score events ────────────────────────────────────────────────
    // Hard acceleration: speed increased > 15 km/h in one poll interval
    if (_prevSpeedKmh > 0 && speed - _prevSpeedKmh > 15) {
      _hardAccelEvents++;
    }
    _prevSpeedKmh = speed;

    // Over-rev: RPM above 5 500 (sustained, not just a blip) — a sample only
    // counts when the previous one was over the limit too.
    if (rpm > 5500 && _prevRpm > 5500) {
      _overRevEvents++;
    }
    _prevRpm = rpm;

    // Sustained high speed: > 120 km/h
    if (speed > 120) {
      _highSpeedSecs += dtSec;
    }
  }
}
