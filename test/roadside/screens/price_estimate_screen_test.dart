import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/price_estimate_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/searching_driver_screen.dart';

import 'roadside_screen_harness.dart';

void main() {
  late GatedRoadsideRepository repo;
  late RoadsideBloc bloc;

  setUp(() => repo = GatedRoadsideRepository());

  Future<void> pumpEstimate(
    WidgetTester tester, {
    Locale locale = kEn,
    int photos = 0,
  }) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    await seedEstimate(tester, bloc);
    for (var i = 0; i < photos; i++) {
      bloc.add(AddPhotoPath('/data/user/0/cache/photo_$i.jpg'));
    }
    await tester.pump();
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const PriceEstimateScreen(), locale: locale);
  }

  final requestButton = find.byIcon(Icons.local_shipping_rounded);

  group('layout', () {
    testWidgets('English: service, address and price breakdown', (tester) async {
      await pumpEstimate(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Service Details'), findsOneWidget);
      expect(find.text(ServiceType.batteryJump.label), findsOneWidget);
      expect(find.text('Olaya St, Riyadh'), findsOneWidget);
      // Backend price 80 = base 65 + distance 15; total adds the $5 fee.
      expect(find.text('\$65'), findsOneWidget);
      expect(find.text('\$15'), findsOneWidget);
      expect(find.text('\$85'), findsOneWidget);
      expect(find.text('Request Service — \$85'), findsOneWidget);
      expect(find.text('No photos added — tap Add to take one'), findsOneWidget);
    });

    testWidgets('Arabic: translated, right-to-left, no overflow', (tester) async {
      await pumpEstimate(tester, locale: kAr);

      expect(tester.takeException(), isNull);
      final title = find.text('تفاصيل الخدمة');
      expect(title, findsOneWidget);
      expect(directionAt(tester, title), TextDirection.rtl);
      expect(find.text('الدفع نقداً عند اكتمال الخدمة'), findsOneWidget);
      expect(find.text('طلب الخدمة — \$85'), findsOneWidget);
      // The location icon leads its card, so in RTL it is on the right.
      expect(tester.getCenter(find.byIcon(Icons.location_on_rounded)).dx,
          greaterThan(tester.getCenter(find.text('موقعك')).dx));
    });
  });

  group('photos', () {
    testWidgets('Add is offered below the limit', (tester) async {
      await pumpEstimate(tester, photos: RoadsideState.maxPhotos - 1);

      expect(tester.takeException(), isNull);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('No photos added — tap Add to take one'), findsNothing);
      // Camera captures are device files, not bundled assets.
      final thumbs = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(thumbs, hasLength(RoadsideState.maxPhotos - 1));
      expect(thumbs.map((i) => i.image), everyElement(isA<FileImage>()));
    });

    testWidgets('Add is hidden once maxPhotos are attached', (tester) async {
      await pumpEstimate(tester, photos: RoadsideState.maxPhotos);

      expect(bloc.state.photoPaths, hasLength(RoadsideState.maxPhotos));
      expect(find.text('Add'), findsNothing);
      expect(find.byIcon(Icons.add_a_photo_rounded), findsNothing);
    });
  });

  group('submit', () {
    testWidgets('sends the notes and opens the searching screen', (tester) async {
      repo.createGate = Completer<void>();
      await pumpEstimate(tester);

      await tester.enterText(find.byType(TextField), 'White Camry, hazard on');
      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await settle(tester);

      expect(find.byType(SearchingDriverScreen), findsOneWidget);
      expect(bloc.state.isSubmitting, isTrue);

      repo.createGate!.complete();
      await settle(tester);

      expect(repo.createCalls, hasLength(1));
      expect(repo.createCalls.single['notes'], 'White Camry, hazard on');
      expect(repo.createCalls.single['address'], 'Olaya St, Riyadh');
      expect(find.byType(SearchingDriverScreen), findsOneWidget);
    });

    testWidgets('a quick second tap does not submit twice', (tester) async {
      repo.createGate = Completer<void>();
      await pumpEstimate(tester);

      await tester.ensureVisible(requestButton);
      final target = tester.getCenter(requestButton);
      // The second tap lands before the next frame, while the estimate is
      // still what's on screen (the navigator absorbs it during the push).
      await tester.tapAt(target);
      await tester.tapAt(target);
      await settle(tester);
      repo.createGate!.complete();
      await settle(tester);

      expect(repo.createCalls, hasLength(1));
      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('a failed submit returns here with the backend error',
        (tester) async {
      repo.createError = ApiException('address must be a string');
      await pumpEstimate(tester);

      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await settle(tester);

      expect(bloc.state.phase, RoadsidePhase.estimate);
      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsNothing);
      expect(find.byType(PriceEstimateScreen), findsOneWidget);
      expect(snackText(tester), 'address must be a string');
      // The request button is usable again (not stuck on a spinner).
      expect(requestButton, findsOneWidget);
    });

    testWidgets('Arabic: a failed submit shows the translated generic error',
        (tester) async {
      repo.createError = StateError('unexpected');
      await pumpEstimate(tester, locale: kAr);

      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await settle(tester);

      expect(find.byType(PriceEstimateScreen), findsOneWidget);
      expect(snackText(tester), 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
    });

    testWidgets('a failed photo upload returns here with the upload error',
        (tester) async {
      repo.uploadError = ApiException('File too large', statusCode: 413);
      await pumpEstimate(tester, photos: 2);

      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await settle(tester);

      expect(repo.uploadCalls, hasLength(1));
      expect(repo.createCalls, isEmpty);
      expect(find.byType(SearchingDriverScreen, skipOffstage: false),
          findsNothing);
      expect(snackText(tester), "Couldn't upload your photos. Please try again.");
      // Photos are kept for the retry.
      expect(bloc.state.photoPaths, hasLength(2));
    });

    testWidgets('Arabic: a failed photo upload shows the translated error',
        (tester) async {
      repo.uploadError = StateError('file gone');
      await pumpEstimate(tester, locale: kAr, photos: 1);

      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await settle(tester);

      expect(find.byType(PriceEstimateScreen), findsOneWidget);
      expect(snackText(tester), 'تعذّر رفع الصور. يرجى المحاولة مرة أخرى.');
    });

    testWidgets('can retry after a failed submit', (tester) async {
      repo.createError = ApiException('Service unavailable', statusCode: 503);
      await pumpEstimate(tester);

      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton);
      await settle(tester);
      expect(snackText(tester), 'Service unavailable');

      repo.createError = null;
      await tester.ensureVisible(requestButton);
      await tester.tap(requestButton, warnIfMissed: false);
      await settle(tester);

      expect(repo.createCalls, hasLength(2));
      expect(bloc.state.activeRequest, isNotNull);
      expect(find.byType(SearchingDriverScreen), findsOneWidget);
    });
  });
}
