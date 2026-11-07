// Flow 2 — the OBD-II diagnostics journey in Arabic (the app's default
// locale): right-to-left layout, Arabic texts on every screen, and no
// exceptions or layout overflows along the way. The journey runs twice:
// tolerating only the reported overflow listed in flow_harness.dart's
// knownOverflowFiles, and fully strict (skipped while that REGRESSION stands).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/flow_harness.dart';
import 'helpers/obd_steps.dart';

const _ar = Locale('ar');

/// The ambient text direction at [finder].
TextDirection _directionAt(WidgetTester tester, Finder finder) =>
    Directionality.of(tester.element(finder));

/// The whole Arabic journey; the caller decides the overflow tolerance.
Future<void> _arabicJourney(WidgetTester tester, FakeOBDAdapter fake) async {
  fake
    ..dtcsToReturn = ['P0420', 'P0171']
    ..clearShouldFail = true;

  // ── Splash → app shell (Home tab), in Arabic and RTL ───────────────
  await bootToShell(tester, locale: _ar);
  await advance(tester, const Duration(seconds: 1));
  _expectArabicNav(tester);
  expect(_directionAt(tester, find.byType(NavigationBar)), TextDirection.rtl);

  // ── Dashboard (disconnected) ───────────────────────────────────────
  expect(_directionAt(tester, find.byType(DashboardScreen)), TextDirection.rtl);
  expect(findTr('obd_not_connected', 'ar'), findsOneWidget);
  expect(findTr('quick_scan', 'ar'), findsOneWidget);
  expect(findTr('warning_lights', 'ar'), findsOneWidget);

  // ── Connect through the connection screen ──────────────────────────
  await connectThroughConnectionScreen(tester, fake, lang: 'ar');
  expect(findTr('connected', 'ar'), findsOneWidget);
  expect(findTr('live_data', 'ar'), findsOneWidget);

  fake.emitLiveData(driving());
  await advance(tester, const Duration(milliseconds: 200));
  expect(gaugeShowing('2500'), findsOneWidget);

  // ── Codes screen: scan, refused clear, successful clear ────────────
  await tapOn(tester, findTr('quick_scan', 'ar'));
  await advance(tester, const Duration(milliseconds: 400));
  expectOnScreen<DiagnosticCodesScreen>();
  expect(findTr('diagnostic_codes', 'ar'), findsOneWidget);
  await pumpUntilFoundAsync(tester, find.text('P0420'));
  expect(find.text('P0171'), findsOneWidget);

  await clearCodesViaDialog(tester, lang: 'ar');
  expect(findTr('failed_clear_codes_hint', 'ar'), findsOneWidget);
  expect(find.text('P0420'), findsOneWidget);
  await advance(tester, const Duration(seconds: 9)); // snackbar timeout

  fake.clearShouldFail = false;
  await clearCodesViaDialog(tester, lang: 'ar');
  await pumpUntilFoundAsync(tester, findTr('no_codes_found', 'ar'));
  expect(find.text('P0420'), findsNothing);

  // ── Back to the dashboard ──────────────────────────────────────────
  await pressBack(tester);
  await advance(tester, const Duration(milliseconds: 500));
  expectOnScreen<DashboardScreen>();
  expect(findTr('connected', 'ar'), findsOneWidget);

  // ── Disconnect through the connected header (Arabic adapter screen) ─
  await disconnectThroughHeader(tester, fake, lang: 'ar');
  await pressBack(tester);
  await advance(tester, const Duration(milliseconds: 500));
  expectOnScreen<DashboardScreen>();
  expect(findTr('obd_not_connected', 'ar'), findsOneWidget);
  expect(OBDService.instance.isInitialized, isFalse);

  // ── Other tabs, still Arabic and RTL; Back returns to Home ─────────
  for (final tab in AppTab.values.skip(1)) {
    await goToTab(tester, tab, lang: 'ar');
    expect(currentTab(tester), tab);
    _expectArabicNav(tester);
    await pressBack(tester);
    await advance(tester, const Duration(milliseconds: 400));
    expect(currentTab(tester), AppTab.home);
    expectOnScreen<DashboardScreen>();
  }

  await unmountApp(tester);
}

/// Every bottom-navigation label is the Arabic one, none English.
void _expectArabicNav(WidgetTester tester) {
  for (final tab in AppTab.values) {
    expect(navTab(tab, lang: 'ar'), findsOneWidget, reason: '$tab');
    expect(navTab(tab), findsNothing, reason: '$tab: no English leak');
  }
}

void main() {
  late FakeOBDAdapter fake;

  setUpAll(FakeBlePlatform.install);

  setUp(installPlatformFakes);

  testWidgets('Arabic (RTL) diagnostics journey', (tester) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    await withKnownOverflows(() => _arabicJourney(tester, fake));
  });

  group('', () {
    testWidgets('Arabic (RTL) diagnostics journey with no overflow at all', (
      tester,
    ) async {
      usePhoneSurface(tester);
      fake = newFakeAdapter();
      await withKnownOverflows(
        files: const [],
        () => _arabicJourney(tester, fake),
      );
    });
  });

  // Was 'Arabic service hub lays out without overflow': the hub is replaced
  // by the bottom-navigation shell, so every tab is checked instead.
  testWidgets('Arabic app shell: every tab lays out without overflow', (
    tester,
  ) async {
    usePhoneSurface(tester);
    fake = newFakeAdapter();
    // Strict: no overflow tolerance at all.
    await bootToShell(tester, locale: _ar);
    await advance(tester, const Duration(seconds: 2));
    for (final tab in [...AppTab.values.skip(1), AppTab.home]) {
      await goToTab(tester, tab, lang: 'ar');
      await advance(tester, const Duration(seconds: 1));
      expect(currentTab(tester), tab);
    }
    await unmountApp(tester);
  });
}
