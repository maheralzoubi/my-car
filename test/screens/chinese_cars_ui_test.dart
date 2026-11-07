// Chinese cars, user-facing side: how the dashboard, diagnostic codes, code
// detail and connection screens present what a Chinese car's OBD-II side
// returns, in English and Arabic (RTL), on a 390x844 phone.
//
// The adapter layer is replaced by [ChineseCarAdapter] (a FakeOBDAdapter that
// also answers VIN / readiness), so these tests cover presentation only. DTC
// descriptions come from the real bundled database via [DtcRepository]
// (offline: connectivity is mocked to "none").
//
// Tests that assert correct behaviour the app does not have yet are skipped
// with `skip: bug('BUG: …')` (`'BUG: REGRESSION: …'` for a defect introduced
// by a fix — bug() requires the 'BUG:' prefix); run them with
//   flutter test --dart-define=RUN_BUG_TESTS=true test/screens/chinese_cars_ui_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/modules/home/presentation/pages/connectionScreen/connection_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/obd_gauge.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';

import '../helpers/elm327_sim.dart' show FakeDevice;
import '../helpers/fake_obd_adapter.dart';
import 'helpers/chinese_cars_ui_helpers.dart';
import 'helpers/screen_harness.dart';

const _locales = [en, ar];

/// Latin-script words acceptable on the Arabic dashboard: units, SAE J1930
/// acronyms that Arabic workshops use as-is (RPM, MAP, MAF, EGR, MIL, STFT /
/// LTFT — the app already writes "مستشعر MAF", "مستشعر O2") and the fake
/// adapter's Bluetooth name ("FakeAdapter"; a real adapter's advertised name
/// such as "OBDII" is a device name, not UI copy). The VIN line and the
/// maker (a brand name) are filtered separately.
const _arDashboardAllow = {
  'kpa',
  'mpa',
  'rpm',
  'stft',
  'ltft',
  'maf',
  'egr',
  'mil',
  'fakeadapter',
};

String _code(String raw) => raw.startsWith('~') ? raw.substring(1) : raw;

String _sys(String code) => switch (code[0]) {
  'P' => 'engine',
  'C' => 'system_chassis',
  'B' => 'body',
  _ => 'network',
};

final _routes = <String, WidgetBuilder>{
  AppRoutes.codeDetail: (ctx) => CodeDetailScreen(
    code:
        (ModalRoute.of(ctx)!.settings.arguments as Map<String, dynamic>?) ??
        <String, dynamic>{},
  ),
};

