// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/app/app.dart';
import 'package:mycar/modules/home/presentation/pages/spalchScreen/spalch_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // The app is laid out for a 390x844 portrait phone (ScreenUtil design
    // size). The default 800x600 landscape test surface doesn't fit the
    // splash layout, so render on a phone-sized portrait surface instead.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const App());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);

    // Let the splash intro animations (2.3 s of chained delays) run, then
    // unmount before its 5 s navigation timer fires; the timer is
    // mounted-guarded, so advancing past it just drains it.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
