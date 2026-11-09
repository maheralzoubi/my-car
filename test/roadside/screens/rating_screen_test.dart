import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/driver_model.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/rating_screen.dart';

import 'roadside_screen_harness.dart';

void main() {
  late GatedRoadsideRepository repo;
  late RoadsideBloc bloc;

  setUp(() => repo = GatedRoadsideRepository());

  Future<void> pumpRating(
    WidgetTester tester, {
    Locale locale = kEn,
    DriverModel driver = kDriver,
  }) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    await seedSearching(tester, bloc);
    await pushUpdate(tester, repo,
        driverRequest(RequestStatus.completed, driver: driver, cashCollected: true));
    expect(bloc.state.phase, RoadsidePhase.rating);
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const RatingScreen(), locale: locale);
  }

  final submit = find.byType(ElevatedButton);
  ElevatedButton submitButton(WidgetTester tester) =>
      tester.widget<ElevatedButton>(submit);
  Finder star(int i) => find.byIcon(Icons.star_outline_rounded).at(i);

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await settle(tester);
  }

  group('layout', () {
    testWidgets('English: receipt and driver rating card', (tester) async {
      await pumpRating(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Service Completed!'), findsOneWidget);
      expect(find.text('\$77.50'), findsOneWidget);
      expect(find.text('✓ Paid'), findsOneWidget);
      expect(find.text('Ahmed Al-Rashidi'), findsOneWidget);
      expect(find.text('How was your experience?'), findsOneWidget);
      expect(find.text('Skip & Done'), findsOneWidget);
    });

    testWidgets('Arabic: translated prompt, RTL, long driver details fit',
        (tester) async {
      await pumpRating(tester,
          locale: kAr,
          driver: const DriverModel(
            id: 'drv-2',
            name: 'Abdulrahman Mohammed Al-Qahtani',
            phone: '+966500000001',
            rating: 4.7,
            totalJobs: 98765,
            vehicleType: 'Heavy Duty Flatbed Tow Truck',
            vehiclePlate: 'XYZ 9876',
            avatarInitials: 'AQ',
            distanceKm: 3,
          ));

      expect(tester.takeException(), isNull);
      final prompt = find.text('كيف كانت تجربتك؟');
      expect(prompt, findsOneWidget);
      expect(directionAt(tester, prompt), TextDirection.rtl);
      // Avatar leads the driver row, so in RTL it is right of the name.
      expect(tester.getCenter(find.text('AQ')).dx,
          greaterThan(tester.getCenter(
              find.text('Abdulrahman Mohammed Al-Qahtani')).dx));
    });
  });

  group('submit', () {
    testWidgets('stars update the label and the rating sent', (tester) async {
      await pumpRating(tester);

      await tester.ensureVisible(star(3));
      await tester.tap(star(3)); // 4th star
      await tester.pump();
      expect(find.text('Great!'), findsOneWidget);
      expect(find.text('Submit Rating'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Quick and friendly');
      await tapSubmit(tester);

      expect(repo.rateCalls, [('req-1', 4, 'Quick and friendly')]);
    });

    testWidgets('waits for the save (spinner, no double submit), then goes home',
        (tester) async {
      repo.rateGate = Completer<void>();
      await pumpRating(tester);

      await tester.ensureVisible(star(4));
      await tester.tap(star(4));
      await tester.pump();
      await tapSubmit(tester);

      expect(find.byType(RatingScreen), findsOneWidget);
      expect(find.descendant(
              of: submit, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);
      await tester.tap(submit, warnIfMissed: false);
      await settle(tester);

      repo.rateGate!.complete();
      await settle(tester);

      expect(repo.rateCalls, [('req-1', 5, null)]);
      expect(bloc.state.phase, RoadsidePhase.idle);
      expect(onRoot(), isTrue);
    });

    testWidgets('a failed save stays here with the error and can be retried',
        (tester) async {
      repo.rateError = ApiException('Request is not completed yet');
      await pumpRating(tester);

      await tester.ensureVisible(star(2));
      await tester.tap(star(2));
      await tester.pump();
      await tapSubmit(tester);

      expect(snackText(tester), 'Request is not completed yet');
      expect(find.byType(RatingScreen), findsOneWidget);
      expect(find.text('Submit Rating'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);

      repo.rateError = null;
      await tester.pump(const Duration(seconds: 5)); // let the snackbar go
      await settle(tester);
      await tapSubmit(tester);

      expect(repo.rateCalls, hasLength(2));
      expect(onRoot(), isTrue);
    });

    testWidgets('Arabic: a failed save shows the translated error',
        (tester) async {
      repo.rateError = StateError('boom');
      await pumpRating(tester, locale: kAr);

      await tapSubmit(tester);

      expect(snackText(tester), 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
      expect(find.byType(RatingScreen), findsOneWidget);
    });

    // Documents current behaviour (open product question, intentionally not
    // changed): skipping without choosing stars records a 5-star rating.
    testWidgets('"Skip & Done" with no stars chosen submits 5 stars',
        (tester) async {
      await pumpRating(tester);

      expect(find.text('Skip & Done'), findsOneWidget);
      await tapSubmit(tester);

      expect(repo.rateCalls, [('req-1', 5, null)]);
      expect(onRoot(), isTrue);
    });
  });
}
