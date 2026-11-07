import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/constants/app_colors.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/modules/roadside/presentation/pages/roadside_error_snackbar.dart';

import 'roadside_screen_harness.dart';

/// A page with one button per error passed in; tapping it shows that error.
Widget _app(Locale locale, List<String> errors) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < errors.length; i++)
                TextButton(
                  key: ValueKey('show-$i'),
                  onPressed: () => showRoadsideError(context, errors[i]),
                  child: Text('show $i'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('translates a localization key (English)', (tester) async {
    setUpRoadsideTestEnvironment(tester);
    await tester.pumpWidget(_app(kEn, ['roadside_error_generic']));
    await tester.tap(find.byKey(const ValueKey('show-0')));
    await tester.pump();

    expect(snackText(tester), 'Something went wrong. Please try again.');
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, AppColors.error);
  });

  testWidgets('translates a localization key (Arabic, RTL)', (tester) async {
    setUpRoadsideTestEnvironment(tester);
    await tester.pumpWidget(_app(kAr, ['roadside_error_generic']));
    await tester.tap(find.byKey(const ValueKey('show-0')));
    await tester.pump();

    expect(snackText(tester), 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
    expect(directionAt(tester, find.byType(SnackBar)), TextDirection.rtl);
  });

  testWidgets('passes backend (API) messages through unchanged',
      (tester) async {
    setUpRoadsideTestEnvironment(tester);
    await tester.pumpWidget(_app(kAr, ['Request not found']));
    await tester.tap(find.byKey(const ValueKey('show-0')));
    await tester.pump();

    expect(snackText(tester), 'Request not found');
  });

  testWidgets('a new error replaces the one on screen instead of queueing',
      (tester) async {
    setUpRoadsideTestEnvironment(tester);
    await tester.pumpWidget(_app(kEn, ['first error', 'second error']));
    await tester.tap(find.byKey(const ValueKey('show-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('show-1')));
    // Let the first snackbar's exit animation finish.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('first error'), findsNothing);
    expect(find.text('second error'), findsOneWidget);
  });
}
