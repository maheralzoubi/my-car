import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/modules/home/presentation/pages/settingsScreen/dash_cam_settings_screen.dart';

import 'helpers/screen_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) => pumpScreen(
  tester,
  const DashCamSettingsScreen(),
  locale: locale,
  size: size,
  pushed: pushed,
);

/// Switch tracks, in order: dash cam (master), loop, auto start, incident.
Finder get _switches => find.byType(AnimatedAlign);

Finder _quality(String q) => find.text(q);

bool _isOn(WidgetTester tester, int i) {
  final a = tester.widget<AnimatedAlign>(_switches.at(i)).alignment;
  final dir = directionAt(tester, find.byType(DashCamSettingsScreen));
  // Accept either physical or directional alignments.
  final resolved = a.resolve(dir);
  return resolved.x > 0 == (dir == TextDirection.ltr) && resolved.x != 0;
}

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'dash_cam_settings',
          'dash_cam',
          'loop_recording',
          'auto_start_recording',
          'video_quality',
          'incident_detection',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(find.byIcon(Icons.videocam), findsOneWidget);
        expect(
          directionAt(tester, find.byType(DashCamSettingsScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('small phone, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      expect(englishLeaks(tester, allow: {'HD', '1080p', '720p'}), isEmpty);
    });

    testWidgets('defaults: enabled, loop on, auto-start off, incident on', (
      tester,
    ) async {
      await _pump(tester);
      expect(_switches, findsNWidgets(4));
      expect(
        [for (var i = 0; i < 4; i++) _isOn(tester, i)],
        [true, true, false, true],
      );
    });
  });

  group('interactions', () {
    testWidgets('turning the dash cam off disables the dependent options', (
      tester,
    ) async {
      await _pump(tester);
      expect(_quality('720p'), findsOneWidget);

      await tester.tap(_switches.at(0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsNothing);
      // Quality chips are hidden while disabled.
      expect(_quality('720p'), findsNothing);

      // Dependent switches ignore taps.
      final before = _isOn(tester, 2);
      await tapVisible(tester, _switches.at(2));
      await tester.pumpAndSettle();
      expect(_isOn(tester, 2), before);
    });

    testWidgets('turning it back on restores the options', (tester) async {
      await _pump(tester);
      await tester.tap(_switches.at(0));
      await tester.pumpAndSettle();
      await tester.tap(_switches.at(0));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(_quality('720p'), findsOneWidget);
    });

    testWidgets('dependent switches toggle while enabled', (tester) async {
      await _pump(tester);
      for (final i in [1, 2, 3]) {
        final before = _isOn(tester, i);
        await tapVisible(tester, _switches.at(i));
        await tester.pumpAndSettle();
        expect(_isOn(tester, i), !before, reason: 'switch $i');
      }
    });

    testWidgets('choosing 720p updates the status summary', (tester) async {
      await _pump(tester);
      await tapVisible(tester, _quality('720p'));
      await tester.pumpAndSettle();
      // Status line under the header now mentions 720p.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('720p'), findsNWidgets(2));
    });

    testWidgets('interactions work in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      await tester.tap(_switches.at(0));
      await tester.pumpAndSettle();
      expectNoException(tester);
      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('back arrow pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });
}
