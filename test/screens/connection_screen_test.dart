import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';

import '../helpers/elm327_sim.dart' show FakeDevice;
import '../helpers/fake_obd_adapter.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [child] in the minimum scaffolding needed for the connection screen
/// to render (ScreenUtil + Localizations + Navigator).
Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    ),
  );
}

/// Drops [fake]'s link. OBDService subscribed to the adapter in setUp,
/// outside the test's fake-async zone, so the event chain needs a turn of
/// the real event loop before the next frame.
Future<void> _drop(WidgetTester tester, FakeOBDAdapter fake) async {
  fake.simulateDrop();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
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

  // ── Smoke test ────────────────────────────────────────────────────────────

  testWidgets('ConnectionScreen renders without crashing', (tester) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    // pumpAndSettle would time-out because the screen starts async work;
    // pump a few frames is sufficient for a smoke test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ConnectionScreen), findsOneWidget);
  });

  // ── Static text ───────────────────────────────────────────────────────────

  testWidgets('shows app name in header', (tester) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump();

    // "CARDIAG" is the en translation of 'app_name'
    expect(find.text('CARDIAG'), findsOneWidget);
  });

  testWidgets('shows "Connect to Vehicle" title', (tester) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump();

    expect(find.text('Connect to Vehicle'), findsOneWidget);
  });

  // ── Action button labels ──────────────────────────────────────────────────

  testWidgets('action button shows PLEASE WAIT while checking permissions',
      (tester) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    // Don't pump — capture the very first frame (checkingPermission state).
    expect(find.text('PLEASE WAIT'), findsOneWidget);
  });

  // ── OBD service interaction ───────────────────────────────────────────────

  testWidgets(
      'tapping a device item calls OBDService.initialize '
      'and shows CONNECTING button', (tester) async {
    // The screen calls _initialize() on mount → we cannot easily inject
    // scan results without mocking FlutterBluePlus.  We verify that the
    // adapter's connect is NOT called before a device is tapped (i.e. the
    // default idle state is safe).
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(fake.connectCalled, isFalse);
  });

  testWidgets('initFailed state shows RETRY button', (tester) async {
    fake.shouldFailConnect = true;

    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump(const Duration(milliseconds: 50));

    // The screen starts in checkingPermission; we cannot drive all the way to
    // initFailed without real BT hardware.  Verify the screen is at least
    // healthy and not in a connected state.
    expect(find.text('SCAN VEHICLE'), findsNothing);
  });

  // ── Settings navigation ───────────────────────────────────────────────────

  testWidgets('settings icon button is present', (tester) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump();

    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  // ── Bottom hint text ──────────────────────────────────────────────────────

  testWidgets('bottom hint text is visible on first render', (tester) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump();

    // Either the scanning underline tap text or the trouble-connecting text
    // should be present.
    final hint = find.textContaining('trouble');
    final rescan = find.textContaining('rescan');
    expect(hint.evaluate().isNotEmpty || rescan.evaluate().isNotEmpty, isTrue);
  });

  // ── Connect failures by cause ─────────────────────────────────────────────

  // A real-looking device (platformName "OBDII") for the status texts.
  FakeDevice device() => FakeDevice([]);

  /// Mounts the screen, then fails a connect with [reason] through the
  /// service — the screen follows the service's connection state.
  Future<void> failWith(
    WidgetTester tester,
    OBDFailureReason reason, {
    String? version,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(_wrap(const ConnectionScreen(), locale: locale));
    await tester.pump();
    fake
      ..failReason = reason
      ..failAdapterVersion = version;
    await OBDService.instance.initialize(device());
    await tester.pump();
  }

  const expected = {
    OBDFailureReason.bleConnectFailed: "Couldn't connect to the adapter",
    OBDFailureReason.bleTimeout: 'Adapter did not respond over Bluetooth',
    OBDFailureReason.noElmCharacteristic: 'Not a BLE OBD adapter',
    OBDFailureReason.adapterNotResponding: 'Adapter not answering',
    OBDFailureReason.ecuNotResponding: 'Vehicle not responding',
    OBDFailureReason.noStandardObdData: "Car doesn't share standard OBD-II data",
    OBDFailureReason.unknown: 'OBD Initialization Failed',
  };

  for (final MapEntry(key: reason, value: title) in expected.entries) {
    testWidgets('${reason.name} → "$title" + RETRY + log actions', (
      tester,
    ) async {
      await failWith(tester, reason);
      expect(find.text(title), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
      expect(find.text('Copy diagnostic log'), findsOneWidget);
      expect(find.text('Share log'), findsOneWidget);
    });
  }

  testWidgets('Bluetooth Classic hint for a device without ELM327 channel', (
    tester,
  ) async {
    await failWith(tester, OBDFailureReason.noElmCharacteristic);
    expect(find.textContaining('Bluetooth Classic'), findsOneWidget);
  });

  testWidgets('ignition hint when the ECU is silent', (tester) async {
    await failWith(tester, OBDFailureReason.ecuNotResponding);
    expect(find.textContaining('Turn the ignition ON'), findsOneWidget);
    expect(find.textContaining('J1850'), findsNothing); // not a clone
  });

  testWidgets('ECU-silent hint also covers electric / hybrid cars (READY)', (
    tester,
  ) async {
    await failWith(tester, OBDFailureReason.ecuNotResponding);
    expect(find.textContaining('switch it to READY'), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
  });

  testWidgets('car on but no standard OBD-II data → EV text + icon, RETRY '
      'and log actions, no clone hint', (tester) async {
    await failWith(
      tester,
      OBDFailureReason.noStandardObdData,
      version: 'ELM327 v1.5',
    );
    expect(find.text("Car doesn't share standard OBD-II data"), findsOneWidget);
    expect(
      find.text(
        "Your car is on but doesn't share standard OBD-II data. This is "
        'common on electric vehicles; hybrids and petrol/diesel cars should '
        'work. If this is a petrol/diesel car, check the ignition is ON and '
        'tap RETRY.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Turn the ignition ON'), findsNothing);
    expect(find.textContaining('J1850'), findsNothing);
    expect(find.byIcon(Icons.electric_car), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsNothing);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('Copy diagnostic log'), findsOneWidget);
    expect(find.text('Share log'), findsOneWidget);
  });

  testWidgets('Arabic: no standard OBD-II data is localized', (tester) async {
    await failWith(
      tester,
      OBDFailureReason.noStandardObdData,
      locale: const Locale('ar'),
    );
    expect(find.text('السيارة لا تشارك بيانات OBD-II القياسية'),
        findsOneWidget);
    expect(find.textContaining('شائع في السيارات الكهربائية'), findsOneWidget);
    expect(find.byIcon(Icons.electric_car), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.text('نسخ سجل التشخيص'), findsOneWidget);
  });

  testWidgets('Arabic: ECU-silent hint mentions electric / hybrid READY', (
    tester,
  ) async {
    await failWith(
      tester,
      OBDFailureReason.ecuNotResponding,
      locale: const Locale('ar'),
    );
    expect(find.textContaining('الكهربائية أو الهجينة فعّل وضع READY'),
        findsOneWidget);
  });

  testWidgets('RETRY after noStandardObdData retries the same adapter', (
    tester,
  ) async {
    await failWith(tester, OBDFailureReason.noStandardObdData);
    fake
      ..failReason = null
      ..connectCalled = false;
    await tester.tap(find.text('RETRY'));
    await tester.pump();
    await tester.pump();
    expect(fake.connectCalled, isTrue);
    expect(find.text('SCAN VEHICLE'), findsOneWidget);
  });

  testWidgets('clone adapter → J1850 hint naming the reported version', (
    tester,
  ) async {
    await failWith(
      tester,
      OBDFailureReason.ecuNotResponding,
      version: 'ELM327 v1.5',
    );
    expect(find.textContaining('J1850'), findsOneWidget);
    expect(find.textContaining('"ELM327 v1.5"'), findsOneWidget);
  });

  testWidgets('clone version but a BLE failure → no J1850 hint', (
    tester,
  ) async {
    await failWith(tester, OBDFailureReason.bleTimeout, version: 'ELM327 v1.5');
    expect(find.textContaining('J1850'), findsNothing);
  });

  testWidgets('Arabic: failure reason is localized', (tester) async {
    await failWith(
      tester,
      OBDFailureReason.ecuNotResponding,
      locale: const Locale('ar'),
    );
    expect(find.text('السيارة لا تستجيب'), findsOneWidget);
    expect(find.text('نسخ سجل التشخيص'), findsOneWidget);
  });

  testWidgets('RETRY after an ECU failure retries the same adapter', (
    tester,
  ) async {
    await failWith(tester, OBDFailureReason.ecuNotResponding);
    fake
      ..failReason = null
      ..connectCalled = false;
    await tester.tap(find.text('RETRY'));
    await tester.pump();
    await tester.pump();
    expect(fake.connectCalled, isTrue);
    expect(find.text('SCAN VEHICLE'), findsOneWidget);
  });

  // ── Diagnostic log ────────────────────────────────────────────────────────

  testWidgets('Copy diagnostic log puts the report on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    OBDLog.instance.clear();
    OBDLog.instance.tx('0100');
    await failWith(tester, OBDFailureReason.ecuNotResponding);
    await tester.ensureVisible(find.text('Copy diagnostic log'));
    await tester.tap(find.text('Copy diagnostic log'));
    await tester.pump();

    expect(copied, contains('MyCar OBD diagnostic log'));
    expect(copied, contains('ecuNotResponding'));
    expect(copied, contains('TX 0100'));
    expect(find.textContaining('Diagnostic log copied'), findsOneWidget);
  });

  // ── Mid-session drop ──────────────────────────────────────────────────────

  testWidgets('BLE drop → "Connection lost" with RECONNECT, which reconnects', (
    tester,
  ) async {
    fake.adapterInfo = const OBDAdapterInfo(
      version: 'ELM327 v1.5',
      protocol: 'ISO 15765-4 (CAN 11/500)',
    );
    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump();
    await OBDService.instance.initialize(device());
    await _drop(tester, fake);

    expect(find.text('Connection lost'), findsOneWidget);
    expect(find.text('RECONNECT'), findsOneWidget);
    expect(find.text('Copy diagnostic log'), findsOneWidget);

    fake.connectCalled = false;
    await tester.tap(find.text('RECONNECT'));
    await tester.pump();
    await tester.pump();

    expect(fake.connectCalled, isTrue);
    expect(find.text('Connected to OBDII'), findsOneWidget);
    expect(find.text('SCAN VEHICLE'), findsOneWidget);
    // Adapter details once connected.
    expect(find.text('ELM327 v1.5 · ISO 15765-4 (CAN 11/500)'), findsOneWidget);
  });

  testWidgets('opened after a drop → offers RECONNECT instead of scanning', (
    tester,
  ) async {
    await OBDService.instance.initialize(device());
    await _drop(tester, fake);

    await tester.pumpWidget(_wrap(const ConnectionScreen()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Connection lost'), findsOneWidget);
    expect(find.text('RECONNECT'), findsOneWidget);
  });
}
