import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/constants/app_strings.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/home/bloc/counter/counter_bloc.dart';
import 'package:mycar/modules/home/presentation/pages/home_page.dart';

import 'helpers/screen_harness.dart';

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  ThemeData? theme,
  RecordingObserver? observer,
}) => pumpScreen(
  tester,
  BlocProvider(create: (_) => CounterBloc(), child: const HomePage()),
  locale: locale,
  size: size,
  theme: theme,
  observer: observer,
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in [en, ar]) {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      testWidgets('renders (${locale.languageCode}, '
          '${theme.brightness.name})', (tester) async {
        await _pump(tester, locale: locale, theme: theme);
        expectNoException(tester);
        expect(find.text(tr('home', locale)), findsOneWidget);
        expect(find.text(tr('home_welcome', locale)), findsOneWidget);
        expect(find.text(tr('roadside_assistance', locale)), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      });
    }
  }

  testWidgets('small phone, Arabic: no overflow', (tester) async {
    await _pump(tester, locale: ar, size: smallPhone);
    expectNoException(tester);
  });

  testWidgets('counter increments and decrements', (tester) async {
    await _pump(tester);
    await tapVisible(tester, find.text(AppStrings.increment));
    await tapVisible(tester, find.text(AppStrings.increment));
    expect(find.text('2'), findsOneWidget);
    await tapVisible(tester, find.text(AppStrings.decrement));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('roadside card opens roadside assistance', (tester) async {
    final observer = RecordingObserver();
    await _pump(tester, observer: observer);
    await tapVisible(tester, find.text(tr('roadside_assistance')));
    await tester.pumpAndSettle();
    expect(observer.pushedNames, contains(AppRoutes.roadside));
  });
}
