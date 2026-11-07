// Flow 1 — the full OBD-II diagnostics journey through the real app:
//
//   splash → app shell, Home tab: dashboard (not connected) → connection screen
//   → scan finds the ELM327 → connect → back to the dashboard with live data
//   → diagnostic codes → scan finds codes → clear refused by the ECU shows
//   the "turn engine off" hint → clear succeeds → codes gone → back to the
//   dashboard → disconnect.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/app/app.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/obd_gauge.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';
import 'package:mycar/modules/home/presentation/pages/spalchScreen/spalch_screen.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/flow_harness.dart';
import 'helpers/obd_steps.dart';

void main() {
  late FakeOBDAdapter fake;

  setUpAll(FakeBlePlatform.install);

  setUp(installPlatformFakes);

  testWidgets('diagnostics journey: connect, live data, scan, clear, back', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      fake
        ..dtcsToReturn = ['P0420', 'P0171']
        ..clearShouldFail = true;

      // ── Splash → app shell, Home tab: dashboard (not yet connected) ──────
      await tester.pumpWidget(const App());
      await setAppLocale(tester, const Locale('en'));
      expectOnScreen<SplashScreen>();
      await advance(tester, const Duration(milliseconds: 5500));
      expectOnScreen<AppShell>();
      expect(
        find.byType(SplashScreen, skipOffstage: false),
        findsNothing,
        reason: 'splash must be replaced, not kept under the app shell',
      );
      expect(currentTab(tester), AppTab.home);
      expectOnScreen<DashboardScreen>();
      expect(findTr('obd_not_connected'), findsOneWidget);
      expect(fake.startLiveDataCalled, isFalse);

      // ── Dashboard → connection screen → scan → connect ───────────────────
      await connectThroughConnectionScreen(tester, fake);

      // ── Back on the dashboard: connected, polling, live data ─────────────
      expectOnScreen<DashboardScreen>();
      expect(findTr('connected'), findsOneWidget);
      expect(findTr('obd_not_connected'), findsNothing);
      expect(find.text('FakeAdapter'), findsOneWidget); // adapter name header
      expect(fake.startLiveDataCalled, isTrue);
      expect(
        fake.getDtcsCalled,
        isTrue,
        reason: 'dashboard refreshes the warning lights on connect',
      );

      fake.emitLiveData(driving());
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2500'), findsOneWidget); // RPM
      expect(gaugeShowing('60'), findsOneWidget); // speed
      expect(find.byType(OBDGauge), findsWidgets);

      // ── Dashboard → diagnostic codes → scan finds codes ──────────────────
      fake.getDtcsCalled = false;
      await tapOn(tester, findTr('quick_scan'));
      await advance(tester, const Duration(milliseconds: 400));
      expectOnScreen<DiagnosticCodesScreen>();
      await pumpUntilFoundAsync(tester, find.text('P0420'));
      expect(fake.getDtcsCalled, isTrue);
      expect(find.text('P0420'), findsOneWidget);
      expect(find.text('P0171'), findsOneWidget);

      // ── Clear refused by the ECU → "turn engine off" hint, codes kept ────
      await clearCodesViaDialog(tester);
      expect(fake.clearDtcsCalled, isTrue);
      expect(findTr('failed_clear_codes_hint'), findsOneWidget);
      expect(find.text('P0420'), findsOneWidget);
      expect(find.text('P0171'), findsOneWidget);
      // Let the 8 s hint snackbar run its course.
      await advance(tester, const Duration(seconds: 9));

      // ── Engine off, retry: clear succeeds → rescan → codes gone ──────────
      fake.clearShouldFail = false;
      await clearCodesViaDialog(tester);
      await pumpUntilFoundAsync(tester, findTr('no_codes_found'));
      expect(find.text('P0420'), findsNothing);
      expect(find.text('P0171'), findsNothing);
      expect(findTr('failed_clear_codes_hint'), findsNothing);

      // ── Back to the dashboard: still connected, still live ───────────────
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DashboardScreen>();
      expect(findTr('connected'), findsOneWidget);
      fake.emitLiveData(driving(rpm: 3100));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('3100'), findsOneWidget);

      // ── Disconnect ───────────────────────────────────────────────────────
      // Connected header → adapter screen → tap the live adapter → Back.
      await disconnectThroughHeader(tester, fake);
      expect(fake.stopLiveDataCalled, isTrue);
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DashboardScreen>();
      // The dashboard follows the connection state back to the banner.
      expect(findTr('obd_not_connected'), findsOneWidget);
      expect(findTr('connected'), findsNothing);

      // Re-entering the codes screen now shows the not-connected state.
      await tapOn(tester, findTr('quick_scan'));
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DiagnosticCodesScreen>();
      expect(findTr('go_to_connection'), findsOneWidget);
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 500));

      await unmountApp(tester);
    });
  });

  testWidgets('connected dashboard lets the user reach the adapter screen to '
      'disconnect', (tester) async {
    // Once connected, the header (_buildConnectedHeader) has no tap target
    // and no dashboard or settings control routes to ConnectionScreen, the
    // only screen with a disconnect action (connection_screen.dart:197).
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await connectThroughConnectionScreen(tester, fake);
      expect(findTr('connected'), findsOneWidget);

      await tapOn(tester, findTr('connected'));
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<ConnectionScreen>();

      // Tapping the connected adapter disconnects it.
      await tapOn(tester, find.text('OBDII'));
      await advance(tester, const Duration(milliseconds: 300));
      expect(fake.disconnectCalled, isTrue);
      expect(OBDService.instance.isInitialized, isFalse);
      await unmountApp(tester);
    });
  });

  testWidgets('adapter dropping mid-session returns the dashboard to the '
      'connect banner, and reconnecting restores live data', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await connectThroughConnectionScreen(tester, fake);
      fake.emitLiveData(driving());
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2500'), findsOneWidget);

      fake.simulateDrop();
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DashboardScreen>();
      expect(findTr('obd_not_connected'), findsOneWidget);
      expect(findTr('connected'), findsNothing);

      // The adapter screen explains the drop and offers RECONNECT to the
      // last adapter.
      fake.connectCalled = false;
      await tapOn(tester, findTr('obd_not_connected'));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<ConnectionScreen>();
      expect(findTr('obd_connection_lost'), findsOneWidget);
      await tapOn(tester, findTr('btn_reconnect'));
      await advance(tester, const Duration(milliseconds: 300));
      expect(fake.connectCalled, isTrue);
      expect(OBDService.instance.isInitialized, isTrue);
      await tapOn(tester, findTr('scan_vehicle'));
      await advance(tester, const Duration(seconds: 2));
      expectOnScreen<DashboardScreen>();
      expect(findTr('connected'), findsOneWidget);
      fake.emitLiveData(driving(rpm: 2700));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2700'), findsOneWidget);
      await unmountApp(tester);
    });
  });

  testWidgets('failed connection keeps the dashboard disconnected', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      fake.shouldFailConnect = true;
      await bootToDashboard(tester);

      await tapOn(tester, findTr('obd_not_connected'));
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<ConnectionScreen>();
      await pumpUntilFound(tester, find.text('OBDII'));
      await tapOn(tester, find.text('OBDII'));
      await advance(tester, const Duration(milliseconds: 300));

      expect(fake.connectCalled, isTrue);
      expect(findTr('obd_init_failed'), findsOneWidget);
      expect(findTr('btn_retry'), findsOneWidget);
      expect(findTr('scan_vehicle'), findsNothing);

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DashboardScreen>();
      expect(findTr('obd_not_connected'), findsOneWidget);
      expect(fake.startLiveDataCalled, isFalse);
      await unmountApp(tester);
    });
  });

  testWidgets('connected dashboard lays out without overflow', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    // Strict: no overflow tolerance at all.
    await bootToDashboard(tester);
    await connectThroughConnectionScreen(tester, fake);
    fake.emitLiveData(driving());
    await advance(tester, const Duration(seconds: 1));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -600),
    );
    await advance(tester, const Duration(milliseconds: 500));
    await unmountApp(tester);
  });

  // ── Adversarial double-checks ──────────────────────────────────────────────

  testWidgets('header disconnect stops polling and shows the connect banner; '
      'reconnecting from the banner restores a live session', (tester) async {
    usePhoneSurface(tester);
    final fake = newCountingFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await connectThroughConnectionScreen(tester, fake);
      fake.emitLiveData(driving());
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2500'), findsOneWidget);
      final listenersWhileLive = fake.liveListeners;
      expect(listenersWhileLive, greaterThan(0));

      await disconnectThroughHeader(tester, fake);
      // The adapter screen falls back to a fresh scan for a new connection.
      await pumpUntilFound(tester, find.text('OBDII'));
      expect(findTr('scan_vehicle'), findsNothing);

      final startsBeforeBack = fake.startLiveDataCalls;
      await pressBack(tester);
      await advance(tester, const Duration(seconds: 1));
      expectOnScreen<DashboardScreen>();
      expect(findTr('obd_not_connected'), findsOneWidget);
      expect(findTr('connected'), findsNothing);
      expect(find.text('FakeAdapter'), findsNothing);
      expect(
        fake.startLiveDataCalls,
        startsBeforeBack,
        reason: 'returning disconnected must not restart polling',
      );
      // Idle for a while: polling stays stopped.
      await advance(tester, const Duration(seconds: 3));
      expect(fake.startLiveDataCalls, startsBeforeBack);
      expect(OBDService.instance.isInitialized, isFalse);

      // Reconnect through the banner: a fresh session, same listener set.
      fake
        ..connectCalled = false
        ..startLiveDataCalled = false
        ..getDtcsCalled = false;
      await connectThroughConnectionScreen(tester, fake);
      expect(findTr('connected'), findsOneWidget);
      expect(fake.startLiveDataCalled, isTrue);
      expect(fake.getDtcsCalled, isTrue);
      expect(
        fake.liveListeners,
        listenersWhileLive,
        reason: 'reconnecting must not stack duplicate live-data listeners',
      );
      final before = fake.deliveries;
      fake.emitLiveData(driving(rpm: 3300));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('3300'), findsOneWidget);
      expect(fake.deliveries - before, listenersWhileLive);
      await unmountApp(tester);
    });
  });

  testWidgets('disconnect then reconnect within one visit to the adapter '
      'screen starts a new live session on return', (tester) async {
    usePhoneSurface(tester);
    final fake = newCountingFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await connectThroughConnectionScreen(tester, fake);
      final listenersWhileLive = fake.liveListeners;

      await disconnectThroughHeader(tester, fake);
      await pumpUntilFound(tester, find.text('OBDII'));
      fake
        ..connectCalled = false
        ..startLiveDataCalled = false;
      await tapOn(tester, find.text('OBDII'));
      await advance(tester, const Duration(milliseconds: 300));
      expect(fake.connectCalled, isTrue);
      expect(OBDService.instance.isInitialized, isTrue);
      await tapOn(tester, findTr('scan_vehicle'));
      await advance(tester, const Duration(seconds: 2));
      expectOnScreen<DashboardScreen>();
      expect(findTr('connected'), findsOneWidget);
      expect(fake.startLiveDataCalled, isTrue);
      expect(fake.liveListeners, listenersWhileLive);
      fake.emitLiveData(driving(rpm: 2900));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2900'), findsOneWidget);
      await unmountApp(tester);
    });
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('[$lang] EV with no standard OBD-II data gets the EV message, '
        'not the ignition one', (tester) async {
      usePhoneSurface(tester);
      final fake = newFakeAdapter();
      fake.failReason = OBDFailureReason.noStandardObdData;
      await withKnownOverflows(() async {
        await bootToDashboard(tester, locale: Locale(lang));
        await tapOn(tester, findTr('obd_not_connected', lang));
        await advance(tester, const Duration(milliseconds: 500));
        await pumpUntilFound(tester, find.text('OBDII'));
        await tapOn(tester, find.text('OBDII'));
        await advance(tester, const Duration(milliseconds: 300));

        expect(fake.connectCalled, isTrue);
        expect(OBDService.instance.isInitialized, isFalse);
        expect(
          OBDService.instance.lastError?.reason,
          OBDFailureReason.noStandardObdData,
        );
        expect(findTr('obd_err_no_std_obd', lang), findsOneWidget);
        expect(findTr('obd_err_no_std_obd_sub', lang), findsOneWidget);
        expect(find.byIcon(Icons.electric_car), findsOneWidget);
        // Not the ignition-off advice, nor the generic failure.
        expect(findTr('obd_err_ecu_silent', lang), findsNothing);
        expect(findTr('obd_err_ecu_silent_sub', lang), findsNothing);
        expect(findTr('obd_init_failed', lang), findsNothing);
        expect(find.byIcon(Icons.directions_car), findsNothing);
        expect(findTr('scan_vehicle', lang), findsNothing);

        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 500));
        expectOnScreen<DashboardScreen>();
        expect(findTr('obd_not_connected', lang), findsOneWidget);
        expect(fake.startLiveDataCalled, isFalse);
        await unmountApp(tester);
      });
    });
  }

  testWidgets('a silent ECU (ignition off) still gets the ignition message', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final fake = newFakeAdapter();
    fake.failReason = OBDFailureReason.ecuNotResponding;
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await tapOn(tester, findTr('obd_not_connected'));
      await advance(tester, const Duration(milliseconds: 500));
      await pumpUntilFound(tester, find.text('OBDII'));
      await tapOn(tester, find.text('OBDII'));
      await advance(tester, const Duration(milliseconds: 300));
      expect(findTr('obd_err_ecu_silent'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car), findsOneWidget);
      expect(findTr('obd_err_no_std_obd'), findsNothing);
      expect(find.byIcon(Icons.electric_car), findsNothing);
      await unmountApp(tester);
    });
  });
}
