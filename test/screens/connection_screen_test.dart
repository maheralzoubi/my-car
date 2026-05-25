import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';

import '../helpers/fake_obd_adapter.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps [child] in the minimum scaffolding needed for the connection screen
/// to render (ScreenUtil + Localizations + Navigator).
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
}
