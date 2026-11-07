// Light / dark × EN / AR render checks for the Diagnose screens: fault codes
// (not connected, codes + readiness), code detail, solution and DTC lookup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/solution_screen.dart';
import 'package:mycar/modules/home/presentation/pages/dtc_lookup_page.dart';

import '../helpers/fake_obd_adapter.dart';
import 'helpers/screen_harness.dart';

/// Reports readiness monitors and a freeze frame, unlike the base fake.
class _ReadinessFake extends FakeOBDAdapter {
  @override
  Future<ReadinessResult> getReadinessMonitors() async => const ReadinessResult(
    milOn: true,
    dtcCount: 2,
    monitors: [
      ReadinessMonitor(name: 'Misfire', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'Fuel System', status: MonitorStatus.ready),
      ReadinessMonitor(name: 'Catalyst', status: MonitorStatus.notReady),
      ReadinessMonitor(name: 'A/C System', status: MonitorStatus.notApplicable),
    ],
  );

  @override
  Future<Map<String, String>> getFreezeFrame() async => {
    'RPM': '850 rpm',
    'Speed': '0 km/h',
  };
}

Map<String, dynamic> _code() => {
  'code': 'P0420',
  'title': 'Catalyst System Efficiency Below Threshold (Bank 1)',
  'title_ar': 'كفاءة المحول الحفاز أقل من الحد (الضفة 1)',
  'severity': 'critical',
  'system': 'Engine',
  'system_ar': 'المحرك',
  'description': 'Catalyst System Efficiency Below Threshold (Bank 1)',
  'pending': true,
  'freeze_frame': {'RPM': '850 rpm', 'Speed': '0 km/h'},
};

void main() {
  setUpAll(loadAppFonts);

  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  for (final MapEntry(key: themeName, value: theme) in themes.entries) {
    for (final locale in [en, ar]) {
      final tag = '$themeName ${locale.languageCode}';

      group(tag, () {
        late FakeOBDAdapter fake;

        setUp(() {
          SharedPreferences.setMockInitialValues({});
          fake = _ReadinessFake();
          OBDService.setTestAdapter(fake);
        });

        tearDown(() => fake.dispose());

        testWidgets('fault codes: not connected', (tester) async {
          await pumpScreen(
            tester,
            DiagnosticCodesScreen(repository: FakeDtcRepository()),
            locale: locale,
            theme: theme,
            size: smallPhone,
          );
          expectNoException(tester);
          expect(find.text(tr('no_obd_connected', locale)), findsOneWidget);
        });

        testWidgets('fault codes: codes, readiness and monitors', (
          tester,
        ) async {
          fake.dtcsToReturn = ['P0420', '~P0171', 'C1201', 'U0100'];
          await OBDService.instance.initialize(MockBluetoothDevice());
          await pumpScreen(
            tester,
            DiagnosticCodesScreen(repository: FakeDtcRepository()),
            locale: locale,
            theme: theme,
            size: const Size(360, 1400),
          );
          await tester.pumpAndSettle();
          expectNoException(tester);

          expect(find.text('P0420'), findsOneWidget);
          expect(find.text(tr('emissions_readiness', locale)), findsOneWidget);
          expect(
            find.text(
              tr(
                'dtc_monitors_ready',
                locale,
              ).replaceAll('{ready}', '2').replaceAll('{total}', '3'),
            ),
            findsOneWidget,
          );
          // Header subtitle: "Last scan · <time>".
          expect(
            find.textContaining(
              tr('dtc_last_scan', locale).split('{time}').first,
            ),
            findsOneWidget,
          );

          // Per-monitor rows are behind "Show monitors".
          expect(find.text(tr('monitor_catalyst', locale)), findsNothing);
          await tester.tap(find.text(tr('dtc_show_monitors', locale)));
          await tester.pumpAndSettle();
          expect(find.text(tr('monitor_catalyst', locale)), findsOneWidget);
          expectNoException(tester);
          // (The fake repository's "Description for X" copy is test data.)
          if (locale == ar) {
            expect(
              englishLeaks(tester, allow: {'description', 'for'}),
              isEmpty,
            );
          }
        });

        testWidgets('code detail with freeze frame', (tester) async {
          await pumpScreen(
            tester,
            CodeDetailScreen(code: _code()),
            locale: locale,
            theme: theme,
            size: const Size(360, 1800),
          );
          expectNoException(tester);
          expect(find.text('850 rpm'), findsOneWidget);
          expect(find.text(tr('dtc_pending', locale)), findsOneWidget);
        });

        testWidgets('solution', (tester) async {
          await pumpScreen(
            tester,
            SolutionScreen(code: _code()),
            locale: locale,
            theme: theme,
            size: smallPhone,
          );
          expectNoException(tester);
          expect(find.text('P0420'), findsOneWidget);
        });

        testWidgets('DTC lookup: empty-code error', (tester) async {
          await pumpScreen(
            tester,
            const DtcLookupPage(),
            locale: locale,
            theme: theme,
            size: smallPhone,
          );
          expectNoException(tester);
          await tester.tap(find.text(tr('dtc_get_description', locale)));
          await tester.pump();
          expect(find.text(tr('dtc_enter_code_error', locale)), findsOneWidget);
          expectNoException(tester);
        });
      });
    }
  }
}
