// Flow 3 — maintenance tracking through the real app, from a fresh install:
//
//   fresh install → dashboard shows no (false) service warning → maintenance
//   tracker → log an oil change → nothing due → odometer advances a full
//   interval → back on the dashboard the "1 item due" alert appears → tap it
//   → log the service again → alert gone.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/services/maintenance_service.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/maintenanceScreen/maintenance_screen.dart';

import 'helpers/flow_harness.dart';
import 'helpers/obd_steps.dart';

/// The dashboard's "N maintenance items due" banner (its wrench icon).
Finder get _dueAlert => find.descendant(
  of: find.byType(DashboardScreen),
  matching: find.byIcon(Icons.build_outlined),
);

/// Text of the due banner, which starts with the due count.
String _dueAlertText(WidgetTester tester) {
  final row = find.ancestor(of: _dueAlert, matching: find.byType(Row)).first;
  return tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');
}

/// The dashboard's "Service" warning lamp is lit (orange label).
bool _serviceLampOn(WidgetTester tester, [String lang = 'en']) {
  final label = find.descendant(
    of: find.byType(GridView),
    matching: findTr('service', lang),
  );
  expect(label, findsOneWidget, reason: 'service lamp in the warning grid');
  return tester.widget<Text>(label).style?.color == const Color(0xFFFF6B35);
}

/// Opens the maintenance tracker by route from the dashboard (the
/// permanent card is exercised separately).
Future<void> _openTrackerByRoute(WidgetTester tester) async {
  Navigator.of(
    tester.element(find.byType(DashboardScreen)),
  ).pushNamed(AppRoutes.maintenance);
  await advance(tester, const Duration(milliseconds: 600));
  expectOnScreen<MaintenanceScreen>();
}

/// Taps the first item's "Log" button and confirms.
Future<void> _logFirstItem(WidgetTester tester) async {
  await tapOn(tester, findTr('log_label').first);
  await advance(tester, const Duration(milliseconds: 400));
  await tapOn(tester, findTr('confirm'));
  await advance(tester, const Duration(milliseconds: 400));
}

Future<void> _setMileage(WidgetTester tester, String km) async {
  await tapOn(tester, findTr('set'));
  await advance(tester, const Duration(milliseconds: 400));
  await tester.enterText(find.byType(TextField), km);
  await tapOn(tester, findTr('save'));
  await advance(tester, const Duration(milliseconds: 400));
}

