import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/maintenance_service.dart';
import 'package:mycar/modules/home/presentation/pages/maintenanceScreen/maintenance_screen.dart';

import 'helpers/screen_harness.dart';

const _itemsKey = 'maintenance_v1';
const _mileageKey = 'maintenance_mileage_v1';

const _red = Color(0xFFFF1744);
const _yellow = Color(0xFFFFD600);

// Tall enough that all 7 default items are laid out (ListView.builder is
// lazy) — used for tests that inspect every card.
const _tall = Size(390, 1800);

/// Seeds prefs. `'{}'` for the items key resets the [MaintenanceService]
/// singleton to the defaults on load (it keeps its in-memory items when the
/// key is absent).
void _seed({double mileage = 0, Map<String, dynamic> items = const {}}) {
  SharedPreferences.setMockInitialValues({
    _itemsKey: jsonEncode(items),
    _mileageKey: mileage,
  });
}

Map<String, dynamic> _logged({required double km, required int daysAgo}) => {
  'lastMileageKm': km,
  'lastServiceDate': DateTime.now()
      .subtract(Duration(days: daysAgo))
      .toIso8601String(),
  'notes': '',
};

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) async {
  await pumpScreen(
    tester,
    const MaintenanceScreen(),
    locale: locale,
    size: size,
    pushed: pushed,
  );
  // MaintenanceService.load() → SharedPreferences (in-memory) → setState.
  await tester.pump();
  await tester.pump();
}

Finder _logButtons([Locale l = en]) => find.text(tr('log_label', l));

/// Status pills currently shown (Overdue / Due soon / OK).
Finder _statusPills([Locale l = en]) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data == tr('status_overdue', l) ||
          w.data == tr('status_due_soon', l) ||
          w.data == tr('status_ok', l)),
);

/// Colours of the small dots drawn on item icons when due/overdue (the only
/// [Positioned] widgets inside the list).
Iterable<Color?> _dotColors(WidgetTester tester) => tester
    .widgetList<Positioned>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Positioned),
      ),
    )
    .map((p) {
      final c = p.child as Container;
      return (c.decoration as BoxDecoration).color;
    });

