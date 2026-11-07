import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/location_picker_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/price_estimate_screen.dart';

import 'roadside_screen_harness.dart';

void main() {
  late GatedRoadsideRepository repo;
  late RoadsideBloc bloc;

  setUp(() => repo = GatedRoadsideRepository());

  Future<void> pumpPicker(WidgetTester tester, {Locale locale = kEn}) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    bloc.add(const SelectService(ServiceType.batteryJump));
    await tester.pump();
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const LocationPickerScreen(), locale: locale);
  }

  final confirmButton = find.byType(ElevatedButton);
  ElevatedButton button(WidgetTester tester) =>
      tester.widget<ElevatedButton>(confirmButton);
  Finder buttonSpinner() => find.descendant(
      of: confirmButton, matching: find.byType(CircularProgressIndicator));

  testWidgets('renders the map, centre pin and confirm bar without overflow',
      (tester) async {
    await pumpPicker(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Set Your Location'), findsOneWidget);
    expect(find.text('Move map to set location'), findsOneWidget);
    expect(find.text('Confirm Location'), findsOneWidget);
    expect(find.byIcon(Icons.location_pin), findsOneWidget);
  });

  testWidgets('confirm shows a spinner and waits for the price before navigating',
      (tester) async {
    repo.priceGate = Completer<void>();
    await pumpPicker(tester);

    await tester.tap(find.text('Confirm Location'));
    await settle(tester);

    // Still here, busy, and the button can't be pressed again.
    expect(find.byType(LocationPickerScreen), findsOneWidget);
    expect(find.byType(PriceEstimateScreen), findsNothing);
    expect(buttonSpinner(), findsOneWidget);
    expect(find.text('Confirm Location'), findsNothing);
    expect(button(tester).onPressed, isNull);

    repo.priceGate!.complete();
    await settle(tester);

    expect(repo.priceCalls, hasLength(1));
    expect(bloc.state.phase, RoadsidePhase.estimate);
    expect(find.byType(LocationPickerScreen, skipOffstage: false), findsNothing,
        reason: 'the picker is replaced by the estimate');
    expect(find.byType(PriceEstimateScreen), findsOneWidget);
    // Total = backend price (80) + platform fee (5).
    expect(find.text('\$85'), findsOneWidget);
  });

  testWidgets('a failed estimate shows the error, stays, and allows a retry',
      (tester) async {
    repo.priceError = ApiException('Could not reach the server.');
    await pumpPicker(tester);

    await tester.tap(find.text('Confirm Location'));
    await settle(tester);

    expect(snackText(tester), 'Could not reach the server.');
    expect(find.byType(LocationPickerScreen), findsOneWidget);
    expect(find.byType(PriceEstimateScreen), findsNothing);
    expect(buttonSpinner(), findsNothing);
    expect(button(tester).onPressed, isNotNull);

    // The snackbar covers the confirm bar until it times out.
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    repo.priceError = null;
    await tester.tap(find.text('Confirm Location'));
    await settle(tester);

    expect(repo.priceCalls, hasLength(2));
    expect(find.byType(PriceEstimateScreen), findsOneWidget);
  });

  testWidgets('Arabic: unexpected errors use the translated generic message',
      (tester) async {
    repo.priceError = StateError('socket closed');
    await pumpPicker(tester, locale: kAr);

    await tester.tap(find.text('Confirm Location'));
    await settle(tester);

    expect(snackText(tester), 'حدث خطأ ما. يرجى المحاولة مرة أخرى.');
    expect(find.byType(LocationPickerScreen), findsOneWidget);
  });

  testWidgets('Arabic: top bar is mirrored (back button on the right)',
      (tester) async {
    await pumpPicker(tester, locale: kAr);

    expect(tester.takeException(), isNull);
    final back = find.byIcon(Icons.arrow_back_ios_new_rounded);
    expect(directionAt(tester, back), TextDirection.rtl);
    expect(tester.getCenter(back).dx, greaterThan(kPhoneSize.width / 2));
    expect(tester.getCenter(find.text('Set Your Location')).dx,
        lessThan(tester.getCenter(back).dx));
  });

  testWidgets('back button returns to the previous screen', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await settle(tester);

    expect(find.byType(LocationPickerScreen), findsNothing);
    expect(onRoot(), isTrue);
  });

  testWidgets('leaving while the location lookup is pending does not crash',
      (tester) async {
    final permission = Completer<Object?>();
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester, onGeolocator: (call) {
      if (call.method == 'checkPermission') return permission.future;
      return Future.value(0);
    });
    bloc.add(const SelectService(ServiceType.batteryJump));
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const LocationPickerScreen());

    // The "my location" button shows the lookup in progress.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await settle(tester);
    expect(onRoot(), isTrue);

    permission.complete(0); // denied, after the screen is gone
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