void main() {
  setUpAll(() async {
    await loadAppFonts();
    mockOffline();
  });
  tearDownAll(clearOfflineMock);

  late ChineseCarAdapter fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DtcRepository.resetCaches();
    // Placeholder; each test plugs in its car.
    fake = ChineseCarAdapter(changanCs75Plus);
    OBDService.setTestAdapter(fake);
  });

  tearDown(() => fake.dispose());

  Future<void> plugInto(ChineseCar car) async {
    fake.dispose();
    fake = ChineseCarAdapter(car);
    OBDService.setTestAdapter(fake);
    await OBDService.instance.initialize(MockBluetoothDevice());
  }

  /// Connects [car], mounts the dashboard, lets the DTC / readiness / VIN
  /// requests finish (300 ms settle each), then emits the car's live data.
  /// Returns the RenderFlex overflow reports collected meanwhile.
  Future<List<String>> showCar(
    WidgetTester tester,
    ChineseCar car,
    Locale locale, {
    Size size = phonePortrait,
    bool keepCollecting = false,
  }) async {
    final overflows = collectOverflows();
    await plugInto(car);
    await pumpScreen(
      tester,
      const DashboardScreen(),
      locale: locale,
      size: size,
    );
    await tester.pump(const Duration(seconds: 1));
    fake.emitLiveData(car.live);
    await tester.pump();
    await tester.pump();
    // Open the "All parameters" list under the live tiles (collapsed by
    // default), so every live reading is on screen.
    final allParams = find.byKey(const ValueKey('dash_more_params'));
    await tester.ensureVisible(allParams);
    await tester.pump();
    await tester.tap(allParams);
    await tester.pump();
    // From here on an overflow fails the test directly, unless the caller
    // keeps collecting (it must call stopCollectingOverflows() first).
    if (!keepCollecting) stopCollectingOverflows();
    return overflows;
  }

  /// Whether the warning light [key] is lit: lit lamps are listed on the
  /// dashboard (the full grid is behind "See all").
  bool lit(WidgetTester tester, String key, Locale locale) => find
      .descendant(
        of: find.byKey(const ValueKey('dash_lit_lamps')),
        matching: find.text(tr(key, locale)),
      )
      .evaluate()
      .isNotEmpty;

  // ══ 1. Dashboard ═══════════════════════════════════════════════════════════

  group('dashboard', () {
    Finder live(Finder f, Locale locale) => find.descendant(
      of: find
          .ancestor(
            of: find.text(tr('live_data', locale)),
            matching: find.byType(Column),
          )
          .first,
      matching: f,
    );

    for (final car in allChineseCars) {
      for (final locale in _locales) {
        final lang = locale.languageCode;

        testWidgets('${car.name} [$lang]: VIN card, live tiles, no new '
            'overflow', (tester) async {
          final overflows = await showCar(
            tester,
            car,
            locale,
            keepCollecting: true,
          );
          // Scroll the whole page so every section is laid out, then stop
          // collecting before any expect.
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -1500),
          );
          await tester.pump();
          stopCollectingOverflows();

          // ── VIN card ──
          // Maker (VinDecoder WMI), model year (GB 16735 position 10), the
          // country in the UI language and the full VIN.
          expect(find.text('${car.maker}  •  ${car.year}'), findsOneWidget);
          expect(
            find.text(
              '${lang == 'ar' ? 'الصين' : 'China'}  •  VIN: ${car.vin}',
            ),
            findsOneWidget,
          );

          // ── Live tiles ──
          final d = car.live;
          final speedGauge = find.widgetWithText(
            OBDGauge,
            tr('dash_speed', locale),
          );
          expect(
            find.descendant(
              of: speedGauge,
              matching: find.text(d.speedKmh!.toStringAsFixed(0)),
            ),
            findsOneWidget,
          );
          // Battery: PID 0142 or the adapter's ATRV fallback — same field.
          // The tile shows the value and its unit ("V") as separate texts.
          final batteryTile = find.widgetWithText(
            OBDGauge,
            tr('battery', locale),
          );
          expect(
            find.descendant(
              of: batteryTile,
              matching: find.text(d.batteryVoltage!.toStringAsFixed(1)),
            ),
            findsOneWidget,
          );
          if (d.coolantTempC != null) {
            expect(
              live(find.text(d.coolantTempC!.toStringAsFixed(0)), locale),
              findsWidgets,
            );
          }

          if (car.diesel) {
            expect(
              live(find.text(tr('accel_pedal', locale)), locale),
              findsOneWidget,
            );
            expect(live(find.text('12.5'), locale), findsOneWidget);
            expect(
              live(find.text(tr('rail_pressure', locale)), locale),
              findsOneWidget,
            );
            expect(live(find.text('32.0'), locale), findsOneWidget);
            expect(
              live(find.text(tr('throttle', locale)), locale),
              findsNothing,
            );
            expect(live(find.text(tr('timing', locale)), locale), findsNothing);
            expect(live(find.text('STFT B1'), locale), findsNothing);
          } else if (!car.ev && d.throttlePct != null) {
            expect(
              live(find.text(tr('throttle', locale)), locale),
              findsOneWidget,
            );
            expect(
              live(find.text(d.throttlePct!.toStringAsFixed(1)), locale),
              findsOneWidget,
            );
            expect(
              live(find.text(tr('timing', locale)), locale),
              findsOneWidget,
            );
          }

          if (d.o2B1S1Voltage == null && d.lambdaB1S1 != null) {
            expect(
              live(find.text('λ ${d.lambdaB1S1!.toStringAsFixed(2)}'), locale),
              findsOneWidget,
            );
          } else if (d.o2B1S1Voltage != null) {
            expect(
              live(
                find.text('${d.o2B1S1Voltage!.toStringAsFixed(2)}V'),
                locale,
              ),
              findsOneWidget,
            );
            expect(live(find.textContaining('λ'), locale), findsNothing);
          }

          if (!car.diesel && d.fuelRailPressureKpa != null) {
            // GDI petrol (Changan Blue Core) also reports rail pressure.
            expect(
              live(
                find.text((d.fuelRailPressureKpa! / 1000).toStringAsFixed(1)),
                locale,
              ),
              findsOneWidget,
            );
          }

          if (car.ev) {
            // No engine ECU: the engine tiles stay at '--' instead of 0.
            final rpmGauge = find.widgetWithText(
              OBDGauge,
              tr('engine', locale),
            );
            expect(
              find.descendant(of: rpmGauge, matching: find.text('--')),
              findsOneWidget,
            );
          }

          // RTL in Arabic.
          expect(
            directionAt(tester, find.byType(DashboardScreen)),
            lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );

          // The trip card's drive-score Row no longer overflows either, so
          // any overflow is now a failure.
          expect(overflows, isEmpty, reason: overflows.join('\n---\n'));

          await unmount(tester);
        });
      }
    }

    for (final car in [bydSongPlusDmi, bydAtto3]) {
      for (final locale in _locales) {
        testWidgets(
          '${car.name} [${locale.languageCode}]: VIN card names the maker BYD',
          (tester) async {
            await showCar(tester, car, locale);
            expect(find.text('BYD  •  ${car.year}'), findsOneWidget);
            await unmount(tester);
          },
        );
      }
    }

    testWidgets(
      'Changan [ar]: VIN card country is localized (الصين, not "China")',
      (tester) async {
        await showCar(tester, changanCs75Plus, ar);
        expect(find.textContaining('الصين'), findsOneWidget);
        expect(find.textContaining('China'), findsNothing);
        await unmount(tester);
      },
    );

    testWidgets('Changan [ar]: live-data and health labels are Arabic', (
      tester,
    ) async {
      await showCar(tester, changanCs75Plus, ar);
      final leaks = englishLeaks(tester, allow: _arDashboardAllow)
          // The VIN line and the maker (brand name) stay in Latin script.
          .where((s) => !s.contains(changanCs75Plus.vin))
          .where((s) => !s.startsWith('${changanCs75Plus.maker}  •'))
          .toList();
      expect(leaks, isEmpty, reason: leaks.join(' | '));
      await unmount(tester);
    });

    // ── Warning lights for Chinese DTC mixes ──

    for (final locale in _locales) {
      final lang = locale.languageCode;

      testWidgets('[$lang] Chinese codes light the matching warning lights', (
        tester,
      ) async {
        await showCar(tester, gwmPoerDiesel, locale);
        expect(lit(tester, 'fuel', locale), isTrue); // P0087 rail pressure
        expect(lit(tester, 'egr', locale), isTrue); // ~P0401
        expect(lit(tester, 'check_engine', locale), isTrue); // P2002 DPF
        expect(lit(tester, 'mil', locale), isTrue);
        expect(lit(tester, 'network', locale), isFalse);
        await unmount(tester);

        await showCar(tester, geelyCoolray, locale);
        expect(lit(tester, 'body', locale), isTrue); // B1000
        expect(lit(tester, 'check_engine', locale), isTrue); // P0016 cam/crank
        expect(lit(tester, 'o2_sensor', locale), isFalse);
        await unmount(tester);

        await showCar(tester, havalJolion, locale);
        expect(lit(tester, 'network', locale), isTrue); // U0140
        expect(lit(tester, 'misfire', locale), isTrue); // P0301
        await unmount(tester);
      });

      testWidgets(
        'Chery Tiggo 8 Pro [$lang]: C1201 (ABS inlet valve) does not light '
        'the steering lamp',
        (tester) async {
          await showCar(tester, cheryTiggo8Pro, locale);
          expect(lit(tester, 'steering', locale), isFalse);
          await unmount(tester);
        },
      );
    }

    testWidgets('Changan [en]: health card counts fault codes, not lit lamps', (
      tester,
    ) async {
      await showCar(tester, changanCs75Plus, en);
      // 3 confirmed + 1 pending → "3 …" plus "+1 pending" (the old
      // assertion accepted 3 or 4; the spec is now confirmed (+N pending)).
      expect(find.text('3 active fault codes detected'), findsOneWidget);
      expect(find.text('+1 pending'), findsOneWidget);
      expect(find.textContaining('4 active fault'), findsNothing);
      expect(find.textContaining('5 active fault'), findsNothing);
      await unmount(tester);
    });
  });

  // ══ 2. Diagnostic codes screen ═════════════════════════════════════════════

  group('diagnostic codes', () {
    late DtcRepository repo;
    setUp(() => repo = DtcRepository());

    /// Mounts the codes screen for [car] after warming the bundled DB.
    /// Tall surface (same 390 width) so every card is built.
    Future<Map<String, String?>> showCodes(
      WidgetTester tester,
      ChineseCar car,
      Locale locale, {
      Size size = const Size(390, 2000),
    }) async {
      final descs = await warmDtcs(
        tester,
        repo,
        car.dtcs,
        lang: locale.languageCode,
      );
      await plugInto(car);
      await pumpScreen(
        tester,
        DiagnosticCodesScreen(repository: repo),
        locale: locale,
        size: size,
        routes: _routes,
      );
      await tester.pumpAndSettle();
      return descs;
    }

    for (final car in allChineseCars) {
      for (final locale in _locales) {
        final lang = locale.languageCode;
        testWidgets('${car.name} [$lang]: cards, descriptions, pending, '
            'system chips', (tester) async {
          final descs = await showCodes(tester, car, locale);
          expectNoException(tester);

          final codes = car.dtcs.map(_code).toList();
          for (final code in codes) {
            expect(find.text(code), findsWidgets, reason: code);
            final desc = descs[code];
            if (desc != null) {
              expect(find.text(desc), findsWidgets, reason: '$code: $desc');
            }
          }
          // Never a blank / "null" description, never a raw '~'.
          final texts = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .toList();
          expect(texts.where((t) => t == 'null'), isEmpty);
          expect(texts.where((t) => t.contains('~')), isEmpty);

          // Pending chips (+1: the summary's "Pending" label).
          final pending = car.dtcs.where((c) => c.startsWith('~')).length;
          expect(
            find.text(tr('dtc_pending', locale)),
            findsNWidgets(pending + 1),
          );

          // System chips (+1: the filter chip with the same label).
          for (final key in ['engine', 'system_chassis', 'body', 'network']) {
            final n = codes.where((c) => _sys(c) == key).length;
            expect(
              find.text(tr(key, locale)),
              findsNWidgets(n + 1),
              reason: key,
            );
          }

          // Summary: confirmed / pending counts.
          final confirmed = car.dtcs.length - pending;
          expect(find.text('$confirmed'), findsWidgets);
          expect(find.text('$pending'), findsWidgets);

          expect(
            directionAt(tester, find.byType(DiagnosticCodesScreen)),
            lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
        });
      }
    }

    // ── Manufacturer-specific / hybrid descriptions ──

    for (final locale in _locales) {
      final lang = locale.languageCode;

      testWidgets('Geely [$lang]: manufacturer-specific B1000 / C1000 not in '
          'the DB show the manufacturer label', (tester) async {
        final descs = await showCodes(tester, geelyCoolray, locale);
        for (final code in ['B1000', 'C1000']) {
          expect(descs[code], isNotNull);
          expect(descs[code], contains(code));
          expect(find.text(descs[code]!), findsOneWidget);
        }
      });

      testWidgets(
        'BYD Song Plus DM-i [$lang]: hybrid P0Axx codes have a description',
        (tester) async {
          final descs = await showCodes(tester, bydSongPlusDmi, locale);
          for (final code in ['P0A80', 'P0AA6', 'P0A7F']) {
            expect(descs[code], isNotNull, reason: code);
            // Code chip only — not repeated as the description.
            expect(find.text(code), findsOneWidget, reason: code);
          }
        },
      );

      testWidgets(
        'Changan [$lang]: U1012 is not described as a Ford J1850 SCP fault',
        (tester) async {
          final descs = await showCodes(tester, changanCs75Plus, locale);
          expect(descs['U1012'], isNot(contains('J1850')));
          expect(find.textContaining('J1850'), findsNothing);
        },
      );
    }

    testWidgets('Geely [ar]: the manufacturer-specific label is in Arabic', (
      tester,
    ) async {
      final descs = await showCodes(tester, geelyCoolray, ar);
      expect(descs['B1000'], matches(RegExp('[؀-ۿ]')));
      expect(find.textContaining('Manufacturer-specific'), findsNothing);
    });

    // ── Clear ──

    for (final locale in _locales) {
      final lang = locale.languageCode;

      testWidgets('Haval Jolion [$lang]: clear refused (engine running) → '
          '"turn the engine off" hint, codes kept', (tester) async {
        fake.clearShouldFail = true;
        await showCodes(tester, havalJolion, locale, size: phonePortrait);
        fake.clearShouldFail = true;

        await tester.tap(find.byIcon(Icons.delete_outline_rounded));
        await tester.pump();
        await tester.tap(find.text(tr('clear', locale)));
        await tester.pumpAndSettle();

        expect(fake.clearDtcsCalled, isTrue);
        expect(
          find.text(tr('failed_clear_codes_hint', locale)),
          findsOneWidget,
        );
        expect(find.text('P0301'), findsOneWidget);
        expectNoException(tester);
        await unmount(tester);
      });

      testWidgets('MG5 [$lang]: clear OK → empty state', (tester) async {
        await showCodes(tester, mg5, locale, size: phonePortrait);

        await tester.tap(find.byIcon(Icons.delete_outline_rounded));
        await tester.pump();
        await tester.tap(find.text(tr('clear', locale)));
        await tester.pumpAndSettle();

        expect(fake.clearDtcsCalled, isTrue);
        expect(find.text(tr('no_codes_found', locale)), findsOneWidget);
        expect(find.text('P0420'), findsNothing);
        expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
        expectNoException(tester);
      });
    }

    // ── Export report ──

    for (final locale in _locales) {
      final lang = locale.languageCode;
      testWidgets(
        'Changan [$lang]: exported report lists codes, descriptions and the '
        'pending code',
        (tester) async {
          final shares = captureShares(tester);
          final descs = await showCodes(tester, changanCs75Plus, locale);

          await tester.tap(find.byIcon(Icons.share_outlined));
          await tester.pumpAndSettle();
          expectNoException(tester);

          expect(shares, hasLength(1));
          final text = (shares.single.arguments as Map)['text'] as String;
          expect(text, contains(tr('report_title', locale)));
          expect(
            text,
            contains(tr('report_fault_codes', locale).replaceAll('{n}', '4')),
          );
          for (final c in ['P0300', 'P1336', 'U1012']) {
            expect(text, contains(c));
            expect(text, contains(descs[c]!));
          }
          expect(text, contains(tr('report_pending_codes', locale)));
          expect(text, contains('[${tr('report_pending_tag', locale)}] P0171'));
          expect(text, isNot(contains('~')));
        },
      );
    }
  });

  // ══ 3. Code detail ═════════════════════════════════════════════════════════

  group('code detail', () {
    late DtcRepository repo;
    setUp(() => repo = DtcRepository());

    Future<String?> openDetail(
      WidgetTester tester,
      ChineseCar car,
      String code,
      Locale locale,
    ) async {
      final descs = await warmDtcs(
        tester,
        repo,
        car.dtcs,
        lang: locale.languageCode,
      );
      await plugInto(car);
      await pumpScreen(
        tester,
        DiagnosticCodesScreen(repository: repo),
        locale: locale,
        size: const Size(390, 2000),
        routes: _routes,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(code).first);
      await tester.pumpAndSettle();
      expect(find.byType(CodeDetailScreen), findsOneWidget);
      return descs[code];
    }

    Finder inDetail(Finder f) =>
        find.descendant(of: find.byType(CodeDetailScreen), matching: f);

    for (final locale in _locales) {
      final lang = locale.languageCode;

      testWidgets('Geely B1000 [$lang]: code, manufacturer label, Body, Info', (
        tester,
      ) async {
        final label = await openDetail(tester, geelyCoolray, 'B1000', locale);
        expect(inDetail(find.text('B1000')), findsOneWidget);
        expect(inDetail(find.text(label!)), findsWidgets);
        expect(inDetail(find.text(tr('body', locale))), findsOneWidget);
        expect(
          inDetail(find.text(tr('severity_info', locale))),
          findsOneWidget,
        );
        expect(
          directionAt(tester, find.byType(CodeDetailScreen)),
          lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      });

      // Was "DB description for a P1 code": P1xxx is manufacturer-controlled,
      // so the bundled (Ford/GM) text is no longer shown as its description.
      testWidgets('Chery P1607 [$lang]: manufacturer label for a P1 code', (
        tester,
      ) async {
        final desc = await openDetail(tester, cheryTiggo8Pro, 'P1607', locale);
        expect(
          desc,
          DtcRepository.manufacturerLabel('P1607', languageCode: lang),
        );
        expect(inDetail(find.text('P1607')), findsOneWidget);
        expect(inDetail(find.text(desc!)), findsWidgets);
        expect(inDetail(find.text(tr('engine', locale))), findsOneWidget);
      });

      testWidgets(
        'Geely B1000 [$lang]: detail does not blame the O2 sensor / catalyst '
        'for a body-module code',
        (tester) async {
          await openDetail(tester, geelyCoolray, 'B1000', locale);
          expect(
            inDetail(find.text(tr('cause_o2_catalyst', locale))),
            findsNothing,
          );
          expect(inDetail(find.text('P0171')), findsNothing);
        },
      );
    }
  });

  // ══ 4. Connection screen ═══════════════════════════════════════════════════

  group('connection', () {
    /// Mounts the screen, then fails a connect with [reason].
    Future<void> failWith(
      WidgetTester tester,
      ChineseCar car,
      OBDFailureReason reason,
      Locale locale,
    ) async {
      fake.dispose();
      fake = ChineseCarAdapter(car);
      OBDService.setTestAdapter(fake);
      await pumpScreen(tester, const ConnectionScreen(), locale: locale);
      fake.failReason = reason;
      await OBDService.instance.initialize(FakeDevice([]));
      await tester.pump();
    }

    for (final locale in _locales) {
      final lang = locale.languageCode;

      testWidgets('BYD Atto 3 EV [$lang]: no engine ECU → "Vehicle not '
          'responding" + ignition hint, RETRY → connected with adapter / '
          'protocol line', (tester) async {
        await failWith(
          tester,
          bydAtto3,
          OBDFailureReason.ecuNotResponding,
          locale,
        );
        expectNoException(tester);

        expect(find.text(tr('obd_err_ecu_silent', locale)), findsOneWidget);
        expect(find.text(tr('obd_err_ecu_silent_sub', locale)), findsOneWidget);
        expect(find.text(tr('btn_retry', locale)), findsOneWidget);
        expect(find.byIcon(Icons.directions_car), findsWidgets);

        // The user switches the car to READY and retries.
        fake.failReason = null;
        await tester.tap(find.text(tr('btn_retry', locale)));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('${tr('connected_to', locale)} OBDII'),
          findsOneWidget,
        );
        expect(
          find.text('ELM327 v2.1 · ISO 15765-4 (CAN 11/500)'),
          findsOneWidget,
        );
        expect(find.text(tr('scan_vehicle', locale)), findsOneWidget);
        expectNoException(tester);
        await unmount(tester);
      });

      testWidgets(
        'BYD Atto 3 EV [$lang]: the ECU-silent hint also covers electric '
        'vehicles that are already switched on',
        (tester) async {
          await failWith(
            tester,
            bydAtto3,
            OBDFailureReason.ecuNotResponding,
            locale,
          );
          expect(
            find.textContaining(
              lang == 'ar'
                  ? RegExp('كهربائي')
                  : RegExp(r'electric|\bEV', caseSensitive: false),
            ),
            findsWidgets,
          );
        },
      );

      for (final car in [changanCs75Plus, geelyCoolray, gwmPoerDiesel]) {
        testWidgets('${car.name} [$lang]: adapter info line after RETRY', (
          tester,
        ) async {
          await failWith(
            tester,
            car,
            OBDFailureReason.ecuNotResponding,
            locale,
          );
          fake.failReason = null;
          await tester.tap(find.text(tr('btn_retry', locale)));
          await tester.pump();
          await tester.pump();
          expect(find.text('ELM327 v2.1 · ${car.protocol}'), findsOneWidget);
          expectNoException(tester);
          await unmount(tester);
        });
      }
    }
  });

  // ══ 5. Double-check (independent verification of the Chinese-car fixes) ═══

  group('double-check', () {
    late DtcRepository repo;
    setUp(() => repo = DtcRepository());

    final manufacturerRange = RegExp(r'^(?:P1|P3[0-3]|[BCU][12])');
    final arabicScript = RegExp('[؀-ۿ]');
    final latinWord = RegExp('[A-Za-z]{3,}');

    Future<Map<String, String?>> codesScreen(
      WidgetTester tester,
      ChineseCar car,
      Locale locale, {
      Size size = const Size(390, 2400),
    }) async {
      final descs = await warmDtcs(
        tester,
        repo,
        car.dtcs,
        lang: locale.languageCode,
      );
      await plugInto(car);
      await pumpScreen(
        tester,
        DiagnosticCodesScreen(repository: repo),
        locale: locale,
        size: size,
        routes: _routes,
      );
      await tester.pumpAndSettle();
      return descs;
    }

    Finder inDetail(Finder f) =>
        find.descendant(of: find.byType(CodeDetailScreen), matching: f);

    Future<void> openCode(WidgetTester tester, String code) async {
      // The code list is lazy: on a small phone the card may not be built.
      if (find.text(code).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(code),
          200,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
      }
      await tester.tap(find.text(code).first);
      await tester.pumpAndSettle();
      expect(find.byType(CodeDetailScreen), findsOneWidget);
    }

    List<String> detailTexts(WidgetTester tester) => tester
        .widgetList<Text>(inDetail(find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .toList();

    for (final car in allChineseCars) {
      final confirmed = car.dtcs.where((c) => !c.startsWith('~')).length;
      final pending = car.dtcs.length - confirmed;

      for (final locale in _locales) {
        final lang = locale.languageCode;
        final isAr = lang == 'ar';

        // ── Dashboard ──

        testWidgets('${car.name} [$lang]: VIN card maker + localized country', (
          tester,
        ) async {
          await showCar(tester, car, locale);
          expect(find.text('${car.maker}  •  ${car.year}'), findsOneWidget);
          expect(find.textContaining(tr('vin_unknown', locale)), findsNothing);
          expect(
            find.text('${isAr ? 'الصين' : 'China'}  •  VIN: ${car.vin}'),
            findsOneWidget,
          );
          if (isAr) expect(find.textContaining('China'), findsNothing);
          await unmount(tester);
        });

        if (isAr) {
          testWidgets('${car.name} [ar]: dashboard has no English beyond '
              'acronyms, the maker and the VIN', (tester) async {
            await showCar(tester, car, ar);
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -3000),
            );
            await tester.pump();
            final leaks = englishLeaks(tester, allow: _arDashboardAllow)
                .where((s) => !s.contains(car.vin))
                .where((s) => !s.startsWith('${car.maker}  •'))
                .toList();
            expect(leaks, isEmpty, reason: leaks.join(' | '));
            await unmount(tester);
          });
        }

        for (final size in [phonePortrait, smallPhone]) {
          final dims = '${size.width.toInt()}x${size.height.toInt()}';
          testWidgets('${car.name} [$lang] $dims: dashboard has no overflow', (
            tester,
          ) async {
            final overflows = await showCar(
              tester,
              car,
              locale,
              size: size,
              keepCollecting: true,
            );
            for (var i = 0; i < 4; i++) {
              await tester.drag(
                find.byType(SingleChildScrollView).first,
                const Offset(0, -800),
              );
              await tester.pump();
            }
            stopCollectingOverflows();
            expect(overflows, isEmpty, reason: overflows.join('\n---\n'));
            expectNoException(tester);
            await unmount(tester);
          });
        }

        testWidgets('${car.name} [$lang]: health card counts $confirmed '
            'confirmed (+$pending pending) codes', (tester) async {
          await showCar(tester, car, locale);
          final key = confirmed == 0
              ? (pending == 1
                    ? 'dash_pending_only_one'
                    : 'dash_pending_only_many')
              : (confirmed == 1 ? 'dash_fault_code_n' : 'dash_fault_codes_n');
          final n = confirmed == 0 ? pending : confirmed;
          expect(
            find.text(tr(key, locale).replaceAll('{n}', '$n')),
            findsOneWidget,
          );
          final plusPending = find.text(
            tr('dash_pending_codes_n', locale).replaceAll('{n}', '$pending'),
          );
          expect(
            plusPending,
            confirmed > 0 && pending > 0 ? findsOneWidget : findsNothing,
          );
          // Never the total (confirmed + pending) or a lamp count instead.
          if (pending > 0) {
            expect(
              find.text(
                tr(
                  'dash_fault_codes_n',
                  locale,
                ).replaceAll('{n}', '${car.dtcs.length}'),
              ),
              findsNothing,
            );
          }
          await unmount(tester);
        });

        // ── Diagnostic codes screen ──

        testWidgets('${car.name} [$lang]: every code has a real, localized '
            'description; manufacturer codes get the manufacturer label', (
          tester,
        ) async {
          final descs = await codesScreen(tester, car, locale);
          expectNoException(tester);
          for (final code in car.dtcs.map(_code)) {
            final desc = descs[code];
            expect(desc, isNotNull, reason: code);
            expect(desc!.trim(), isNotEmpty, reason: code);
            expect(desc.trim(), isNot(code), reason: code);
            // The code chip only — never repeated as its own description.
            expect(find.text(code), findsOneWidget, reason: code);
            expect(find.text(desc), findsWidgets, reason: '$code: $desc');
            expect(desc, isNot(contains(tr('dtc_no_description', locale))));
            if (isAr) {
              expect(desc, matches(arabicScript), reason: '$code: $desc');
            }
            if (manufacturerRange.hasMatch(code)) {
              expect(
                desc,
                DtcRepository.manufacturerLabel(code, languageCode: lang),
                reason: code,
              );
              expect(desc, contains(code));
              if (isAr) {
                // Fully Arabic: no Latin word besides the code itself.
                expect(latinWord.hasMatch(desc), isFalse, reason: desc);
              } else {
                expect(desc, startsWith('Manufacturer-specific code'));
              }
            } else {
              expect(desc, isNot(contains('Manufacturer-specific')));
              expect(desc, isNot(contains('الشركة المصنعة')));
            }
          }
          expect(find.textContaining(RegExp(r'J1850|\bSCP\b')), findsNothing);
          expect(find.text(tr('dtc_no_description', locale)), findsNothing);
          final texts = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .toList();
          expect(texts.where((t) => t == 'null' || t.contains('~')), isEmpty);
        });

        if (isAr) {
          testWidgets(
            '${car.name} [ar]: SAE code descriptions are fully Arabic '
            '(acronyms aside)',
            (tester) async {
              final descs = await codesScreen(tester, car, ar);
              const acronyms = {
                'EGR',
                'MAF',
                'ECM',
                'PCM',
                'TCM',
                'CAN',
                'EVAP',
                'DPF',
                'ABS',
              };
              for (final code in car.dtcs.map(_code)) {
                if (manufacturerRange.hasMatch(code)) continue;
                final english = latinWord
                    .allMatches(descs[code]!)
                    .map((m) => m[0]!)
                    .where((w) => !acronyms.contains(w))
                    .toList();
                expect(english, isEmpty, reason: '$code: ${descs[code]}');
              }
            },
          );
        }

        testWidgets('${car.name} [$lang] 360x640: codes screen has no '
            'overflow', (tester) async {
          await codesScreen(tester, car, locale, size: smallPhone);
          for (var i = 0; i < 3; i++) {
            await tester.drag(
              find.byType(Scrollable).last,
              const Offset(0, -500),
            );
            await tester.pumpAndSettle();
          }
          expectNoException(tester);
          await unmount(tester);
        });
      }
    }

    for (final locale in _locales) {
      final lang = locale.languageCode;
      final isAr = lang == 'ar';

      // ── Hybrid / EV codes ──

      for (final car in [bydSongPlusDmi, bydAtto3]) {
        testWidgets('${car.name} [$lang]: hybrid P0Axx codes show the real '
            'description, not the generic fallback', (tester) async {
          final descs = await codesScreen(tester, car, locale);
          final hybrid = car.dtcs.map(_code).where((c) => c.startsWith('P0A'));
          expect(hybrid, isNotEmpty);
          for (final code in hybrid) {
            final desc = descs[code]!;
            expect(
              desc,
              isNot(DtcRepository.genericSaeLabel(code, languageCode: lang)),
            );
            // Generic labels embed the code; real descriptions don't.
            expect(desc, isNot(contains(code)), reason: desc);
            expect(desc, isNot(contains('offline')));
            expect(desc, contains(isAr ? 'الهجين' : 'Hybrid'), reason: desc);
            expect(find.text(desc), findsWidgets);
          }
        });
      }

      testWidgets(
        'BYD Song Plus DM-i [$lang]: P0A80 reads '
        '"${isAr ? 'استبدال حزمة بطارية الهجين' : 'Replace Hybrid Battery Pack'}"',
        (tester) async {
          final descs = await codesScreen(tester, bydSongPlusDmi, locale);
          expect(
            descs['P0A80'],
            isAr ? 'استبدال حزمة بطارية الهجين' : 'Replace Hybrid Battery Pack',
          );
        },
      );

      // ── Export report ──

      testWidgets('BYD Song Plus DM-i [$lang]: exported report — hybrid '
          'text, manufacturer label, pending code, localized', (tester) async {
        final shares = captureShares(tester);
        final descs = await codesScreen(tester, bydSongPlusDmi, locale);

        await tester.tap(find.byIcon(Icons.share_outlined));
        await tester.pumpAndSettle();
        expectNoException(tester);

        expect(shares, hasLength(1));
        final args = shares.single.arguments as Map;
        final text = args['text'] as String;
        expect(text, contains(tr('report_title', locale)));
        expect(
          text,
          contains(tr('report_fault_codes', locale).replaceAll('{n}', '4')),
        );
        for (final c in ['P0A80', 'P0AA6', 'P1A00']) {
          expect(text, contains(c));
          expect(text, contains(descs[c]!));
        }
        expect(
          text,
          contains(
            '[${tr('report_pending_tag', locale)}] P0A7F  ${descs['P0A7F']}',
          ),
        );
        expect(
          text,
          contains(
            DtcRepository.manufacturerLabel('P1A00', languageCode: lang),
          ),
        );
        expect(text, isNot(contains('~')));
        expect(text, isNot(contains('J1850')));
        expect(text, contains(tr('report_generated_by', locale)));
        if (isAr) {
          expect(text, isNot(contains('Manufacturer-specific')));
          expect(text, isNot(contains('Hybrid')));
          expect(text, isNot(contains('FAULT CODES')));
        }
      });

      // ── Code detail ──

      testWidgets('Geely B1000 [$lang]: detail — no fabricated cause / cost '
          '/ time / related codes; body category, manufacturer type, '
          'confirmed', (tester) async {
        await codesScreen(tester, geelyCoolray, locale);
        await openCode(tester, 'B1000');
        final texts = detailTexts(tester);

        expect(texts.where((t) => t.contains(r'$')), isEmpty, reason: '$texts');
        expect(
          inDetail(find.text(tr('cause_o2_catalyst', locale))),
          findsNothing,
        );
        expect(
          texts.where(
            (t) => RegExp(
              r'\bO2\b|catalyst|oxygen|حفاز|الأكسجين',
              caseSensitive: false,
            ).hasMatch(t),
          ),
          isEmpty,
        );
        for (final related in ['P0171', 'P0174', 'P0430']) {
          expect(texts.where((t) => t.contains(related)), isEmpty);
        }
        expect(inDetail(find.text(tr('dtc_cat_b', locale))), findsOneWidget);
        expect(
          inDetail(find.text(tr('dtc_type_manufacturer', locale))),
          findsOneWidget,
        );
        // Manufacturer codes have no SAE subsystem to claim.
        expect(
          inDetail(find.text(tr('dtc_subsystem_label', locale))),
          findsNothing,
        );
        expect(
          inDetail(find.text(tr('dtc_status_confirmed', locale))),
          findsOneWidget,
        );
        expect(inDetail(find.text(tr('dtc_pending', locale))), findsNothing);
        expect(
          inDetail(find.text(tr('dtc_step_manufacturer', locale))),
          findsOneWidget,
        );
        expect(inDetail(find.text(tr('dtc_step_b', locale))), findsOneWidget);
        expect(inDetail(find.text(tr('dtc_step_p', locale))), findsNothing);
        if (isAr) {
          expect(texts.where((t) => t.contains('Manufacturer')), isEmpty);
        }
      });

      for (final (car, code, cat, sub) in [
        (changanCs75Plus, 'P0300', 'dtc_cat_p', 'dtc_sub_ignition'),
        (havalJolion, 'U0140', 'dtc_cat_u', 'dtc_sub_net_comm'),
        (bydSongPlusDmi, 'P0A80', 'dtc_cat_p', 'dtc_sub_hybrid'),
        (gwmPoerDiesel, 'P0087', 'dtc_cat_p', 'dtc_sub_fuel_air_aux'),
      ]) {
        testWidgets('${car.name} $code [$lang]: category / generic type / '
            'subsystem', (tester) async {
          await codesScreen(tester, car, locale);
          await openCode(tester, code);
          expect(inDetail(find.text(tr(cat, locale))), findsOneWidget);
          expect(
            inDetail(find.text(tr('dtc_type_generic', locale))),
            findsOneWidget,
          );
          expect(inDetail(find.text(tr(sub, locale))), findsOneWidget);
          expect(
            inDetail(find.text(tr('dtc_status_confirmed', locale))),
            findsOneWidget,
          );
          expect(detailTexts(tester).where((t) => t.contains(r'$')), isEmpty);
        });
      }

      testWidgets('Changan ~P0171 [$lang]: detail shows the Pending label, '
          'status and pending step', (tester) async {
        await codesScreen(tester, changanCs75Plus, locale);
        await openCode(tester, 'P0171');
        expect(inDetail(find.text('P0171')), findsOneWidget);
        expect(inDetail(find.textContaining('~')), findsNothing);
        expect(inDetail(find.text(tr('dtc_pending', locale))), findsOneWidget);
        expect(
          inDetail(find.text(tr('dtc_status_pending', locale))),
          findsOneWidget,
        );
        expect(
          inDetail(find.text(tr('dtc_status_confirmed', locale))),
          findsNothing,
        );
        expect(
          inDetail(find.text(tr('dtc_step_pending', locale))),
          findsOneWidget,
        );
        expect(
          inDetail(find.text(tr('dtc_sub_fuel_air', locale))),
          findsOneWidget,
        );
      });

      testWidgets('Changan ~P0171 [$lang] 360x640: detail has no overflow', (
        tester,
      ) async {
        await codesScreen(tester, changanCs75Plus, locale, size: smallPhone);
        await openCode(tester, 'P0171');
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expectNoException(tester);
      });

      testWidgets('Geely B1000 [$lang]: detail share sends the localized '
          'code summary', (tester) async {
        final shares = captureShares(tester);
        final descs = await codesScreen(tester, geelyCoolray, locale);
        await openCode(tester, 'B1000');
        await tester.tap(inDetail(find.byIcon(Icons.share_outlined)));
        await tester.pumpAndSettle();
        expectNoException(tester);
        expect(shares, hasLength(1));
        final text = (shares.single.arguments as Map)['text'] as String;
        expect(text, startsWith('B1000 — ${descs['B1000']}'));
        expect(text, contains(tr('dtc_cat_b', locale)));
        expect(text, contains(tr('dtc_type_manufacturer', locale)));
        expect(text, contains(tr('dtc_status_confirmed', locale)));
        expect(text, isNot(contains(r'$')));
        if (isAr) expect(text, isNot(contains('Manufacturer-specific')));
      });

      // ── Steering lamp ──

      for (final (car, codes) in [
        (cheryTiggo8Pro, ['C1201']),
        (geelyCoolray, ['C1000']),
        (geelyCoolray, ['C1000', 'C1201', 'C2100']),
      ]) {
        testWidgets('${car.name} $codes [$lang]: manufacturer C-codes leave '
            'the steering lamp off', (tester) async {
          await showCar(tester, car.withDtcs(codes), locale);
          expect(lit(tester, 'steering', locale), isFalse);
          expect(lit(tester, 'abs', locale), isFalse);
          expect(lit(tester, 'traction', locale), isFalse);
          // Still counted as fault codes on the health card.
          expect(
            find.text(
              tr(
                codes.length == 1 ? 'dash_fault_code_n' : 'dash_fault_codes_n',
                locale,
              ).replaceAll('{n}', '${codes.length}'),
            ),
            findsOneWidget,
          );
          await unmount(tester);
        });
      }

      for (final code in ['C0365', 'C0710', 'C0191']) {
        testWidgets('$code [$lang]: an SAE steering code lights the steering '
            'lamp (and not ABS / traction)', (tester) async {
          await showCar(tester, cheryTiggo8Pro.withDtcs([code]), locale);
          expect(lit(tester, 'steering', locale), isTrue);
          expect(lit(tester, 'abs', locale), isFalse);
          expect(lit(tester, 'traction', locale), isFalse);
          await unmount(tester);
        });
      }

      testWidgets('C0035 [$lang]: an ABS code lights ABS, not steering', (
        tester,
      ) async {
        await showCar(tester, cheryTiggo8Pro.withDtcs(['C0035']), locale);
        expect(lit(tester, 'abs', locale), isTrue);
        expect(lit(tester, 'steering', locale), isFalse);
        await unmount(tester);
      });

      for (final code in ['C0455', 'C0460', 'C0470', 'C0196', 'C0379']) {
        testWidgets(
          '$code [$lang]: a brake / suspension / yaw-rate / drive-shaft code '
          '(per the bundled DTC database) does not light the steering lamp',
          (tester) async {
            await showCar(tester, cheryTiggo8Pro.withDtcs([code]), locale);
            expect(lit(tester, 'steering', locale), isFalse);
            await unmount(tester);
          },
        );
      }

      // ── Connection screen: EV vs ignition message ──

      Future<void> failConnect(
        WidgetTester tester,
        OBDFailureReason reason,
      ) async {
        fake.dispose();
        fake = ChineseCarAdapter(bydAtto3);
        OBDService.setTestAdapter(fake);
        await pumpScreen(tester, const ConnectionScreen(), locale: locale);
        fake.failReason = reason;
        await OBDService.instance.initialize(FakeDevice([]));
        await tester.pump();
        expectNoException(tester);
      }

      testWidgets('[$lang] noStandardObdData → EV message, not the ignition '
          'one', (tester) async {
        await failConnect(tester, OBDFailureReason.noStandardObdData);
        expect(find.text(tr('obd_err_no_std_obd', locale)), findsOneWidget);
        final sub = tr('obd_err_no_std_obd_sub', locale);
        expect(find.text(sub), findsOneWidget);
        expect(sub, contains(isAr ? 'الكهربائية' : 'electric vehicles'));
        expect(find.byIcon(Icons.electric_car), findsWidgets);
        expect(find.text(tr('obd_err_ecu_silent', locale)), findsNothing);
        expect(find.text(tr('obd_err_ecu_silent_sub', locale)), findsNothing);
        expect(find.text(tr('btn_retry', locale)), findsOneWidget);
        await unmount(tester);
      });

      testWidgets('[$lang] ecuNotResponding → ignition / READY message, not '
          'the EV one', (tester) async {
        await failConnect(tester, OBDFailureReason.ecuNotResponding);
        expect(find.text(tr('obd_err_ecu_silent', locale)), findsOneWidget);
        final sub = tr('obd_err_ecu_silent_sub', locale);
        expect(find.text(sub), findsOneWidget);
        expect(sub, contains(isAr ? 'الإشعال' : 'ignition'));
        expect(sub, contains('READY'));
        expect(find.text(tr('obd_err_no_std_obd', locale)), findsNothing);
        expect(find.byIcon(Icons.electric_car), findsNothing);
        await unmount(tester);
      });
    }
  });
}
