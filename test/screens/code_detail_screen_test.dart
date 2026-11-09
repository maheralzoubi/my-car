import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/screen_harness.dart';

const _critical = Color(0xFFFF1744);
const _warning = Color(0xFFFF6B35);
const _info = Color(0xFFFFD600);

Map<String, dynamic> _code({
  String code = 'P0300',
  String severity = 'critical',
  String title = 'Random/Multiple Cylinder Misfire Detected',
  String description = 'Engine misfire detected on several cylinders',
  String system = 'Engine',
}) => {
  'code': code,
  'title': title,
  'title_ar': 'عنوان $code',
  'severity': severity,
  'system': system,
  'system_ar': 'المحرك',
  'description': description,
  'description_ar': 'وصف $code',
};

final _routes = <String, WidgetBuilder>{
  AppRoutes.codeDetail: (ctx) => CodeDetailScreen(
    code:
        (ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>?) ??
        <String, dynamic>{},
  ),
};

/// Every visible text in the scrollable body, minus the per-code fields.
Future<Set<String>> _cannedTexts(
  WidgetTester tester,
  Map<String, dynamic> code,
) async {
  await pumpScreen(
    tester,
    CodeDetailScreen(code: code),
    size: const Size(390, 2400),
  );
  final perCode = {
    for (final k in ['code', 'title', 'description', 'system', 'severity'])
      '${code[k]}',
    '${code['severity']}'.toUpperCase(),
  };
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((s) => s.isNotEmpty && !perCode.contains(s))
      .toSet();
}

