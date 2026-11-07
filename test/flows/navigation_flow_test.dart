// Flow 5 — navigation, the system back button, and state preservation
// between screens of the running app: polling pauses and resumes around the
// codes scan, the dashboard keeps its connection/live data across the
// bottom-navigation tabs (Home · Diagnose · Roadside · History · Profile),
// the codes list survives a detail round-trip, Back on a tab returns to Home,
// Back on Home does not drop the user out on one press, and logout.
// Expected-but-broken behaviours are skipped as REGRESSIONs.

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
import 'package:mycar/modules/home/presentation/pages/settingsScreen/settings_screen.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';
import 'package:mycar/modules/home/presentation/pages/smartKeyScreen/smart_key_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/roadside_home_screen.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/flow_harness.dart';
import 'helpers/obd_steps.dart';

/// Asserts the shell is on Home and the navigation bar highlights it.
void _expectHomeSelected(WidgetTester tester) {
  expect(currentTab(tester), AppTab.home);
  expect(highlightedTab(tester), AppTab.home);
  expectOnScreen<DashboardScreen>();
}

/// Each tab and the screen it shows.
const _tabScreens = <AppTab, Type>{
  AppTab.home: DashboardScreen,
  AppTab.diagnose: DiagnosticCodesScreen,
  AppTab.roadside: RoadsideHomeScreen,
  AppTab.history: HistoryScreen,
  AppTab.profile: SettingsScreen,
};

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

      await goToTab(tester, AppTab.history);
      expectOnScreen<HistoryScreen>();
      expect(find.byType(DashboardScreen), findsNothing);

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));
      _expectHomeSelected(tester);
      expect(tester.state(find.byType(DashboardScreen)), same(dashboardState));
      expect(findTr('connected'), findsOneWidget);
      expect(OBDService.instance.isInitialized, isTrue);
      fake.emitLiveData(driving(rpm: 2200));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2200'), findsOneWidget);

      await unmountApp(tester);
    });
  });

  // Was 'back on the service hub asks before exiting; cancel stays'. The hub
  // is gone; Home is the root tab and a single Back must not drop the user
  // out of the app (the dashboard asks for a second press).
  testWidgets('back on Home does not leave the app on one press', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToShell(tester);
      await advance(tester, const Duration(seconds: 1));

      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 400));
      expect(findTr('press_back_to_exit'), findsOneWidget);
      _expectHomeSelected(tester);
      expectOnScreen<AppShell>();

      await advance(tester, const Duration(seconds: 3)); // snackbar timeout
      await unmountApp(tester);
    });
  });

  // Was 'back from the dashboard returns to the hub and stops polling;
  // re-entering resumes it'. Tabs are kept alive, so leaving Home for
  // another tab keeps the dashboard — and its live session — running.
  testWidgets('leaving Home for another tab keeps the link and the live '
      'session; coming back shows fresh data', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      final dashboardState = tester.state(find.byType(DashboardScreen));

      await goToTab(tester, AppTab.profile);
      expectOnScreen<SettingsScreen>();
      expect(find.byType(DashboardScreen), findsNothing);
      expect(
        OBDService.instance.isInitialized,
        isTrue,
        reason: 'switching tabs must not drop the link',
      );
      expect(fake.disconnectCalled, isFalse);

      await goToTab(tester, AppTab.home);
      _expectHomeSelected(tester);
      expect(tester.state(find.byType(DashboardScreen)), same(dashboardState));
      expect(findTr('connected'), findsOneWidget);
      fake.emitLiveData(driving(rpm: 1900));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('1900'), findsOneWidget);

      await unmountApp(tester);
    });
  });

  testWidgets('returning from a tab re-selects the Home tab', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      _expectHomeSelected(tester);

      await goToTab(tester, AppTab.history);
      expectOnScreen<HistoryScreen>();
      expect(highlightedTab(tester), AppTab.history);
      await pressBack(tester);
      await advance(tester, const Duration(milliseconds: 600));

      _expectHomeSelected(tester);
      await unmountApp(tester);
    });
  });

  testWidgets('code detail screen lays out without overflow', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    fake.dtcsToReturn = ['P0420'];
    // Only the screens on the way in are tolerated, not the detail screen.
    await withKnownOverflows(
      files: ['dashboard_screen.dart'],
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
      files: ['dashboard_screen.dart'],
      () async {
        await bootToDashboard(tester);
        await goToTab(tester, AppTab.history);
        await advance(tester, const Duration(milliseconds: 200));
        expectOnScreen<HistoryScreen>();
        await unmountApp(tester);
      },
    );
  });

  // ── Adversarial double-checks ──────────────────────────────────────────────

  // Was 'hub ↔ dashboard round-trips …': the dashboard is no longer
  // disposed when the user leaves it (tabs stay alive), so the checks are now
  // that repeated tab trips keep one live session and never stack listeners.
  testWidgets('Home ↔ tab round-trips keep the link and the live session and '
      'never stack live-data listeners', (tester) async {
    usePhoneSurface(tester);
    final counting = newCountingFakeAdapter();
    fake = counting; // connectedDashboard drives the shared `fake`
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      counting.emitLiveData(driving());
      await advance(tester, const Duration(milliseconds: 200));
      expect(counting.liveListeners, greaterThan(0));
      final dashboardState = tester.state(find.byType(DashboardScreen));

      int? listenersAfterFirstRound;
      for (var round = 1; round <= 3; round++) {
        for (final tab in [AppTab.history, AppTab.roadside, AppTab.profile]) {
          await goToTab(tester, tab);
          expect(find.byType(_tabScreens[tab]!), findsOneWidget);
          await advance(tester, const Duration(milliseconds: 500));
          expect(OBDService.instance.isInitialized, isTrue);
          expect(counting.disconnectCalled, isFalse);
          // Back with the system button on one tab, the Home tab otherwise.
          if (tab == AppTab.history) {
            await pressBack(tester);
            await advance(tester, const Duration(milliseconds: 400));
          } else {
            await goToTab(tester, AppTab.home);
          }
          _expectHomeSelected(tester);
        }
        expect(
          tester.state(find.byType(DashboardScreen)),
          same(dashboardState),
          reason: 'round $round: the dashboard is kept, not rebuilt',
        );
        expect(findTr('connected'), findsOneWidget);
        expect(findTr('obd_not_connected'), findsNothing);
        await advance(tester, const Duration(seconds: 1));
        expect(counting.pollingActive, isTrue, reason: 'round $round');

        listenersAfterFirstRound ??= counting.liveListeners;
        expect(
          counting.liveListeners,
          listenersAfterFirstRound,
          reason: 'round $round: tab trips must not add listeners',
        );

        final before = counting.deliveries;
        counting.emitLiveData(driving(rpm: 1000.0 + round * 100));
        await advance(tester, const Duration(milliseconds: 200));
        expect(gaugeShowing('${1000 + round * 100}'), findsOneWidget);
        expect(
          counting.deliveries - before,
          counting.liveListeners,
          reason: 'each poll reaches each listener exactly once',
        );
      }
      await unmountApp(tester);
    });
  });

  // Was 'leaving the dashboard while its on-connect requests are in flight
  // does not restart polling afterwards' (the dashboard was disposed). Now
  // the dashboard stays alive on its tab, so the requests must finish and
  // live polling must resume exactly once.
  testWidgets('switching tabs while the on-connect requests are in flight '
      'lets them finish and resumes one live session', (tester) async {
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
      // still waiting out their 300 ms settle when the user switches tab.
      await advance(tester, const Duration(milliseconds: 150));
      expectOnScreen<DashboardScreen>();
      expect(fake.getDtcsCalled, isFalse, reason: 'request still in flight');
      await goToTab(tester, AppTab.history);
      expectOnScreen<HistoryScreen>();

      await advance(tester, const Duration(seconds: 3));
      expect(fake.getDtcsCalled, isTrue);
      expect(fake.pollingActive, isTrue, reason: 'live session resumed');
      final listeners = fake.liveListeners;
      expect(listeners, greaterThan(0));
      final starts = fake.startLiveDataCalls;
      await advance(tester, const Duration(seconds: 3));
      expect(fake.startLiveDataCalls, starts, reason: 'no restart loop');
      expect(OBDService.instance.isInitialized, isTrue);

      await goToTab(tester, AppTab.home);
      expect(findTr('connected'), findsOneWidget);
      expect(fake.liveListeners, listeners);
      fake.emitLiveData(driving(rpm: 2600));
      await advance(tester, const Duration(milliseconds: 200));
      expect(gaugeShowing('2600'), findsOneWidget);
      await unmountApp(tester);
    });
  });

  testWidgets('every tab round-trip gives the highlight back to Home', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(files: const [], () async {
      await bootToDashboard(tester);
      _expectHomeSelected(tester);

      for (final tab in [
        AppTab.history,
        AppTab.diagnose,
        AppTab.roadside,
        AppTab.profile,
      ]) {
        final screen = _tabScreens[tab]!;
        await goToTab(tester, tab);
        expect(find.byType(screen), findsOneWidget, reason: '$screen opened');
        expect(highlightedTab(tester), tab);
        expect(
          Navigator.of(tester.element(find.byType(AppShell))).canPop(),
          isFalse,
          reason: 'tabs switch in place; no route is pushed',
        );
        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 600));
        _expectHomeSelected(tester);
      }

      // The same, leaving through the Home tab itself.
      await goToTab(tester, AppTab.history);
      await goToTab(tester, AppTab.home);
      _expectHomeSelected(tester);

      // A screen pushed from Home (the Maintenance service, not a tab)
      // leaves the highlight on Home, and its back arrow returns there.
      await tapOn(tester, findTr('dash_svc_maintenance'));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<MaintenanceScreen>();
      expect(highlightedTab(tester), AppTab.home);
      await tapOn(
        tester,
        find.byIcon(Icons.arrow_back_rounded).last,
        scroll: false,
      );
      await advance(tester, const Duration(milliseconds: 600));
      _expectHomeSelected(tester);

      // Tapping Home itself keeps it selected and pushes nothing.
      await goToTab(tester, AppTab.home);
      _expectHomeSelected(tester);
      expect(
        Navigator.of(tester.element(find.byType(AppShell))).canPop(),
        isFalse,
      );
      await unmountApp(tester);
    });
  });

  testWidgets('logout from Profile lands on the auth screen and Back cannot '
      'return into the app', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() async {
      await connectedDashboard(tester);
      expect(AppServices.instance.session.isLoggedIn, isTrue);

      await goToTab(tester, AppTab.profile);
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
        AppShell,
        SettingsScreen,
        DashboardScreen,
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
      expect(find.byType(AppShell, skipOffstage: false), findsNothing);
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
    // Smart Key was a tab on the dashboard's old bottom bar; it is now
    // opened from Home's Services row.
    testWidgets('smart key screen lays out without overflow', (tester) async {
      usePhoneSurface(tester);
      fake = newFakeAdapter();
      await withKnownOverflows(files: const [], () async {
        await bootToDashboard(tester);
        await tapOn(tester, findTr('smart_key'));
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<SmartKeyScreen>();
        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 600));
        _expectHomeSelected(tester);
        await unmountApp(tester);
      });
    });
  });
}
