import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/modules/home/presentation/pages/modeSelectionScreen/mode_selection_screen.dart';

import 'helpers/screen_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  RecordingObserver? observer,
}) async {
  await pumpScreen(
    tester,
    const ModeSelectionScreen(),
    locale: locale,
    size: size,
    observer: observer,
  );
  // Entrance animations; the background orbit/pulse repeat forever, so step
  // the clock instead of settling.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Records SystemNavigator.pop (the platform "exit app" call).
List<MethodCall> _recordPlatform(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (c) async {
      calls.add(c);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders both mode cards (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'what_do_you_need',
          'car_diagnostics',
          'car_diagnostics_sub',
          'live_engine_data',
          'fault_code_scanner',
          'performance_metrics',
          'connect_bluetooth',
          'roadside_assistance',
          'roadside_assistance_sub',
          'towing_service',
          'battery_tire_repair',
          'fuel_delivery',
          'request_help',
          'switch_services',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(
          directionAt(tester, find.byType(ModeSelectionScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
        await unmount(tester);
      });
    }

    for (final size in [smallPhone, const Size(320, 568)]) {
      testWidgets('no overflow on ${size.width.toInt()}x${size.height.toInt()} '
          '(ar)', (tester) async {
        await _pump(tester, locale: ar, size: size);
        expectNoException(tester);
        await unmount(tester);
      });
    }

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      // "OBD-II" and "24 / 7" are the cards' tag badges.
      expect(englishLeaks(tester), isEmpty);
      await unmount(tester);
    });
  });

  group('navigation', () {
    testWidgets('diagnostics card opens the diagnostics flow', (tester) async {
      final observer = RecordingObserver();
      await _pump(tester, observer: observer);

      await tester.tap(find.text(tr('car_diagnostics')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        observer.pushedNames.last,
        anyOf(AppRoutes.dashboard, AppRoutes.connectionscreen),
      );
      await unmount(tester);
    });

    testWidgets('roadside card opens /roadside', (tester) async {
      final observer = RecordingObserver();
      await _pump(tester, observer: observer);

      await tester.tap(find.text(tr('roadside_assistance')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(observer.pushedNames.last, AppRoutes.roadside);
      expect(find.text('route:${AppRoutes.roadside}'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('cards are tappable in Arabic too', (tester) async {
      final observer = RecordingObserver();
      await _pump(tester, locale: ar, observer: observer);

      await tester.tap(find.text(tr('request_help', ar)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(observer.pushedNames.last, AppRoutes.roadside);
      await unmount(tester);
    });
  });

  group('back button', () {
    Future<void> pressBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('asks before exiting; cancel stays', (tester) async {
      final platform = _recordPlatform(tester);
      await _pump(tester);
      await pressBack(tester);

      expect(find.text(tr('exit_app')), findsOneWidget);
      expect(find.text(tr('exit_app_confirm')), findsOneWidget);

      await tester.tap(find.text(tr('cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(tr('exit_app')), findsNothing);
      expect(find.byType(ModeSelectionScreen), findsOneWidget);
      expect(platform.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
      await unmount(tester);
    });

    testWidgets('confirming exit closes the app', (tester) async {
      final platform = _recordPlatform(tester);
      await _pump(tester);
      await pressBack(tester);

      await tester.tap(find.text(tr('exit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expectNoException(tester);
      expect(
        platform.where((c) => c.method == 'SystemNavigator.pop'),
        isNotEmpty,
      );
      await unmount(tester);
    });
  });

  // Independent re-check of the mode-selection fixes.
  group('double-check', () {
    Future<void> pressBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('Arabic exit dialog is localized and Exit closes the app', (
      tester,
    ) async {
      final platform = _recordPlatform(tester);
      await _pump(tester, locale: ar);
      await pressBack(tester);
      expect(find.text(tr('exit_app', ar)), findsOneWidget);
      expect(find.text(tr('exit_app_confirm', ar)), findsOneWidget);
      expect(englishLeaks(tester), isEmpty);

      await tester.tap(find.text(tr('exit', ar)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        platform.where((c) => c.method == 'SystemNavigator.pop'),
        hasLength(1),
      );
      expectNoException(tester);
      await unmount(tester);
    });

    testWidgets('dismissing the exit dialog by the barrier stays put', (
      tester,
    ) async {
      final platform = _recordPlatform(tester);
      await _pump(tester);
      await pressBack(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(tr('exit_app')), findsNothing);
      expect(find.byType(ModeSelectionScreen), findsOneWidget);
      expect(platform.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
      await unmount(tester);
    });

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone, const Size(320, 568)]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), scrolled through', (tester) async {
          await _pump(tester, locale: locale, size: size);
          expectNoException(tester);
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            await tester.drag(scrollables.first, const Offset(0, -2000));
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 250));
            }
          }
          expectNoException(tester);
          await unmount(tester);
        });
      }
    }
  });
}
