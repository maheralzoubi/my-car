import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/location_picker_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/request_history_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/roadside_home_screen.dart';

import '../helpers/roadside_fakes.dart';
import 'roadside_screen_harness.dart';

void main() {
  late GatedRoadsideRepository repo;
  late RoadsideBloc bloc;

  // Not in setUp: the bloc must be created inside the test's fake-async zone
  // so its event handling is driven by `tester.pump`.
  setUp(() => repo = GatedRoadsideRepository());

  Future<void> pumpHome(WidgetTester tester, {Locale locale = kEn}) async {
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
    setUpRoadsideTestEnvironment(tester);
    await pumpRoadsideScreen(tester,
        bloc: bloc, screen: const RoadsideHomeScreen(), locale: locale);
  }

  group('layout', () {
    testWidgets('English: header and every service card render without overflow',
        (tester) async {
      await pumpHome(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Roadside Assistance'), findsOneWidget);
      expect(find.text('Select the service you need'), findsOneWidget);
      expect(find.text('Avg. 15 min'), findsOneWidget);
      expect(find.text('Certified Drivers'), findsOneWidget);
      expect(find.text('4.8 Rating'), findsOneWidget);
      for (final type in ServiceType.values) {
        expect(find.text(type.label), findsOneWidget, reason: type.name);
      }
    });

    testWidgets('Arabic: header is translated and laid out right-to-left',
        (tester) async {
      await pumpHome(tester, locale: kAr);

      expect(tester.takeException(), isNull);
      final title = find.text('المساعدة على الطريق');
      expect(title, findsOneWidget);
      expect(find.text('اختر الخدمة التي تحتاجها'), findsOneWidget);
      expect(find.text('سائقون معتمدون'), findsOneWidget);
      expect(directionAt(tester, title), TextDirection.rtl);

      // The header title starts on the right-hand side.
      expect(tester.getTopRight(title).dx, greaterThan(kPhoneSize.width / 2));
      // Each service card leads with its icon, so in RTL it sits right of the
      // label.
      final first = ServiceType.values.first;
      expect(tester.getCenter(find.byIcon(first.icon)).dx,
          greaterThan(tester.getCenter(find.text(first.label)).dx));
    });
  });

  group('service selection', () {
    testWidgets('tapping a card selects that service and opens the location picker',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text(ServiceType.tireRepair.label));
      await settle(tester);

      expect(bloc.state.selectedService, ServiceType.tireRepair);
      expect(bloc.state.phase, RoadsidePhase.locationPicker);
      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a repeated selection opens the location picker only once',
        (tester) async {
      await pumpHome(tester);

      // A second SelectService (e.g. a double tap that slipped in before the
      // push) arrives while the picker is already open.
      await tester.tap(find.text(ServiceType.fuelDelivery.label));
      await settle(tester);
      bloc.add(const SelectService(ServiceType.fuelDelivery));
      await settle(tester);

      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsOneWidget);
      // Back once returns to the service list, not to a second picker.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await settle(tester);
      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsNothing);
      expect(find.text('Roadside Assistance'), findsOneWidget);
    });

    testWidgets('a failed price estimate does not stack another location picker',
        (tester) async {
      repo.priceError = ApiException('Could not reach the server.');
      await pumpHome(tester);

      await tester.tap(find.text(ServiceType.batteryJump.label));
      await settle(tester);
      await tester.tap(find.text('Confirm Location'));
      await settle(tester);

      expect(snackText(tester), 'Could not reach the server.');
      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('after backing out of the picker, another service can be chosen',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text(ServiceType.batteryJump.label));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await settle(tester);
      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsNothing);

      await tester.tap(find.text(ServiceType.carTowing.label));
      await settle(tester);

      expect(bloc.state.selectedService, ServiceType.carTowing);
      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('re-choosing the same service after backing out reopens the picker',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text(ServiceType.batteryJump.label));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await settle(tester);

      await tester.tap(find.text(ServiceType.batteryJump.label));
      await settle(tester);

      expect(find.byType(LocationPickerScreen, skipOffstage: false), findsOneWidget);
    });
  });

  group('history', () {
    testWidgets('"My Requests" lists past requests from the live repository',
        (tester) async {
      repo.history = [sampleRequest(status: RequestStatus.completed)];
      await pumpHome(tester);

      await tester.tap(find.text('My Requests'));
      await settle(tester);

      expect(find.byType(RequestHistoryScreen), findsOneWidget);
      expect(find.text('Olaya St, Riyadh'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
    });

    testWidgets('history shows the empty state in Arabic', (tester) async {
      await pumpHome(tester, locale: kAr);

      await tester.tap(find.text('طلباتي'));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(RequestHistoryScreen), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsWidgets);
    });
  });
}
