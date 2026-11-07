import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/alert_service.dart';
import 'package:mycar/core/services/obd_service.dart';

import '../helpers/fake_obd_adapter.dart';

// AlertService hard-wires FlutterLocalNotificationsPlugin, AudioPlayer and
// HapticFeedback. They are faked at the platform-channel level:
//   * audioplayers channels → succeed with null (player "created")
//   * flutter_local_notifications channel → recorded, succeed
//   * flutter/platform (haptics) → OptionalMethodChannel, ignored
// Live data is fed through OBDService + FakeOBDAdapter, exactly as in the app.
//
// AlertService is a singleton: every test starts from resetForTesting() (no
// cooldowns) and drives the injectable `clock` with a fake time, so cooldown
// expiry (10 s / 30 s / 5 min) is tested exactly without real waits.

const _notifChannel = 'dexterous.com/flutter/local_notifications';
const _codec = StandardMethodCodec();

/// A reading where every monitored value is comfortably normal.
const _normal = OBDLiveData(
  rpm: 2500,
  speedKmh: 60,
  coolantTempC: 90,
  oilTempC: 100,
  batteryVoltage: 14.2,
  timingAdvanceDeg: 12,
  fuelLevelPct: 55,
  intakeAirTempC: 35,
);

OBDLiveData _with({
  double? rpm,
  double? coolantTempC,
  double? oilTempC,
  double? batteryVoltage,
  double? timingAdvanceDeg,
  double? fuelLevelPct,
  double? intakeAirTempC,
}) =>
    OBDLiveData(
      rpm: rpm ?? _normal.rpm,
      speedKmh: _normal.speedKmh,
      coolantTempC: coolantTempC ?? _normal.coolantTempC,
      oilTempC: oilTempC ?? _normal.oilTempC,
      batteryVoltage: batteryVoltage ?? _normal.batteryVoltage,
      timingAdvanceDeg: timingAdvanceDeg ?? _normal.timingAdvanceDeg,
      fuelLevelPct: fuelLevelPct ?? _normal.fuelLevelPct,
      intakeAirTempC: intakeAirTempC ?? _normal.intakeAirTempC,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final notifCalls = <MethodCall>[];
  bool notificationsFail = false;

  late FakeOBDAdapter fake;
  late List<OBDAlert> alerts;
  StreamSubscription<OBDAlert>? alertSub;
  late DateTime now;

  Future<void> emit(OBDLiveData d) async {
    fake.emitLiveData(d);
    await pumpEventQueue();
  }

  /// Moves the fake clock forward by [d], then emits [data].
  Future<void> emitAfter(Duration d, OBDLiveData data) {
    now = now.add(d);
    return emit(data);
  }

  /// Critical alerts await ~400 ms of haptics before posting a notification.
  Future<void> settleSideEffects() =>
      Future<void>.delayed(const Duration(milliseconds: 700));

  Iterable<MethodCall> shows() => notifCalls.where((c) => c.method == 'show');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = (channel, mockHandler, message) {
      if (mockHandler != null) return mockHandler(message);
      if (channel == _notifChannel) {
        final call = _codec.decodeMethodCall(message);
        notifCalls.add(call);
        if (notificationsFail && call.method == 'show') {
          return Future.value(
              _codec.encodeErrorEnvelope(code: 'error', message: 'denied'));
        }
        return Future.value(_codec
            .encodeSuccessEnvelope(call.method == 'initialize' ? true : null));
      }
      if (channel.startsWith('xyz.luan/audioplayers')) {
        return Future.value(_codec.encodeSuccessEnvelope(null));
      }
      return null; // unhandled → MissingPlugin / ignored for optional channels
    };
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .allMessagesHandler = null;
  });

  setUp(() async {
    notificationsFail = false;
    notifCalls.clear();
    fake = FakeOBDAdapter();
    OBDService.setTestAdapter(fake);
    AlertService.instance.resetForTesting();
    now = DateTime(2026, 3, 1, 8);
    AlertService.instance.clock = () => now;
    AlertService.instance.startMonitoring();
    alerts = [];
    alertSub = AlertService.instance.alerts.listen(alerts.add);
  });

  tearDown(() async {
    await alertSub?.cancel();
    AlertService.instance.stopMonitoring();
    AlertService.instance.resetForTesting();
    fake.dispose();
  });

  // ── Quiet cases ────────────────────────────────────────────────────────────

  group('no false alarms', () {
    test('normal driving produces no alerts', () async {
      for (var i = 0; i < 5; i++) {
        await emit(_normal);
      }
      expect(alerts, isEmpty);
    });

    test('missing PIDs (all null) never trigger alerts', () async {
      await emit(const OBDLiveData());
      await emit(const OBDLiveData(rpm: 800));
      expect(alerts, isEmpty);
    });
  });

  // ── Critical thresholds ────────────────────────────────────────────────────

  group('critical alerts', () {
    test('coolant: 107 °C quiet, 108 °C fires once and stays debounced',
        () async {
      await emit(_with(coolantTempC: 107));
      expect(alerts, isEmpty);

      await emit(_with(coolantTempC: 108));
      expect(alerts, hasLength(1));
      expect(alerts.single.id, 'overheat');
      expect(alerts.single.severity, AlertSeverity.critical);
      expect(alerts.single.message, contains('108°C'));

      // Still hot on the next polls → no repeat inside the 30 s cooldown.
      await emit(_with(coolantTempC: 110));
      await emit(_with(coolantTempC: 112));
      expect(alerts, hasLength(1));

      // Critical cooldown is NOT reset by a momentary normal reading, so a
      // sensor flapping around the threshold can't spam the driver.
      await emit(_with(coolantTempC: 100));
      await emit(_with(coolantTempC: 109));
      expect(alerts, hasLength(1));

      await settleSideEffects();
      final s = shows().toList();
      expect(s, hasLength(1));
      final args = s.single.arguments as Map;
      expect(args['id'], 'overheat'.hashCode);
      expect(args['title'], alerts.single.title);
      expect(args['body'], alerts.single.message);
    });

    test('oil temp: 134 °C quiet, 135 °C fires critical', () async {
      await emit(_with(oilTempC: 134));
      expect(alerts, isEmpty);
      await emit(_with(oilTempC: 135));
      expect(alerts.single.id, 'oil_overheat');
      expect(alerts.single.severity, AlertSeverity.critical);
      expect(alerts.single.message, contains('135°C'));
      await settleSideEffects();
    });

    test('battery: 11.0 V quiet, 10.9 V fires critical', () async {
      await emit(_with(batteryVoltage: 11.0));
      expect(alerts, isEmpty);
      await emit(_with(batteryVoltage: 10.9));
      expect(alerts.single.id, 'battery');
      expect(alerts.single.severity, AlertSeverity.critical);
      expect(alerts.single.message, startsWith('10.9 V'));
      await settleSideEffects();
    });
  });

  // ── Warning thresholds ─────────────────────────────────────────────────────

  group('warning alerts — thresholds', () {
    test('over-rev: 6500 rpm quiet, 6501 rpm fires', () async {
      await emit(_with(rpm: 6500));
      expect(alerts, isEmpty);
      await emit(_with(rpm: 6501));
      expect(alerts.single.id, 'overrev');
      expect(alerts.single.severity, AlertSeverity.warning);
    });

    test('knock retard: −8° quiet, −8.5° fires', () async {
      await emit(_with(timingAdvanceDeg: -8));
      expect(alerts, isEmpty);
      await emit(_with(timingAdvanceDeg: -8.5));
      expect(alerts.single.id, 'knock_retard');
      expect(alerts.single.message, contains('-8.5°'));
    });

    test('low fuel: 8.1 % quiet, 8 % fires (inclusive)', () async {
      await emit(_with(fuelLevelPct: 8.1));
      expect(alerts, isEmpty);
      await emit(_with(fuelLevelPct: 8));
      expect(alerts.single.id, 'low_fuel');
      expect(alerts.single.message, startsWith('8%'));
    });

    test('intake heat soak: 65 °C quiet, 66 °C fires', () async {
      await emit(_with(intakeAirTempC: 65));
      expect(alerts, isEmpty);
      await emit(_with(intakeAirTempC: 66));
      expect(alerts.single.id, 'intake_heat');
    });

    test('several conditions in one frame raise one alert each', () async {
      await emit(_with(rpm: 7000, fuelLevelPct: 5, intakeAirTempC: 70));
      expect(alerts.map((a) => a.id),
          ['overrev', 'low_fuel', 'intake_heat']);
      expect(alerts.every((a) => a.severity == AlertSeverity.warning), isTrue);
    });

    test('warning posts a system notification with the alert text', () async {
      await emit(_with(rpm: 6800));
      await settleSideEffects();
      final s = shows().toList();
      expect(s, hasLength(1));
      final args = s.single.arguments as Map;
      expect(args['id'], 'overrev'.hashCode);
      expect(args['title'], alerts.single.title);
      expect(args['body'], '6800 RPM — Reduce throttle');
    });
  });

  // ── Debouncing ─────────────────────────────────────────────────────────────

  group('warning alerts — debouncing', () {
    test('a sustained condition fires only once within its cooldown',
        () async {
      for (var i = 0; i < 4; i++) {
        await emit(_with(rpm: 7000));
      }
      expect(alerts, hasLength(1));
    });

    test('a warning re-arms once the condition clears (new episode)',
        () async {
      await emit(_with(rpm: 7000));
      await emit(_with(rpm: 3000));
      await emit(_with(rpm: 7000));
      expect(alerts.map((a) => a.id), ['overrev', 'overrev']);
    });

    test(
      'low fuel sloshing around 8 % does not re-alert within 5 minutes',
      () async {
        await emit(_with(fuelLevelPct: 8));
        await emit(_with(fuelLevelPct: 9));
        await emit(_with(fuelLevelPct: 7));
        await emit(_with(fuelLevelPct: 9));
        await emit(_with(fuelLevelPct: 8));
        expect(alerts, hasLength(1));
      },
    );

    test('intake heat flapping around 65 °C does not re-alert', () async {
      await emit(_with(intakeAirTempC: 66));
      await emit(_with(intakeAirTempC: 63));
      await emit(_with(intakeAirTempC: 67));
      expect(alerts, hasLength(1));
    });

    test('low fuel re-arms after a real refuel', () async {
      await emit(_with(fuelLevelPct: 7));
      await emit(_with(fuelLevelPct: 60));
      await emit(_with(fuelLevelPct: 8));
      expect(alerts.map((a) => a.id), ['low_fuel', 'low_fuel']);
    });
  });

  // ── Cooldown expiry (fake clock) ──────────────────────────────────────────

  group('cooldown expiry', () {
    const justUnder = Duration(milliseconds: 1);

    Future<void> expectCooldown(
      Duration cooldown,
      OBDLiveData firing,
      String id,
    ) async {
      await emit(firing);
      expect(alerts.map((a) => a.id), [id]);

      await emitAfter(cooldown - justUnder, firing);
      expect(alerts, hasLength(1), reason: 'still inside the cooldown');

      await emitAfter(justUnder, firing);
      expect(alerts.map((a) => a.id), [id, id],
          reason: 'fires again exactly when the cooldown expires');

      // The repeat starts a fresh cooldown measured from itself.
      await emitAfter(cooldown - justUnder, firing);
      expect(alerts, hasLength(2));
      await emitAfter(justUnder, firing);
      expect(alerts, hasLength(3));
    }

    test('over-rev held above the limit repeats every 10 s', () async {
      await expectCooldown(
          const Duration(seconds: 10), _with(rpm: 7000), 'overrev');
    });

    test('knock retard held repeats every 30 s', () async {
      await expectCooldown(const Duration(seconds: 30),
          _with(timingAdvanceDeg: -12), 'knock_retard');
    });

    test('intake heat soak held repeats every 30 s', () async {
      await expectCooldown(const Duration(seconds: 30),
          _with(intakeAirTempC: 70), 'intake_heat');
    });

    test('low fuel held repeats every 5 minutes', () async {
      await expectCooldown(
          const Duration(minutes: 5), _with(fuelLevelPct: 6), 'low_fuel');
    });

    test('critical coolant held repeats every 30 s', () async {
      await expectCooldown(const Duration(seconds: 30),
          _with(coolantTempC: 115), 'overheat');
      expect(alerts.every((a) => a.severity == AlertSeverity.critical),
          isTrue);
      await settleSideEffects();
    });

    test('critical oil temp held repeats every 30 s', () async {
      await expectCooldown(
          const Duration(seconds: 30), _with(oilTempC: 140), 'oil_overheat');
      await settleSideEffects();
    });

    test('critical battery held repeats every 30 s', () async {
      await expectCooldown(const Duration(seconds: 30),
          _with(batteryVoltage: 10.5), 'battery');
      await settleSideEffects();
    });

    test('a critical alert flapping through normal waits out its 30 s',
        () async {
      await emit(_with(coolantTempC: 110));
      await emitAfter(const Duration(seconds: 5), _with(coolantTempC: 80));
      await emitAfter(const Duration(seconds: 24, milliseconds: 999),
          _with(coolantTempC: 110));
      expect(alerts, hasLength(1)); // 29.999 s after the first alert
      await emitAfter(const Duration(milliseconds: 1), _with(coolantTempC: 110));
      expect(alerts.map((a) => a.id), ['overheat', 'overheat']);
      await settleSideEffects();
    });

    test('a warning parked in its hysteresis band still re-fires by time',
        () async {
      await emit(_with(intakeAirTempC: 66));
      await emitAfter(const Duration(seconds: 10), _with(intakeAirTempC: 63));
      await emitAfter(const Duration(seconds: 19), _with(intakeAirTempC: 66));
      expect(alerts, hasLength(1)); // 29 s
      await emitAfter(const Duration(seconds: 1), _with(intakeAirTempC: 66));
      expect(alerts, hasLength(2)); // 30 s
    });

    test('cooldowns are tracked per alert id', () async {
      await emit(_with(rpm: 7000));
      await emitAfter(
          const Duration(seconds: 1), _with(rpm: 7000, intakeAirTempC: 70));
      expect(alerts.map((a) => a.id), ['overrev', 'intake_heat']);

      // Over-rev expires at 10 s; intake heat (fired at 1 s) is still cooling.
      await emitAfter(
          const Duration(seconds: 9), _with(rpm: 7000, intakeAirTempC: 70));
      expect(alerts.map((a) => a.id), ['overrev', 'intake_heat', 'overrev']);
    });

    test('triggeredAt is the service clock time', () async {
      await emitAfter(const Duration(minutes: 3), _with(rpm: 7000));
      expect(alerts.single.triggeredAt, DateTime(2026, 3, 1, 8, 3));
    });

    test('resetForTesting() clears critical cooldowns', () async {
      await emit(_with(batteryVoltage: 10));
      await emit(_with(batteryVoltage: 10));
      expect(alerts, hasLength(1));

      AlertService.instance.resetForTesting();
      AlertService.instance.clock = () => now;
      await emit(_with(batteryVoltage: 10));
      expect(alerts, hasLength(2));
      await settleSideEffects();
    });
  });

  // ── Re-arm hysteresis ─────────────────────────────────────────────────────
  // A warning starts a new episode (cooldown cleared) only once the value is
  // back past its re-arm level; inside the band it waits out the cooldown.

  group('warning re-arm hysteresis', () {
    Future<void> expectRearm({
      required OBDLiveData firing,
      required OBDLiveData inBand,
      required OBDLiveData rearmed,
    }) async {
      await emit(firing);
      await emitAfter(const Duration(seconds: 1), inBand);
      await emitAfter(const Duration(seconds: 1), firing);
      expect(alerts, hasLength(1), reason: 'in-band reading must not re-arm');

      await emitAfter(const Duration(seconds: 1), rearmed);
      await emitAfter(const Duration(seconds: 1), firing);
      expect(alerts, hasLength(2), reason: 're-arm level starts a new episode');
    }

    test('over-rev re-arms at ≤ 6000 rpm, not 6001', () async {
      await expectRearm(
        firing: _with(rpm: 7000),
        inBand: _with(rpm: 6001),
        rearmed: _with(rpm: 6000),
      );
    });

    test('knock re-arms at ≥ −5°, not −5.1°', () async {
      await expectRearm(
        firing: _with(timingAdvanceDeg: -10),
        inBand: _with(timingAdvanceDeg: -5.1),
        rearmed: _with(timingAdvanceDeg: -5),
      );
    });

    test('low fuel re-arms at ≥ 12 %, not 11.9 %', () async {
      await expectRearm(
        firing: _with(fuelLevelPct: 7),
        inBand: _with(fuelLevelPct: 11.9),
        rearmed: _with(fuelLevelPct: 12),
      );
    });

    test('intake heat re-arms at ≤ 60 °C, not 60.1 °C', () async {
      await expectRearm(
        firing: _with(intakeAirTempC: 70),
        inBand: _with(intakeAirTempC: 60.1),
        rearmed: _with(intakeAirTempC: 60),
      );
    });

    test('a frame with missing PIDs re-arms nothing', () async {
      await emit(_with(rpm: 7000, timingAdvanceDeg: -10, fuelLevelPct: 5,
          intakeAirTempC: 70));
      expect(alerts, hasLength(4));
      await emitAfter(const Duration(seconds: 1), const OBDLiveData());
      await emitAfter(const Duration(seconds: 1), _with(rpm: 7000,
          timingAdvanceDeg: -10, fuelLevelPct: 5, intakeAirTempC: 70));
      expect(alerts, hasLength(4));
    });

    test('a re-armed episode starts its own cooldown', () async {
      await emit(_with(rpm: 7000));
      await emitAfter(const Duration(seconds: 2), _with(rpm: 3000));
      await emitAfter(const Duration(seconds: 2), _with(rpm: 7000)); // t = 4 s
      expect(alerts, hasLength(2));
      await emitAfter(const Duration(seconds: 9, milliseconds: 999),
          _with(rpm: 7000));
      expect(alerts, hasLength(2));
      await emitAfter(const Duration(milliseconds: 1), _with(rpm: 7000));
      expect(alerts, hasLength(3)); // 10 s after the re-armed alert
    });
  });

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  group('lifecycle', () {
    test('stopMonitoring() stops evaluating live data', () async {
      AlertService.instance.stopMonitoring();
      await emit(_with(rpm: 7500));
      expect(alerts, isEmpty);
    });

    test('calling startMonitoring() twice does not double-fire', () async {
      AlertService.instance.startMonitoring();
      AlertService.instance.startMonitoring();
      await emit(_with(intakeAirTempC: 80));
      expect(alerts, hasLength(1));
    });

    test('init() creates the high-importance "obd_critical" channel',
        () async {
      await AlertService.instance.init();
      expect(notifCalls.map((c) => c.method),
          containsAll(['initialize', 'createNotificationChannel']));
      final ch = notifCalls
          .firstWhere((c) => c.method == 'createNotificationChannel')
          .arguments as Map;
      expect(ch['id'], 'obd_critical');
      expect(ch['importance'], Importance.max.value);
      expect(ch['playSound'], isTrue);
    });

    test(
      'init() succeeds on iOS',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await expectLater(AlertService.instance.init(), completes);
      },
    );

    test(
      'a failing system notification does not escape as an unhandled error',
      () async {
        notificationsFail = true;
        await emit(_with(timingAdvanceDeg: -12));
        expect(alerts.single.id, 'knock_retard'); // in-app alert delivered
        await settleSideEffects(); // must not surface an uncaught error
      },
    );
  });
}
