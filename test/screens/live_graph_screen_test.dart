import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/core/widgets/widgets.dart';
import 'package:mycar/modules/home/presentation/pages/liveGraphScreen/live_graph_screen.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/screen_harness.dart';

late FakeOBDAdapter _fake;

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  ThemeData? theme,
  bool pushed = false,
}) => pumpScreen(
  tester,
  const LiveGraphScreen(),
  locale: locale,
  size: size,
  theme: theme,
  pushed: pushed,
);

Future<void> _emit(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    _fake.emitLiveData(
      OBDLiveData(
        rpm: 800.0 + i * 50,
        speedKmh: 10.0 + i,
        coolantTempC: 80,
        engineLoad: 30,
      ),
    );
    await tester.pump();
  }
}

Finder _chip(String label) => find.widgetWithText(AppFilterChip, label);

bool _selected(WidgetTester tester, String label) =>
    tester.widget<AppFilterChip>(_chip(label)).selected;

int _lines(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.length;

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    _fake = FakeOBDAdapter();
    OBDService.setTestAdapter(_fake);
  });

  group('rendering', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final locale in [en, ar]) {
        testWidgets('${theme.brightness.name} theme, small phone '
            '(${locale.languageCode}) with live samples', (tester) async {
          await _pump(tester, locale: locale, size: smallPhone, theme: theme);
          expectNoException(tester);
          expect(find.text(tr('live_data_graph', locale)), findsOneWidget);
          expect(
            find.text(tr('graph_window', locale).replaceAll('{n}', '3')),
            findsOneWidget,
          );
          await _emit(tester, 5);
          expectNoException(tester);
          expect(find.byType(LineChart), findsOneWidget);
          expect(
            directionAt(tester, find.byType(LiveGraphScreen)),
            locale == ar ? TextDirection.rtl : TextDirection.ltr,
          );
        });
      }
    }
  });

  group('channels', () {
    testWidgets('RPM, speed and coolant are on by default and drawn', (
      tester,
    ) async {
      await _pump(tester);
      expect(_selected(tester, 'RPM'), isTrue);
      expect(_selected(tester, tr('dash_speed')), isTrue);
      expect(_selected(tester, tr('dash_coolant')), isTrue);
      expect(_selected(tester, tr('dash_engine_load')), isFalse);
      await _emit(tester, 3);
      expect(_lines(tester), 3);
      // Legend shows the latest value of each active channel.
      expect(find.text('900.0 rpm'), findsOneWidget);
    });

    testWidgets('a chip toggles its channel on and off', (tester) async {
      await _pump(tester);
      await _emit(tester, 2);
      await tester.tap(_chip(tr('dash_engine_load')));
      await tester.pump();
      expect(_selected(tester, tr('dash_engine_load')), isTrue);
      await _emit(tester, 1);
      expect(_lines(tester), 4);

      await tester.tap(_chip('RPM'));
      await tester.pump();
      expect(_selected(tester, 'RPM'), isFalse);
      expect(_lines(tester), 3);
    });

    testWidgets('the last active channel cannot be turned off', (tester) async {
      await _pump(tester);
      await tester.tap(_chip(tr('dash_speed')));
      await tester.pump();
      await tester.tap(_chip(tr('dash_coolant')));
      await tester.pump();
      await tester.tap(_chip('RPM'));
      await tester.pump();
      expect(_selected(tester, 'RPM'), isTrue);
    });
  });

  testWidgets('back arrow pops', (tester) async {
    await _pump(tester, pushed: true);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text(launcherText), findsOneWidget);
  });
}