void main() {
  setUpAll(loadAppFonts);
  setUp(() => _seed());

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets(
        'renders at phone size without exceptions (${locale.languageCode})',
        (tester) async {
          await _pump(tester, locale: locale);
          expectNoException(tester);

          expect(find.byType(MaintenanceScreen), findsOneWidget);
          expect(find.text(tr('maintenance_tracker', locale)), findsOneWidget);
          expect(find.text(tr('current_mileage', locale)), findsOneWidget);
          expect(find.text(tr('set', locale)), findsOneWidget);
          expect(_logButtons(locale), findsWidgets);
          expect(
            directionAt(tester, find.byType(MaintenanceScreen)),
            locale == ar ? TextDirection.rtl : TextDirection.ltr,
          );
        },
      );
    }

    testWidgets('renders on a small phone without overflow', (tester) async {
      await _pump(tester, size: smallPhone, locale: ar);
      expectNoException(tester);
    });

    // Header: the title used to sit unconstrained next to the back button.
    for (final locale in [en, ar]) {
      testWidgets(
        'header title is one ellipsized line on a 320-wide phone '
        '(${locale.languageCode})',
        (tester) async {
          await _pump(tester, size: const Size(320, 568), locale: locale);
          expectNoException(tester);
          final title = tester.widget<Text>(
            find.text(tr('maintenance_tracker', locale)),
          );
          expect(title.maxLines, 1);
          expect(title.overflow, TextOverflow.ellipsis);
          // The title ends before the screen edge.
          final rect = tester.getRect(
            find.text(tr('maintenance_tracker', locale)),
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
        },
      );
    }

    testWidgets('shows a spinner until the service has loaded', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(buildHarness(const MaintenanceScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('lists all seven default service items', (tester) async {
      await _pump(tester, size: _tall);
      expect(
        _logButtons(),
        findsNWidgets(MaintenanceService.instance.items.length),
      );
      expect(MaintenanceService.instance.items, hasLength(7));
    });
  });

  group('never-serviced items', () {
    testWidgets('show neutral styling: no status pill, no badge dot', (
      tester,
    ) async {
      _seed(mileage: 250000); // far past every interval — still unknown.
      await _pump(tester, size: _tall);

      expect(_logButtons(), findsNWidgets(7));
      expect(_statusPills(), findsNothing);
      expect(_dotColors(tester), isEmpty);
      expect(find.text(tr('never_serviced')), findsNWidgets(7));
    });

    testWidgets('card border is neutral, not red/yellow/green', (tester) async {
      _seed(mileage: 250000);
      await _pump(tester, size: _tall);

      final borders = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.border)
          .whereType<Border>()
          .map((b) => b.top.color.withValues(alpha: 1))
          .toSet();
      for (final status in const [_red, _yellow, Color(0xFF00E676)]) {
        expect(
          borders.contains(status),
          isFalse,
          reason: 'never-serviced card bordered with $status',
        );
      }
    });
  });

  group('logged items', () {
    testWidgets('overdue item shows the overdue pill and a red badge', (
      tester,
    ) async {
      _seed(mileage: 6000, items: {'oil': _logged(km: 0, daysAgo: 10)});
      await _pump(tester, size: _tall);

      expect(find.text(tr('status_overdue')), findsOneWidget);
      expect(_dotColors(tester), [_red]);
      expect(find.text(tr('never_serviced')), findsNWidgets(6));
    });

    testWidgets('due-soon item shows the due-soon pill and a yellow badge', (
      tester,
    ) async {
      _seed(mileage: 4900, items: {'oil': _logged(km: 0, daysAgo: 10)});
      await _pump(tester, size: _tall);

      expect(find.text(tr('status_due_soon')), findsOneWidget);
      expect(_dotColors(tester), [_yellow]);
    });

    testWidgets('item well within its interval shows OK and no badge', (
      tester,
    ) async {
      _seed(mileage: 1000, items: {'oil': _logged(km: 0, daysAgo: 10)});
      await _pump(tester, size: _tall);

      expect(find.text(tr('status_ok')), findsOneWidget);
      expect(_dotColors(tester), isEmpty);
    });

    testWidgets('date-overdue item is overdue even with low mileage', (
      tester,
    ) async {
      // Oil: 180-day interval.
      _seed(mileage: 100, items: {'oil': _logged(km: 0, daysAgo: 400)});
      await _pump(tester, size: _tall);

      expect(find.text(tr('status_overdue')), findsOneWidget);
    });
  });

  group('log a service', () {
    testWidgets('confirming marks the item serviced and persists it', (
      tester,
    ) async {
      _seed(mileage: 12000);
      await _pump(tester, size: _tall);
      expect(_statusPills(), findsNothing);

      await tester.tap(_logButtons().first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // The dialog quotes the current mileage.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('12000'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(tr('confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr('status_ok')), findsOneWidget);
      expect(find.text(tr('never_serviced')), findsNWidgets(6));

      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(_itemsKey)!) as Map;
      final first = MaintenanceService.instance.items.first.id;
      expect((saved[first] as Map)['lastMileageKm'], 12000);
      expect((saved[first] as Map)['lastServiceDate'], isNotNull);
    });

    testWidgets('cancelling leaves the item unserviced', (tester) async {
      await _pump(tester, size: _tall);

      await tester.tap(_logButtons().first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(_statusPills(), findsNothing);
      expect(find.text(tr('never_serviced')), findsNWidgets(7));
    });

    testWidgets('log flow works in Arabic', (tester) async {
      await _pump(tester, size: _tall, locale: ar);

      await tester.tap(_logButtons(ar).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('confirm', ar)));
      await tester.pumpAndSettle();

      expectNoException(tester);
      expect(find.text(tr('status_ok', ar)), findsOneWidget);
    });
  });

  group('odometer', () {
    testWidgets('shows the stored mileage', (tester) async {
      _seed(mileage: 48250);
      await _pump(tester);
      expect(find.textContaining('48250'), findsOneWidget);
    });

    testWidgets('Set → save updates the card and persists', (tester) async {
      _seed(mileage: 100);
      await _pump(tester);

      await tester.tap(find.text(tr('set')));
      await tester.pumpAndSettle();
      expect(find.text(tr('set_current_mileage')), findsOneWidget);
      // Pre-filled with the current value.
      expect(find.widgetWithText(TextField, '100'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '75500');
      await tester.tap(find.text(tr('save')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('75500'), findsOneWidget);
      expect(MaintenanceService.instance.currentMileageKm, 75500);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(_mileageKey), 75500);
    });

    testWidgets('non-numeric input is ignored and the dialog closes', (
      tester,
    ) async {
      _seed(mileage: 100);
      await _pump(tester);

      await tester.tap(find.text(tr('set')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.text(tr('save')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(MaintenanceService.instance.currentMileageKm, 100);
    });

    testWidgets('cancel keeps the old mileage', (tester) async {
      _seed(mileage: 100);
      await _pump(tester);

      await tester.tap(find.text(tr('set')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '999');
      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();

      expect(MaintenanceService.instance.currentMileageKm, 100);
    });

    testWidgets('raising the odometer turns a logged item due/overdue', (
      tester,
    ) async {
      _seed(mileage: 1000, items: {'oil': _logged(km: 0, daysAgo: 1)});
      await _pump(tester, size: _tall);
      expect(find.text(tr('status_ok')), findsOneWidget);

      await tester.tap(find.text(tr('set')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9000');
      await tester.tap(find.text(tr('save')));
      await tester.pumpAndSettle();

      expect(find.text(tr('status_overdue')), findsOneWidget);
      expect(_dotColors(tester), [_red]);
    });
  });

  group('navigation', () {
    testWidgets('back arrow pops the screen', (tester) async {
      await _pump(tester, pushed: true);
      expect(find.byType(MaintenanceScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(MaintenanceScreen), findsNothing);
      expect(find.text(launcherText), findsOneWidget);
    });
  });
}
