// ignore_for_file: invalid_use_of_visible_for_testing_member
// Screenshot gallery of every screen, rendered from the current code at the
// real phone size (390x844 logical px) and saved at 2x into design/screens/.
//
// Not part of the normal suite (lives outside test/). Run with:
//   flutter test test_gallery
//
// Files are named <NN>_<screen>_<light|dark|ar>.png (ar = Arabic, light theme).
// Framework errors raised while a screen is shown (e.g. RenderFlex overflow)
// do not fail the capture; they are logged to design/screens/_capture_log.txt.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/core/bloc/locale/locale_bloc.dart';
import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/services/maintenance_service.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/core/widgets/app_button.dart';
import 'package:mycar/modules/home/bloc/counter/counter_bloc.dart';
import 'package:mycar/modules/home/presentation/pages/authScreen/auth_screen.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/solution_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dtc_lookup_page.dart';
import 'package:mycar/modules/home/presentation/pages/home_page.dart';
import 'package:mycar/modules/home/presentation/pages/liveGraphScreen/live_graph_screen.dart';
import 'package:mycar/modules/home/presentation/pages/maintenanceScreen/maintenance_screen.dart';
import 'package:mycar/modules/home/presentation/pages/parentModeScreen/parent_mode_screen.dart';
import 'package:mycar/modules/home/presentation/pages/profileScreen/edit_profile_screen.dart';
import 'package:mycar/modules/home/presentation/pages/profileScreen/profile_screen.dart';
import 'package:mycar/modules/home/presentation/pages/settingsScreen/dash_cam_settings_screen.dart';
import 'package:mycar/modules/home/presentation/pages/settingsScreen/settings_screen.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';
import 'package:mycar/modules/home/presentation/pages/smartKeyScreen/smart_key_screen.dart';
import 'package:mycar/modules/home/presentation/pages/spalchScreen/spalch_screen.dart';
import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/upload_video_screen.dart';
import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/video_player_screen.dart';
import 'package:mycar/modules/home/presentation/pages/videoTutorialsScreen/video_tutorials_screen.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/pages/location_picker_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/price_estimate_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/rating_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/request_history_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/searching_driver_screen.dart';
import 'package:mycar/modules/roadside/presentation/pages/tracking_screen.dart';

import '../test/flows/helpers/flow_harness.dart'
    show FakeBlePlatform, installPlatformFakes;
import '../test/helpers/fake_obd_adapter.dart';
import '../test/roadside/helpers/roadside_fakes.dart' show sampleRequest;
import '../test/roadside/screens/roadside_screen_harness.dart'
    show GatedRoadsideRepository, driverRequest, pushUpdate, seedEstimate,
        seedSearching;
import '../test/screens/helpers/screen_harness.dart';

// ── Output ────────────────────────────────────────────────────────────────────

final String _outDir = () {
  // flutter test runs with the package root as the working directory.
  final dir = Directory('${Directory.current.path}/design/screens');
  dir.createSync(recursive: true);
  return dir.path;
}();

final List<String> _log = [];

/// The repaint boundary of the route the user currently sees: the first
/// full-screen [RenderRepaintBoundary] above that route's outermost Scaffold.
RenderRepaintBoundary _boundary(WidgetTester tester) {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final scaffolds = find
      .byType(Scaffold)
      .evaluate()
      .where((e) => ModalRoute.of(e)?.isCurrent ?? true)
      .toList();
  if (scaffolds.isEmpty) throw StateError('no Scaffold on the current route');
  RenderObject? r = scaffolds.first.renderObject;
  while (r != null) {
    if (r is RenderRepaintBoundary &&
        (r.size.width - screen.width).abs() < 0.5 &&
        (r.size.height - screen.height).abs() < 0.5) {
      return r;
    }
    r = r.parent;
  }
  throw StateError('no full-screen RepaintBoundary above the Scaffold');
}

