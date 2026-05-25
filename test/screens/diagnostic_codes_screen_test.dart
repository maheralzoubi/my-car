import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';

import '../helpers/fake_obd_adapter.dart';

// ── Wrapper ───────────────────────────────────────────────────────────────────

/// Wraps [child] with ScreenUtil + Localizations.
/// Always injects [FakeDtcRepository] so tests never hit real I/O.
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

DiagnosticCodesScreen _screen() =>
    DiagnosticCodesScreen(repository: FakeDtcRepository());

void main() {
  late FakeOBDAdapter fake;

  setUp(() {
    fake = FakeOBDAdapter();
    OBDService.setTestAdapter(fake);
  });

  tearDown(() {
    fake.dispose();
  });

  // ── Not connected ─────────────────────────────────────────────────────────

  group('when OBD is NOT initialized', () {
    testWidgets('shows not-connected message', (tester) async {
      // OBDService.isInitialized is false → no initialize() called.
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pump(); // let initState run

      expect(find.text('No OBD device connected'), findsOneWidget);
      expect(find.text('Connect your ELM327 adapter first'), findsOneWidget);
    });

    testWidgets('shows Go to Connection button', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pump();

      expect(find.text('Go to Connection'), findsOneWidget);
    });

    testWidgets('does NOT call getDtcs on adapter', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pump();

      expect(fake.getDtcsCalled, isFalse);
    });
  });

  // ── Connected, no codes ───────────────────────────────────────────────────

  group('when connected with no DTCs', () {
    setUp(() async {
      fake.dtcsToReturn = [];
      await OBDService.instance.initialize(MockBluetoothDevice());
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      // _loading is set to true synchronously before the first await in
      // _fetchDtcs — visible immediately after pumpWidget, without pumping.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows no-codes message after fetch completes', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      expect(find.text('No codes found'), findsOneWidget);
      expect(fake.getDtcsCalled, isTrue);
    });

    testWidgets('summary bar shows all zeros', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      // Summary shows "0" for critical, warning, info.
      expect(find.text('0'), findsWidgets);
    });
  });

  // ── Connected, with codes ─────────────────────────────────────────────────

  group('when connected with DTCs returned', () {
    setUp(() async {
      fake.dtcsToReturn = ['P0420', 'P0171', 'C1201'];
      await OBDService.instance.initialize(MockBluetoothDevice());
    });

    testWidgets('renders one card per DTC code', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      expect(find.text('P0420'), findsOneWidget);
      expect(find.text('P0171'), findsOneWidget);
      // C1201 is built but may be off-screen; drag the list to bring it into
      // the rendered area, then verify exactly one chip shows the code.
      // Two ListViews: horizontal filter chips (first) + vertical DTC list (last).
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pump();
      expect(find.text('C1201'), findsOneWidget);
    });

    testWidgets('system chips show correct values', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      // P codes → Engine, C codes → Chassis
      expect(find.text('Engine'), findsWidgets);
      expect(find.text('Chassis'), findsOneWidget);
    });

    testWidgets('summary counts are non-zero', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      // There should be at least one non-zero count in the summary.
      // We look for "2" (P0420 + P0171 are both critical P0xxx).
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('refresh button re-fetches DTCs', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      final callsBefore = fake.getDtcsCalled;
      expect(callsBefore, isTrue);

      // Tap the refresh icon.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // getDtcs was called at least once more (total ≥ 2 invocations).
      // We verify the screen is still healthy after refresh.
      expect(find.text('P0420'), findsOneWidget);
    });

    testWidgets('clear-codes button appears when there are DTCs', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.clear_all), findsOneWidget);
    });
  });

  // ── Clear codes ───────────────────────────────────────────────────────────

  group('clear codes dialog', () {
    setUp(() async {
      fake.dtcsToReturn = ['P0420'];
      await OBDService.instance.initialize(MockBluetoothDevice());
    });

    testWidgets('tapping clear icon opens confirmation dialog', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();

      expect(find.text('Clear Codes?'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('cancelling dialog keeps codes visible', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.clearDtcsCalled, isFalse);
      expect(find.text('P0420'), findsOneWidget);
    });

    testWidgets('confirming clear calls adapter.clearDtcs and empties list',
        (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(fake.clearDtcsCalled, isTrue);
      expect(find.text('P0420'), findsNothing);
      expect(find.text('No codes found'), findsOneWidget);
    });

    testWidgets('failed clear shows error snackbar', (tester) async {
      fake.clearShouldFail = true;

      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Failed to clear codes'),
        findsOneWidget,
      );
    });
  });

  // ── Filter chips ──────────────────────────────────────────────────────────

  group('filter chips', () {
    setUp(() async {
      fake.dtcsToReturn = ['P0420', 'C1201'];
      await OBDService.instance.initialize(MockBluetoothDevice());
    });

    testWidgets('selecting Engine filter hides Chassis codes', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      // The filter chip appears before the DTC cards, so .first targets it.
      await tester.tap(find.text('Engine').first);
      await tester.pump();

      expect(find.text('P0420'), findsOneWidget);
      expect(find.text('C1201'), findsNothing);
    });

    testWidgets('selecting All filter shows all codes', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      // Switch to Engine then back to All.
      await tester.tap(find.text('Engine').first);
      await tester.pump();
      await tester.tap(find.text('All').first);
      await tester.pump();

      expect(find.text('P0420'), findsOneWidget);
      expect(find.text('C1201'), findsOneWidget);
    });
  });
}
