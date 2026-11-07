import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/app/app.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/modules/home/presentation/pages/spalchScreen/spalch_screen.dart';

// The splash is pumped through the real [App] so it runs with the app's own
// ScreenUtil design size (390x844, minTextAdapt, splitScreenMode).

void _setSurface(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Unmounts the splash before its 5 s navigation timer fires, then drains
/// the timer (it is mounted-guarded).
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  for (final (name, size) in [
    ('phone portrait 390x844', const Size(390, 844)),
    ('phone landscape 844x390', const Size(844, 390)),
    ('small phone landscape 667x375', const Size(667, 375)),
  ]) {
    testWidgets('lays out without overflow — $name', (tester) async {
      _setSurface(tester, size);

      await tester.pumpWidget(const App());
      // Let the intro animations finish (2.3 s of delays + 2 s car zoom),
      // checking for layout errors along the way.
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }

      expect(find.byType(SplashScreen), findsOneWidget);
      // The status line is localized; resolve it in the app's active locale.
      final initializing = AppLocalizations.of(
        tester.element(find.byType(SplashScreen)),
      ).tr('splash_initializing');
      expect(find.text('CARDIAG'), findsOneWidget);
      expect(find.text(initializing), findsOneWidget);

      // All content stays on screen (edges inclusive).
      final screen = Offset.zero & size;
      for (final text in ['CARDIAG', initializing]) {
        final rect = tester.getRect(find.text(text));
        expect(screen.intersect(rect), rect,
            reason: '"$text" at $rect is outside $screen');
      }

      await _unmount(tester);
    });
  }

  testWidgets('disposing during the intro delays does not throw', (tester) async {
    _setSurface(tester, const Size(390, 844));

    // Before the 500 ms car delay.
    await tester.pumpWidget(const App());
    await tester.pump(const Duration(milliseconds: 100));
    await _unmount(tester);
    expect(tester.takeException(), isNull);

    // Between the car (500 ms) and title (+1800 ms) delays.
    await tester.pumpWidget(const App());
    await tester.pump(const Duration(milliseconds: 1000));
    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });
}
