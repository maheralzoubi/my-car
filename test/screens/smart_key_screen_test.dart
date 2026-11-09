import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/smartKeyScreen/smart_key_screen.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/screen_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) => pumpScreen(
  tester,
  const SmartKeyScreen(),
  locale: locale,
  size: size,
  pushed: pushed,
);

Finder _lockIcons() => find.byIcon(Icons.lock);
Finder _powerIcons() => find.byIcon(Icons.power_settings_new);

void main() {
  late FakeOBDAdapter fake;

  setUpAll(loadAppFonts);
  setUp(() {
    fake = FakeOBDAdapter();
    OBDService.setTestAdapter(fake); // not initialized = no vehicle link
  });
  tearDown(() => fake.dispose());

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'smart_key_title',
          'lock',
          'unlock',
          'start_engine',
          'quick_actions',
          'climate',
          'find_car',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(
          directionAt(tester, find.byType(SmartKeyScreen)),
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

    testWidgets('does not claim "connected" without a vehicle link', (
      tester,
    ) async {
      expect(OBDService.instance.isInitialized, isFalse);
      await _pump(tester);
      expect(find.text(tr('connected')), findsNothing);
      await unmount(tester);
    });
  });

  group('lock / unlock / engine', () {
    testWidgets('starts locked: car shows the lock overlay', (tester) async {
      await _pump(tester);
      // Car overlay + lock button.
      expect(_lockIcons(), findsNWidgets(2));
      // Engine button only, no running indicator.
      expect(_powerIcons(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('engine cannot start while locked', (tester) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('start_engine')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(tr('start_engine')), findsOneWidget);
      expect(find.text(tr('stop_engine')), findsNothing);
      expect(_powerIcons(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('unlock removes the lock overlay', (tester) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('unlock')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_lockIcons(), findsOneWidget); // lock button only
      await unmount(tester);
    });

    testWidgets('unlocked: start then stop the engine', (tester) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('unlock')));
      await tapVisible(tester, find.text(tr('start_engine')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(tr('stop_engine')), findsOneWidget);
      expect(_powerIcons(), findsNWidgets(2)); // + running indicator

      await tapVisible(tester, find.text(tr('stop_engine')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(tr('start_engine')), findsOneWidget);
      expect(_powerIcons(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('locking while running also stops the engine', (tester) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('unlock')));
      await tapVisible(tester, find.text(tr('start_engine')));
      await tapVisible(tester, find.text(tr('lock')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(tr('start_engine')), findsOneWidget);
      expect(_lockIcons(), findsNWidgets(2));
      expect(_powerIcons(), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('works in Arabic (RTL)', (tester) async {
      await _pump(tester, locale: ar);
      await tapVisible(tester, find.text(tr('unlock', ar)));
      await tapVisible(tester, find.text(tr('start_engine', ar)));
      await tester.pump(const Duration(milliseconds: 300));
      expectNoException(tester);
      expect(find.text(tr('stop_engine', ar)), findsOneWidget);
      await unmount(tester);
    });
  });

  group('navigation', () {
    testWidgets('back arrow pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back));
      // The pulse animation never settles; pump through the transition.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SmartKeyScreen), findsNothing);
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  // Independent re-check of the smart-key fix.
  group('double-check', () {
    for (final locale in [en, ar]) {
      testWidgets('status pill says Demo, never Connected '
          '(${locale.languageCode})', (tester) async {
        await _pump(tester, locale: locale);
        expect(find.text(tr('smart_key_demo', locale)), findsOneWidget);
        expect(find.text(tr('connected', locale)), findsNothing);
        expect(find.text(tr('connected', en)), findsNothing);
        expect(find.text('Connected'), findsNothing);
        await unmount(tester);
      });
    }

    testWidgets('still Demo after the lock / engine controls are used', (
      tester,
    ) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('unlock')));
      await tapVisible(tester, find.text(tr('start_engine')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(tr('smart_key_demo')), findsOneWidget);
      expect(find.text(tr('connected')), findsNothing);
      await unmount(tester);
    });

    testWidgets(
      'quick actions respond instead of a dead tap',
      (tester) async {
        await _pump(tester);
        for (final key in ['climate', 'find_car']) {
          await tapVisible(tester, find.text(tr(key)));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SnackBar), findsOneWidget, reason: key);
          ScaffoldMessenger.of(
            tester.element(find.byType(SmartKeyScreen)),
          ).removeCurrentSnackBar();
          await tester.pump(const Duration(milliseconds: 300));
        }
        await unmount(tester);
      },
    );

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), engine running', (tester) async {
          await _pump(tester, locale: locale, size: size);
          expectNoException(tester);
          await tapVisible(tester, find.text(tr('unlock', locale)));
          await tapVisible(tester, find.text(tr('start_engine', locale)));
          await tester.pump(const Duration(milliseconds: 300));
          expectNoException(tester);
          await unmount(tester);
        });
      }
    }
  });
}
