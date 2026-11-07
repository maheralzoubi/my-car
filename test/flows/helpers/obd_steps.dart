// Reusable user-journey steps for the OBD-II flows (English and Arabic).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/app/app.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/obd_gauge.dart';
import 'package:mycar/modules/home/presentation/pages/modeSelectionScreen/mode_selection_screen.dart';

import '../../helpers/fake_obd_adapter.dart';
import 'flow_harness.dart';

/// Creates a [FakeOBDAdapter] and installs it behind [OBDService].
///
/// Call it inside the test body, not in setUp: OBDService subscribes to the
/// adapter's connection-state stream when it is built, and a subscription
/// made in setUp lives in the root zone — its events (e.g. a simulated BLE
/// drop) would only be delivered after the test's fake-async frames.
FakeOBDAdapter newFakeAdapter() {
  final fake = FakeOBDAdapter();
  OBDService.setTestAdapter(fake);
  addTearDown(fake.dispose);
  return fake;
}

/// A [FakeOBDAdapter] that also counts live-data subscriptions and polling
/// start/stop calls, to catch duplicated or leaked listeners.
class CountingFakeAdapter extends FakeOBDAdapter {
  /// Live-data subscriptions currently open (dashboard subs, StreamBuilders,
  /// AlertService …).
  int liveListeners = 0;

  /// Events delivered to listeners so far (one per listener per emit).
  int deliveries = 0;

  int startLiveDataCalls = 0;
  int stopLiveDataCalls = 0;

  /// Whether the adapter's poll timer is running (last start/stop wins).
  bool pollingActive = false;

  @override
  Stream<OBDLiveData> get liveDataStream {
    final source = super.liveDataStream;
    return Stream<OBDLiveData>.multi((c) {
      liveListeners++;
      final sub = source.listen(
        (d) {
          deliveries++;
          c.addSync(d);
        },
        onError: c.addErrorSync,
        onDone: c.closeSync,
      );
      c.onCancel = () {
        liveListeners--;
        return sub.cancel();
      };
    }, isBroadcast: true);
  }

  @override
  void startLiveData() {
    startLiveDataCalls++;
    pollingActive = true;
    super.startLiveData();
  }

  @override
  void stopLiveData() {
    stopLiveDataCalls++;
    pollingActive = false;
    super.stopLiveData();
  }
}

/// Like [newFakeAdapter], with a [CountingFakeAdapter].
CountingFakeAdapter newCountingFakeAdapter() {
  final fake = CountingFakeAdapter();
  OBDService.setTestAdapter(fake);
  addTearDown(fake.dispose);
  return fake;
}

/// The adapter screen opened from the connected dashboard's header: it lists
/// the live adapter as connected; tapping it disconnects.
Future<void> disconnectThroughHeader(
  WidgetTester tester,
  FakeOBDAdapter fake, {
  String lang = 'en',
}) async {
  await tapOn(tester, findTr('connected', lang));
  await advance(tester, const Duration(milliseconds: 500));
  expectOnScreen<ConnectionScreen>();
  expect(find.text('${tr('connected_to', lang)} OBDII'), findsOneWidget);
  expect(fake.disconnectCalled, isFalse);

  await tapOn(tester, find.text('OBDII'));
  await advance(tester, const Duration(milliseconds: 300));
  expect(fake.disconnectCalled, isTrue);
  expect(OBDService.instance.isInitialized, isFalse);
}

/// A calm, in-range reading: no sensor warning and no driving alert fires.
OBDLiveData driving({double rpm = 2500, double speedKmh = 60}) => OBDLiveData(
  rpm: rpm,
  speedKmh: speedKmh,
  coolantTempC: 90,
  throttlePct: 20,
  fuelLevelPct: 55,
  engineLoad: 35,
  batteryVoltage: 14.2,
  oilTempC: 100,
  intakeAirTempC: 35,
  timingAdvanceDeg: 12,
);

/// An [OBDGauge] (live-data arc gauge) currently rendering [value].
Finder gaugeShowing(String value) =>
    find.descendant(of: find.byType(OBDGauge), matching: find.text(value));

/// Boots the real [App] in [locale] and waits out the splash.
Future<void> bootToModeSelection(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(const App());
  await setAppLocale(tester, locale);
  await advance(tester, const Duration(milliseconds: 5500));
  expectOnScreen<ModeSelectionScreen>();
}

/// From mode selection, taps the "Car Diagnostics" card.
Future<void> openDiagnostics(WidgetTester tester, {String lang = 'en'}) async {
  // Let the 900 ms entrance animation bring the cards in.
  await advance(tester, const Duration(seconds: 1));
  await tapOn(tester, findTr('car_diagnostics', lang));
  await advance(tester, const Duration(milliseconds: 600));
  expectOnScreen<DashboardScreen>();
}

Future<void> bootToDashboard(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await bootToModeSelection(tester, locale: locale);
  await openDiagnostics(tester, lang: locale.languageCode);
}

/// Dashboard (disconnected) → connection screen → scan → tap the ELM327 →
/// connected → "SCAN VEHICLE" back to the dashboard, then drains the
/// dashboard's on-connect OBD requests (DTCs, readiness, VIN).
Future<void> connectThroughConnectionScreen(
  WidgetTester tester,
  FakeOBDAdapter fake, {
  String lang = 'en',
}) async {
  await tapOn(tester, findTr('obd_not_connected', lang));
  await advance(tester, const Duration(milliseconds: 500));
  expectOnScreen<ConnectionScreen>();

  // The fake BLE stack is ON and the scan reports one ELM327 adapter.
  await pumpUntilFound(tester, find.text('OBDII'));
  expect(findTr('available_devices', lang), findsOneWidget);
  expect(fake.connectCalled, isFalse);

  await tapOn(tester, find.text('OBDII'));
  await advance(tester, const Duration(milliseconds: 300));
  expect(fake.connectCalled, isTrue);
  expect(OBDService.instance.isInitialized, isTrue);
  expect(find.text('${tr('connected_to', lang)} OBDII'), findsOneWidget);

  await tapOn(tester, findTr('scan_vehicle', lang));
  await advance(tester, const Duration(milliseconds: 500));
  expectOnScreen<DashboardScreen>();
  // DTC scan + readiness + VIN each wait out OBDService's 300 ms settle.
  await advance(tester, const Duration(seconds: 2));
}

/// Pumps until [finder] matches, also letting real async work (asset
/// loading / JSON decoding of the DTC database) complete between frames.
Future<void> pumpUntilFoundAsync(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 200,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final error = tester.takeException();
    if (error != null) fail('Exception while waiting for $finder: $error');
  }
  fail('Timed out waiting for $finder');
}

/// On the codes screen: clear-all icon → confirm dialog → "Clear".
Future<void> clearCodesViaDialog(
  WidgetTester tester, {
  String lang = 'en',
}) async {
  await tapOn(tester, find.byIcon(Icons.clear_all));
  await advance(tester, const Duration(milliseconds: 400));
  expect(findTr('clear_codes', lang), findsOneWidget);
  await tapOn(tester, findTr('clear', lang));
  // clearDtcs settle delay (300 ms) + rescan settle (300 ms) + rebuild.
  await advance(tester, const Duration(milliseconds: 1200));
}

/// Unmounts the app and drains every pending timer (splash, alert
/// auto-dismiss, snackbars) so the test ends clean.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}
