// Shared scaffolding for the end-to-end flow tests in test/flows/.
//
// The flows pump the real [App] (or, for roadside, the real screens behind a
// mock repository) at phone size, with every platform plugin the journeys
// touch faked at its platform-interface or platform-channel level:
//
//   * Bluetooth (flutter_blue_plus)   → [FakeBlePlatform]: adapter ON, one
//                                       scan result (an ELM327 "OBDII").
//   * OBD link                        → FakeOBDAdapter via
//                                       OBDService.setTestAdapter (per test).
//   * Secure storage (session token)  → in-memory, logged in by default.
//   * SharedPreferences               → in-memory, empty (fresh install).
//   * audioplayers / notifications /
//     google maps / platform views    → channel handlers that just succeed.
//
// Widgets are located by type, icon or by the *translated value* of a
// localization key ([tr]) — never by a hard-coded English string — so the
// tests keep passing while screens are being localized.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// flutter_blue_plus re-exports only a few platform-interface types; the fake
// platform needs the base class and the Bm* message types. It is the very
// package flutter_blue_plus itself depends on, so no version skew is possible.
// ignore: depend_on_referenced_packages
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// Same rationale: google_maps_flutter does not re-export the platform base
// class that the fake map below must extend.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/core/bloc/locale/locale_bloc.dart';
import 'package:mycar/core/bloc/locale/locale_event.dart';
import 'package:mycar/core/localization/app_localizations.dart';

// ── Localization ──────────────────────────────────────────────────────────────

/// The translated value of [key] in [lang], exactly as `context.tr` renders it.
String tr(String key, [String lang = 'en']) =>
    AppLocalizations(Locale(lang)).tr(key);

/// Finds text equal to the translation of [key] in [lang].
Finder findTr(String key, [String lang = 'en']) => find.text(tr(key, lang));

/// Switches the running [App] to [locale] through its real [LocaleBloc]
/// (the app boots in Arabic).
Future<void> setAppLocale(WidgetTester tester, Locale locale) async {
  final ctx = tester.element(find.byType(MaterialApp));
  BlocProvider.of<LocaleBloc>(ctx).add(ChangeLocale(locale));
  await tester.pump();
  await tester.pump();
}

// ── Surface ───────────────────────────────────────────────────────────────────

/// Renders on a 390x844 portrait phone (the app's ScreenUtil design size).
void usePhoneSurface(
  WidgetTester tester, {
  Size logical = const Size(390, 844),
}) {
  tester.view.physicalSize = logical * 3.0;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

// ── Time ──────────────────────────────────────────────────────────────────────

/// Advances fake time by [total] in [step] frames, failing fast on any
/// framework exception (layout overflow, setState after dispose, ...).
Future<void> advance(
  WidgetTester tester,
  Duration total, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    final next = total - elapsed < step ? total - elapsed : step;
    await tester.pump(next);
    elapsed += next;
    final error = tester.takeException();
    if (error != null) {
      fail(
        'Exception after ${elapsed.inMilliseconds} ms: $error'
        '${_whereReported()}',
      );
    }
  }
}

/// Pumps (in [step] frames) until [finder] matches, or fails after [timeout].
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  var elapsed = Duration.zero;
  while (finder.evaluate().isEmpty) {
    if (elapsed >= timeout) {
      fail('Timed out after ${timeout.inMilliseconds} ms waiting for $finder');
    }
    await tester.pump(step);
    elapsed += step;
    final error = tester.takeException();
    if (error != null) {
      fail('Exception while waiting for $finder: $error${_whereReported()}');
    }
  }
}

/// Taps [finder] (which must match exactly one widget) and pumps a frame.
///
/// With [scroll] (default) it is first scrolled into view; pass false for
/// targets under a pinned header, where scrolling would tuck them beneath it.
Future<void> tapOn(
  WidgetTester tester,
  Finder finder, {
  bool scroll = true,
}) async {
  if (scroll) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
  await tester.tap(finder);
  await tester.pump();
}

/// Simulates the Android system back button.
Future<void> pressBack(WidgetTester tester) async {
  final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
  // ignore: avoid_dynamic_calls
  await widgetsAppState.didPopRoute();
  await tester.pump();
}

/// Asserts the current top route renders a widget of type [T].
void expectOnScreen<T extends Widget>() {
  expect(
    find.byType(T),
    findsOneWidget,
    reason: 'expected the visible screen to be $T',
  );
}

// ── Platform fakes ────────────────────────────────────────────────────────────

const _codec = StandardMethodCodec();

