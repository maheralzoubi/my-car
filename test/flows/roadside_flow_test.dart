// Flow 4 — roadside assistance happy path, under fake time, with the real
// screens and bloc backed by MockRoadsideRepository (whose timers simulate
// the driver: found after 4 s, en route 2 s later, then 2 s movement ticks
// until arrival, in progress 3 s later, completed 5 s after that):
//
//   app shell → Roadside tab → pick service → location → estimate →
//   request → searching → driver found / en route → arrived → in progress →
//   completed → rating → back on the Roadside tab, request saved with the
//   rating.
//
// App wires the live ApiRoadsideRepository through AppServices with no seam,
// so this harness mirrors App's widget stack (ScreenUtil, RoadsideBloc,
// localizations, the bottom-navigation AppShell as first route, the roadside
// route).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/core/widgets/widgets.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/data/repositories/mock_roadside_repository.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';
import 'package:mycar/modules/roadside/presentation/pages/location_picker_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/price_estimate_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/rating_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/roadside_home_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/searching_driver_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/tracking_screen.dart';

import 'helpers/flow_harness.dart';
import 'helpers/obd_steps.dart';

Widget _roadsideApp(RoadsideBloc bloc, {Locale locale = const Locale('en')}) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    splitScreenMode: true,
    child: BlocProvider<RoadsideBloc>.value(
      value: bloc,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: const AppShell(),
        routes: {AppRoutes.roadside: (_) => const RoadsideHomeScreen()},
      ),
    ),
  );
}

/// Status-banner icon on the tracking screen for each live status.
const _statusIcon = {
  RequestStatus.driverFound: Icons.check_circle_rounded,
  RequestStatus.driverEnRoute: Icons.navigation_rounded,
  RequestStatus.arrived: Icons.pin_drop_rounded,
  RequestStatus.inProgress: Icons.build_circle_rounded,
};

