import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/modules/roadside/data/models/driver_model.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';

import '../helpers/roadside_fakes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared harness for the roadside screen widget tests.
// ─────────────────────────────────────────────────────────────────────────────

/// A small Android phone (logical pixels). Smaller than the 390×844 design
/// size so tight layouts surface as overflow errors.
const kPhoneSize = Size(360, 740);

const kEn = Locale('en');
const kAr = Locale('ar');

/// [FakeRoadsideRepository] whose calls can be held open, so tests can see
/// what the UI does while the backend is still answering. (Its
/// `createRequestWithPhotos` goes through [createRequest], so [createGate]
/// holds the bloc's submit too.)
///
/// Create it and the bloc inside the test body, not in `setUp`: the bloc must
/// live in the test's fake-async zone for `tester.pump` to drive it.
class GatedRoadsideRepository extends FakeRoadsideRepository {
  Completer<void>? priceGate;
  Completer<void>? createGate;
  Completer<void>? cancelGate;
  Completer<void>? rateGate;
  Completer<void>? uploadGate;
  List<ServiceRequest> history = const [];

  @override
  Future<double> getEstimatedPrice(ServiceType type, LatLng location) async {
    await priceGate?.future;
    return super.getEstimatedPrice(type, location);
  }

  @override
  Future<ServiceRequest> createRequest({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
  }) async {
    await createGate?.future;
    return super.createRequest(
        type: type, location: location, address: address, notes: notes);
  }

  @override
  Future<List<String>> uploadPhotos(List<String> paths) async {
    await uploadGate?.future;
    return super.uploadPhotos(paths);
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    await cancelGate?.future;
    return super.cancelRequest(requestId);
  }

  @override
  Future<void> rateDriver(String requestId, int stars, String? review) async {
    await rateGate?.future;
    return super.rateDriver(requestId, stars, review);
  }

  @override
  Future<List<ServiceRequest>> getHistory() async => history;
}

const kDriver = DriverModel(
  id: 'drv-1',
  name: 'Ahmed Al-Rashidi',
  phone: '+966501234567',
  rating: 4.9,
  totalJobs: 1243,
  vehicleType: 'Flatbed Carrier',
  vehiclePlate: 'ABC 1234',
  avatarInitials: 'AA',
  distanceKm: 1.2,
);

/// [sampleRequest] with a driver assigned, as the tracking stream sends it.
ServiceRequest driverRequest(
  RequestStatus status, {
  LatLng? driverLocation,
  DriverModel driver = kDriver,
  bool cashCollected = false,
}) {
  final base = sampleRequest(status: status);
  return ServiceRequest(
    id: base.id,
    serviceType: base.serviceType,
    customerLocation: base.customerLocation,
    customerAddress: base.customerAddress,
    estimatedPrice: base.estimatedPrice,
    estimatedMinutes: base.estimatedMinutes,
    status: status,
    assignedDriver: driver,
    driverLocation: driverLocation,
    createdAt: base.createdAt,
    cashCollected: cashCollected,
  );
}

/// Sizes the test view like a phone and stubs the platform plugins the
/// roadside screens touch:
///  * `GoogleMap` creates an Android platform view — answered here so the map
///    renders as an empty texture;
///  * `Geolocator` permission checks report "denied", so the location picker
///    stays on its default centre.
///
/// [onGeolocator] can replace the geolocator handler (e.g. to hold a call).
void setUpRoadsideTestEnvironment(
  WidgetTester tester, {
  Future<Object?> Function(MethodCall call)? onGeolocator,
}) {
  tester.view.physicalSize = kPhoneSize * 3;
  tester.view.devicePixelRatio = 3;
  // Android status bar; the 3-button navigation bar sits outside the window.
  tester.view.padding = const FakeViewPadding(top: 24.0 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 24.0 * 3);
  addTearDown(tester.view.reset);

  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform_views,
      (call) async {
    switch (call.method) {
      case 'create':
        return 1; // texture id
      case 'resize':
        final args = call.arguments as Map;
        return {'width': args['width'], 'height': args['height']};
    }
    return null;
  });

  Future<Object?> deniedGeolocator(MethodCall call) async {
    switch (call.method) {
      case 'checkPermission':
      case 'requestPermission':
        return 0; // LocationPermission.denied
    }
    return null;
  }

  for (final name in const [
    'flutter.baseflow.com/geolocator',
    'flutter.baseflow.com/geolocator_android',
  ]) {
    messenger.setMockMethodCallHandler(
        MethodChannel(name), onGeolocator ?? deniedGeolocator);
  }
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final name in const [
      'flutter.baseflow.com/geolocator',
      'flutter.baseflow.com/geolocator_android',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });
}

/// Key of the button on the root ("app home") route that opens the screen
/// under test. Screens that finish the flow pop back to this route.
const kLaunchKey = ValueKey('launch-roadside');

/// Root route standing in for the app's home page.
const kRootTitle = 'ROOT';

/// Pumps an app with [bloc] provided above the navigator (as in `App`), a
/// root route, and [screen] pushed on top of it.
Future<void> pumpRoadsideScreen(
  WidgetTester tester, {
  required RoadsideBloc bloc,
  required Widget screen,
  Locale locale = kEn,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      child: BlocProvider<RoadsideBloc>.value(
        value: bloc,
        child: MaterialApp(
          theme: theme,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: kLaunchKey,
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => screen)),
                  child: const Text(kRootTitle),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(kLaunchKey));
  await settle(tester);
}

/// Advances past route transitions and bloc events. Unlike `pumpAndSettle`
/// this terminates on screens with endless animations (searching radar,
/// progress spinners).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// True when the root route (not a roadside screen) is what the user sees.
bool onRoot() =>
    find.byKey(kLaunchKey, skipOffstage: true).evaluate().isNotEmpty;

/// Drives [bloc] (through the real event handlers) to the price-estimate
/// phase: service picked, location confirmed, price fetched.
Future<void> seedEstimate(
  WidgetTester tester,
  RoadsideBloc bloc, {
  ServiceType type = ServiceType.batteryJump,
  String address = 'Olaya St, Riyadh',
}) async {
  bloc.add(SelectService(type));
  bloc.add(ConfirmLocation(const LatLng(24.7136, 46.6753), address));
  await tester.pump();
  await tester.pump();
}

/// Drives [bloc] to the searching phase with an active request whose watch
/// stream is `repo.watcher('req-1')`.
Future<void> seedSearching(
  WidgetTester tester,
  RoadsideBloc bloc, {
  ServiceType type = ServiceType.batteryJump,
}) async {
  await seedEstimate(tester, bloc, type: type);
  bloc.add(const SubmitRequest());
  await tester.pump();
  await tester.pump();
}

/// Pushes a tracking update through the fake watch stream and lets the bloc
/// and listeners react.
Future<void> pushUpdate(
  WidgetTester tester,
  FakeRoadsideRepository repo,
  ServiceRequest update,
) async {
  repo.watcher(update.id).add(update);
  await tester.pump();
  await tester.pump();
}

/// The snackbar text currently shown, or null.
String? snackText(WidgetTester tester) {
  final bar = find.byType(SnackBar);
  if (bar.evaluate().isEmpty) return null;
  final text = find.descendant(of: bar, matching: find.byType(Text));
  return tester.widget<Text>(text.first).data;
}

/// The text direction in effect at [finder].
TextDirection directionAt(WidgetTester tester, Finder finder) =>
    Directionality.of(tester.element(finder.first));
