// Flow 5 — navigation, the system back button, and state preservation
// between screens of the running app: polling pauses and resumes around the
// codes scan, the dashboard keeps its connection/live data across tab
// screens, the codes list survives a detail round-trip, and the hub's exit
// confirmation, tab round-trips and logout. Expected-but-broken behaviours
// are skipped as REGRESSIONs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/authScreen/auth_screen.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';
import 'package:mycar/modules/home/presentation/pages/historyScreen/history_screen.dart';
import 'package:mycar/modules/home/presentation/pages/maintenanceScreen/maintenance_screen.dart';
import 'package:mycar/modules/home/presentation/pages/modeSelectionScreen/mode_selection_screen.dart';
import 'package:mycar/modules/home/presentation/pages/settingsScreen/settings_screen.dart';
import 'package:mycar/modules/home/presentation/pages/smartKeyScreen/smart_key_screen.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/flow_harness.dart';
import 'helpers/obd_steps.dart';

/// The bottom-nav item labelled with [key], as its icon's colour tells
/// whether it is the selected tab (cyan) or not.
bool _tabSelected(WidgetTester tester, IconData icon) {
  final nav = find.descendant(
    of: find.byType(DashboardScreen),
    matching: find.byIcon(icon),
  );
  final widget = tester.widget<Icon>(nav.last);
  return widget.color == const Color(0xFF00D9FF);
}

/// Smart Key header Row (back button + 24 sp title + Spacer + status chip,
/// nothing flexible): 5.3 px past the edge in English at 390 px.
// Fixed (header title is Expanded + ellipsis); kept empty so the tab
// round-trip below is strict.
const _smartKeyHeader = <String>[];

/// The bottom-nav item with [icon] on the dashboard.
Finder _tab(IconData icon) => find
    .descendant(of: find.byType(DashboardScreen), matching: find.byIcon(icon))
    .last;

/// Asserts Home is the only highlighted bottom-nav tab.
void _expectHomeOnlySelected(WidgetTester tester) {
  expect(_tabSelected(tester, Icons.home), isTrue, reason: 'Home tab');
  for (final icon in [
    Icons.search,
    Icons.vpn_key,
    Icons.history,
    Icons.settings,
  ]) {
    expect(_tabSelected(tester, icon), isFalse, reason: '$icon tab');
  }
}

