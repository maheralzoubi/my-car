import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_routes.dart';
import 'bloc/counter/counter_bloc.dart';
import 'presentation/pages/authScreen/auth_screen.dart';
import 'presentation/pages/connectionScreen/connection_screen.dart';
import 'presentation/pages/dashboardScreen/dashboard_screen.dart';
import 'presentation/pages/historyScreen/history_screen.dart';
import 'presentation/pages/diagnosticCodesScreen/diagnostic_codes_screen.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/pages/parentModeScreen/parent_mode_screen.dart';
import 'presentation/pages/settingsScreen/settings_screen.dart';
import 'presentation/pages/smartKeyScreen/smart_key_screen.dart';
import 'presentation/pages/spalchScreen/spalch_screen.dart';
import 'presentation/pages/videoTutorialsScreen/video_tutorials_screen.dart';

/// Home feature module: provides [CounterBloc], [SplashScreen], and [HomePage].
abstract final class HomeModule {
  HomeModule._();

  /// List of [BlocProvider]s required for the home feature.
  static List<BlocProvider> get providers => [
    BlocProvider<CounterBloc>(create: (_) => CounterBloc()),
  ];

  /// Splash screen (initial route).
  static Widget get splashPage => const SplashScreen();

  /// Auth screen (login / signup).
  static Widget get authPage => const AuthScreen();

  /// Home screen (after splash).
  static Widget get homePage => const HomePage();

  /// Connection screen.
  static Widget get connectionPage => const ConnectionScreen();

  /// Dashboard screen.
  static Widget get dashboardPage => const DashboardScreen();

  /// Diagnostic codes screen.
  static Widget get diagnosticCodesPage => const DiagnosticCodesScreen();

  /// Parent mode screen.
  static Widget get parentModePage => const ParentModeScreen();

  /// Smart key screen.
  static Widget get smartKeyPage => const SmartKeyScreen();

  /// History screen.
  static Widget get historyPage => const HistoryScreen();

  /// Settings screen.
  static Widget get settingsPage => const SettingsScreen();

  /// Video tutorials screen.
  static Widget get videoTutorialsPage => const VideoTutorialsScreen();

  /// Route names for app navigation.
  static const String splashRoute = AppRoutes.splash;
  static const String homeRoute = AppRoutes.home;
}