Future<void> _shot(WidgetTester tester, String file) async {
  final boundary = _boundary(tester);
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$file.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

// ── Variants ──────────────────────────────────────────────────────────────────

class _Variant {
  const _Variant(this.tag, this.theme, this.locale);
  final String tag;
  final ThemeData theme;
  final Locale locale;
}

final _variants = [
  _Variant('light', AppTheme.light, en),
  _Variant('dark', AppTheme.dark, en),
  _Variant('ar', AppTheme.light, ar),
];

// ── Pump helpers ─────────────────────────────────────────────────────────────

/// Pumps [child] at 390x844 inside the screen harness (ScreenUtil + the app's
/// MaterialApp setup), with the app-level blocs provided above the navigator
/// as in `App`.
Future<void> _pumpApp(
  WidgetTester tester,
  Widget child,
  _Variant v, {
  RoadsideBloc? roadside,
  Map<String, WidgetBuilder> routes = const {},
}) async {
  final rb = roadside ?? RoadsideBloc(GatedRoadsideRepository());
  if (roadside == null) addTearDown(rb.close);
  final lb = LocaleBloc();
  addTearDown(lb.close);
  // The Appearance setting shows the mode the capture is rendered in.
  AppServices.instance.theme.value = v.theme.brightness == Brightness.dark
      ? ThemeMode.dark
      : ThemeMode.light;
  setPhoneSurface(tester, phonePortrait);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<LocaleBloc>.value(value: lb),
        BlocProvider<RoadsideBloc>.value(value: rb),
      ],
      child: buildHarness(child, locale: v.locale, theme: v.theme, routes: routes),
    ),
  );
  await tester.pump();
}

/// Pumps [n] frames of [step], letting real async work (asset loads) run
/// between them.
Future<void> _settleReal(
  WidgetTester tester, {
  int n = 10,
  Duration step = const Duration(milliseconds: 200),
}) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(step);
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  var t = Duration.zero;
  while (t < total) {
    await tester.pump(step);
    t += step;
  }
}

/// Completes a route push (page transition).
Future<void> _afterPush(WidgetTester tester) async {
  await tester.pump();
  await _pumpFor(tester, const Duration(milliseconds: 700));
}

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _CarFake extends FakeOBDAdapter {
  _CarFake({this.mil = false});
  final bool mil;

  @override
  Future<String?> getVin() async => 'JTDBR32E720123456';

  @override
  Future<ReadinessResult> getReadinessMonitors() async => ReadinessResult(
    milOn: mil,
    dtcCount: mil ? 2 : 0,
    monitors: const [
      ReadinessMonitor(name: 'Misfire', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'Fuel System', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'Components', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'Catalyst', status: MonitorStatus.notReady),
      ReadinessMonitor(name: 'EVAP System', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'O2 Sensor', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'A/C System', status: MonitorStatus.notApplicable),
    ],
  );

  @override
  Future<Map<String, String>> getFreezeFrame() async => {
    'RPM': '850 rpm',
    'Speed': '0 km/h',
    'Coolant': '88 °C',
  };
}

const _liveSample = OBDLiveData(
  rpm: 2150,
  speedKmh: 64,
  coolantTempC: 90,
  intakeAirTempC: 31,
  batteryVoltage: 14.1,
  throttlePct: 18,
  fuelLevelPct: 62,
  engineLoad: 35,
  mapKpa: 42,
  timingAdvanceDeg: 12,
  fuelTrimShortPct: 1.6,
  fuelTrimLongPct: -2.3,
  oilTempC: 95,
  o2B1S1Voltage: 0.62,
);

Future<_CarFake> _connect({bool mil = false, List<String> dtcs = const []}) async {
  final fake = _CarFake(mil: mil)
    ..dtcsToReturn = List.of(dtcs)
    ..adapterInfo = const OBDAdapterInfo(
      version: 'ELM327 v1.5',
      protocol: 'ISO 15765-4 (CAN 11/500)',
    );
  OBDService.setTestAdapter(fake);
  addTearDown(fake.dispose);
  await OBDService.instance.initialize(MockBluetoothDevice());
  return fake;
}

void _disconnected() {
  final fake = FakeOBDAdapter();
  OBDService.setTestAdapter(fake);
  addTearDown(fake.dispose);
}

Future<void> _seedPrefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
}

/// History with a few scans (newest first after load).
Map<String, Object> _historyPrefs() {
  final now = DateTime.now();
  Map<String, dynamic> e(DateTime at, double km, List<String> codes) => {
    'scannedAt': at.toIso8601String(),
    'mileageKm': km,
    'codes': codes,
  };
  return {
    'dtc_history_v1': jsonEncode([
      e(now.subtract(const Duration(days: 24)), 40100, ['P0420']),
      e(now.subtract(const Duration(days: 10)), 41000, ['P0420', 'P0171']),
      e(now.subtract(const Duration(days: 1, hours: 2)), 42000, [
        'P0300',
        '~P0171',
      ]),
      e(now.subtract(const Duration(hours: 1)), 42500, []),
    ]),
  };
}