void main() {
  setUpAll(FakeBlePlatform.install);

  setUp(installPlatformFakes);

  testWidgets('fresh install: no false service warning; logging a service '
      'and driving a full interval makes it due', (tester) async {
    usePhoneSurface(tester);
    newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);

      // ── Fresh install: nothing has been logged → nothing is due ──────
      await advance(tester, const Duration(milliseconds: 300));
      expect(MaintenanceService.instance.dueCount, 0);
      expect(
        _dueAlert,
        findsNothing,
        reason: 'never-serviced items must not raise a service warning',
      );

      // ── Tracker: every item "never serviced", no status badges ───────
      await _openTrackerByRoute(tester);
      // (The list is lazy: count the visible rows, not all items.)
      final visibleNever = findTr('never_serviced').evaluate().length;
      expect(visibleNever, greaterThan(1));
      expect(
        MaintenanceService.instance.items.where((i) => i.hasHistory),
        isEmpty,
      );
      expect(findTr('status_due_soon'), findsNothing);
      expect(findTr('status_ok'), findsNothing);

      // ── Log the oil change at 0 km → OK, still nothing due ───────────
      await _logFirstItem(tester);
      expect(findTr('never_serviced'), findsNWidgets(visibleNever - 1));
      expect(findTr('status_ok'), findsOneWidget);
      expect(MaintenanceService.instance.dueCount, 0);

      // ── Odometer reaches the 5000 km oil interval → due ──────────────
      await _setMileage(tester, '5000');
      expect(MaintenanceService.instance.currentMileageKm, 5000);
      expect(findTr('status_due_soon'), findsOneWidget);
      expect(findTr('status_ok'), findsNothing);
      expect(MaintenanceService.instance.dueCount, 1);

      // ── Back to the dashboard ────────────────────────────────────────
      await tapOn(tester, find.byIcon(Icons.arrow_back));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<DashboardScreen>();

      await unmountApp(tester);
    });
  });

  testWidgets('maintenance log survives an app restart', (tester) async {
    usePhoneSurface(tester);
    newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await _openTrackerByRoute(tester);
      await _logFirstItem(tester);
      await _setMileage(tester, '4900');
      expect(MaintenanceService.instance.dueCount, 1);
      await unmountApp(tester);

      // Cold start: same persisted prefs, fresh widget tree.
      await bootToDashboard(tester);
      await advance(tester, const Duration(milliseconds: 300));
      expect(MaintenanceService.instance.currentMileageKm, 4900);
      expect(MaintenanceService.instance.dueCount, 1);
      expect(_dueAlert, findsOneWidget);
      expect(_dueAlertText(tester), startsWith('1'));

      // The banner leads to the tracker, where servicing clears the item.
      await tapOn(tester, _dueAlert);
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<MaintenanceScreen>();
      expect(findTr('status_due_soon'), findsOneWidget);
      await _logFirstItem(tester);
      expect(MaintenanceService.instance.dueCount, 0);
      expect(findTr('status_ok'), findsOneWidget);
      await unmountApp(tester);
    });
  });

  testWidgets('fresh dashboard offers a way into the maintenance tracker', (
    tester,
  ) async {
    usePhoneSurface(tester);
    newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await advance(tester, const Duration(milliseconds: 300));
      expect(MaintenanceService.instance.dueCount, 0);

      // Any visible control on the dashboard (or the settings it links
      // to) labelled with the tracker's title.
      await tapOn(tester, findTr('maintenance_tracker'));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<MaintenanceScreen>();
      await unmountApp(tester);
    });
  });

  testWidgets('maintenance tracker lays out without overflow', (tester) async {
    usePhoneSurface(tester);
    newFakeAdapter();
    // Strict: no overflow tolerance at all.
    await bootToDashboard(tester);
    await _openTrackerByRoute(tester);
    await advance(tester, const Duration(milliseconds: 500));
    await unmountApp(tester);
  });

  testWidgets('due banner reflects changes made in the tracker', (
    tester,
  ) async {
    usePhoneSurface(tester);
    newFakeAdapter();
    await withKnownOverflows(() async {
      await bootToDashboard(tester);
      await _openTrackerByRoute(tester);
      await _logFirstItem(tester);
      await _setMileage(tester, '5000');
      expect(MaintenanceService.instance.dueCount, 1);

      await tapOn(tester, find.byIcon(Icons.arrow_back));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<DashboardScreen>();
      expect(_dueAlert, findsOneWidget);
      expect(_dueAlertText(tester), startsWith('1'));

      await tapOn(tester, _dueAlert);
      await advance(tester, const Duration(milliseconds: 600));
      await _logFirstItem(tester);
      expect(MaintenanceService.instance.dueCount, 0);
      await tapOn(tester, find.byIcon(Icons.arrow_back));
      await advance(tester, const Duration(milliseconds: 600));
      expectOnScreen<DashboardScreen>();
      expect(_dueAlert, findsNothing);
      await unmountApp(tester);
    });
  });

  // ── Adversarial double-check ──────────────────────────────────────────────

  for (final lang in ['en', 'ar']) {
    testWidgets('[$lang] fresh install: card → log → back shows nothing due; '
        'making it due shows the banner and lamp without a restart; '
        'servicing it clears both', (tester) async {
      usePhoneSurface(tester);
      newFakeAdapter();
      await withKnownOverflows(() async {
        await bootToDashboard(tester, locale: Locale(lang));
        await advance(tester, const Duration(milliseconds: 300));
        expect(MaintenanceService.instance.dueCount, 0);
        expect(_dueAlert, findsNothing);
        expect(_serviceLampOn(tester, lang), isFalse);

        // The permanent card opens the tracker on a fresh install.
        await tapOn(tester, findTr('maintenance_tracker', lang));
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<MaintenanceScreen>();
        await tapOn(tester, findTr('log_label', lang).first);
        await advance(tester, const Duration(milliseconds: 400));
        await tapOn(tester, findTr('confirm', lang));
        await advance(tester, const Duration(milliseconds: 400));
        expect(findTr('status_ok', lang), findsOneWidget);
        expect(MaintenanceService.instance.dueCount, 0);

        await tapOn(tester, find.byIcon(Icons.arrow_back));
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<DashboardScreen>();
        expect(_dueAlert, findsNothing, reason: 'just serviced: nothing due');
        expect(_serviceLampOn(tester, lang), isFalse);

        // Odometer reaches the interval (card again, system Back this time).
        await tapOn(tester, findTr('maintenance_tracker', lang));
        await advance(tester, const Duration(milliseconds: 600));
        await tapOn(tester, findTr('set', lang));
        await advance(tester, const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField), '5000');
        await tapOn(tester, findTr('save', lang));
        await advance(tester, const Duration(milliseconds: 400));
        expect(MaintenanceService.instance.dueCount, 1);
        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<DashboardScreen>();
        expect(_dueAlert, findsOneWidget, reason: 'banner without a restart');
        expect(_dueAlertText(tester), startsWith('1'));
        expect(_serviceLampOn(tester, lang), isTrue);

        // Banner → tracker → service it → back: banner and lamp clear.
        await tapOn(tester, _dueAlert);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<MaintenanceScreen>();
        expect(findTr('status_due_soon', lang), findsOneWidget);
        await tapOn(tester, findTr('log_label', lang).first);
        await advance(tester, const Duration(milliseconds: 400));
        await tapOn(tester, findTr('confirm', lang));
        await advance(tester, const Duration(milliseconds: 400));
        expect(MaintenanceService.instance.dueCount, 0);
        await pressBack(tester);
        await advance(tester, const Duration(milliseconds: 600));
        expectOnScreen<DashboardScreen>();
        expect(_dueAlert, findsNothing);
        expect(_serviceLampOn(tester, lang), isFalse);
        await unmountApp(tester);
      });
    });
  }
}
