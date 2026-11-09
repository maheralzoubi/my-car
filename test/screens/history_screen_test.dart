import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/dtc_history_service.dart';
import 'package:mycar/modules/home/presentation/pages/historyScreen/history_screen.dart';

import 'helpers/screen_harness.dart';

const _key = 'dtc_history_v1';

Map<String, dynamic> _entry(DateTime at, double km, List<String> codes) => {
  'scannedAt': at.toIso8601String(),
  'mileageKm': km,
  'codes': codes,
};

/// Seeds the history store. An explicit `'[]'` (rather than no key) resets
/// the [DtcHistoryService] singleton, which keeps its entries when the key is
/// absent.
void _seed(List<Map<String, dynamic>> entries) =>
    SharedPreferences.setMockInitialValues({_key: jsonEncode(entries)});

final _now = DateTime.now();

/// Newest first after load: clean (today), confirmed+pending (yesterday),
/// confirmed only (10 days ago).
List<Map<String, dynamic>> _three() => [
  _entry(_now.subtract(const Duration(days: 10)), 41000, ['P0420']),
  _entry(_now.subtract(const Duration(hours: 1)), 42500, []),
  _entry(_now.subtract(const Duration(days: 1, hours: 2)), 42000, [
    'P0300',
    '~P0171',
  ]),
];

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) async {
  await pumpScreen(
    tester,
    const HistoryScreen(),
    locale: locale,
    size: size,
    pushed: pushed,
  );
  await tester.pump();
  // Entry fade-in (TweenAnimationBuilder, up to ~400 ms).
  await tester.pump(const Duration(seconds: 1));
}

Finder get _filterRow => find.byWidgetPredicate(
  (w) => w is ListView && w.scrollDirection == Axis.horizontal,
);

Finder _filterChip(String key, [Locale l = en]) =>
    find.descendant(of: _filterRow, matching: find.text(tr(key, l)));

Finder get _entryList => find.byWidgetPredicate(
  (w) => w is ListView && w.scrollDirection == Axis.vertical,
);

Finder _inEntries(String text) =>
    find.descendant(of: _entryList, matching: find.text(text));

