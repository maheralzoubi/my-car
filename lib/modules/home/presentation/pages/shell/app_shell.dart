import 'package:flutter/material.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../roadside/presentation/pages/roadside_home_screen.dart';
import '../dashboardScreen/dashboard_screen.dart';
import '../diagnosticCodesScreen/diagnostic_codes_screen.dart';
import '../historyScreen/history_screen.dart';
import '../settingsScreen/settings_screen.dart';

/// The five top-level destinations, in bottom-bar order.
enum AppTab { home, diagnose, roadside, history, profile }

/// The signed-in app: a bottom navigation bar over the five top-level
/// screens. Each tab is built the first time it is opened and then kept
/// alive (so a scan or a roadside request survives switching tabs).
///
/// Screens can switch tabs with `AppShell.maybeOf(context)?.goTo(...)`.
/// Android back on any tab but Home returns to Home first.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = AppTab.home});

  final AppTab initialTab;

  /// The enclosing shell, or null when a screen is shown outside it (tests,
  /// pushed routes).
  static AppShellState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late AppTab _tab = widget.initialTab;
  late final Set<AppTab> _built = {widget.initialTab};

  /// Bumped on every visit to Diagnose: a fresh [DiagnosticCodesScreen]
  /// scans in `initState`, so each visit (and each Quick Scan, even while
  /// already on the tab) reads the car's current codes / connection state
  /// instead of showing the previous scan.
  int _diagnoseRun = 0;

  AppTab get tab => _tab;

  void goTo(AppTab tab) {
    if (tab == _tab && tab != AppTab.diagnose) return;
    setState(() {
      if (tab == AppTab.diagnose) _diagnoseRun++;
      _tab = tab;
      _built.add(tab);
    });
  }

  Widget _screen(AppTab tab) => switch (tab) {
    AppTab.home => const DashboardScreen(),
    AppTab.diagnose => DiagnosticCodesScreen(key: ValueKey(_diagnoseRun)),
    AppTab.roadside => const RoadsideHomeScreen(),
    AppTab.history => const HistoryScreen(),
    AppTab.profile => const SettingsScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return PopScope(
      canPop: _tab == AppTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goTo(AppTab.home);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab.index,
          children: [
            for (final t in AppTab.values)
              _built.contains(t)
                  ? TickerMode(enabled: t == _tab, child: _screen(t))
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: NavigationBar(
            selectedIndex: _tab.index,
            onDestinationSelected: (i) => goTo(AppTab.values[i]),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: context.tr('nav_home'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.monitor_heart_outlined),
                selectedIcon: const Icon(Icons.monitor_heart_rounded),
                label: context.tr('nav_diagnose'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.local_shipping_outlined),
                selectedIcon: const Icon(Icons.local_shipping_rounded),
                label: context.tr('nav_roadside'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.history_rounded),
                selectedIcon: const Icon(Icons.history_rounded),
                label: context.tr('nav_history'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline_rounded),
                selectedIcon: const Icon(Icons.person_rounded),
                label: context.tr('nav_profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