Map<String, dynamic> _logged(double km, int daysAgo) => {
  'lastMileageKm': km,
  'lastServiceDate': DateTime.now()
      .subtract(Duration(days: daysAgo))
      .toIso8601String(),
  'notes': '',
};

Map<String, dynamic> _codeMap() => {
  'code': 'P0301',
  'title': 'Cylinder 1 Misfire Detected',
  'title_ar': 'اكتشاف خلل في إشعال الأسطوانة 1',
  'severity': 'critical',
  'system': 'Engine',
  'system_ar': 'المحرك',
  'description': 'Cylinder 1 Misfire Detected',
  'description_ar': 'اكتشاف خلل في إشعال الأسطوانة 1',
  'pending': false,
  'freeze_frame': {'RPM': '850 rpm', 'Speed': '0 km/h', 'Coolant': '88 °C'},
};

Future<void> _pumpShell(
  WidgetTester tester,
  _Variant v,
  AppTab tab, {
  RoadsideBloc? roadside,
}) async {
  await _pumpApp(
    tester,
    AppShell(initialTab: tab),
    v,
    roadside: roadside,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

RoadsideBloc _roadsideBloc(GatedRoadsideRepository repo) {
  final bloc = RoadsideBloc(repo);
  addTearDown(bloc.close);
  return bloc;
}

// ── Screens ───────────────────────────────────────────────────────────────────

typedef _Build = Future<void> Function(WidgetTester tester, _Variant v);

final _screens = <(String, _Build)>[
  ('splash', (tester, v) async {
    _disconnected();
    await _pumpApp(tester, const SplashScreen(), v);
    // Intro animations finish at ~4.3 s; the screen navigates at 5 s.
    await _pumpFor(tester, const Duration(milliseconds: 4500));
  }),
  ('sign_in', (tester, v) async {
    await _pumpApp(tester, const AuthScreen(), v);
    await tester.pumpAndSettle();
  }),
  ('sign_up', (tester, v) async {
    await _pumpApp(tester, const AuthScreen(), v);
    await tester.pumpAndSettle();
    final toSignup = find.widgetWithText(
      AppButton,
      tr('auth_create_account', v.locale),
    );
    await tester.ensureVisible(toSignup);
    await tester.tap(toSignup);
    await tester.pumpAndSettle();
    // Back to the top for the capture.
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.drag(scrollable.first, const Offset(0, 3000));
      await tester.pumpAndSettle();
    }
  }),
  ('home_connected', (tester, v) async {
    await _seedPrefs({});
    await MaintenanceService.instance.setMileage(42500);
    final fake = await _connect();
    await _pumpShell(tester, v, AppTab.home);
    await tester.pump(const Duration(seconds: 1));
    fake.emitLiveData(_liveSample);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }),
  ('home_disconnected', (tester, v) async {
    await _seedPrefs({});
    _disconnected();
    await _pumpShell(tester, v, AppTab.home);
    await tester.pump(const Duration(milliseconds: 600));
  }),
  ('connection', (tester, v) async {
    _disconnected();
    FakeBlePlatform.install(
      devices: {
        '00:1D:A5:68:98:8B': 'OBDII',
        'AA:BB:CC:DD:EE:FF': 'JBL Flip 5',
        '11:22:33:44:55:66': 'Galaxy Buds2',
      },
    );
    await _pumpApp(tester, const ConnectionScreen(), v);
    for (var i = 0; i < 30 && find.text('OBDII').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }),
  ('live_graph', (tester, v) async {
    final fake = await _connect();
    await _pumpApp(tester, const LiveGraphScreen(), v);
    for (var i = 0; i < 40; i++) {
      final t = i / 6.0;
      fake.emitLiveData(
        OBDLiveData(
          rpm: 1800 + 700 * math.sin(t),
          speedKmh: 55 + 20 * math.sin(t * 0.7),
          coolantTempC: 86 + i * 0.1,
          engineLoad: 30 + 10 * math.sin(t * 1.3),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
    }
  }),
  ('diagnostic_codes', (tester, v) async {
    await _seedPrefs({});
    await _connect(mil: true, dtcs: ['P0301', 'P0420', '~P0171']);
    await _pumpShell(tester, v, AppTab.diagnose);
    await _settleReal(tester, n: 20);
  }),
  ('code_detail', (tester, v) async {
    await _pumpApp(tester, CodeDetailScreen(code: _codeMap()), v);
    await tester.pumpAndSettle();
  }),
  ('solution', (tester, v) async {
    await _pumpApp(tester, SolutionScreen(code: _codeMap()), v);
    await tester.pumpAndSettle();
  }),
  ('dtc_lookup', (tester, v) async {
    await _seedPrefs({});
    await _pumpApp(tester, const DtcLookupPage(), v);
    await tester.enterText(find.byType(TextField).first, 'P0420');
    await tester.pump();
    await tester.tap(find.text(tr('dtc_get_description', v.locale)));
    await tester.pump();
    // The bundled code database is decoded off the main isolate: give it
    // real time until the spinner is gone.
    for (var i = 0;
        i < 50 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
  }),
  ('roadside_home', (tester, v) async {
    _disconnected();
    final bloc = _roadsideBloc(GatedRoadsideRepository());
    await _pumpShell(tester, v, AppTab.roadside, roadside: bloc);
    await tester.pump(const Duration(milliseconds: 600));
  }),
  ('location_picker', (tester, v) async {
    final bloc = _roadsideBloc(GatedRoadsideRepository());
    bloc.add(const SelectService(ServiceType.batteryJump));
    await tester.pump();
    await _pumpApp(tester, const LocationPickerScreen(), v, roadside: bloc);
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('price_estimate', (tester, v) async {
    final bloc = _roadsideBloc(GatedRoadsideRepository());
    await seedEstimate(tester, bloc);
    await _pumpApp(tester, const PriceEstimateScreen(), v, roadside: bloc);
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('searching_driver', (tester, v) async {
    final bloc = _roadsideBloc(GatedRoadsideRepository());
    await seedSearching(tester, bloc);
    await _pumpApp(tester, const SearchingDriverScreen(), v, roadside: bloc);
    await _pumpFor(tester, const Duration(seconds: 2));
  }),
  ('tracking', (tester, v) async {
    final repo = GatedRoadsideRepository();
    final bloc = _roadsideBloc(repo);
    await seedSearching(tester, bloc);
    await pushUpdate(
      tester,
      repo,
      driverRequest(
        RequestStatus.driverEnRoute,
        driverLocation: const LatLng(24.7225, 46.6753),
      ),
    );
    await _pumpApp(tester, const TrackingScreen(), v, roadside: bloc);
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('rating', (tester, v) async {
    final repo = GatedRoadsideRepository();
    final bloc = _roadsideBloc(repo);
    await seedSearching(tester, bloc);
    await pushUpdate(
      tester,
      repo,
      driverRequest(RequestStatus.completed, cashCollected: true),
    );
    await _pumpApp(tester, const RatingScreen(), v, roadside: bloc);
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('request_history', (tester, v) async {
    final repo = GatedRoadsideRepository()
      ..history = [
        sampleRequest(status: RequestStatus.completed),
        sampleRequest(
          id: 'req-2',
          status: RequestStatus.cancelled,
          type: ServiceType.tireRepair,
        ),
        sampleRequest(
          id: 'req-3',
          status: RequestStatus.completed,
          type: ServiceType.flatbedTowing,
        ),
      ];
    final bloc = _roadsideBloc(repo);
    await _pumpApp(tester, const RequestHistoryScreen(), v, roadside: bloc);
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('history', (tester, v) async {
    _disconnected();
    await _seedPrefs(_historyPrefs());
    await _pumpShell(tester, v, AppTab.history);
    await tester.pump();
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('settings', (tester, v) async {
    _disconnected();
    await _pumpShell(tester, v, AppTab.profile);
    await _pumpFor(tester, const Duration(milliseconds: 600));
  }),
  ('data_privacy', (tester, v) async {
    await _pumpApp(tester, const SettingsScreen(), v);
    await tester.pump(const Duration(milliseconds: 100));
    await tapVisible(tester, find.text(tr('data_privacy', v.locale)));
    await tester.pumpAndSettle();
  }),
  ('my_profile', (tester, v) async {
    await _seedPrefs(_historyPrefs());
    await _pumpApp(tester, const ProfileScreen(), v);
    await tester.pump();
    await _pumpFor(tester, const Duration(milliseconds: 600));
  }),
  ('edit_profile', (tester, v) async {
    await _pumpApp(tester, const EditProfileScreen(), v);
    await tester.pumpAndSettle();
  }),
  ('dash_cam_settings', (tester, v) async {
    await _pumpApp(tester, const DashCamSettingsScreen(), v);
    await tester.pumpAndSettle();
  }),
  ('maintenance', (tester, v) async {
    await _seedPrefs({
      'maintenance_v1': jsonEncode({
        'oil': _logged(36500, 190),
        'tires': _logged(33000, 200),
        'air': _logged(30000, 300),
        'brakes': _logged(20000, 400),
        'coolant': _logged(40000, 60),
        'spark': _logged(40000, 60),
        'belt': _logged(40000, 60),
      }),
      'maintenance_mileage_v1': 42500.0,
    });
    await MaintenanceService.instance.load();
    await _pumpApp(tester, const MaintenanceScreen(), v);
    await tester.pump();
    await tester.pump();
    await _pumpFor(tester, const Duration(milliseconds: 600));
  }),
  ('smart_key', (tester, v) async {
    _disconnected();
    await _pumpApp(tester, const SmartKeyScreen(), v);
    await _pumpFor(tester, const Duration(milliseconds: 600));
  }),
  ('parent_mode', (tester, v) async {
    await _pumpApp(tester, const ParentModeScreen(), v);
    await _pumpFor(tester, const Duration(milliseconds: 600));
  }),
  ('video_tutorials', (tester, v) async {
    await _pumpApp(tester, const VideoTutorialsScreen(), v);
    await _pumpFor(tester, const Duration(seconds: 1));
  }),
  ('video_player', (tester, v) async {
    // Opened from the tutorials list, so it gets the same (localized)
    // arguments as in the app.
    await _pumpApp(
      tester,
      const VideoTutorialsScreen(),
      v,
      routes: {AppRoutes.videoPlayer: VideoPlayerScreen.fromContext},
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    final list = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.vertical,
    );
    final firstTitle = find
        .descendant(
          of: list,
          matching: find.byWidgetPredicate((w) => w is Text && w.maxLines == 2),
        )
        .first;
    await tester.tap(firstTitle);
    await _afterPush(tester);
  }),
  ('upload_video', (tester, v) async {
    await _pumpApp(tester, const UploadVideoScreen(), v);
    await tester.pumpAndSettle();
  }),
  ('home_page_legacy', (tester, v) async {
    await _pumpApp(
      tester,
      BlocProvider(create: (_) => CounterBloc(), child: const HomePage()),
      v,
    );
    await tester.pumpAndSettle();
  }),
];

void main() {
  setUpAll(() async {
    FakeBlePlatform.install();
    await loadAppFonts();
  });

  setUp(() async {
    await installPlatformFakes(); // signed-in session, empty prefs, map fake
    // Location permission denied: the picker stays on its default centre.
    for (final name in const [
      'flutter.baseflow.com/geolocator',
      'flutter.baseflow.com/geolocator_android',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async {
            switch (call.method) {
              case 'checkPermission':
              case 'requestPermission':
                return 0;
            }
            return null;
          });
    }
    addTearDown(() {
      for (final name in const [
        'flutter.baseflow.com/geolocator',
        'flutter.baseflow.com/geolocator_android',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), null);
      }
    });
    AppServices.instance.theme.value = ThemeMode.light;
    _disconnected();
  });

  tearDownAll(() {
    File('$_outDir/_capture_log.txt').writeAsStringSync(
      _log.isEmpty ? 'No framework errors.\n' : '${_log.join('\n')}\n',
    );
  });

  for (var i = 0; i < _screens.length; i++) {
    final (name, build) = _screens[i];
    final nn = (i + 1).toString().padLeft(2, '0');
    for (final v in _variants) {
      final file = '${nn}_${name}_${v.tag}';
      testWidgets(file, (tester) async {
        // The test binding draws elevation as a hard black outline unless
        // real shadows are switched on.
        debugDisableShadows = false;
        // Record (instead of failing on) framework errors such as overflow.
        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (d) {
          final where = RegExp(
            r'file:///\S+?/lib/(\S+:\d+:\d+)',
          ).firstMatch(d.toString())?.group(1);
          errors.add(
            '${d.exceptionAsString().split('\n').first}'
            '${where == null ? '' : ' (lib/$where)'}',
          );
        };
        addTearDown(() => FlutterError.onError = original);

        try {
          await build(tester, v);
          await _shot(tester, file);
        } finally {
          // Checked by the binding right after the body, before tear-downs.
          debugDisableShadows = true;
        }

        final pending = tester.takeException();
        if (pending != null) errors.add('$pending'.split('\n').first);
        for (final e in errors.toSet()) {
          _log.add('$file: $e');
        }

        // Drain timers / repeating animations.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
        FlutterError.onError = original;
      });
    }
  }
}
