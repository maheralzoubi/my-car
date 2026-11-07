// AppShell: the signed-in app's bottom navigation over the five top-level
// screens (Home · Diagnose · Roadside · History · Profile).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/bloc/locale/locale_bloc.dart';
import 'package:mycar/core/services/obd_service.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/home/presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'package:mycar/modules/home/presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';
import 'package:mycar/modules/home/presentation/pages/historyScreen/history_screen.dart';
import 'package:mycar/modules/home/presentation/pages/settingsScreen/settings_screen.dart';
import 'package:mycar/modules/home/presentation/pages/shell/app_shell.dart';
import 'package:mycar/modules/roadside/data/repositories/mock_roadside_repository.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/pages/roadside_home_screen.dart';

import '../flows/helpers/flow_harness.dart'
    show FakeBlePlatform, installPlatformFakes, pressBack;
import '../helpers/fake_obd_adapter.dart';
import 'helpers/screen_harness.dart';

/// Tab → (screen type, label key), in bottom-bar order.
const _tabs = <AppTab, (Type, String)>{
  AppTab.home: (DashboardScreen, 'nav_home'),
  AppTab.diagnose: (DiagnosticCodesScreen, 'nav_diagnose'),
  AppTab.roadside: (RoadsideHomeScreen, 'nav_roadside'),
  AppTab.history: (HistoryScreen, 'nav_history'),
  AppTab.profile: (SettingsScreen, 'nav_profile'),
};

Future<void> _pumpShell(
  WidgetTester tester, {
  Locale locale = en,
  ThemeData? theme,
  AppTab initialTab = AppTab.home,
}) async {
  // Created in the test body so its handlers run in the fake-async zone.
  final roadside = RoadsideBloc(MockRoadsideRepository());
  addTearDown(roadside.close);
  final localeBloc = LocaleBloc();
  addTearDown(localeBloc.close);
  await pumpScreen(
    tester,
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: localeBloc),
        BlocProvider.value(value: roadside),
      ],
      child: AppShell(initialTab: initialTab),
    ),
    locale: locale,
    theme: theme,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _navLabel(String key, [Locale l = en]) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.text(tr(key, l)),
);