void main() {
  setUpAll(loadAppFonts);

  group('rendering', () {
    testWidgets('EN shows code, title, description and system', (tester) async {
      await pumpScreen(tester, CodeDetailScreen(code: _code()));
      expectNoException(tester);

      expect(find.text('P0300'), findsOneWidget);
      expect(
        find.text('Random/Multiple Cylinder Misfire Detected'),
        findsOneWidget,
      );
      expect(
        find.text('Engine misfire detected on several cylinders'),
        findsOneWidget,
      );
      expect(find.text('Engine'), findsOneWidget);
      expect(
        directionAt(tester, find.byType(CodeDetailScreen)),
        TextDirection.ltr,
      );
    });

    testWidgets('AR uses the _ar fields and lays out RTL', (tester) async {
      await pumpScreen(tester, CodeDetailScreen(code: _code()), locale: ar);
      expectNoException(tester);

      expect(find.text('P0300'), findsOneWidget);
      expect(find.text('عنوان P0300'), findsOneWidget);
      expect(find.text('وصف P0300'), findsOneWidget);
      expect(find.text('المحرك'), findsOneWidget);
      expect(
        find.text('Random/Multiple Cylinder Misfire Detected'),
        findsNothing,
      );
      expect(
        directionAt(tester, find.byType(CodeDetailScreen)),
        TextDirection.rtl,
      );
    });

    testWidgets('AR falls back to English fields when _ar is missing', (
      tester,
    ) async {
      final code = _code()
        ..remove('title_ar')
        ..remove('description_ar');
      await pumpScreen(tester, CodeDetailScreen(code: code), locale: ar);

      expect(
        find.text('Random/Multiple Cylinder Misfire Detected'),
        findsOneWidget,
      );
      expect(
        find.text('Engine misfire detected on several cylinders'),
        findsOneWidget,
      );
    });

    testWidgets('small phone: long description does not overflow', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        CodeDetailScreen(
          code: _code(
            title: 'A very long diagnostic trouble code title ' * 3,
            description: 'Long description. ' * 40,
          ),
        ),
        size: smallPhone,
      );
      expectNoException(tester);
    });

    for (final locale in [en, ar]) {
      testWidgets(
        'header title + share button fit a 320-wide phone '
        '(${locale.languageCode})',
        (tester) async {
          await pumpScreen(
            tester,
            CodeDetailScreen(code: _code()..['pending'] = true),
            locale: locale,
            size: const Size(320, 568),
          );
          expectNoException(tester);
          final finder = find.text(tr('code_details', locale));
          final title = tester.widget<Text>(finder);
          expect(title.maxLines, 1);
          expect(title.overflow, TextOverflow.ellipsis);
          final share = tester.getRect(find.byIcon(Icons.share));
          expect(share.left, greaterThanOrEqualTo(0));
          expect(share.right, lessThanOrEqualTo(320));
          expect(tester.getRect(finder).overlaps(share), isFalse);
          // The pending chip fits next to the code and system chips.
          expect(find.text(tr('dtc_pending', locale)), findsOneWidget);
        },
      );
    }

    testWidgets('empty arguments render placeholders instead of crashing', (
      tester,
    ) async {
      await pumpScreen(tester, const CodeDetailScreen(code: {}));
      expectNoException(tester);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await pumpScreen(
        tester,
        CodeDetailScreen(code: _code()),
        locale: ar,
        size: const Size(390, 2400),
      );
      expect(englishLeaks(tester), isEmpty);
    });
  });

  group('severity', () {
    for (final (sev, color) in [
      ('critical', _critical),
      ('warning', _warning),
      ('info', _info),
    ]) {
      testWidgets('$sev colours the code chip', (tester) async {
        await pumpScreen(tester, CodeDetailScreen(code: _code(severity: sev)));
        final chip = tester.widget<Text>(find.text('P0300'));
        expect(chip.style?.color, color);
      });
    }

    testWidgets('unknown severity falls back to the accent colour', (
      tester,
    ) async {
      await pumpScreen(tester, CodeDetailScreen(code: _code(severity: 'x')));
      final chip = tester.widget<Text>(find.text('P0300'));
      expect(chip.style?.color, isNot(anyOf(_critical, _warning, _info)));
    });
  });

  group('content', () {
    testWidgets(
      'cause / cost / related codes are specific to the code',
      (tester) async {
        final misfire = await _cannedTexts(tester, _code());
        final abs = await _cannedTexts(
          tester,
          _code(
            code: 'C1201',
            severity: 'info',
            title: 'Engine control system malfunction',
            description: 'ABS disabled by engine control fault',
            system: 'Chassis',
          ),
        );
        // Headings/labels may legitimately repeat; the diagnosis may not.
        final shared = misfire.intersection(abs);
        expect(
          shared.length,
          lessThan(misfire.length - 4),
          reason: 'identical body for P0300 and C1201: $shared',
        );
        // Nothing fabricated: no canned cause, price, repair time or
        // "related" codes on either screen.
        for (final texts in [misfire, abs]) {
          expect(texts.where((t) => t.contains(r'$')), isEmpty);
          expect(texts, isNot(contains(tr('cause_o2_catalyst'))));
          for (final related in ['P0171', 'P0174', 'P0430']) {
            expect(texts.where((t) => t.contains(related)), isEmpty);
          }
        }
        // Structure-derived facts differ: generic powertrain vs
        // manufacturer-specific chassis.
        expect(misfire, containsAll([tr('dtc_cat_p'), tr('dtc_type_generic'),
            tr('dtc_sub_ignition')]));
        expect(abs, containsAll([tr('dtc_cat_c'),
            tr('dtc_type_manufacturer')]));
        expect(abs, isNot(contains(tr('dtc_sub_ignition'))));
      },
    );
  });

  group('navigation', () {
    testWidgets('solution button pushes /solution with the same code', (
      tester,
    ) async {
      final observer = RecordingObserver();
      final code = _code();
      await pumpScreen(
        tester,
        CodeDetailScreen(code: code),
        observer: observer,
      );

      final button = find.byType(ElevatedButton);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(observer.pushedNames.last, AppRoutes.solution);
      expect(observer.pushed.last.settings.arguments, same(code));
      expect(find.text('route:${AppRoutes.solution}'), findsOneWidget);
    });

    testWidgets('back arrow pops', (tester) async {
      await pumpScreen(tester, CodeDetailScreen(code: _code()), pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });

    testWidgets(
      'share button shares the code',
      (tester) async {
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (c) async {
            calls.add(c);
            return 'dev.fluttercommunity.plus/share/unavailable';
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'),
            null,
          ),
        );

        await pumpScreen(tester, CodeDetailScreen(code: _code()));
        await tester.tap(find.byIcon(Icons.share));
        await tester.pumpAndSettle();
        expectNoException(tester);
        expect(calls, hasLength(1));
        final text = (calls.single.arguments as Map)['text'] as String;
        expect(text, contains('P0300'));
        expect(text, contains('Random/Multiple Cylinder Misfire Detected'));
        expect(text, contains(tr('dtc_cat_p')));
        expect(text, isNot(contains(r'$')));
      },
    );
  });

  // ── Opened from the diagnostic codes list (real repository) ─────────────────

  group('from the diagnostic codes list', () {
    late FakeOBDAdapter fake;
    late DtcRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fake = FakeOBDAdapter();
      OBDService.setTestAdapter(fake);
      repo = DtcRepository();
    });

    tearDown(() => fake.dispose());

    /// Loads the bundled DTC JSON outside fake-async (large asset loads run
    /// on a background isolate and never complete under FakeAsync); the
    /// parsed map is cached statically for the screen's lookups.
    Future<String?> warm(WidgetTester tester, String code) =>
        tester.runAsync<String?>(() => repo.getDtcDescription(code));

    Future<void> openFromList(
      WidgetTester tester,
      List<String> dtcs,
      String tapCode,
    ) async {
      fake.dtcsToReturn = dtcs;
      await OBDService.instance.initialize(MockBluetoothDevice());
      await pumpScreen(
        tester,
        DiagnosticCodesScreen(repository: repo),
        routes: _routes,
        size: const Size(390, 1400),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(tapCode).first);
      await tester.pumpAndSettle();
      expect(find.byType(CodeDetailScreen), findsOneWidget);
    }

    testWidgets('SAE code shows its database description', (tester) async {
      final desc = await warm(tester, 'P0300');
      expect(desc, isNotNull);

      await openFromList(tester, ['P0300'], 'P0300');
      final detail = find.byType(CodeDetailScreen);
      expect(
        find.descendant(of: detail, matching: find.text('P0300')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text(desc!)),
        findsWidgets,
      );
    });

    testWidgets('manufacturer-specific code shows the manufacturer label', (
      tester,
    ) async {
      // P1FFF is in the manufacturer-controlled block and not in the DB.
      final label = await warm(tester, 'P1FFF');
      expect(label, isNotNull);
      expect(label, contains('P1FFF'));

      await openFromList(tester, ['P1FFF'], 'P1FFF');
      final detail = find.byType(CodeDetailScreen);
      expect(
        find.descendant(of: detail, matching: find.text(label!)),
        findsWidgets,
      );
    });

    testWidgets(
      'pending (~) code is labelled pending on the detail screen',
      (tester) async {
        await warm(tester, 'P0300');
        await openFromList(tester, ['~P0300'], 'P0300');

        final detail = find.byType(CodeDetailScreen);
        expect(
          find.descendant(of: detail, matching: find.text('~P0300')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: detail,
            matching: find.textContaining(
              RegExp('pending', caseSensitive: false),
            ),
          ),
          findsWidgets,
        );
      },
    );

    testWidgets('pending code shows without the "~" prefix', (tester) async {
      await warm(tester, 'P0300');
      await openFromList(tester, ['~P0300'], 'P0300');

      final detail = find.byType(CodeDetailScreen);
      expect(
        find.descendant(of: detail, matching: find.text('P0300')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.textContaining('~')),
        findsNothing,
      );
    });
  });
}
