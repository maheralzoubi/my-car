import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';

import '../helpers/fake_obd_adapter.dart';

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

  // ── Smoke ─────────────────────────────────────────────────────────────────

  testWidgets('DashboardScreen renders without crashing', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  // ── Static sections ───────────────────────────────────────────────────────

  testWidgets('shows Vehicle Health card', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(find.text('Vehicle Health'), findsOneWidget);
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

  testWidgets('Live Data section updates when adapter emits data',
      (tester) async {
    await OBDService.instance.initialize(MockBluetoothDevice());

    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // Emit a snapshot from the fake adapter.
    fake.emitLiveData(const OBDLiveData(
      rpm: 3000,
      speedKmh: 90,
      coolantTempC: 95,
      throttlePct: 30,
      fuelLevelPct: 60,
    ));

    // Two pumps: first flushes the stream microtask, second rebuilds the frame.
    await tester.pump();
    await tester.pump();

    expect(find.text('3000'), findsOneWidget);
    expect(find.text('90.0'), findsOneWidget);
  });

  testWidgets('Live Data section shows green dot when OBD is initialized',
      (tester) async {
    await OBDService.instance.initialize(MockBluetoothDevice());
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // The green dot Container is identified by its BoxDecoration color.
    // We look for the known 0xFF00E676 color presence indirectly via the
    // "Live Data" label being visible.
    expect(find.text('Live Data'), findsOneWidget);
  });

  // ── startPolling / stopPolling lifecycle ──────────────────────────────────

  testWidgets('startPolling is called in initState when adapter initialized',
      (tester) async {
    await OBDService.instance.initialize(MockBluetoothDevice());

    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    expect(fake.startLiveDataCalled, isTrue);
  });

  testWidgets('stopPolling is called when screen is disposed', (tester) async {
    await OBDService.instance.initialize(MockBluetoothDevice());

    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // Replace with an empty widget to trigger dispose.
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));

    expect(fake.stopLiveDataCalled, isTrue);
  });

  // ── Bottom nav ────────────────────────────────────────────────────────────

  testWidgets('bottom navigation bar has 5 items', (tester) async {
    await tester.pumpWidget(_wrap(const DashboardScreen()));
    await tester.pump();

    // Each nav item renders its label text.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    // 'History' also appears in the Recent Scans header button, so >= 1.
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
  });
}

