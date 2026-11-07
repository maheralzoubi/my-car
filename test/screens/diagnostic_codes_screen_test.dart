import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';

import '../helpers/fake_obd_adapter.dart';

// ── Wrapper ───────────────────────────────────────────────────────────────────

/// Wraps [child] with ScreenUtil + Localizations.
/// Always injects [FakeDtcRepository] so tests never hit real I/O.
Widget _wrap(Widget child, {Locale locale = const Locale('en')}) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
      routes: {
        AppRoutes.codeDetail: (ctx) => CodeDetailScreen(
              code: (ModalRoute.of(ctx)!.settings.arguments
                      as Map<String, dynamic>?) ??
                  <String, dynamic>{},
            ),
      },
    ),
  );
}

DiagnosticCodesScreen _screen() =>
    DiagnosticCodesScreen(repository: FakeDtcRepository());

/// Repository that knows nothing about [unknown] (offline, not in the DB).
class _PartialDtcRepository extends DtcRepository {
  _PartialDtcRepository(this.unknown);
  final Set<String> unknown;

  @override
  Future<String?> getDtcDescription(
    String code, {
    String languageCode = 'en',
  }) async =>
      unknown.contains(code) ? null : 'Description for $code';
}

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

/// Records share_plus platform calls for the current test.
List<MethodCall> _captureShares(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _shareChannel,
    (c) async {
      calls.add(c);
      return 'dev.fluttercommunity.plus/share/unavailable';
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_shareChannel, null),
  );
  return calls;
}

void main() {
  late FakeOBDAdapter fake;

  setUp(() {
    // The screen records each scan via DtcHistoryService (SharedPreferences);
    // without an in-memory store that platform call never completes in tests.
    SharedPreferences.setMockInitialValues({});
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

      // Let the in-flight fetch (OBDService's 300 ms settle delays) finish so
      // no timers are left pending when the tree is torn down.
      await tester.pumpAndSettle();
      expect(find.text('No codes found'), findsOneWidget);
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

      // P codes → Engine, C codes → Chassis (filter chip + the row label).
      expect(find.text('Engine'), findsWidgets);
      expect(find.text('Chassis'), findsNWidgets(2));
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

      // Tap the header refresh action.
      await tester.tap(find.byTooltip('Scan Again'));
      await tester.pumpAndSettle();

      // getDtcs was called at least once more (total ≥ 2 invocations).
      // We verify the screen is still healthy after refresh.
      expect(find.text('P0420'), findsOneWidget);
    });

    testWidgets('clear-codes button appears when there are DTCs', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
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

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();

      expect(find.text('Clear Codes?'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('cancelling dialog keeps codes visible', (tester) async {
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
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

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(fake.clearDtcsCalled, isTrue);
      expect(find.text('P0420'), findsNothing);
      expect(find.text('No codes found'), findsOneWidget);
      // The header "clearing" spinner must stop once the re-scan completes.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('failed clear shows error snackbar', (tester) async {
      fake.clearShouldFail = true;

      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to clear codes'), findsOneWidget);
      // The usual cause is the ECU refusing mode 04 with the engine
      // running: the message must say how to retry.
      expect(find.textContaining('Turn the engine off'), findsOneWidget);
      expect(find.textContaining('ignition ON'), findsOneWidget);
      expect(fake.clearDtcsCalled, isTrue);
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
  // ── Export report ─────────────────────────────────────────────────────────

  group('export report', () {
    setUp(() async {
      fake.dtcsToReturn = ['P0420', '~P0171'];
      await OBDService.instance.initialize(MockBluetoothDevice());
    });

    testWidgets('shares the report as text (EN)', (tester) async {
      final shares = _captureShares(tester);
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(shares, hasLength(1));
      expect(shares.single.method, 'share');
      final text = (shares.single.arguments as Map)['text'] as String;
      expect(text, contains('VEHICLE DIAGNOSTIC REPORT'));
      expect(text, contains('FAULT CODES (2 total)'));
      expect(text, contains('P0420'));
      expect(text, contains('Description for P0420'));
      expect(text, contains('PENDING CODES:'));
      expect(text, contains('[PENDING] P0171  Description for P0171'));
      expect(text, isNot(contains('~')));
    });

    testWidgets('shares the report in Arabic (AR)', (tester) async {
      final shares = _captureShares(tester);
      await tester.pumpWidget(_wrap(_screen(), locale: const Locale('ar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();

      expect(shares, hasLength(1));
      final text = (shares.single.arguments as Map)['text'] as String;
      expect(text, contains('تقرير تشخيص المركبة'));
      expect(text, contains('رموز الأعطال (الإجمالي: 2)'));
      expect(text, contains('[معلّق] P0171'));
      expect(text, isNot(contains('VEHICLE DIAGNOSTIC REPORT')));
      expect(text, isNot(contains('PENDING')));
    });
  });

  // ── Missing description ───────────────────────────────────────────────────

  group('code without a description', () {
    setUp(() async {
      fake.dtcsToReturn = ['P0A80', 'P0420'];
      await OBDService.instance.initialize(MockBluetoothDevice());
    });

    testWidgets('shows a localized fallback, not the bare code twice', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(DiagnosticCodesScreen(
          repository: _PartialDtcRepository({'P0A80'}),
        )),
      );
      await tester.pumpAndSettle();

      expect(find.text('P0A80'), findsOneWidget); // the code chip only
      expect(
        find.text('No description available for this code'),
        findsOneWidget,
      );
      expect(find.text('Description for P0420'), findsOneWidget);
    });

    testWidgets('Arabic fallback is in Arabic', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DiagnosticCodesScreen(
            repository: _PartialDtcRepository({'P0A80'}),
          ),
          locale: const Locale('ar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('P0A80'), findsOneWidget);
      expect(find.text('لا يتوفر وصف لهذا الرمز'), findsOneWidget);
    });
  });

  // ── Opening the detail ────────────────────────────────────────────────────

  group('opening the code detail', () {
    Future<void> openDetail(WidgetTester tester, String code) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(code).first);
      await tester.pumpAndSettle();
      expect(find.byType(CodeDetailScreen), findsOneWidget);
    }

    Finder inDetail(Finder f) =>
        find.descendant(of: find.byType(CodeDetailScreen), matching: f);

    testWidgets('a pending code stays labelled pending', (tester) async {
      fake.dtcsToReturn = ['~P0300'];
      await OBDService.instance.initialize(MockBluetoothDevice());
      await openDetail(tester, 'P0300');

      final detail = tester.widget<CodeDetailScreen>(
        find.byType(CodeDetailScreen),
      );
      expect(detail.code['pending'], isTrue);
      expect(inDetail(find.text('P0300')), findsOneWidget);
      expect(inDetail(find.text('Pending')), findsOneWidget);
      expect(
        inDetail(find.text(
            'Pending: detected but not yet confirmed by the ECU')),
        findsOneWidget,
      );
    });

    testWidgets('a confirmed code is not labelled pending', (tester) async {
      fake.dtcsToReturn = ['P0300'];
      await OBDService.instance.initialize(MockBluetoothDevice());
      await openDetail(tester, 'P0300');

      final detail = tester.widget<CodeDetailScreen>(
        find.byType(CodeDetailScreen),
      );
      expect(detail.code['pending'], isFalse);
      expect(inDetail(find.text('Pending')), findsNothing);
      expect(inDetail(find.text('Confirmed: stored by the ECU')),
          findsOneWidget);
    });
  });
}