/// Installs the platform fakes shared by every flow. Call from `setUp`.
///
/// [loggedIn] seeds a session token so the splash routes to mode selection
/// (instead of the auth screen), as on a returning user's device.
Future<void> installPlatformFakes({bool loggedIn = true}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues(
    loggedIn
        ? {
            'auth_token': 'flow-test-token',
            'auth_user_id': 'u1',
            'auth_role': 'customer',
            'auth_name': 'Flow Tester',
            'auth_email': 'flow@test.dev',
            'auth_phone': '+966500000000',
          }
        : {},
  );
  await AppServices.instance.session.load();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.allMessagesHandler = (channel, mockHandler, message) {
    if (mockHandler != null) return mockHandler(message);
    if (channel.startsWith('xyz.luan/audioplayers') ||
        channel == 'dexterous.com/flutter/local_notifications' ||
        channel.startsWith('plugins.flutter.io/google_maps') ||
        channel.startsWith('plugins.flutter.dev/google_maps')) {
      final call = _codec.decodeMethodCall(message);
      return Future.value(
        _codec.encodeSuccessEnvelope(call.method == 'initialize' ? true : null),
      );
    }
    return null; // unhandled → MissingPluginException (caught by the app)
  };
  final originalMaps = GoogleMapsFlutterPlatform.instance;
  GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
  addTearDown(() {
    messenger.allMessagesHandler = null;
    GoogleMapsFlutterPlatform.instance = originalMaps;
  });
}

/// A GoogleMap that renders as an empty box and never reports its native
/// view as created, so no camera/marker/overlay call reaches a platform.
class FakeMapsPlatform extends GoogleMapsFlutterPlatform {
  static const mapKey = ValueKey('fake-google-map');

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) => const SizedBox.expand(key: mapKey);
}

/// A Bluetooth stack with the adapter ON whose scans find [devices]
/// (`remoteId → name`). Installed as the flutter_blue_plus platform so the
/// real [ConnectionScreen] scan/connect UI runs unmodified.
final class FakeBlePlatform extends FlutterBluePlusPlatform {
  FakeBlePlatform({Map<String, String>? devices})
    : devices = devices ?? {'00:1D:A5:68:98:8B': 'OBDII'};

  final Map<String, String> devices;
  final _scan = StreamController<BmScanResponse>.broadcast();
  final _adapter = StreamController<BmBluetoothAdapterState>.broadcast();
  int startScanCalls = 0;

  /// Installs a fresh fake as the global flutter_blue_plus platform.
  static FakeBlePlatform install({Map<String, String>? devices}) {
    final fake = FakeBlePlatform(devices: devices);
    FlutterBluePlusPlatform.instance = fake;
    return fake;
  }

  @override
  Stream<BmScanResponse> get onScanResponse => _scan.stream;

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => _adapter.stream;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(
    BmBluetoothAdapterStateRequest request,
  ) async => BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;

  @override
  Future<bool> startScan(BmScanSettings request) async {
    startScanCalls++;
    // Deliver the advertisements right after the scan starts listening.
    scheduleMicrotask(() {
      if (_scan.isClosed) return;
      _scan.add(
        BmScanResponse(
          advertisements: [
            for (final e in devices.entries)
              BmScanAdvertisement(
                remoteId: DeviceIdentifier(e.key),
                platformName: e.value,
                advName: e.value,
                connectable: true,
                txPowerLevel: null,
                appearance: null,
                manufacturerData: const {},
                serviceData: const {},
                serviceUuids: const [],
                rssi: -55,
              ),
          ],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;
}

FlutterErrorDetails? _lastReported;

/// The source location of the widget behind the last reported error, if
/// widget-creation tracking captured it.
String _whereReported() {
  final details = _lastReported;
  _lastReported = null;
  if (details == null) return '';
  final match = RegExp(
    r'file:///\S+?/lib/(\S+:\d+:\d+)',
  ).firstMatch(details.toString());
  return match == null ? '' : ' (at lib/${match.group(1)})';
}

// ── Known layout bugs ─────────────────────────────────────────────────────────

/// Known, reported layout overflows at phone size, as `file.dart:line`
/// widget-creation locations (matched narrowly, so the rest of the file is
/// still checked). Flows that merely pass *through* them tolerate those
/// overflows (a dedicated strict test asserts the fix);
/// overflows anywhere else still fail.
///
/// The earlier entries (mode selection bullets, the dashboard trip card
/// :794, the maintenance / code detail / history headers) are fixed and now
/// asserted strictly by the formerly skipped layout tests.
const knownOverflowFiles = <String>[
  // Empty: the live-data header (dashboard_screen.dart) and the smart key
  // header overflows are fixed and asserted strictly.
];

/// Runs [body] with RenderFlex overflows raised from [files] recorded into
/// [sink] instead of failing the test. Every other error is reported as usual.
Future<void> withKnownOverflows(
  Future<void> Function() body, {
  List<String> files = knownOverflowFiles,
  List<String>? sink,
}) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('overflowed') && files.any(text.contains)) {
      sink?.add(details.exceptionAsString());
      return;
    }
    _lastReported = details;
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}