void main() {
  late MockRoadsideRepository repo;
  late RoadsideBloc bloc;

  // The shell opens on Home (the dashboard), which needs BLE and an OBD
  // adapter even while disconnected.
  setUpAll(FakeBlePlatform.install);

  setUp(installPlatformFakes);

  // Created inside each test body on purpose: a bloc built in setUp runs its
  // event handlers in the root zone, outside the test's fake-async zone, so
  // its state emissions would be delivered only after the test had moved on.
  void createBloc() {
    newFakeAdapter();
    repo = MockRoadsideRepository();
    bloc = RoadsideBloc(repo);
    addTearDown(bloc.close);
  }

  /// Drives the whole request from the shell to the rating screen (status by
  /// status), then picks 4 stars.
  Future<void> driveToRating(
    WidgetTester tester,
    String lang,
    Locale locale,
  ) async {
    await tester.pumpWidget(_roadsideApp(bloc, locale: locale));
    await advance(tester, const Duration(seconds: 1));

    // ── Shell → Roadside tab ─────────────────────────────────────────
    await goToTab(tester, AppTab.roadside, lang: lang);
    expectOnScreen<RoadsideHomeScreen>();
    expect(findTr('select_service_needed', lang), findsOneWidget);

    // ── Pick a service → location picker ─────────────────────────────
    await tapOn(
      tester,
      find.byIcon(ServiceType.batteryJump.icon).hitTestable().first,
      scroll: false,
    );
    await advance(tester, const Duration(milliseconds: 600));
    expectOnScreen<LocationPickerScreen>();
    expect(bloc.state.phase, RoadsidePhase.locationPicker);
    expect(bloc.state.selectedService, ServiceType.batteryJump);

    // ── Confirm location → price estimate ────────────────────────────
    await tapOn(
      tester,
      find.descendant(
        of: find.byType(LocationPickerScreen),
        matching: find.byType(AppButton),
      ),
    );
    await advance(tester, const Duration(milliseconds: 800));
    expectOnScreen<PriceEstimateScreen>();
    expect(
      find.byType(LocationPickerScreen),
      findsNothing,
      reason: 'estimate replaces the picker',
    );
    expect(bloc.state.phase, RoadsidePhase.estimate);
    expect(bloc.state.estimatedPrice, greaterThan(0));
    expect(findTr('total_estimate', lang), findsOneWidget);

    // ── Request → searching for a driver ─────────────────────────────
    await tapOn(tester, find.byIcon(Icons.local_shipping_rounded));
    await advance(tester, const Duration(milliseconds: 600));
    expectOnScreen<SearchingDriverScreen>();
    expect(findTr('finding_nearest_driver', lang), findsOneWidget);
    expect(bloc.state.activeRequest?.status, RequestStatus.searching);

    // ── Driver found (t+4 s) → tracking ──────────────────────────────
    await advanceUntil(
      tester,
      () => bloc.state.activeRequest?.status == RequestStatus.driverFound,
      timeout: const Duration(seconds: 6),
    );
    await advance(tester, const Duration(milliseconds: 500)); // transition
    expectOnScreen<TrackingScreen>();
    expect(find.byType(SearchingDriverScreen), findsNothing);
    expect(bloc.state.activeRequest?.assignedDriver, isNotNull);
    expect(
      find.byIcon(_statusIcon[RequestStatus.driverFound]!),
      findsOneWidget,
    );

    // ── En route (t+2 s); the driver can be cancelled only now ───────
    await advanceUntil(
      tester,
      () => bloc.state.activeRequest?.status == RequestStatus.driverEnRoute,
      timeout: const Duration(seconds: 3),
    );
    await advance(tester, const Duration(milliseconds: 500)); // transition
    expect(bloc.state.activeRequest?.status, RequestStatus.driverEnRoute);
    expect(
      find.byIcon(_statusIcon[RequestStatus.driverEnRoute]!),
      findsOneWidget,
    );
    expect(findTr('cancel', lang), findsOneWidget);
    final enRouteAt = bloc.state.activeRequest!.driverLocation!;

    // Movement ticks every 2 s bring the driver closer.
    await advance(tester, const Duration(seconds: 4));
    final movedTo = bloc.state.activeRequest!.driverLocation!;
    expect(movedTo, isNot(enRouteAt));

    // ── Arrived (≤ 31 ticks) ─────────────────────────────────────────
    await advanceUntil(
      tester,
      () => bloc.state.activeRequest?.status == RequestStatus.arrived,
      timeout: const Duration(seconds: 70),
    );
    await tester.pump();
    expect(find.byIcon(_statusIcon[RequestStatus.arrived]!), findsOneWidget);
    expect(
      bloc.state.activeRequest!.driverLocation,
      bloc.state.activeRequest!.customerLocation,
    );
    expect(
      findTr('cancel', lang),
      findsNothing,
      reason: 'cancel is only offered while the driver is en route',
    );

    // ── In progress (t+3 s) ──────────────────────────────────────────
    await advanceUntil(
      tester,
      () => bloc.state.activeRequest?.status == RequestStatus.inProgress,
      timeout: const Duration(seconds: 4),
    );
    await advance(tester, const Duration(milliseconds: 500)); // transition
    expect(bloc.state.activeRequest?.status, RequestStatus.inProgress);
    expect(find.byIcon(_statusIcon[RequestStatus.inProgress]!), findsOneWidget);

    // ── Completed (t+5 s) → rating ───────────────────────────────────
    await advanceUntil(
      tester,
      () => bloc.state.activeRequest?.status == RequestStatus.completed,
      timeout: const Duration(seconds: 6),
    );
    await advance(tester, const Duration(milliseconds: 500)); // transition
    await advance(tester, const Duration(milliseconds: 600));
    expect(bloc.state.phase, RoadsidePhase.rating);
    expectOnScreen<RatingScreen>();
    expect(find.byType(TrackingScreen), findsNothing);
    expect(findTr('how_was_experience', lang), findsOneWidget);

    await tapOn(tester, find.byIcon(Icons.star_outline_rounded).at(3));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
  }

  for (final (lang, locale) in [
    ('en', const Locale('en')),
    ('ar', const Locale('ar')),
  ]) {
    testWidgets('[$lang] request → estimate → search → en route → arrived → '
        'in progress → completed → rating', (tester) async {
      usePhoneSurface(tester);
      createBloc();
      await withKnownOverflows(() async {
        await driveToRating(tester, lang, locale);
        await unmountApp(tester);
      });
    });
  }

  group('flow reset (regression: estimate screen left in the stack must not '
      'crash on ResetFlow / CancelRequest)', () {
    for (final (lang, locale) in [
      ('en', const Locale('en')),
      ('ar', const Locale('ar')),
    ]) {
      testWidgets('[$lang] submitting the rating returns to the Roadside tab '
          'with the rating saved', (tester) async {
        usePhoneSurface(tester);
        createBloc();
        await withKnownOverflows(() async {
          await driveToRating(tester, lang, locale);
          await tapOn(
            tester,
            find.descendant(
              of: find.byType(RatingScreen),
              matching: find.byType(AppButton),
            ),
          );
          await advance(tester, const Duration(milliseconds: 800));

          _expectBackOnRoadsideTab(tester);
          expect(findTr('select_service_needed', lang), findsOneWidget);
          expect(bloc.state.phase, RoadsidePhase.idle);
          expect(bloc.state.activeRequest, isNull);

          // The completed request is in history with the rating attached.
          final history = await _history(tester, repo);
          expect(history, hasLength(1));
          expect(history.single.status, RequestStatus.completed);
          expect(history.single.rating, 4);
          expect(history.single.serviceType, ServiceType.batteryJump);

          await unmountApp(tester);
        });
      });

      testWidgets('[$lang] cancelling while the driver is en route returns to '
          'the Roadside tab', (tester) async {
        usePhoneSurface(tester);
        createBloc();
        await withKnownOverflows(() async {
          await tester.pumpWidget(_roadsideApp(bloc, locale: locale));
          await advance(tester, const Duration(seconds: 1));
          await goToTab(tester, AppTab.roadside, lang: lang);
          await tapOn(
            tester,
            find.byIcon(ServiceType.tireRepair.icon).hitTestable().first,
            scroll: false,
          );
          await advance(tester, const Duration(milliseconds: 600));
          await tapOn(
            tester,
            find.descendant(
              of: find.byType(LocationPickerScreen),
              matching: find.byType(AppButton),
            ),
          );
          await advance(tester, const Duration(milliseconds: 800));
          await tapOn(tester, find.byIcon(Icons.local_shipping_rounded));
          await advanceUntil(
            tester,
            () =>
                bloc.state.activeRequest?.status == RequestStatus.driverEnRoute,
            timeout: const Duration(seconds: 9),
          );
          await advance(tester, const Duration(milliseconds: 500));
          expectOnScreen<TrackingScreen>();
          expect(bloc.state.activeRequest?.status, RequestStatus.driverEnRoute);

          await tapOn(tester, findTr('cancel', lang));
          await advance(tester, const Duration(milliseconds: 800));

          _expectBackOnRoadsideTab(tester);
          expect(bloc.state.phase, RoadsidePhase.idle);
          // (activeRequest after a cancel: see the skipped REGRESSION test.)
          final history = await _history(tester, repo);
          expect(history.single.status, RequestStatus.cancelled);

          // The simulation is stopped: nothing changes any more.
          await advance(
            tester,
            const Duration(seconds: 20),
            step: const Duration(seconds: 1),
          );
          expect(
            (await _history(tester, repo)).single.status,
            RequestStatus.cancelled,
          );
          _expectBackOnRoadsideTab(tester);

          // A new request starts cleanly from the Roadside tab after the
          // cancel.
          expect(bloc.state.phase, isNot(RoadsidePhase.tracking));
          await tapOn(
            tester,
            find.byIcon(ServiceType.tireRepair.icon).hitTestable().first,
            scroll: false,
          );
          await advance(tester, const Duration(milliseconds: 600));
          expectOnScreen<LocationPickerScreen>();
          expect(bloc.state.phase, RoadsidePhase.locationPicker);

          await unmountApp(tester);
        });
      });
    }
  });

  group('', () {
    testWidgets('cancel clears the active request for good', (tester) async {
      usePhoneSurface(tester);
      createBloc();
      await withKnownOverflows(() async {
        await tester.pumpWidget(_roadsideApp(bloc));
        await advance(tester, const Duration(seconds: 1));
        await goToTab(tester, AppTab.roadside);
        await tapOn(
          tester,
          find.byIcon(ServiceType.tireRepair.icon).hitTestable().first,
          scroll: false,
        );
        await advance(tester, const Duration(milliseconds: 600));
        await tapOn(
          tester,
          find.descendant(
            of: find.byType(LocationPickerScreen),
            matching: find.byType(AppButton),
          ),
        );
        await advance(tester, const Duration(milliseconds: 800));
        await tapOn(tester, find.byIcon(Icons.local_shipping_rounded));
        await advanceUntil(
          tester,
          () => bloc.state.activeRequest?.status == RequestStatus.driverEnRoute,
          timeout: const Duration(seconds: 9),
        );
        await advance(tester, const Duration(milliseconds: 500));
        await tapOn(tester, findTr('cancel'));
        await advance(tester, const Duration(seconds: 2));
        _expectBackOnRoadsideTab(tester);
        expect(bloc.state.phase, RoadsidePhase.idle);
        expect(bloc.state.activeRequest, isNull);
        await unmountApp(tester);
      });
    });
  });
}

