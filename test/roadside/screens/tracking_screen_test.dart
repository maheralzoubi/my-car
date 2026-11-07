import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/driver_model.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/rating_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/tracking_screen.dart';

import 'roadside_screen_harness.dart';

/// ~1 km north of the customer in `sampleRequest` → 2 min at 0.5 km/min.
const _driver1km = LatLng(24.7225, 46.6753);

void main() {
  late GatedRoadsideRepository repo;
  late RoadsideBloc bloc;

  setUp(() => repo = GatedRoadsideRepository());

  /// Searching → [first] (a tracking status) → tracking screen open.
  Future<void> pumpTracking(
    WidgetTester tester, {
    Locale locale = kEn,
    ServiceRequest? first,
  }) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    await seedSearching(tester, bloc);
    await pushUpdate(
        tester, repo, first ?? driverRequest(RequestStatus.driverFound));
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const TrackingScreen(), locale: locale);
  }

  Finder bannerCancel(String label) => find.text(label);

  group('live updates', () {
    testWidgets('shows the assigned driver and request details',
        (tester) async {
      await pumpTracking(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Driver found — preparing to depart'), findsOneWidget);
      expect(find.text('Ahmed Al-Rashidi'), findsOneWidget);
      expect(find.text('Flatbed Carrier  ·  ABC 1234'), findsOneWidget);
      expect(find.text('(1243 jobs)'), findsOneWidget);
      // estimatedPrice 77.5 + $5 platform fee.
      expect(find.text('\$83 cash'), findsOneWidget);
      // Cancelling is only offered once the driver is en route.
      expect(bannerCancel('Cancel'), findsNothing);
    });

    testWidgets('ETA is right on the first frame, before any further update',
        (tester) async {
      await pumpTracking(tester,
          first: driverRequest(RequestStatus.driverEnRoute,
              driverLocation: _driver1km));

      expect(find.text('2 min away'), findsOneWidget);
    });

    testWidgets('follows status changes through to arrival and service',
        (tester) async {
      await pumpTracking(tester);

      await pushUpdate(
          tester,
          repo,
          driverRequest(RequestStatus.driverEnRoute,
              driverLocation: _driver1km));
      expect(find.text('Driver is on the way'), findsOneWidget);
      expect(find.text('2 min away'), findsOneWidget);
      expect(bannerCancel('Cancel'), findsOneWidget);

      // The driver moves closer: the ETA follows.
      await pushUpdate(
          tester,
          repo,
          driverRequest(RequestStatus.driverEnRoute,
              driverLocation: const LatLng(24.7150, 46.6753)));
      expect(find.text('1 min away'), findsOneWidget);

      await pushUpdate(
          tester,
          repo,
          driverRequest(RequestStatus.arrived,
              driverLocation: const LatLng(24.7136, 46.6753)));
      expect(bloc.state.phase, RoadsidePhase.tracking);
      expect(find.text('Driver has arrived'), findsOneWidget);
      expect(find.byIcon(Icons.pin_drop_rounded), findsOneWidget);
      expect(bannerCancel('Cancel'), findsNothing);

      await pushUpdate(tester, repo, driverRequest(RequestStatus.inProgress));
      expect(find.text('Service in progress'), findsOneWidget);
      expect(find.text('Servicing'), findsOneWidget);
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('completion opens the rating screen', (tester) async {
      await pumpTracking(tester);

      await pushUpdate(tester, repo, driverRequest(RequestStatus.completed));
      await settle(tester);

      expect(bloc.state.phase, RoadsidePhase.rating);
      expect(find.byType(TrackingScreen, skipOffstage: false), findsNothing);
      expect(find.byType(RatingScreen), findsOneWidget);
    });

    testWidgets('a server-side cancellation returns home', (tester) async {
      await pumpTracking(tester);

      await pushUpdate(tester, repo, driverRequest(RequestStatus.cancelled));
      await settle(tester);

      expect(onRoot(), isTrue);
    });

    testWidgets('a tracking stream error is shown and tracking continues',
        (tester) async {
      await pumpTracking(tester);

      repo.watcher('req-1').addError(
          ApiException('Request not found', statusCode: 404));
      await settle(tester);

      expect(snackText(tester), 'Request not found');
      expect(find.byType(TrackingScreen), findsOneWidget);

      await pushUpdate(tester, repo, driverRequest(RequestStatus.arrived));
      expect(find.text('Driver has arrived'), findsOneWidget);
    });

    testWidgets('a long driver name and vehicle fit the card', (tester) async {
      await pumpTracking(tester,
          first: driverRequest(RequestStatus.driverEnRoute,
              driverLocation: _driver1km,
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
              )));

      expect(tester.takeException(), isNull);
    });
  });

  group('cancel (driver en route)', () {
    Future<void> pumpEnRoute(WidgetTester tester, {Locale locale = kEn}) =>
        pumpTracking(tester,
            locale: locale,
            first: driverRequest(RequestStatus.driverEnRoute,
                driverLocation: _driver1km));

    testWidgets('waits for the backend, then returns home', (tester) async {
      repo.cancelGate = Completer<void>();
      await pumpEnRoute(tester);

      await tester.tap(bannerCancel('Cancel'));
      await settle(tester);

      // Pending: still tracking, cancel replaced by a spinner (no 2nd tap).
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(bannerCancel('Cancel'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.cancelGate!.complete();
      await settle(tester);

      expect(repo.cancelCalls, ['req-1']);
      expect(bloc.state.phase, RoadsidePhase.idle);
      expect(onRoot(), isTrue);
    });

    testWidgets('a refused cancel keeps tracking and explains why',
        (tester) async {
      repo.cancelError =
          ApiException('Driver has already arrived', statusCode: 409);
      await pumpEnRoute(tester);

      await tester.tap(bannerCancel('Cancel'));
      await settle(tester);

      expect(snackText(tester), 'Driver has already arrived');
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(bloc.state.activeRequest?.status, RequestStatus.driverEnRoute);
      // Cancel is offered again.
      expect(bannerCancel('Cancel'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Arabic: refusal translated; banner mirrored', (tester) async {
      repo.cancelError = StateError('boom');
      await pumpEnRoute(tester, locale: kAr);

      expect(tester.takeException(), isNull);
      final cancel = bannerCancel('إلغاء');
      expect(cancel, findsOneWidget);
      expect(directionAt(tester, cancel), TextDirection.rtl);
      // Status icon leads (right), cancel trails (left).
      expect(tester.getCenter(cancel).dx,
          lessThan(tester.getCenter(find.byIcon(Icons.navigation_rounded)).dx));

      await tester.tap(cancel);
      await settle(tester);

      expect(snackText(tester), 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
      expect(find.byType(TrackingScreen), findsOneWidget);
    });
  });
}
