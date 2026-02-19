import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/constants/app_routes.dart';
import '../core/constants/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../modules/home/home_module.dart';
import '../modules/home/presentation/pages/diagnosticCodesScreen/code_detail_screen.dart';
import '../modules/home/presentation/pages/diagnosticCodesScreen/solution_screen.dart';
import '../modules/home/presentation/pages/profileScreen/edit_profile_screen.dart';
import '../modules/home/presentation/pages/videoTutorialsScreen/upload_video_screen.dart';
import '../modules/home/presentation/pages/videoTutorialsScreen/video_player_screen.dart';

/// Root application widget: theme, providers, and routes (splash → home).
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: HomeModule.providers,
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        initialRoute: AppRoutes.splash,
        routes: {
          AppRoutes.splash: (_) => HomeModule.splashPage,
          AppRoutes.auth: (_) => HomeModule.authPage,
          AppRoutes.home: (_) => HomeModule.homePage,
          AppRoutes.connectionscreen: (_) => HomeModule.connectionPage,
          AppRoutes.dashboard: (_) => HomeModule.dashboardPage,
          AppRoutes.diagnosticCodes: (_) => HomeModule.diagnosticCodesPage,
          AppRoutes.parentMode: (_) => HomeModule.parentModePage,
          AppRoutes.smartKey: (_) => HomeModule.smartKeyPage,
          AppRoutes.history: (_) => HomeModule.historyPage,
          AppRoutes.settings: (_) => HomeModule.settingsPage,
          AppRoutes.videoTutorials: (_) => HomeModule.videoTutorialsPage,
          AppRoutes.videoPlayer: (context) =>
              VideoPlayerScreen.fromContext(context),
          AppRoutes.uploadVideo: (_) => const UploadVideoScreen(),
          AppRoutes.profile: (_) => HomeModule.profilePage,
          AppRoutes.editProfile: (_) => const EditProfileScreen(),
          AppRoutes.codeDetail: (context) {
            final args = ModalRoute.of(context)?.settings.arguments
                as Map<String, dynamic>?;
            return CodeDetailScreen(
              code: args ?? <String, dynamic>{},
            );
          },
          AppRoutes.solution: (context) {
            final args = ModalRoute.of(context)?.settings.arguments
                as Map<String, dynamic>?;
            return SolutionScreen(
              code: args ?? <String, dynamic>{},
            );
          },
        },
      ),
    );
  }
}
