import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycar/core/theme/app_palette.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/pages/location_picker_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/price_estimate_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/rating_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/request_history_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/roadside_home_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/searching_driver_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/tracking_screen.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';

import '../helpers/roadside_fakes.dart';
import 'roadside_screen_harness.dart';

/// Every roadside screen renders without exceptions or overflow in the light
/// and dark app themes, in English and Arabic, on the solid theme background.
void main() {
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};
  final locales = {'en': kEn, 'ar': kAr};

  /// Builds the bloc state the screen expects, then returns the screen.
  final screens =
      <String,
          Future<Widget> Function(
            WidgetTester tester,
            RoadsideBloc bloc,
            GatedRoadsideRepository repo,
          )>{
        'home': (tester, bloc, repo) async => const RoadsideHomeScreen(),
        'location picker': (tester, bloc, repo) async {
          bloc.add(const SelectService(ServiceType.batteryJump));
          await tester.pump();
          return const LocationPickerScreen();
        },
        'price estimate': (tester, bloc, repo) async {
          await seedEstimate(tester, bloc);
          return const PriceEstimateScreen();
        },
        'searching': (tester, bloc, repo) async {
          await seedSearching(tester, bloc);
          return const SearchingDriverScreen();
        },
        'tracking': (tester, bloc, repo) async {
          await seedSearching(tester, bloc);
          await pushUpdate(tester, repo,
              driverRequest(RequestStatus.driverEnRoute));
          return const TrackingScreen();
        },
        'rating': (tester, bloc, repo) async {
          await seedSearching(tester, bloc);
          await pushUpdate(tester, repo,
              driverRequest(RequestStatus.completed, cashCollected: true));
          return const RatingScreen();
        },
        'request history': (tester, bloc, repo) async {
          repo.history = [
            sampleRequest(status: RequestStatus.completed),
            sampleRequest(id: 'req-2', status: RequestStatus.cancelled),
          ];
          return const RequestHistoryScreen();
        },
      };

  for (final screen in screens.entries) {
    for (final theme in themes.entries) {
      for (final locale in locales.entries) {
        testWidgets(
            '${screen.key}: ${theme.key} theme, ${locale.key}', (tester) async {
          final repo = GatedRoadsideRepository();
          final bloc = RoadsideBloc(repo);
          addTearDown(bloc.close);
          setUpRoadsideTestEnvironment(tester);
          final widget = await screen.value(tester, bloc, repo);
          await pumpRoadsideScreen(tester,
              bloc: bloc,
              screen: widget,
              locale: locale.value,
              theme: theme.value);

          expect(tester.takeException(), isNull);
          final scaffold = find.byType(Scaffold).last;
          final ctx = tester.element(scaffold);
          expect(Theme.of(ctx).brightness, theme.value.brightness);
          // Screens sit on the palette's solid background.
          expect(Theme.of(ctx).scaffoldBackgroundColor, ctx.colors.bg);
        });
      }
    }
  }
}
