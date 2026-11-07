import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/theme/app_palette.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/core/widgets/app_card.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/services/maintenance_service.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/core/services/trip_service.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/obd_gauge.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/screen_harness.dart';

/// [FakeOBDAdapter] whose readiness reply says compression ignition (diesel).
class _DieselFakeAdapter extends FakeOBDAdapter {
  @override
  Future<ReadinessResult> getReadinessMonitors() async => const ReadinessResult(
    milOn: false,
    dtcCount: 0,
    monitors: [],
    compressionIgnition: true,
  );
}

/// [FakeOBDAdapter] that also reports a VIN.
class _VinFakeAdapter extends FakeOBDAdapter {
  _VinFakeAdapter(this.vin);
  final String vin;

  @override
  Future<String?> getVin() async => vin;
}

Widget _wrap(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

/// When connected, initState kicks off OBD requests (DTC scan → readiness,
/// VIN) that each wait out OBDService's 300 ms settle delay. Advance fake time
/// past them so no timers are left pending when the test ends.
Future<void> _drainObdRequests(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

/// Opens the "All parameters" list under the live tiles (collapsed by
/// default; the extra live parameters live there).
Future<void> _showAllParams(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('dash_more_params'));
  await tester.ensureVisible(toggle);
  await tester.pump();
  await tester.tap(toggle);
  await tester.pump();
}

void main() {
  late FakeOBDAdapter fake;

  setUp(() {
    fake = FakeOBDAdapter();
    OBDService.setTestAdapter(fake);
  });

  tearDown(() {
    fake.dispose();
  });

  // ── Smoke ─────────────────────────────────────────────────────────────────

  testWidgets('DashboardScreen renders without crashing', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  // ── Static sections ───────────────────────────────────────────────────────

  testWidgets('shows Vehicle Health card', (tester) async {
    // Not connected: the health card is replaced by the connect card.
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();
    expect(find.text('OBD Not Connected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    await OBDService.instance.initialize(MockBluetoothDevice());
    await tester.pumpWidget(_wrap(const DashboardScreen(key: ValueKey(2))));
    await tester.pump();
    expect(find.text('Vehicle Health'), findsOneWidget);

    await _drainObdRequests(tester);
  });

  testWidgets('shows Warning Lights section', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(find.text('Warning Lights'), findsOneWidget);
  });

  testWidgets('shows Quick Scan button', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(find.text('Quick Scan'), findsOneWidget);
  });

  // ── Live data section ─────────────────────────────────────────────────────

  testWidgets('Live Data section shows -- when no data yet', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // Each tile shows '--' for its value until the first poll arrives.
    expect(find.text('--'), findsWidgets);
  });

  testWidgets('Live Data section updates when adapter emits data', (
    tester,
  ) async {
    await OBDService.instance.initialize(MockBluetoothDevice());

    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // Emit a snapshot from the fake adapter.
    fake.emitLiveData(
      const OBDLiveData(
        rpm: 3000,
        speedKmh: 90,
        coolantTempC: 95,
        throttlePct: 30,
        fuelLevelPct: 60,
      ),
    );

    // Two pumps: first flushes the stream microtask, second rebuilds the frame.
    await tester.pump();
    await tester.pump();

    // Scope the lookup to the Live Data tiles (labelled "Engine" / "Speed").
    // The tiles render whole numbers (decimals: 0).
    final rpmGauge = find.widgetWithText(OBDGauge, 'Engine');
    final speedGauge = find.widgetWithText(OBDGauge, 'Speed');
    expect(
      find.descendant(of: rpmGauge, matching: find.text('3000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: speedGauge, matching: find.text('90')),
      findsOneWidget,
    );

    await _drainObdRequests(tester);
  });

  testWidgets('Live Data section shows green dot when OBD is initialized', (
    tester,
  ) async {
    await OBDService.instance.initialize(MockBluetoothDevice());
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(find.text('Live Data'), findsOneWidget);
    // The connected indicator is a circular Container filled with the
    // theme's ok color in the Live Data header row (scope the search to that
    // row).
    final liveDataHeader = find
        .ancestor(of: find.text('Live Data'), matching: find.byType(Row))
        .first;
    final greenDot = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration as BoxDecoration).color == AppPalette.light.ok,
    );
    expect(
      find.descendant(of: liveDataHeader, matching: greenDot),
      findsOneWidget,
    );

    await _drainObdRequests(tester);
  });

  // ── Wide-band O2 / diesel tiles ───────────────────────────────────────────

  /// Mounts the dashboard connected to [adapter], lets the readiness request
  /// (which tells diesel from petrol) finish, then emits [data].
  Future<void> showLive(
    WidgetTester tester,
    FakeOBDAdapter adapter,
    OBDLiveData data,
  ) async {
    OBDService.setTestAdapter(adapter);
    await OBDService.instance.initialize(MockBluetoothDevice());
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();
    await _drainObdRequests(tester);
    adapter.emitLiveData(data);
    await tester.pump();
    await tester.pump();
    await _showAllParams(tester);
  }

  /// [f] restricted to the Live Data section (labels such as "Throttle" are
  /// also warning-light names further down the page).
  Finder live(Finder f) => find.descendant(
    of: find
        .ancestor(of: find.text('Live Data'), matching: find.byType(Column))
        .first,
    matching: f,
  );

  testWidgets('petrol: wide-band λ is shown in the O2 B1S1 tile when the '
      'narrow-band voltage is absent', (tester) async {
    await showLive(tester, fake, const OBDLiveData(lambdaB1S1: 0.984));

    expect(live(find.text('O2 B1S1')), findsOneWidget);
    expect(live(find.text('λ 0.98')), findsOneWidget);
    // Petrol layout unchanged.
    expect(live(find.text('Throttle')), findsOneWidget);
    expect(live(find.text('Timing')), findsOneWidget);
    expect(live(find.text('STFT B1')), findsOneWidget);
  });

  testWidgets('petrol: narrow-band voltage wins over λ', (tester) async {
    await showLive(
      tester,
      fake,
      const OBDLiveData(o2B1S1Voltage: 0.62, lambdaB1S1: 1.0),
    );

    expect(live(find.text('0.62V')), findsOneWidget);
    expect(live(find.textContaining('λ')), findsNothing);
  });

  testWidgets('diesel: pedal and rail pressure replace throttle / timing / '
      'fuel trims / empty O2 tiles', (tester) async {
    final diesel = _DieselFakeAdapter();
    addTearDown(diesel.dispose);
    await showLive(
      tester,
      diesel,
      const OBDLiveData(
        rpm: 800,
        acceleratorPedalPct: 14.9,
        fuelRailPressureKpa: 30000,
        oilTempC: 80,
      ),
    );

    expect(live(find.text('Pedal')), findsOneWidget);
    expect(live(find.text('14.9')), findsOneWidget);
    expect(live(find.text('Rail Press.')), findsOneWidget);
    expect(live(find.text('30.0')), findsOneWidget);
    expect(live(find.text('80°C')), findsOneWidget);
    expect(live(find.text('Throttle')), findsNothing);
    expect(live(find.text('Timing')), findsNothing);
    expect(live(find.text('STFT B1')), findsNothing);
    expect(live(find.text('O2 B1S1')), findsNothing);
  });

  testWidgets('diesel reporting a wide-band sensor keeps the O2 row', (
    tester,
  ) async {
    final diesel = _DieselFakeAdapter();
    addTearDown(diesel.dispose);
    await showLive(tester, diesel, const OBDLiveData(lambdaB1S1: 1.85));

    expect(live(find.text('O2 B1S1')), findsOneWidget);
    expect(live(find.text('λ 1.85')), findsOneWidget);
  });

  testWidgets('petrol without a throttle PID but with 0149 shows the pedal', (
    tester,
  ) async {
    await showLive(tester, fake, const OBDLiveData(acceleratorPedalPct: 20));

    expect(live(find.text('Pedal')), findsOneWidget);
    expect(live(find.text('Throttle')), findsNothing);
    expect(live(find.text('Timing')), findsOneWidget);
  });

  // ── startPolling / stopPolling lifecycle ──────────────────────────────────

  testWidgets('startPolling is called in initState when adapter initialized', (
    tester,
  ) async {
    await OBDService.instance.initialize(MockBluetoothDevice());

    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // Checked before any time elapses, so this can only come from initState's
    // startPolling (OBDService re-starts polling after each request too).
    expect(fake.startLiveDataCalled, isTrue);

    await _drainObdRequests(tester);
  });

  testWidgets('stopPolling is called when screen is disposed', (tester) async {
    await OBDService.instance.initialize(MockBluetoothDevice());

    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();
    await _drainObdRequests(tester);

    // OBDService also stops polling around each request it makes on mount,
    // so reset the flag to observe only what dispose() does.
    fake.stopLiveDataCalled = false;

    // Replace with an empty widget to trigger dispose.
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));

    expect(fake.stopLiveDataCalled, isTrue);
  });

  // ── Bottom nav ────────────────────────────────────────────────────────────

  testWidgets('has no bottom navigation bar of its own (AppShell provides '
      'it); History stays reachable from Recent Scans', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(DashboardScreen),
        matching: find.byType(Scaffold),
      ),
    );
    expect(scaffold.bottomNavigationBar, isNull);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Scan'), findsNothing);
    expect(find.text('History'), findsOneWidget);
  });

  // ══ Fixes: navigation, maintenance, localization, lamps, layout ══════════

  group('fixes', () {
    const locales = [en, ar];

    setUpAll(loadAppFonts);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Nothing due at the start of each test (the service is a singleton).
      await MaintenanceService.instance.setMileage(0);
    });

    /// Connects [adapter] and mounts the dashboard (optionally on top of a
    /// launcher page), then lets the on-connect requests finish.
    Future<void> mountConnected(
      WidgetTester tester, {
      Locale locale = en,
      FakeOBDAdapter? adapter,
      bool pushed = false,
      RecordingObserver? observer,
    }) async {
      final a = adapter ?? fake;
      OBDService.setTestAdapter(a);
      await OBDService.instance.initialize(MockBluetoothDevice());
      await pumpScreen(
        tester,
        const DashboardScreen(),
        locale: locale,
        pushed: pushed,
        observer: observer,
      );
      await tester.pump(const Duration(seconds: 1));
    }

    /// Pops the route on top of the dashboard (a [RouteStub]).
    Future<void> popStub(WidgetTester tester) async {
      Navigator.of(tester.element(find.byType(RouteStub))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> systemBack(WidgetTester tester) async {
      final dynamic app = tester.state(find.byType(WidgetsApp));
      // ignore: avoid_dynamic_calls
      await app.didPopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    /// Whether warning light [key] is lit: lit lamps are listed on the page
    /// (the full grid is behind "See all").
    bool lit(WidgetTester tester, String key, Locale locale) => find
        .descendant(
          of: find.byKey(const ValueKey('dash_lit_lamps')),
          matching: find.text(tr(key, locale)),
        )
        .evaluate()
        .isNotEmpty;

    for (final locale in locales) {
      final lang = locale.languageCode;

      // ── 1. Adapter screen from the connected header ──

      testWidgets('[$lang] connected header opens the adapter screen; '
          'disconnecting there brings back the connect banner', (tester) async {
        await mountConnected(tester, locale: locale);
        expect(find.text(tr('dash_manage_adapter', locale)), findsOneWidget);

        await tester.tap(find.text(tr('connected', locale)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.text('route:${AppRoutes.connectionscreen}'),
          findsOneWidget,
        );

        await OBDService.instance.disconnect();
        await popStub(tester);
        expect(find.text(tr('obd_not_connected', locale)), findsOneWidget);
        expect(find.text(tr('connected', locale)), findsNothing);
        await unmount(tester);
      });

      testWidgets('[$lang] switching adapters from the header restarts the '
          'session (DTC scan) on return', (tester) async {
        await mountConnected(tester, locale: locale);
        await tester.tap(find.text('FakeAdapter'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.text('route:${AppRoutes.connectionscreen}'),
          findsOneWidget,
        );

        // Another adapter is picked on the adapter screen.
        await OBDService.instance.disconnect();
        await OBDService.instance.initialize(MockBluetoothDevice());
        fake.getDtcsCalled = false;
        await popStub(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(fake.getDtcsCalled, isTrue);
        expect(find.text(tr('connected', locale)), findsOneWidget);
        await unmount(tester);
      });

      // ── 2. Back returns to the screen that pushed the dashboard ──

      testWidgets('[$lang] back pops to the hub and stops polling but keeps '
          'the link', (tester) async {
        await mountConnected(tester, locale: locale, pushed: true);
        fake.stopLiveDataCalled = false;

        await systemBack(tester);
        expect(find.text(launcherText), findsOneWidget);
        expect(find.byType(DashboardScreen), findsNothing);
        expect(find.text(tr('press_back_to_exit', locale)), findsNothing);
        expect(fake.stopLiveDataCalled, isTrue);
        expect(OBDService.instance.isInitialized, isTrue);
        await unmount(tester);
      });

      testWidgets('[$lang] as the root route, back asks to press again to '
          'exit', (tester) async {
        await pumpScreen(tester, const DashboardScreen(), locale: locale);
        await systemBack(tester);
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.text(tr('press_back_to_exit', locale)), findsOneWidget);
        await unmount(tester);
      });

      // ── 3. Smart key round-trip (the bottom bar now lives in AppShell) ──

      testWidgets('[$lang] the Smart Key shortcut opens the smart key screen '
          'and returns to Home', (tester) async {
        await pumpScreen(tester, const DashboardScreen(), locale: locale);

        await tapVisible(tester, find.text(tr('smart_key', locale)));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('route:${AppRoutes.smartKey}'), findsOneWidget);

        await popStub(tester);
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.text(tr('dash_services', locale)), findsOneWidget);
        await unmount(tester);
      });

      // ── 4 + 5. Maintenance entry point and due banner refresh ──

      testWidgets('[$lang] fresh dashboard links to the maintenance tracker', (
        tester,
      ) async {
        await pumpScreen(tester, const DashboardScreen(), locale: locale);
        expect(MaintenanceService.instance.dueCount, 0);
        expect(find.byIcon(Icons.build_outlined), findsNothing);

        await tapVisible(tester, find.text(tr('dash_svc_maintenance', locale)));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('route:${AppRoutes.maintenance}'), findsOneWidget);
        await unmount(tester);
      });

      testWidgets('[$lang] disconnected dashboard: the due banner follows '
          'changes made in the tracker', (tester) async {
        final svc = MaintenanceService.instance;
        await pumpScreen(tester, const DashboardScreen(), locale: locale);
        await tester.pump();
        expect(find.byIcon(Icons.build_outlined), findsNothing);

        // In the tracker: log the first item, then drive a full interval.
        await tapVisible(tester, find.text(tr('dash_svc_maintenance', locale)));
        await tester.pump(const Duration(milliseconds: 600));
        final item = svc.items.first;
        await svc.logService(item.id);
        await svc.setMileage(item.intervalKm.toDouble());
        expect(svc.dueCount, 1);
        await popStub(tester);

        final banner = find.text(
          tr('dash_maintenance_due_one', locale).replaceAll('{n}', '1'),
        );
        expect(banner, findsOneWidget);
        expect(find.byIcon(Icons.build_outlined), findsOneWidget);
        expect(lit(tester, 'service', locale), isTrue);

        // Back in the tracker: service it again → banner and lamp clear.
        await tapVisible(tester, banner);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('route:${AppRoutes.maintenance}'), findsOneWidget);
        await svc.logService(item.id);
        expect(svc.dueCount, 0);
        await popStub(tester);
        expect(find.byIcon(Icons.build_outlined), findsNothing);
        expect(lit(tester, 'service', locale), isFalse);
        await unmount(tester);
      });

      // ── 6. Localized labels ──

      testWidgets('[$lang] live tiles, gauges, health and trip card are '
          'localized', (tester) async {
        await mountConnected(tester, locale: locale);
        fake.emitLiveData(
          const OBDLiveData(
            rpm: 2100,
            speedKmh: 64,
            coolantTempC: 90,
            intakeAirTempC: 30,
            batteryVoltage: 14.1,
            throttlePct: 18,
            fuelLevelPct: 55,
            engineLoad: 35,
            mapKpa: 40,
            timingAdvanceDeg: 12,
            fuelTrimShortPct: 1.5,
            fuelTrimLongPct: -2,
            oilTempC: 95,
            o2B1S1Voltage: 0.6,
          ),
        );
        await tester.pump();
        await tester.pump();
        await _showAllParams(tester);

        expect(
          find.widgetWithText(OBDGauge, tr('dash_speed', locale)),
          findsOneWidget,
        );
        for (final key in [
          'dash_coolant',
          'dash_air_temp',
          'battery',
          'throttle',
          'fuel',
          'dash_engine_load',
          'dash_map',
          'dash_oil_temp',
          'dash_trip_computer',
          'dash_distance',
          'dash_time',
          'dash_avg_speed',
          'dash_fuel_used',
          'dash_efficiency',
          'drive_score',
          'dash_reset',
        ]) {
          expect(find.text(tr(key, locale)), findsWidgets, reason: key);
        }
        // Score ring + condition label, in the health card.
        final healthCard = find
            .ancestor(
              of: find.text(tr('vehicle_health', locale)),
              matching: find.byType(AppCard),
            )
            .first;
        expect(
          find.descendant(of: healthCard, matching: find.text('100')),
          findsOneWidget,
        );
        expect(find.text(tr('dash_health_excellent', locale)), findsOneWidget);
        // Drive-score band, shown without its emoji.
        expect(
          find.text(tr('dash_drive_eco', locale).replaceAll('🌿', '').trim()),
          findsOneWidget,
        );

        if (lang == 'ar') {
          final leaks = englishLeaks(
            tester,
            allow: {
              // Units, sensor acronyms and the adapter's own name.
              'rpm', 'kpa', 'stft', 'ltft', 'maf', 'egr', 'mil', 'fakeadapter',
            },
          );
          expect(leaks, isEmpty, reason: leaks.join(' | '));
        } else {
          expect(find.widgetWithText(OBDGauge, 'Speed'), findsOneWidget);
          expect(find.text('Trip Computer'), findsOneWidget);
        }
        await unmount(tester);
      });

      testWidgets('[$lang] disconnected health card is localized', (
        tester,
      ) async {
        await pumpScreen(tester, const DashboardScreen(), locale: locale);
        expect(
          find.text(tr('dash_connect_for_health', locale)),
          findsOneWidget,
        );
        expect(find.text(tr('dash_speed', locale)), findsWidgets);
        expect(find.text(tr('dash_coolant', locale)), findsWidgets);
        await unmount(tester);
      });

      testWidgets('[$lang] VIN card country is localized', (tester) async {
        final changan = _VinFakeAdapter('LS5A3DKE0NA000001');
        addTearDown(changan.dispose);
        await mountConnected(tester, locale: locale, adapter: changan);
        final country = lang == 'ar' ? 'الصين' : 'China';
        expect(find.textContaining('$country  •  VIN:'), findsOneWidget);
        if (lang == 'ar') expect(find.textContaining('China'), findsNothing);
        await unmount(tester);
      });

      testWidgets('[$lang] VIN country without an Arabic name falls back to '
          'English', (tester) async {
        // AJ… = Ivory Coast (ISO 3780), not in the Arabic table.
        final ivory = _VinFakeAdapter('AJ1AAAAA0NA000001');
        addTearDown(ivory.dispose);
        await mountConnected(tester, locale: locale, adapter: ivory);
        expect(find.textContaining('Ivory Coast  •  VIN:'), findsOneWidget);
        await unmount(tester);
      });

      // ── 7. Chassis codes → lamps ──

      testWidgets('[$lang] manufacturer chassis code C1201 lights no steering '
          'lamp; SAE steering / ABS / traction codes light theirs', (
        tester,
      ) async {
        fake.dtcsToReturn = ['C1201'];
        await mountConnected(tester, locale: locale);
        expect(lit(tester, 'steering', locale), isFalse);
        expect(lit(tester, 'abs', locale), isFalse);
        expect(lit(tester, 'traction', locale), isFalse);
        // Still a fault code on the health card.
        expect(
          find.text(tr('dash_fault_code_n', locale).replaceAll('{n}', '1')),
          findsOneWidget,
        );
        await unmount(tester);

        await OBDService.instance.disconnect();
        fake.dtcsToReturn = ['C0035', 'C0110', 'C0450'];
        await mountConnected(tester, locale: locale);
        expect(lit(tester, 'abs', locale), isTrue); // C0035 wheel speed
        expect(lit(tester, 'traction', locale), isTrue); // C0110
        expect(
          lit(tester, 'steering', locale),
          isTrue,
        ); // C0450 assist actuator
        await unmount(tester);

        await OBDService.instance.disconnect();
        fake.dtcsToReturn = ['C0191', 'C2100'];
        await mountConnected(tester, locale: locale);
        expect(lit(tester, 'steering', locale), isTrue); // C0191 angle sensor
        expect(lit(tester, 'traction', locale), isFalse);
        await unmount(tester);

        // Per the bundled descriptions: C0196 is a yaw-rate sensor (ESC),
        // C0455 the brake-fluid level switch — neither is steering.
        await OBDService.instance.disconnect();
        fake.dtcsToReturn = ['C0196', 'C0455'];
        await mountConnected(tester, locale: locale);
        expect(lit(tester, 'steering', locale), isFalse);
        expect(lit(tester, 'traction', locale), isTrue); // C0196 yaw rate
        await unmount(tester);
      });

      // ── 8. Health card counts codes ──

      testWidgets('[$lang] health card counts confirmed codes, pending '
          'separately', (tester) async {
        // 3 confirmed + 1 pending lights 4 lamps (misfire, check engine,
        // network, fuel trim): the card must say 3 codes, +1 pending.
        fake.dtcsToReturn = ['P0300', 'P1336', 'U1012', '~P0171'];
        await mountConnected(tester, locale: locale);
        expect(
          find.text(tr('dash_fault_codes_n', locale).replaceAll('{n}', '3')),
          findsOneWidget,
        );
        expect(
          find.text(tr('dash_pending_codes_n', locale).replaceAll('{n}', '1')),
          findsOneWidget,
        );
        if (lang == 'en') {
          expect(find.text('3 active fault codes detected'), findsOneWidget);
        }
        await unmount(tester);
      });

      testWidgets('[$lang] only pending codes: no "0 active codes"', (
        tester,
      ) async {
        fake.dtcsToReturn = ['~P0171'];
        await mountConnected(tester, locale: locale);
        expect(
          find.text(tr('dash_pending_only_one', locale).replaceAll('{n}', '1')),
          findsOneWidget,
        );
        expect(
          find.text(tr('dash_fault_codes_n', locale).replaceAll('{n}', '0')),
          findsNothing,
        );
        await unmount(tester);
      });

      // ── 9. Layout at 390 px ──

      testWidgets('[$lang] connected dashboard (trip card running) lays out '
          'without overflow at 390 px', (tester) async {
        await mountConnected(tester, locale: locale);
        fake.emitLiveData(const OBDLiveData(rpm: 2500, speedKmh: 80));
        await tester.pump();
        await tester.pump();
        expect(TripService.instance.isRunning, isTrue);
        expect(find.text(tr('dash_trip_computer', locale)), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -1500),
        );
        await tester.pump();
        expectNoException(tester);
        await unmount(tester);
      });

      // ── 10. Redesign: themes, navigation targets, warning-light sheet ──

      for (final (themeName, theme) in [
        ('light', AppTheme.light),
        ('dark', AppTheme.dark),
      ]) {
        testWidgets('[$lang][$themeName] disconnected and connected Home '
            'render without exceptions', (tester) async {
          await pumpScreen(
            tester,
            const DashboardScreen(),
            locale: locale,
            theme: theme,
          );
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -2000),
          );
          await tester.pump();
          expectNoException(tester);
          await unmount(tester);

          fake.dtcsToReturn = ['P0300', 'C0035', '~P0171'];
          await mountConnected(tester, locale: locale);
          await pumpScreen(
            tester,
            const DashboardScreen(key: ValueKey('themed')),
            locale: locale,
            theme: theme,
          );
          await tester.pump(const Duration(seconds: 1));
          fake.emitLiveData(
            const OBDLiveData(
              rpm: 2150,
              speedKmh: 64,
              coolantTempC: 90,
              batteryVoltage: 14.1,
              fuelTrimShortB2: 3,
            ),
          );
          await tester.pump();
          await tester.pump();
          await _showAllParams(tester);
          for (var i = 0; i < 4; i++) {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -600),
            );
            await tester.pump();
          }
          expectNoException(tester);
          await unmount(tester);
        });
      }

      testWidgets('[$lang] outside the shell, Connect / Quick Scan / '
          'services / History / Settings push their screens', (tester) async {
        await pumpScreen(tester, const DashboardScreen(), locale: locale);
        Future<void> opens(Finder target, String route) async {
          await tapVisible(tester, target);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text('route:$route'), findsOneWidget, reason: route);
          await popStub(tester);
        }

        await opens(
          find.text(tr('dash_connect', locale)),
          AppRoutes.connectionscreen,
        );
        await opens(
          find.text(tr('quick_scan', locale)),
          AppRoutes.diagnosticCodes,
        );
        await opens(
          find.text(tr('dash_svc_roadside', locale)),
          AppRoutes.roadside,
        );
        await opens(
          find.text(tr('dash_svc_tutorials', locale)),
          AppRoutes.videoTutorials,
        );
        await opens(find.text(tr('history', locale)), AppRoutes.history);
        await opens(find.byTooltip(tr('settings', locale)), AppRoutes.settings);
        await unmount(tester);
      });

      testWidgets('[$lang] connected: codes row, See graph and the adapter '
          'action open their screens', (tester) async {
        fake.dtcsToReturn = ['P0300'];
        await mountConnected(tester, locale: locale);
        Future<void> opens(Finder target, String route) async {
          await tapVisible(tester, target);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text('route:$route'), findsOneWidget, reason: route);
          await popStub(tester);
        }

        await opens(
          find.text(tr('dash_fault_code_n', locale).replaceAll('{n}', '1')),
          AppRoutes.diagnosticCodes,
        );
        await opens(
          find.text(tr('dash_see_graph', locale)),
          AppRoutes.liveGraph,
        );
        await opens(
          find.byTooltip(tr('dash_adapter', locale)),
          AppRoutes.connectionscreen,
        );
        await tester.pump(const Duration(seconds: 1));
        await unmount(tester);
      });

      testWidgets('[$lang] inside AppShell, Quick Scan switches to the '
          'Diagnose tab instead of pushing', (tester) async {
        await pumpScreen(tester, const AppShell(), locale: locale);
        final shell = tester.state<AppShellState>(find.byType(AppShell));
        expect(shell.tab, AppTab.home);
        // No settings action inside the shell: Profile is a tab.
        expect(find.byTooltip(tr('settings', locale)), findsNothing);

        await tapVisible(
          tester,
          find.descendant(
            of: find.byType(DashboardScreen),
            matching: find.text(tr('quick_scan', locale)),
          ),
        );
        expect(shell.tab, AppTab.diagnose);
        expect(find.text('route:${AppRoutes.diagnosticCodes}'), findsNothing);
        await unmount(tester);
      });

      testWidgets('[$lang] lit lamps are listed; "See all" shows every lamp; '
          'a lamp with codes opens its code sheet', (tester) async {
        fake.dtcsToReturn = ['P0300'];
        await mountConnected(tester, locale: locale);
        expect(lit(tester, 'misfire', locale), isTrue);
        expect(lit(tester, 'abs', locale), isFalse);

        await tapVisible(tester, find.text(tr('dash_see_all', locale)));
        await tester.pump(const Duration(milliseconds: 600));
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        for (final key in ['check_engine', 'battery', 'abs', 'misfire']) {
          expect(
            find.descendant(of: sheet, matching: find.text(tr(key, locale))),
            findsOneWidget,
            reason: key,
          );
        }
        Navigator.of(tester.element(sheet)).pop();
        await tester.pump(const Duration(milliseconds: 600));

        await tapVisible(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('dash_lit_lamps')),
            matching: find.text(tr('misfire', locale)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('P0300'),
          ),
          findsOneWidget,
        );
        expectNoException(tester);
        await unmount(tester);
      });
    }
  });
}
