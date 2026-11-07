import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/price_estimate_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/searching_driver_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/tracking_screen.dart';

import 'roadside_screen_harness.dart';

void main() {
  late GatedRoadsideRepository repo;
  late RoadsideBloc bloc;

  setUp(() => repo = GatedRoadsideRepository());

  /// Opens the searching screen the way the app does: from the estimate
  /// screen's request button.
  Future<void> submitFromEstimate(WidgetTester tester,
      {Locale locale = kEn}) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    await seedEstimate(tester, bloc);
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const PriceEstimateScreen(), locale: locale);
    final button = find.byIcon(Icons.local_shipping_rounded);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
  }

  /// Opens the searching screen with the request already created.
  Future<void> pumpSearching(WidgetTester tester, {Locale locale = kEn}) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    await seedSearching(tester, bloc);
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const SearchingDriverScreen(), locale: locale);
  }

  final cancel = find.byType(TextButton);
  TextButton cancelButton(WidgetTester tester) =>
      tester.widget<TextButton>(cancel);

  group('layout', () {
    testWidgets('English: radar, copy and stats fit a phone', (tester) async {
      await pumpSearching(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Finding Nearest Driver'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Drivers Online'), findsOneWidget);
      expect(find.text('Search Radius'), findsOneWidget);
      expect(find.text('Avg. Arrival'), findsOneWidget);
    });

    testWidgets('Arabic: translated and mirrored (cancel on the left)',
        (tester) async {
      await pumpSearching(tester, locale: kAr);

      expect(tester.takeException(), isNull);
      final title = find.text('البحث عن أقرب سائق');
      expect(title, findsOneWidget);
      expect(directionAt(tester, title), TextDirection.rtl);
      expect(find.text('متوسط وقت الوصول'), findsOneWidget);
      final cancelText = find.text('إلغاء');
      expect(cancelText, findsOneWidget);
      expect(tester.getCenter(cancelText).dx, lessThan(kPhoneSize.width / 2));
    });
  });

  group('submit', () {
    testWidgets('cancel is held while the request is still being created',
        (tester) async {
      repo.createGate = Completer<void>();
      await submitFromEstimate(tester);

      expect(find.byType(SearchingDriverScreen), findsOneWidget);
      expect(bloc.state.isSubmitting, isTrue);
      expect(cancelButton(tester).onPressed, isNull);

      repo.createGate!.complete();
      await settle(tester);

      expect(bloc.state.activeRequest, isNotNull);
      expect(cancelButton(tester).onPressed, isNotNull);
    });

    testWidgets('a slow failed submit returns to the estimate with the error',
        (tester) async {
      repo.createGate = Completer<void>();
      repo.createError = ApiException('No drivers in your area');
      await submitFromEstimate(tester);
      expect(find.byType(SearchingDriverScreen), findsOneWidget);

      repo.createGate!.complete();
      await settle(tester);

      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsNothing);
      expect(find.byType(PriceEstimateScreen), findsOneWidget);
      expect(snackText(tester), 'No drivers in your area');
    });

    testWidgets('an immediate failed submit also returns to the estimate',
        (tester) async {
      // Fails before the searching screen has subscribed to the bloc.
      repo.createError = ApiException('Could not reach the server.');
      await submitFromEstimate(tester);

      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsNothing);
      expect(find.byType(PriceEstimateScreen), findsOneWidget);
      expect(snackText(tester), 'Could not reach the server.');
    });

    testWidgets('a photo upload failure returns to the estimate (Arabic)',
        (tester) async {
      repo.uploadGate = Completer<void>();
      repo.uploadError = StateError('file gone');
      bloc = RoadsideBloc(repo);
      addTearDown(bloc.close);
      setUpRoadsideTestEnvironment(tester);
      await seedEstimate(tester, bloc);
      bloc.add(const AddPhotoPath('/data/user/0/cache/flat.jpg'));
      await pumpRoadsideScreen(tester,
          bloc: bloc, screen: const PriceEstimateScreen(), locale: kAr);
      final button = find.byIcon(Icons.local_shipping_rounded);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      expect(find.byType(SearchingDriverScreen), findsOneWidget);

      repo.uploadGate!.complete();
      await settle(tester);

      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsNothing);
      expect(snackText(tester), 'تعذّر رفع الصور. يرجى المحاولة مرة أخرى.');
    });

    testWidgets('a driver accepting opens the tracking screen', (tester) async {
      await pumpSearching(tester);

      await pushUpdate(tester, repo, driverRequest(RequestStatus.driverFound));
      await settle(tester);

      expect(bloc.state.phase, RoadsidePhase.tracking);
      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsNothing);
      expect(find.byType(TrackingScreen), findsOneWidget);
    });
  });

  group('cancel', () {
    testWidgets('waits for the backend, then returns home', (tester) async {
      repo.cancelGate = Completer<void>();
      await pumpSearching(tester);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      // Still searching while the backend answers; no second cancel.
      expect(find.byType(SearchingDriverScreen), findsOneWidget);
      expect(find.descendant(
              of: cancel, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(cancelButton(tester).onPressed, isNull);

      repo.cancelGate!.complete();
      await settle(tester);

      expect(repo.cancelCalls, ['req-1']);
      expect(bloc.state.phase, RoadsidePhase.idle);
      expect(onRoot(), isTrue);
    });

    testWidgets('a refused cancel keeps searching and explains why',
        (tester) async {
      repo.cancelError =
          ApiException('Request can no longer be cancelled', statusCode: 409);
      await pumpSearching(tester);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(snackText(tester), 'Request can no longer be cancelled');
      expect(find.byType(SearchingDriverScreen), findsOneWidget);
      expect(bloc.state.activeRequest, isNotNull);
      // The button is back, so the user can try again.
      expect(find.text('Cancel'), findsOneWidget);
      expect(cancelButton(tester).onPressed, isNotNull);
    });

    testWidgets('Arabic: a refused cancel shows the translated error',
        (tester) async {
      repo.cancelError = StateError('boom');
      await pumpSearching(tester, locale: kAr);

      await tester.tap(find.text('إلغاء'));
      await settle(tester);

      expect(snackText(tester), 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
      expect(find.byType(SearchingDriverScreen), findsOneWidget);
    });
  });
}
