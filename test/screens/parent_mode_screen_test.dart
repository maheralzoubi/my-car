import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/modules/home/presentation/pages/parentModeScreen/parent_mode_screen.dart';

import 'helpers/screen_harness.dart';

// Every test runs at phone size with layout errors (overflow) reported.

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) {
  return pumpScreen(
    tester,
    const ParentModeScreen(),
    locale: locale,
    size: size,
    pushed: pushed,
  );
}

/// Toggle tracks, in order: location tracking, speed alerts, geo-fence.
Finder get _toggles => find.byType(AnimatedAlign);

Finder _alert([Locale l = en]) => find.text(tr('parent_speed_alert', l));

bool _isOn(WidgetTester tester, int i) {
  final dir = directionAt(tester, find.byType(ParentModeScreen));
  final a = tester.widget<AnimatedAlign>(_toggles.at(i)).alignment.resolve(dir);
  return dir == TextDirection.ltr ? a.x > 0 : a.x < 0;
}

/// The pulse animation repeats forever: pump fixed steps, never settle.
Future<void> _step(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 300));

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);
        await unmount(tester);
      });

      testWidgets('renders all sections (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'parent_mode',
          'parent_current_location',
          'parent_drive_time',
          'parent_distance',
          'parent_avg_speed',
          'parent_tracking_settings',
          'parent_location_tracking',
          'parent_speed_alerts',
          'parent_geo_fence',
          'parent_speed_limit',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(
          directionAt(tester, find.byType(ParentModeScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
        await unmount(tester);
      });
    }

    testWidgets('small phone, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
      await unmount(tester);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      expect(englishLeaks(tester), isEmpty);
      await unmount(tester);
    });

    testWidgets('default toggles: tracking on, alerts on, geo-fence off', (
      tester,
    ) async {
      await _pump(tester);
      expect(_toggles, findsNWidgets(3));
      expect(
        [for (var i = 0; i < 3; i++) _isOn(tester, i)],
        [true, true, false],
      );
      await unmount(tester);
    });
  });

  group('speed alert', () {
    testWidgets('shows when the speed exceeds the default limit', (
      tester,
    ) async {
      await _pump(tester);
      expect(_alert(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('raising the limit above the current speed hides it', (
      tester,
    ) async {
      await _pump(tester);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '150');
      await _step(tester);
      expect(_alert(), findsNothing);
      await unmount(tester);
    });

    testWidgets('invalid limit falls back to 100 (alert back on)', (
      tester,
    ) async {
      await _pump(tester);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '150');
      await _step(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await _step(tester);
      expect(_alert(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('turning speed alerts off hides the alert', (tester) async {
      await _pump(tester);
      await tapVisible(tester, _toggles.at(1));
      await _step(tester);
      expect(_isOn(tester, 1), isFalse);
      expect(_alert(), findsNothing);
      await unmount(tester);
    });
  });

  group('toggles', () {
    testWidgets('each toggle flips on tap', (tester) async {
      await _pump(tester);
      for (var i = 0; i < 3; i++) {
        final before = _isOn(tester, i);
        await tapVisible(tester, _toggles.at(i));
        await _step(tester);
        expect(_isOn(tester, i), !before, reason: 'toggle $i');
      }
      await unmount(tester);
    });

    testWidgets('toggles work in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      await tapVisible(tester, _toggles.at(2));
      await _step(tester);
      expectNoException(tester);
      expect(_isOn(tester, 2), isTrue);
      await unmount(tester);
    });
  });

  group('navigation', () {
    testWidgets('back arrow pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ParentModeScreen), findsNothing);
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  // Independent re-check of the parent-mode fixes.
  group('double-check', () {
    for (final locale in [en, ar]) {
      testWidgets('demo data is labelled as such (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expect(find.text(tr('parent_demo_notice', locale)), findsOneWidget);
        expect(find.text(tr('parent_demo_location', locale)), findsOneWidget);
        // The old unlabelled sample values are gone.
        expect(find.text('Downtown'), findsNothing);
        expect(find.text('145km'), findsNothing);
        if (locale == ar) expect(englishLeaks(tester), isEmpty);
        await unmount(tester);
      });
    }

    testWidgets('speed alert follows the toggle both ways, at any limit', (
      tester,
    ) async {
      await _pump(tester);
      expect(_alert(), findsOneWidget);
      await tapVisible(tester, _toggles.at(1)); // alerts off
      await _step(tester);
      expect(_alert(), findsNothing);

      // Still off even with a limit far below the current speed.
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '10');
      await _step(tester);
      expect(_alert(), findsNothing);

      await tapVisible(tester, _toggles.at(1)); // alerts back on
      await _step(tester);
      expect(_alert(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('speed alert toggle works in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      expect(_alert(ar), findsOneWidget);
      await tapVisible(tester, _toggles.at(1));
      await _step(tester);
      expect(_alert(ar), findsNothing);
      expectNoException(tester);
      await unmount(tester);
    });

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), scrolled through', (tester) async {
          await _pump(tester, locale: locale, size: size);
          expectNoException(tester);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -4000),
          );
          await _step(tester);
          await _step(tester);
          expectNoException(tester);
          await unmount(tester);
        });
      }
    }
  });
}