void main() {
  setUpAll(loadAppFonts);
  setUp(() => _seed([]));

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets(
        'renders with entries at phone size (${locale.languageCode})',
        (tester) async {
          _seed(_three());
          await _pump(tester, locale: locale);
          expectNoException(tester);

          expect(find.text(tr('history_title', locale)), findsOneWidget);
          expect(find.text(tr('total_scans', locale)), findsOneWidget);
          expect(_filterChip('all', locale), findsOneWidget);
          expect(_filterChip('with_codes', locale), findsOneWidget);
          expect(_filterChip('clean_scan', locale), findsOneWidget);
          expect(
            directionAt(tester, find.byType(HistoryScreen)),
            locale == ar ? TextDirection.rtl : TextDirection.ltr,
          );
        },
      );

      testWidgets('empty state renders (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        expect(find.byIcon(Icons.history), findsOneWidget);
        expect(find.text(tr('no_scan_history_yet', locale)), findsOneWidget);
        expect(find.text(tr('run_scan_to_log', locale)), findsOneWidget);
      });
    }

    testWidgets('small phone, Arabic, with entries: no overflow', (
      tester,
    ) async {
      _seed(_three());
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    // Header: title + delete button used to overflow (title had no
    // Expanded / ellipsis).
    for (final locale in [en, ar]) {
      testWidgets(
        'header title + delete button fit a 320-wide phone '
        '(${locale.languageCode})',
        (tester) async {
          _seed(_three());
          await _pump(tester, locale: locale, size: const Size(320, 568));
          expectNoException(tester);
          final finder = find.text(tr('history_title', locale));
          final title = tester.widget<Text>(finder);
          expect(title.maxLines, 1);
          expect(title.overflow, TextOverflow.ellipsis);
          expect(find.byIcon(Icons.delete_outline), findsOneWidget);
          final del = tester.getRect(find.byIcon(Icons.delete_outline));
          expect(del.left, greaterThanOrEqualTo(0));
          expect(del.right, lessThanOrEqualTo(320));
          // Title and delete button don't overlap.
          expect(tester.getRect(finder).overlaps(del), isFalse);
        },
      );
    }

    testWidgets('shows a spinner until history has loaded', (tester) async {
      setPhoneSurface(tester);
      await tester.pumpWidget(buildHarness(const HistoryScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      _seed(_three());
      await _pump(tester, locale: ar);
      expect(englishLeaks(tester), isEmpty);
    });
  });

  group('stats', () {
    testWidgets('counts total / with codes / clean', (tester) async {
      _seed(_three());
      await _pump(tester);

      Finder stat(String key) =>
          find.ancestor(of: find.text(tr(key)), matching: find.byType(Column));
      expect(
        find.descendant(
          of: stat('total_scans').first,
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stat('with_codes').first, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: stat('clean_scan').first, matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('empty history shows zero counts', (tester) async {
      await _pump(tester);
      expect(find.text('0'), findsNWidgets(3));
    });
  });

  group('entry list', () {
    testWidgets('lists every scan, newest first', (tester) async {
      _seed(_three());
      await _pump(tester, size: const Size(390, 1400));

      final expected = [
        for (final km in [42500, 42000, 41000]) '$km ${tr('unit_km')}',
      ];
      final mileages = tester
          .widgetList<Text>(
            find.descendant(of: _entryList, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .where(expected.contains)
          .toList();
      expect(mileages, expected);
    });

    testWidgets('pending codes are shown without the "~" prefix', (
      tester,
    ) async {
      _seed(_three());
      await _pump(tester, size: const Size(390, 1400));

      expect(_inEntries('P0171'), findsOneWidget);
      expect(_inEntries('P0300'), findsOneWidget);
      expect(_inEntries('P0420'), findsOneWidget);
      final tilde = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => (t.data ?? '').contains('~'));
      expect(tilde, isEmpty);
    });

    testWidgets('clean scan entry carries the clean badge', (tester) async {
      _seed([_entry(_now, 100, [])]);
      await _pump(tester);
      // Stats label + filter chip + the entry's badge.
      expect(_inEntries(tr('clean_scan')), findsOneWidget);
    });

    testWidgets('confirmed and pending codes get distinct pills', (
      tester,
    ) async {
      _seed([
        _entry(_now, 100, ['P0300', '~P0171']),
      ]);
      await _pump(tester);

      Finder pill(Color c) => find.descendant(
        of: _entryList,
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.style?.color == c && w.style?.fontSize != null,
        ),
      );
      expect(pill(const Color(0xFFFF1744)), findsOneWidget); // confirmed
      expect(pill(const Color(0xFFFFD600)), findsOneWidget); // pending
    });
  });

  group('filters', () {
    testWidgets('"with codes" hides clean scans', (tester) async {
      _seed(_three());
      await _pump(tester, size: const Size(390, 1400));

      await tester.tap(_filterChip('with_codes'));
      await tester.pump(const Duration(seconds: 1));

      expect(_inEntries(tr('clean_scan')), findsNothing);
      expect(_inEntries('P0420'), findsOneWidget);
      expect(_inEntries('P0300'), findsOneWidget);
    });

    testWidgets('"clean" hides scans with codes', (tester) async {
      _seed(_three());
      await _pump(tester, size: const Size(390, 1400));

      await tester.tap(_filterChip('clean_scan'));
      await tester.pump(const Duration(seconds: 1));

      expect(_inEntries('P0420'), findsNothing);
      expect(_inEntries('P0300'), findsNothing);
      expect(_inEntries(tr('clean_scan')), findsOneWidget);
    });

    testWidgets('"all" restores every entry', (tester) async {
      _seed(_three());
      await _pump(tester, size: const Size(390, 1400));

      await tester.tap(_filterChip('clean_scan'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_filterChip('all'));
      await tester.pump(const Duration(seconds: 1));

      expect(_inEntries('P0420'), findsOneWidget);
      expect(_inEntries(tr('clean_scan')), findsOneWidget);
    });

    testWidgets('filter with no matches shows the empty state', (tester) async {
      _seed([
        _entry(_now, 100, ['P0420']),
      ]);
      await _pump(tester);

      await tester.tap(_filterChip('clean_scan'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(tr('no_scan_history_yet')), findsOneWidget);
    });
  });

  group('clear history', () {
    testWidgets('delete button is hidden when history is empty', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('confirming clears entries, prefs and the delete button', (
      tester,
    ) async {
      _seed(_three());
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text(tr('clear_history')), findsOneWidget);
      expect(find.text(tr('clear_history_content')), findsOneWidget);

      await tester.tap(find.text(tr('clear_all')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr('no_scan_history_yet')), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(DtcHistoryService.instance.entries, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);
    });

    testWidgets('cancelling keeps the history', (tester) async {
      _seed(_three());
      await _pump(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(DtcHistoryService.instance.entries, hasLength(3));
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('clear works in Arabic', (tester) async {
      _seed(_three());
      await _pump(tester, locale: ar);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('clear_all', ar)));
      await tester.pumpAndSettle();

      expectNoException(tester);
      expect(find.text(tr('no_scan_history_yet', ar)), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('back arrow pops the screen', (tester) async {
      await _pump(tester, pushed: true);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsNothing);
      expect(find.text(launcherText), findsOneWidget);
    });
  });
}