void main() {
  late FakeOBDAdapter fake;

  setUpAll(FakeBlePlatform.install);

  setUp(installPlatformFakes);

  Future<void> connectedDashboard(WidgetTester tester) async {
    await bootToDashboard(tester);
    await connectThroughConnectionScreen(tester, fake);
    expect(findTr('connected'), findsOneWidget);
  }

  testWidgets('codes scan pauses live polling and resumes it afterwards; '
      'the dashboard stays live when the user returns', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    fake.dtcsToReturn = ['P0300'];
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      final dashboardState = tester.state(find.byType(DashboardScreen));

      fake
        ..startLiveDataCalled = false
        ..stopLiveDataCalled = false;
      await tapOn(tester, findTr('quick_scan'));
      await advance(tester, const Duration(milliseconds: 100));
      expect(
        fake.stopLiveDataCalled,
        isTrue,
        reason: 'polling must pause while the DTC request runs',
      );
      await pumpUntilFoundAsync(tester, find.text('P0300'));
      await advance(tester, const Duration(seconds: 1));
      expect(
        fake.startLiveDataCalled,
        isTrue,
        reason: 'polling resumes once the request is done',
      );

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DashboardScreen>();
      expect(
        tester.state(find.byType(DashboardScreen)),
        same(dashboardState),
        reason: 'returning must not rebuild the dashboard from scratch',
      );
      expect(findTr('connected'), findsOneWidget);
      fake.emitLiveData(driving(rpm: 1800));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('1800'), findsOneWidget);

      await unmountApp(tester);
    });
  });

  testWidgets('code detail round-trip keeps the scanned list without '
      'rescanning', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    fake.dtcsToReturn = ['P0420', 'P0171'];
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      await tapOn(tester, findTr('quick_scan'));
      await pumpUntilFoundAsync(tester, find.text('P0420'));
      await advance(tester, const Duration(seconds: 1));

      fake.getDtcsCalled = false;
      await tapOn(tester, find.text('P0420'));
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<CodeDetailScreen>();
      expect(find.text('P0420'), findsWidgets);

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 500));
      expectOnScreen<DiagnosticCodesScreen>();
      expect(find.text('P0420'), findsOneWidget);
      expect(find.text('P0171'), findsOneWidget);
      expect(fake.getDtcsCalled, isFalse, reason: 'no rescan on return');

      await unmountApp(tester);
    });
  });

  testWidgets('history tab and back keep the dashboard connected and live', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      final dashboardState = tester.state(find.byType(DashboardScreen));

      await tapOn(tester, findTr('history').last, scroll: false);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<HistoryScreen>();

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<DashboardScreen>();
      expect(tester.state(find.byType(DashboardScreen)), same(dashboardState));
      expect(findTr('connected'), findsOneWidget);
      expect(OBDService.instance.isInitialized, isTrue);
      fake.emitLiveData(driving(rpm: 2200));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2200'), findsOneWidget);

      await unmountApp(tester);
    });
  });

  testWidgets('back on the service hub asks before exiting; cancel stays', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToModeSelection(tester);
      await advance(tester, const Duration(seconds: 1));

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 400));
      expect(findTr('exit_app'), findsOneWidget);
      expect(findTr('exit_app_confirm'), findsOneWidget);

      await tapOn(tester, findTr('cancel'));
      await advance(tester, const Duration(milliseconds: 400));
      expect(findTr('exit_app'), findsNothing);
      expectOnScreen<ModeSelectionScreen>();

      await unmountApp(tester);
    });
  });

  testWidgets('back from the dashboard returns to the hub and stops '
      'polling; re-entering resumes it', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      fake.stopLiveDataCalled = false;

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<ModeSelectionScreen>();
      expect(find.byType(DashboardScreen), findsNothing);
      expect(fake.stopLiveDataCalled, isTrue);
      expect(
        OBDService.instance.isInitialized,
        isTrue,
        reason: 'leaving the screen must not drop the link',
      );

      fake.startLiveDataCalled = false;
      await openDiagnostics(tester);
      await advance(tester, const Duration(seconds: 2));
      expect(findTr('connected'), findsOneWidget);
      expect(fake.startLiveDataCalled, isTrue);

      await unmountApp(tester);
    });
  });

  testWidgets('returning from a tab screen re-selects the Home tab', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      expect(_tabSelected(tester, Icons.home), isTrue);

      await tapOn(tester, findTr('history').last, scroll: false);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<HistoryScreen>();
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));

      expectOnScreen<DashboardScreen>();
      expect(_tabSelected(tester, Icons.home), isTrue);
      expect(_tabSelected(tester, Icons.history), isFalse);
      await unmountApp(tester);
    });
  });

  testWidgets('code detail screen lays out without overflow', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    fake.dtcsToReturn = ['P0420'];
    // Only the screens on the way in are tolerated, not the detail screen.
    await withKnownOverflows(
      files: ['dashboard_screen.dart', 'mode_selection_screen.dart'],
      () async {
        await connectedDashboard(tester);
        await tapOn(tester, findTr('quick_scan'));
        await pumpUntilFoundAsync(tester, find.text('P0420'));
        await advance(tester, const Duration(seconds: 1));
        await tapOn(tester, find.text('P0420'));
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<CodeDetailScreen>();
        await unmountApp(tester);
      },
    );
  });

  testWidgets('history screen lays out without overflow', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(
      files: ['dashboard_screen.dart', 'mode_selection_screen.dart'],
      () async {
        await bootToDashboard(tester);
        await tapOn(tester, findTr('history').last, scroll: false);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<HistoryScreen>();
        await unmountApp(tester);
      },
    );
  });

  // ── Adversarial double-checks ──────────────────────────────────────────────

  testWidgets('hub ↔ dashboard round-trips keep the link, stop polling while '
      'away and never stack live-data listeners', (tester) async {
    usePhoneSurface(tester);
    final counting = newCountingFakeAdapter();
    fake = counting; // connectedDashboard drives the shared `fake`
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      counting.emitLiveData(driving());
      await advance(tester, const Duration(milliseconds: 200));
      final baseline = counting.liveListeners;
      expect(baseline, greaterThan(0));

      for (var round = 1; round <= 3; round++) {
        final stopsBefore = counting.stopLiveDataCalls;
        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<ModeSelectionScreen>();
        expect(find.byType(DashboardScreen, skipOffstage: false), findsNothing);
        expect(counting.stopLiveDataCalls, greaterThan(stopsBefore));
        expect(counting.pollingActive, isFalse, reason: 'round $round');
        expect(
          counting.liveListeners,
          0,
          reason:
              'round $round: a disposed dashboard must drop every '
              'live-data subscription (dashboard subs, gauges, alerts)',
        );
        expect(OBDService.instance.isInitialized, isTrue);
        expect(counting.disconnectCalled, isFalse);

        // Nothing restarts polling while the user is on the hub.
        final startsOnHub = counting.startLiveDataCalls;
        await advance(tester, const Duration(seconds: 3));
        expect(
          counting.startLiveDataCalls,
          startsOnHub,
          reason: 'round $round',
        );

        await openDiagnostics(tester);
        await advance(tester, const Duration(seconds: 2));
        expect(findTr('connected'), findsOneWidget);
        expect(findTr('obd_not_connected'), findsNothing);
        expect(counting.startLiveDataCalls, greaterThan(startsOnHub));
        await advance(tester, const Duration(seconds: 1));
        expect(counting.pollingActive, isTrue, reason: 'round $round');
        expect(
          counting.liveListeners,
          baseline,
          reason: 'round $round: re-entering must not duplicate listeners',
        );

        final before = counting.deliveries;
        counting.emitLiveData(driving(rpm: 1000.0 + round * 100));
        await advance(tester, const Duration(milliseconds: 200));
        expect(gaugeShowing('${1000 + round * 100}'), findsOneWidget);
        expect(
          counting.deliveries - before,
          baseline,
          reason: 'each poll reaches each listener exactly once',
        );
      }
      await unmountApp(tester);
    });
  });

  testWidgets('leaving the dashboard while its on-connect requests are in '
      'flight does not restart polling afterwards', (tester) async {
    usePhoneSurface(tester);
    final fake = newCountingFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await tapOn(tester, findTr('obd_not_connected'));
      await advance(tester, const Duration(milliseconds: 500));
      await pumpUntilFound(tester, find.text('OBDII'));
      await tapOn(tester, find.text('OBDII'));
      await advance(tester, const Duration(milliseconds: 300));
      await tapOn(tester, findTr('scan_vehicle'));
      // Back on the dashboard, the DTC / readiness / VIN requests are
      // still waiting out their 300 ms settle when the user leaves.
      await advance(tester, const Duration(milliseconds: 150));
      expectOnScreen<DashboardScreen>();
      expect(fake.getDtcsCalled, isFalse, reason: 'request still in flight');
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<ModeSelectionScreen>();
      expect(find.byType(DashboardScreen, skipOffstage: false), findsNothing);
      // Readiness (chained after the DTC read) and the VIN are still pending
      // or just finishing as the dashboard is disposed; once they are done
      // the adapter's poll timer must be off.
      await advance(tester, const Duration(seconds: 3));
      expect(fake.getDtcsCalled, isTrue);
      expect(
        fake.pollingActive,
        isFalse,
        reason: 'a request finishing after dispose must not resume polling',
      );
      final startsAfterSettled = fake.startLiveDataCalls;
      await advance(tester, const Duration(seconds: 3));
      expect(fake.startLiveDataCalls, startsAfterSettled);
      expect(fake.liveListeners, 0);
      expect(OBDService.instance.isInitialized, isTrue);
      await unmountApp(tester);
    });
  });

  testWidgets('every tab round-trip gives the highlight back to Home', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    // Smart Key's header overflows (see the skipped layout test below);
    // only that one spot is tolerated here.
    await withKnownOverflows(files: _smartKeyHeader, () async {
      await bootToDashboard(tester);
      _expectHomeOnlySelected(tester);

      final tabs = <(IconData, Type)>[
        (Icons.history, HistoryScreen),
        (Icons.search, DiagnosticCodesScreen),
        (Icons.vpn_key, SmartKeyScreen),
        (Icons.settings, SettingsScreen),
      ];
      for (final (icon, screen) in tabs) {
        await tapOn(tester, _tab(icon), scroll: false);
        await advance(tester, const Duration(milliseconds: 600));
        expect(find.byType(screen), findsOneWidget, reason: '$screen opened');
        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<DashboardScreen>();
        _expectHomeOnlySelected(tester);
      }

      // The same, leaving through the screens' own back arrow.
      await tapOn(tester, _tab(Icons.history), scroll: false);
      await advance(tester, const Duration(milliseconds: 600));
      await tapOn(tester, find.byIcon(Icons.arrow_back).last, scroll: false);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<DashboardScreen>();
      _expectHomeOnlySelected(tester);

      // The maintenance card (not a tab) leaves the highlight on Home too.
      await tapOn(tester, findTr('maintenance_tracker'));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<MaintenanceScreen>();
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<DashboardScreen>();
      _expectHomeOnlySelected(tester);

      // Tapping Home itself keeps it selected and pushes nothing.
      await tapOn(tester, _tab(Icons.home), scroll: false);
      await advance(tester, const Duration(milliseconds: 400));
      expectOnScreen<DashboardScreen>();
      _expectHomeOnlySelected(tester);
      await unmountApp(tester);
    });
  });

  testWidgets('logout from settings lands on the auth screen and Back cannot '
      'return into the app', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      expect(AppServices.instance.session.isLoggedIn, isTrue);

      await tapOn(tester, _tab(Icons.settings), scroll: false);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<SettingsScreen>();

      // Cancel first: nothing happens.
      await tapOn(tester, findTr('logout'));
      await advance(tester, const Duration(milliseconds: 400));
      expect(findTr('logout_confirm'), findsOneWidget);
      await tapOn(tester, findTr('cancel'), scroll: false);
      await advance(tester, const Duration(milliseconds: 400));
      expectOnScreen<SettingsScreen>();
      expect(AppServices.instance.session.isLoggedIn, isTrue);

      // Then confirm.
      await tapOn(tester, findTr('logout'));
      await advance(tester, const Duration(milliseconds: 400));
      fake.stopLiveDataCalled = false;
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: findTr('logout'),
        ),
        scroll: false,
      );
      await advance(tester, const Duration(seconds: 1));

      expectOnScreen<AuthScreen>();
      expect(AppServices.instance.session.isLoggedIn, isFalse);
      expect(AppServices.instance.session.token, isNull);
      for (final type in [
        SettingsScreen,
        DashboardScreen,
        ModeSelectionScreen,
        ConnectionScreen,
      ]) {
        expect(
          find.byType(type, skipOffstage: false),
          findsNothing,
          reason: '$type must be removed from the stack',
        );
      }
      expect(
        fake.stopLiveDataCalled,
        isTrue,
        reason: 'the removed dashboard stops live polling',
      );

      // System Back: nothing to go back to — still on auth.
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<AuthScreen>();
      expect(find.byType(DashboardScreen, skipOffstage: false), findsNothing);
      expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
      expect(
        Navigator.of(tester.element(find.byType(AuthScreen))).canPop(),
        isFalse,
      );
      await unmountApp(tester);
    });
  });

  group('', () {
    testWidgets('smart key screen lays out without overflow', (tester) async {
      usePhoneSurface(tester);
      fake = newFakeAdapter();
      await withKnownOverflows(files: const [], () async {
        await bootToDashboard(tester);
        await tapOn(tester, _tab(Icons.vpn_key), scroll: false);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<SmartKeyScreen>();
        await unmountApp(tester);
      });
    });
  });
}