int _selectedIndex(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

Future<void> _tapTab(WidgetTester tester, AppTab tab, [Locale l = en]) async {
  await tester.tap(_navLabel(_tabs[tab]!.$2, l));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Built screens, including tabs kept alive off-screen.
Finder _built(Type t) => find.byType(t, skipOffstage: false);

/// Drains timers (snackbars, polling, delayed loads) before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  setUpAll(() async {
    FakeBlePlatform.install();
    await loadAppFonts();
  });
  setUp(installPlatformFakes);

  late FakeOBDAdapter fake;
  setUp(() {
    fake = FakeOBDAdapter(); // not initialized: no vehicle link
    OBDService.setTestAdapter(fake);
  });
  tearDown(() => fake.dispose());

  group('tabs', () {
    for (final locale in [en, ar]) {
      testWidgets('five tabs with localized labels (${locale.languageCode})', (
        tester,
      ) async {
        await _pumpShell(tester, locale: locale);
        expectNoException(tester);
        expect(find.byType(NavigationDestination), findsNWidgets(5));
        for (final (_, key) in _tabs.values) {
          expect(_navLabel(key, locale), findsOneWidget, reason: key);
        }
        // Bottom-bar order matches AppTab.
        final labels = tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((d) => d.label)
            .toList();
        expect(labels, [for (final (_, k) in _tabs.values) tr(k, locale)]);
        expect(
          directionAt(tester, find.byType(NavigationBar)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
        if (locale == ar) {
          final navText = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(NavigationBar),
                  matching: find.byType(Text),
                ),
              )
              .map((t) => t.data ?? '');
          expect(
            navText.where((s) => RegExp('[A-Za-z]{3,}').hasMatch(s)),
            isEmpty,
          );
        }
        await _unmount(tester);
      });
    }

    testWidgets('opens on Home', (tester) async {
      await _pumpShell(tester);
      expect(_selectedIndex(tester), AppTab.home.index);
      expect(find.byType(DashboardScreen), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('initialTab opens that tab', (tester) async {
      await _pumpShell(tester, initialTab: AppTab.history);
      expect(_selectedIndex(tester), AppTab.history.index);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(_built(DashboardScreen), findsNothing);
      await _unmount(tester);
    });
  });

  group('switching', () {
    testWidgets('tapping a tab shows its screen and selects it', (
      tester,
    ) async {
      await _pumpShell(tester);
      for (final tab in [...AppTab.values.skip(1), AppTab.home]) {
        await _tapTab(tester, tab);
        expectNoException(tester);
        expect(_selectedIndex(tester), tab.index, reason: '$tab');
        final (screen, _) = _tabs[tab]!;
        expect(find.byType(screen), findsOneWidget, reason: '$screen shown');
        for (final other in _tabs.values.map((e) => e.$1)) {
          if (other == screen) continue;
          expect(find.byType(other), findsNothing, reason: '$other hidden');
        }
      }
      // Switching tabs pushes no route: the shell is the only page.
      expect(
        Navigator.of(tester.element(find.byType(AppShell))).canPop(),
        isFalse,
      );
      await _unmount(tester);
    });

    testWidgets('AppShell.maybeOf(context).goTo switches tabs', (
      tester,
    ) async {
      await _pumpShell(tester);
      final ctx = tester.element(find.byType(DashboardScreen));
      expect(AppShell.maybeOf(ctx), isNotNull);
      AppShell.maybeOf(ctx)!.goTo(AppTab.roadside);
      await tester.pump();
      expect(_selectedIndex(tester), AppTab.roadside.index);
      expect(find.byType(RoadsideHomeScreen), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('outside a shell maybeOf is null', (tester) async {
      await pumpScreen(tester, const Text('x'));
      expect(AppShell.maybeOf(tester.element(find.text('x'))), isNull);
    });
  });

  group('lazy tabs', () {
    testWidgets('only the opened tab is built; visited tabs stay alive', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(_built(DashboardScreen), findsOneWidget);
      for (final t in [
        DiagnosticCodesScreen,
        RoadsideHomeScreen,
        HistoryScreen,
        SettingsScreen,
      ]) {
        expect(_built(t), findsNothing, reason: '$t must not be built yet');
      }

      await _tapTab(tester, AppTab.history);
      expect(_built(HistoryScreen), findsOneWidget);
      expect(_built(DiagnosticCodesScreen), findsNothing);
      expect(_built(SettingsScreen), findsNothing);
      final historyState = tester.state(_built(HistoryScreen));
      final homeState = tester.state(_built(DashboardScreen));

      await _tapTab(tester, AppTab.home);
      // History is kept alive off-screen, with the same state.
      expect(find.byType(HistoryScreen), findsNothing);
      expect(_built(HistoryScreen), findsOneWidget);
      expect(tester.state(_built(DashboardScreen)), same(homeState));

      await _tapTab(tester, AppTab.history);
      expect(tester.state(_built(HistoryScreen)), same(historyState));
      expect(_built(RoadsideHomeScreen), findsNothing);
      await _unmount(tester);
    });
  });

  group('Android back', () {
    for (final tab in AppTab.values.skip(1)) {
      testWidgets('back on ${tab.name} returns to Home', (tester) async {
        await _pumpShell(tester);
        await _tapTab(tester, tab);
        expect(_selectedIndex(tester), tab.index);

        await pressBack(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(_selectedIndex(tester), AppTab.home.index);
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.byType(AppShell), findsOneWidget, reason: 'not popped');
        await _unmount(tester);
      });
    }

    // The dashboard (kept alive off-screen on the Home tab) registers its own
    // PopScope, so its "press back again to exit" fires too, and a second
    // Back within 2 s on Home then closes the app.
    testWidgets(
      'back on another tab does not show the exit hint',
      (tester) async {
        await _pumpShell(tester);
        await _tapTab(tester, AppTab.history);
        await pressBack(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(_selectedIndex(tester), AppTab.home.index);
        expect(find.text(tr('press_back_to_exit')), findsNothing);
        await _unmount(tester);
      },
    );

    testWidgets('back on a tab opened as initialTab also returns to Home', (
      tester,
    ) async {
      await _pumpShell(tester, initialTab: AppTab.profile);
      await pressBack(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_selectedIndex(tester), AppTab.home.index);
      expect(find.byType(DashboardScreen), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('themes', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final locale in [en, ar]) {
        testWidgets('every tab renders (${theme.brightness.name}, '
            '${locale.languageCode})', (tester) async {
          await _pumpShell(tester, locale: locale, theme: theme);
          expectNoException(tester);
          for (final tab in [...AppTab.values.skip(1), AppTab.home]) {
            await _tapTab(tester, tab, locale);
            expectNoException(tester);
            expect(find.byType(_tabs[tab]!.$1), findsOneWidget);
          }
          await _unmount(tester);
        });
      }
    }
  });
}