/// Back on the shell's Roadside tab: its root screen is showing and no pushed
/// roadside route (on- or offstage) is left above the shell.
void _expectBackOnRoadsideTab(WidgetTester tester) {
  expectOnScreen<AppShell>();
  expect(currentTab(tester), AppTab.roadside);
  expectOnScreen<RoadsideHomeScreen>();
  expect(
    Navigator.of(tester.element(find.byType(AppShell))).canPop(),
    isFalse,
    reason: 'only the shell is left on the stack',
  );
  for (final type in [
    LocationPickerScreen,
    PriceEstimateScreen,
    SearchingDriverScreen,
    TrackingScreen,
    RatingScreen,
  ]) {
    expect(
      find.byType(type, skipOffstage: false),
      findsNothing,
      reason: '$type must be gone from the stack',
    );
  }
}

/// MockRoadsideRepository.getHistory waits 200 ms on a timer; drive fake
/// time while it does.
Future<List<ServiceRequest>> _history(
  WidgetTester tester,
  MockRoadsideRepository repo,
) async {
  final pending = repo.getHistory();
  await tester.pump(const Duration(milliseconds: 250));
  return pending;
}

/// Advances fake time in 500 ms frames until [done] holds.
Future<void> advanceUntil(
  WidgetTester tester,
  bool Function() done, {
  required Duration timeout,
}) async {
  var elapsed = Duration.zero;
  const step = Duration(milliseconds: 500);
  while (!done()) {
    if (elapsed >= timeout) fail('condition not met within $timeout');
    await advance(tester, step);
    elapsed += step;
  }
}
