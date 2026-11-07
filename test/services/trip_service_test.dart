import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/trip_service.dart';

// TripService reads time through its injectable `clock`. Every test drives a
// fake clock, so sample intervals are exact and no test waits in real time.
// The live app polls roughly every 3 s, which is the default step here.

final trip = TripService.instance;

const _poll = Duration(seconds: 3);

late DateTime _now;

void _advance(Duration d) => _now = _now.add(d);

/// Duration from (possibly fractional) seconds, at millisecond precision.
Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

/// Advances the fake clock by [after] (one poll by default), then samples.
void _sample(OBDLiveData d, {Duration after = _poll}) {
  _advance(after);
  trip.addSample(d);
}

/// km covered at [kmh] for [seconds].
double _km(double kmh, double seconds) => kmh * seconds / 3600.0;

void main() {
  setUp(() {
    _now = DateTime(2026, 3, 1, 8);
    trip.clock = () => _now;
    trip.stop();
    trip.start();
  });

  tearDown(() {
    trip.stop();
    trip.clock = DateTime.now;
  });

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  group('lifecycle', () {
    test('start() resets all counters and marks running', () {
      expect(trip.isRunning, isTrue);
      expect(trip.distanceKm, 0);
      expect(trip.fuelUsedL, 0);
      expect(trip.avgSpeedKmh, 0);
      expect(trip.fuelEfficiencyL100km, 0);
      expect(trip.driveScore, 100);
      expect(trip.elapsed, Duration.zero);
    });

    test('samples are ignored when the trip is not running', () {
      trip.stop();
      _sample(const OBDLiveData(speedKmh: 100, rpm: 7000));
      expect(trip.isRunning, isFalse);
      expect(trip.distanceKm, 0);
      expect(trip.driveScore, 100);
    });

    test('stop() keeps accumulated totals; elapsed reads zero once stopped',
        () {
      _sample(const OBDLiveData(speedKmh: 60));
      final d = trip.distanceKm;
      expect(d, closeTo(_km(60, 3), 1e-12));
      expect(trip.elapsed, _poll);

      trip.stop();
      expect(trip.distanceKm, d);
      expect(trip.elapsed, Duration.zero);
    });

    test('start() after a previous trip begins from zero', () {
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000));
      expect(trip.distanceKm, greaterThan(0));
      trip.start();
      expect(trip.distanceKm, 0);
      expect(trip.fuelUsedL, 0);
      expect(trip.driveScore, 100);
      expect(trip.elapsed, Duration.zero);
    });

    test('reset() zeroes counters but keeps the trip running', () {
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000));
      trip.reset();
      expect(trip.isRunning, isTrue);
      expect(trip.distanceKm, 0);
      expect(trip.fuelUsedL, 0);
      expect(trip.avgSpeedKmh, 0);
      expect(trip.driveScore, 100);
    });

    test('a sample at the same instant as start() is dropped', () {
      // dt == 0 → no integration.
      trip.addSample(const OBDLiveData(speedKmh: 100));
      expect(trip.distanceKm, 0);
      expect(trip.avgSpeedKmh, 0);
    });
  });

  // ── Elapsed time ───────────────────────────────────────────────────────────

  group('elapsed', () {
    test('is wall-clock time since start()', () {
      _advance(const Duration(minutes: 12, seconds: 34));
      expect(trip.elapsed, const Duration(minutes: 12, seconds: 34));
    });

    test('keeps running through sample gaps (it is not driving time)', () {
      _sample(const OBDLiveData(speedKmh: 50));
      _sample(const OBDLiveData(speedKmh: 50), after: const Duration(minutes: 2));
      expect(trip.elapsed, _poll + const Duration(minutes: 2));
    });

    test('reset() restarts elapsed from the reset instant', () {
      _advance(const Duration(minutes: 5));
      trip.reset();
      expect(trip.elapsed, Duration.zero);
      _advance(const Duration(seconds: 7));
      expect(trip.elapsed, const Duration(seconds: 7));
    });

    test('reset() also restarts the sample interval', () {
      _advance(const Duration(minutes: 5));
      trip.reset();
      // Measured from reset(), not from the old start: 3 s, not 5 min 3 s.
      _sample(const OBDLiveData(speedKmh: 60));
      expect(trip.distanceKm, closeTo(_km(60, 3), 1e-12));
    });
  });

  // ── Sample interval rules ──────────────────────────────────────────────────

  group('sample interval', () {
    test('an interval of exactly 10 s is integrated', () {
      _sample(const OBDLiveData(speedKmh: 60), after: _s(10));
      expect(trip.distanceKm, closeTo(_km(60, 10), 1e-12));
    });

    test('an interval just over 10 s is ignored entirely', () {
      _sample(const OBDLiveData(speedKmh: 130, engineLoad: 80, rpm: 3000),
          after: _s(10.001));
      expect(trip.distanceKm, 0);
      expect(trip.fuelUsedL, 0);
      expect(trip.avgSpeedKmh, 0);
      expect(trip.driveScore, 100);
    });

    test('the interval after a gap is measured from the dropped sample', () {
      _sample(const OBDLiveData(speedKmh: 60), after: const Duration(seconds: 30));
      expect(trip.distanceKm, 0);
      _sample(const OBDLiveData(speedKmh: 60));
      expect(trip.distanceKm, closeTo(_km(60, 3), 1e-12));
    });

    test('a duplicate timestamp adds nothing', () {
      _sample(const OBDLiveData(speedKmh: 60));
      final d = trip.distanceKm;
      _sample(const OBDLiveData(speedKmh: 60), after: Duration.zero);
      expect(trip.distanceKm, d);
    });

    test('a clock step backwards adds nothing and re-bases the interval', () {
      _sample(const OBDLiveData(speedKmh: 60), after: _s(-5));
      expect(trip.distanceKm, 0);
      _sample(const OBDLiveData(speedKmh: 60));
      expect(trip.distanceKm, closeTo(_km(60, 3), 1e-12));
    });

    test('sub-millisecond precision is truncated (10 s + 0.5 ms counts)', () {
      _sample(const OBDLiveData(speedKmh: 36),
          after: const Duration(seconds: 10, microseconds: 500));
      expect(trip.distanceKm, closeTo(_km(36, 10), 1e-12));
    });

    test('hard acceleration is not scored across a gap', () {
      // Polling paused (e.g. a DTC read) while the car sped up: the first
      // sample after the gap is a new baseline, not a 60 km/h jump.
      _sample(const OBDLiveData(speedKmh: 30));
      _sample(const OBDLiveData(speedKmh: 90), after: const Duration(seconds: 30));
      _sample(const OBDLiveData(speedKmh: 95));
      expect(trip.driveScore, 100);
    });

    test('the sample after a gap is the hard-acceleration baseline', () {
      _sample(const OBDLiveData(speedKmh: 30));
      _sample(const OBDLiveData(speedKmh: 40), after: const Duration(seconds: 30));
      _sample(const OBDLiveData(speedKmh: 56)); // +16 vs the post-gap 40
      expect(trip.driveScore, 96);
    });

    test('over-rev before a gap does not pair with a blip after it', () {
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000));
      _sample(const OBDLiveData(speedKmh: 80, rpm: 2500),
          after: const Duration(seconds: 30));
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000));
      expect(trip.driveScore, 100);
    });

    test('over-rev continuing through a gap still counts once re-sampled', () {
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000));
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000),
          after: const Duration(seconds: 30)); // dropped, but over the limit
      _sample(const OBDLiveData(speedKmh: 80, rpm: 6000));
      expect(trip.driveScore, 98);
    });
  });

  // ── Distance ───────────────────────────────────────────────────────────────

  group('distance', () {
    test('integrates speed × time (km/h × s / 3600)', () {
      _sample(const OBDLiveData(speedKmh: 100));
      expect(trip.distanceKm, closeTo(_km(100, 3), 1e-12));
    });

    test('uses each sample\'s speed for the interval ending at it', () {
      _sample(const OBDLiveData(speedKmh: 30), after: _s(2));
      _sample(const OBDLiveData(speedKmh: 90), after: _s(4));
      expect(trip.distanceKm, closeTo(_km(30, 2) + _km(90, 4), 1e-12));
    });

    test('stationary samples add no distance', () {
      _sample(const OBDLiveData(speedKmh: 0, rpm: 800));
      _sample(const OBDLiveData(rpm: 800)); // speed unavailable
      expect(trip.distanceKm, 0);
    });

    test('distance is monotonic over several samples', () {
      var last = 0.0;
      for (final s in [30.0, 50.0, 50.0, 40.0]) {
        _sample(OBDLiveData(speedKmh: s));
        expect(trip.distanceKm, greaterThan(last));
        last = trip.distanceKm;
      }
      expect(last, closeTo(_km(170, 3), 1e-12));
    });
  });

  // ── Average speed ──────────────────────────────────────────────────────────

  group('average speed', () {
    test('averages only moving samples (> 2 km/h)', () {
      _sample(const OBDLiveData(speedKmh: 0));
      _sample(const OBDLiveData(speedKmh: 2)); // boundary: not moving
      _sample(const OBDLiveData(speedKmh: 40));
      _sample(const OBDLiveData(speedKmh: 60));
      expect(trip.avgSpeedKmh, closeTo(50, 1e-9));
    });

    test('is a per-sample mean, not weighted by interval length', () {
      _sample(const OBDLiveData(speedKmh: 40), after: _s(1));
      _sample(const OBDLiveData(speedKmh: 80), after: _s(9));
      expect(trip.avgSpeedKmh, closeTo(60, 1e-9));
    });

    test('is 0 when the car never moved', () {
      _sample(const OBDLiveData(speedKmh: 0));
      expect(trip.avgSpeedKmh, 0);
    });
  });

  // ── Fuel model ─────────────────────────────────────────────────────────────
  // Moving: L/100km = 8.0 × (0.4 + 0.6 × load). Idle: 0.5 L/h when load > 10 %.
  // Nothing when the ECU reports rpm 0 (engine stopped).

  group('fuel estimate', () {
    test('moving at 30 % load (default when PID missing) = 4.64 L/100km', () {
      _sample(const OBDLiveData(speedKmh: 90));
      expect(trip.fuelUsedL, closeTo(4.64 * _km(90, 3) / 100, 1e-12));
    });

    test('moving at 100 % load = 8.0 L/100km (upper bound)', () {
      _sample(const OBDLiveData(speedKmh: 90, engineLoad: 100));
      expect(trip.fuelUsedL, closeTo(8.0 * _km(90, 3) / 100, 1e-12));
    });

    test('moving at 0 % load = 3.2 L/100km (lower bound)', () {
      _sample(const OBDLiveData(speedKmh: 90, engineLoad: 0));
      expect(trip.fuelUsedL, closeTo(3.2 * _km(90, 3) / 100, 1e-12));
    });

    test('idling with load > 10 % burns 0.5 L/h', () {
      _sample(const OBDLiveData(speedKmh: 0, engineLoad: 25), after: _s(10));
      expect(trip.distanceKm, 0);
      expect(trip.fuelUsedL, closeTo(0.5 * 10 / 3600, 1e-12));
    });

    test('stationary with load ≤ 10 % burns nothing (boundary at 10 %)', () {
      _sample(const OBDLiveData(speedKmh: 0, engineLoad: 10));
      _sample(const OBDLiveData(speedKmh: 0, engineLoad: 0));
      expect(trip.fuelUsedL, 0);
    });

    test(
      'engine off (rpm 0) burns no fuel even if the load PID is unsupported',
      () {
        _sample(const OBDLiveData(speedKmh: 0, rpm: 0));
        expect(trip.fuelUsedL, 0);
      },
    );

    test('engine off (rpm 0) while rolling burns no fuel', () {
      // Coasting with the engine stopped (start-stop / hybrid EV mode).
      _sample(const OBDLiveData(speedKmh: 40, rpm: 0, engineLoad: 0));
      expect(trip.distanceKm, closeTo(_km(40, 3), 1e-12));
      expect(trip.fuelUsedL, 0);
    });

    test('efficiency reads 0 until more than 0.5 km is covered', () {
      // 90 km/h × 10 s = 0.25 km per sample → exactly 0.5 km after two.
      _sample(const OBDLiveData(speedKmh: 90, engineLoad: 50), after: _s(10));
      _sample(const OBDLiveData(speedKmh: 90, engineLoad: 50), after: _s(10));
      expect(trip.distanceKm, 0.5);
      expect(trip.fuelUsedL, greaterThan(0));
      expect(trip.fuelEfficiencyL100km, 0);
    });

    test('efficiency = fuel × 100 / distance once past 0.5 km', () {
      for (var i = 0; i < 3; i++) {
        _sample(const OBDLiveData(speedKmh: 90, engineLoad: 50), after: _s(10));
      }
      expect(trip.distanceKm, closeTo(0.75, 1e-12));
      // 8.0 × (0.4 + 0.6 × 0.5) = 5.6 L/100km
      expect(trip.fuelEfficiencyL100km, closeTo(5.6, 1e-9));
    });
  });

  // ── Drive score ────────────────────────────────────────────────────────────

  group('drive score — hard acceleration', () {
    test('smooth driving keeps a perfect 100 / Eco', () {
      for (final s in [20.0, 30.0, 40.0, 50.0, 50.0]) {
        _sample(OBDLiveData(speedKmh: s, rpm: 2000));
      }
      expect(trip.driveScore, 100);
      expect(trip.driveScoreLabel, startsWith('Eco'));
    });

    test('speed gain of exactly 15 km/h is not a hard acceleration', () {
      _sample(const OBDLiveData(speedKmh: 40));
      _sample(const OBDLiveData(speedKmh: 55));
      expect(trip.driveScore, 100);
    });

    test('speed gain > 15 km/h in one poll costs 4 points', () {
      _sample(const OBDLiveData(speedKmh: 40));
      _sample(const OBDLiveData(speedKmh: 56));
      expect(trip.driveScore, 96);
    });

    test('pulling away from a standstill is never a hard acceleration', () {
      _sample(const OBDLiveData(speedKmh: 0));
      _sample(const OBDLiveData(speedKmh: 40));
      expect(trip.driveScore, 100);
    });

    test('deceleration is never counted as hard acceleration', () {
      _sample(const OBDLiveData(speedKmh: 100));
      _sample(const OBDLiveData(speedKmh: 40));
      expect(trip.driveScore, 100);
    });

    test('hard-acceleration deduction is capped at 30', () {
      // 10 events → 40 points uncapped.
      for (var i = 0; i < 10; i++) {
        _sample(const OBDLiveData(speedKmh: 10));
        _sample(const OBDLiveData(speedKmh: 30));
      }
      expect(trip.driveScore, 70);
      expect(trip.driveScoreLabel, 'Normal');
    });
  });

  group('drive score — over-rev', () {
    test('RPM of exactly 5500 is not over-rev; sustained 5501 is (−2)', () {
      _sample(const OBDLiveData(speedKmh: 50, rpm: 5500));
      _sample(const OBDLiveData(speedKmh: 50, rpm: 5500));
      expect(trip.driveScore, 100);
      _sample(const OBDLiveData(speedKmh: 50, rpm: 5501));
      expect(trip.driveScore, 100); // first sample over the limit: a blip
      _sample(const OBDLiveData(speedKmh: 50, rpm: 5501));
      expect(trip.driveScore, 98); // second consecutive sample: sustained
    });

    test('each further consecutive over-rev sample costs 2 more', () {
      for (var i = 0; i < 4; i++) {
        _sample(const OBDLiveData(speedKmh: 50, rpm: 6000));
      }
      expect(trip.driveScore, 94); // 3 sustained samples after the first
    });

    test('a single RPM blip above 5500 is not penalised', () {
      _sample(const OBDLiveData(speedKmh: 50, rpm: 2500));
      _sample(const OBDLiveData(speedKmh: 50, rpm: 5800));
      _sample(const OBDLiveData(speedKmh: 50, rpm: 2500));
      expect(trip.driveScore, 100);
    });

    test('a dip below the limit ends the streak', () {
      _sample(const OBDLiveData(speedKmh: 50, rpm: 6000));
      _sample(const OBDLiveData(speedKmh: 50, rpm: 6000)); // −2
      _sample(const OBDLiveData(speedKmh: 50, rpm: 5000));
      _sample(const OBDLiveData(speedKmh: 50, rpm: 6000)); // blip again
      expect(trip.driveScore, 98);
      _sample(const OBDLiveData(speedKmh: 50, rpm: 6000)); // −2
      expect(trip.driveScore, 96);
    });

    test('missing RPM breaks a streak (treated as 0)', () {
      _sample(const OBDLiveData(speedKmh: 50, rpm: 6000));
      _sample(const OBDLiveData(speedKmh: 50));
      _sample(const OBDLiveData(speedKmh: 50, rpm: 6000));
      expect(trip.driveScore, 100);
    });

    test('over-rev deduction is capped at 20', () {
      for (var i = 0; i < 15; i++) {
        _sample(const OBDLiveData(speedKmh: 50, rpm: 6500));
      }
      expect(trip.driveScore, 80);
    });
  });

  group('drive score — sustained high speed (> 120 km/h)', () {
    // Deduction = round(seconds above 120 km/h / 15), capped at 20: the first
    // point lands at 7.5 s, then one more every 15 s.

    test('7.499 s above 120 km/h costs nothing', () {
      _sample(const OBDLiveData(speedKmh: 130), after: _s(7.499));
      expect(trip.driveScore, 100);
    });

    test('7.5 s above 120 km/h costs 1 point', () {
      for (var i = 0; i < 3; i++) {
        _sample(const OBDLiveData(speedKmh: 130), after: _s(2.5));
      }
      expect(trip.driveScore, 99);
    });

    test('a brief stint (two polls) costs nothing', () {
      _sample(const OBDLiveData(speedKmh: 130));
      _sample(const OBDLiveData(speedKmh: 135));
      expect(trip.driveScore, 100);
    });

    test('exactly 120 km/h never counts', () {
      for (var i = 0; i < 20; i++) {
        _sample(const OBDLiveData(speedKmh: 120), after: _s(10));
      }
      expect(trip.driveScore, 100);
    });

    test('second point at 22.5 s, not before', () {
      _sample(const OBDLiveData(speedKmh: 130), after: _s(10));
      _sample(const OBDLiveData(speedKmh: 130), after: _s(10));
      _sample(const OBDLiveData(speedKmh: 130), after: _s(2.499));
      expect(trip.driveScore, 99); // 22.499 s

      trip.start();
      _sample(const OBDLiveData(speedKmh: 130), after: _s(10));
      _sample(const OBDLiveData(speedKmh: 130), after: _s(10));
      _sample(const OBDLiveData(speedKmh: 130), after: _s(2.5));
      expect(trip.driveScore, 98); // 22.5 s
    });

    test('time is attributed to the speed of the sample ending the interval',
        () {
      // 110 ↔ 125 km/h: a 15 km/h change, so no hard-acceleration noise.
      _sample(const OBDLiveData(speedKmh: 110));
      _sample(const OBDLiveData(speedKmh: 125), after: _s(5)); // +5 s
      _sample(const OBDLiveData(speedKmh: 110), after: _s(5)); // +0
      expect(trip.driveScore, 100);
      _sample(const OBDLiveData(speedKmh: 125), after: _s(2.5)); // 7.5 s
      expect(trip.driveScore, 99);
    });

    test('accumulates across separate stints', () {
      _sample(const OBDLiveData(speedKmh: 125), after: _s(5));
      _sample(const OBDLiveData(speedKmh: 110));
      _sample(const OBDLiveData(speedKmh: 110));
      _sample(const OBDLiveData(speedKmh: 125), after: _s(2.5));
      expect(trip.driveScore, 99);
    });

    test('intervals longer than 10 s add no high-speed time', () {
      for (var i = 0; i < 10; i++) {
        _sample(const OBDLiveData(speedKmh: 130), after: _s(10.001));
      }
      expect(trip.driveScore, 100);
      expect(trip.distanceKm, 0);
    });

    test('a gap does not count, but speeding after it does', () {
      _sample(const OBDLiveData(speedKmh: 130), after: _s(5));
      _sample(const OBDLiveData(speedKmh: 130), after: _s(60)); // dropped
      _sample(const OBDLiveData(speedKmh: 130), after: _s(2));
      expect(trip.driveScore, 100); // 7 s
      _sample(const OBDLiveData(speedKmh: 130), after: _s(0.5));
      expect(trip.driveScore, 99); // 7.5 s
    });

    test('deduction reaches its 20-point cap at 292.5 s', () {
      for (var i = 0; i < 29; i++) {
        _sample(const OBDLiveData(speedKmh: 130), after: _s(10));
      }
      _sample(const OBDLiveData(speedKmh: 130), after: _s(2));
      expect(trip.driveScore, 81); // 292 s → 19
      _sample(const OBDLiveData(speedKmh: 130), after: _s(0.5));
      expect(trip.driveScore, 80); // 292.5 s → 20
      for (var i = 0; i < 60; i++) {
        _sample(const OBDLiveData(speedKmh: 130), after: _s(10));
      }
      expect(trip.driveScore, 80); // capped
    });
  });

  group('drive score — combined', () {
    test('hard-accel and over-rev caps combine to 50 (Sporty)', () {
      // 10 hard accels (cap 30) + sustained over-rev (cap 20) = 50.
      for (var i = 0; i < 10; i++) {
        _sample(const OBDLiveData(speedKmh: 10, rpm: 6000));
        _sample(const OBDLiveData(speedKmh: 30, rpm: 6000));
      }
      expect(trip.driveScore, 50);
      expect(trip.driveScoreLabel, 'Sporty');
    });

    test('all three caps together floor the score at 30 (Aggressive)', () {
      for (var i = 0; i < 10; i++) {
        _sample(const OBDLiveData(speedKmh: 10, rpm: 6000));
        _sample(const OBDLiveData(speedKmh: 30, rpm: 6000));
      }
      for (var i = 0; i < 40; i++) {
        _sample(const OBDLiveData(speedKmh: 200, rpm: 8000), after: _s(10));
      }
      expect(trip.driveScore, 30);
      expect(trip.driveScoreLabel, startsWith('Aggressive'));
    });

    test('erratic driving is scored exactly', () {
      // 15 hard accels (cap 30), 29 sustained over-revs (cap 20),
      // 15 × 3 s = 45 s above 120 km/h (3) → 47.
      for (var i = 0; i < 30; i++) {
        _sample(OBDLiveData(speedKmh: i.isEven ? 5 : 200, rpm: 8000));
      }
      expect(trip.driveScore, 47);
      expect(trip.driveScoreLabel, 'Sporty');
    });
  });

  group('drive score labels', () {
    // Labels are derived from the score bands 85 / 65 / 45.

    /// 10 hard accelerations → the full 30-point deduction.
    void maxHardAccel({double rpm = 2000}) {
      for (var i = 0; i < 10; i++) {
        _sample(OBDLiveData(speedKmh: 10, rpm: rpm));
        _sample(OBDLiveData(speedKmh: 30, rpm: rpm));
      }
    }

    test('85: Eco / Normal boundary', () {
      // 4 hard accels → 84 → Normal (just below Eco).
      for (var i = 0; i < 4; i++) {
        _sample(const OBDLiveData(speedKmh: 10));
        _sample(const OBDLiveData(speedKmh: 30));
      }
      expect(trip.driveScore, 84);
      expect(trip.driveScoreLabel, 'Normal');

      trip.start();
      // 3 hard accels + 1 sustained over-rev → 100 − 12 − 2 = 86 → Eco.
      for (var i = 0; i < 3; i++) {
        _sample(const OBDLiveData(speedKmh: 10));
        _sample(const OBDLiveData(speedKmh: 30));
      }
      _sample(const OBDLiveData(speedKmh: 30, rpm: 6000));
      _sample(const OBDLiveData(speedKmh: 30, rpm: 6000));
      expect(trip.driveScore, 86);
      expect(trip.driveScoreLabel, startsWith('Eco'));
    });

    test('65: Normal / Sporty boundary', () {
      // 30 (hard accel) + 2 (one over-rev) + 3 (45 s speeding) = 65.
      maxHardAccel();
      _sample(const OBDLiveData(speedKmh: 30, rpm: 6000));
      _sample(const OBDLiveData(speedKmh: 30, rpm: 6000));
      for (var i = 0; i < 9; i++) {
        _sample(const OBDLiveData(speedKmh: 130, rpm: 3000), after: _s(5));
      }
      expect(trip.driveScore, 65);
      expect(trip.driveScoreLabel, 'Normal');
      _sample(const OBDLiveData(speedKmh: 130, rpm: 3000), after: _s(7.5));
      expect(trip.driveScore, 64); // 52.5 s → 4
      expect(trip.driveScoreLabel, 'Sporty');
    });

    test('45: Sporty / Aggressive boundary', () {
      // 30 + 20 (caps) + 5 (67.5 s speeding) = 45.
      maxHardAccel(rpm: 6000);
      for (var i = 0; i < 6; i++) {
        _sample(const OBDLiveData(speedKmh: 130, rpm: 6000), after: _s(10));
      }
      _sample(const OBDLiveData(speedKmh: 130, rpm: 6000), after: _s(7.5));
      expect(trip.driveScore, 45);
      expect(trip.driveScoreLabel, 'Sporty');
      _sample(const OBDLiveData(speedKmh: 130, rpm: 6000), after: _s(10));
      _sample(const OBDLiveData(speedKmh: 130, rpm: 6000), after: _s(5));
      expect(trip.driveScore, 44); // 82.5 s → 6
      expect(trip.driveScoreLabel, startsWith('Aggressive'));
    });
  });
}
