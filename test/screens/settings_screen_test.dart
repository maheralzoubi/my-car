import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/core/bloc/locale/locale_bloc.dart';
import 'package:mycar/core/bloc/locale/locale_event.dart';
import 'package:mycar/core/bloc/locale/locale_state.dart';
import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/network/api_config.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/home/presentation/pages/settingsScreen/dash_cam_settings_screen.dart';
import 'package:mycar/modules/home/presentation/pages/settingsScreen/settings_screen.dart';

import 'helpers/screen_harness.dart';

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The app shell with a live [LocaleBloc] driving MaterialApp.locale, as in
/// App, so the language selector's effect is observable.
Widget _localeShell(LocaleBloc bloc, RecordingObserver observer) {
  return BlocProvider<LocaleBloc>.value(
    value: bloc,
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      child: BlocBuilder<LocaleBloc, LocaleState>(
        builder: (_, state) => MaterialApp(
          theme: AppTheme.dark,
          locale: state.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          navigatorObservers: [observer],
          home: const _Launcher(),
          onGenerateRoute: (s) => MaterialPageRoute<dynamic>(
            settings: s,
            builder: (_) =>
                RouteStub(name: s.name ?? '', arguments: s.arguments),
          ),
        ),
      ),
    ),
  );
}

/// Pushes SettingsScreen on top of a launcher so back/logout can pop.
class _Launcher extends StatefulWidget {
  const _Launcher();
  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text(launcherText)));
}

late LocaleBloc _bloc;
late RecordingObserver _observer;
late Map<String, String> _stored;

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
}) async {
  setPhoneSurface(tester, size);
  _bloc = LocaleBloc()..add(ChangeLocale(locale));
  addTearDown(_bloc.close);
  _observer = RecordingObserver();
  await tester.pumpWidget(_localeShell(_bloc, _observer));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// The custom toggles, in order: notifications, auto scan, dark mode, sound.
Finder get _toggles => find.byType(AnimatedAlign);

bool _isOn(WidgetTester tester, int i) {
  final a = tester.widget<AnimatedAlign>(_toggles.at(i)).alignment;
  final dir = directionAt(tester, find.byType(SettingsScreen));
  return a.resolve(dir) == AlignmentDirectional.centerEnd.resolve(dir);
}

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    _stored = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
          final args = (call.arguments as Map?) ?? {};
          switch (call.method) {
            case 'read':
              return _stored[args['key']];
            case 'write':
              _stored[args['key'] as String] = args['value'] as String;
              return null;
            case 'delete':
              _stored.remove(args['key']);
              return null;
            case 'deleteAll':
              _stored.clear();
              return null;
            case 'readAll':
              return _stored;
            case 'containsKey':
              return _stored.containsKey(args['key']);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders every section (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'settings_title',
          'general',
          'preferences',
          'about',
          'danger_zone',
          'notifications',
          'auto_scan',
          'dark_mode',
          'sound_effects',
          'dash_cam',
          'dtc_lookup',
          'language',
          'units',
          'logout',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(
          directionAt(tester, find.byType(SettingsScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('phone size, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar);
      expectNoException(tester);
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      // Language names are shown in their own script by design.
      expect(englishLeaks(tester, allow: {'English'}), isEmpty);
    });
  });

  group('language', () {
    testWidgets('selector reflects the active locale', (tester) async {
      await _pump(tester, locale: ar);
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('English'), findsNothing);
    });

    testWidgets('choosing العربية switches the app to Arabic / RTL', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('English'), findsOneWidget);

      await tapVisible(tester, find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('${tr('select')} ${tr('language')}'), findsOneWidget);

      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();

      expect(_bloc.state.locale, ar);
      expect(find.text(tr('settings_title', ar)), findsOneWidget);
      expect(
        directionAt(tester, find.byType(SettingsScreen)),
        TextDirection.rtl,
      );
      expect(find.text('العربية'), findsOneWidget);
      expectNoException(tester);
    });

    testWidgets('and back to English', (tester) async {
      await _pump(tester, locale: ar);

      await tapVisible(tester, find.text('العربية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(_bloc.state.locale, en);
      expect(find.text(tr('settings_title')), findsOneWidget);
      expect(
        directionAt(tester, find.byType(SettingsScreen)),
        TextDirection.ltr,
      );
    });
  });

  group('preferences', () {
    testWidgets('units selector switches metric → imperial', (tester) async {
      await _pump(tester);
      expect(find.text(tr('units_metric')), findsOneWidget);

      await tapVisible(tester, find.text(tr('units_metric')));
      await tester.pumpAndSettle();
      // Current option is ticked.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, tr('units_metric')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(tr('units_imperial')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(tr('units_imperial')), findsOneWidget);
    });

    testWidgets('units options are localized in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      expect(find.text(tr('units_metric', ar)), findsOneWidget);
    });

    testWidgets('toggles flip on tap', (tester) async {
      await _pump(tester);
      expect(_toggles, findsNWidgets(4));
      final before = [for (var i = 0; i < 4; i++) _isOn(tester, i)];
      expect(before, [true, false, true, true]);

      for (var i = 0; i < 4; i++) {
        await tapVisible(tester, _toggles.at(i));
        await tester.pumpAndSettle();
      }
      expect(
        [for (var i = 0; i < 4; i++) _isOn(tester, i)],
        [false, true, false, false],
      );
    });

    testWidgets('toggles work in RTL (knob moves to the end side)', (
      tester,
    ) async {
      await _pump(tester, locale: ar);
      await tester.ensureVisible(_toggles.at(1));
      await tester.pumpAndSettle();
      final knob = find
          .descendant(of: _toggles.at(1), matching: find.byType(Container))
          .first;
      final offBox = tester.getRect(_toggles.at(1));
      final offKnob = tester.getCenter(knob);
      await tester.tap(_toggles.at(1));
      await tester.pumpAndSettle();
      final onKnob = tester.getCenter(knob);
      // In RTL "on" is the left (end) side.
      expect(onKnob.dx, lessThan(offKnob.dx));
      expect(offKnob.dx, greaterThan(offBox.center.dx));
    });

    testWidgets('toggle and unit choices survive leaving the screen', (
      tester,
    ) async {
      await _pump(tester);
      await tapVisible(tester, _toggles.at(1)); // auto scan → on
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(_isOn(tester, 1), isTrue);
    });
  });

  group('navigation', () {
    testWidgets('profile card opens /profile', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(_observer.pushedNames.last, AppRoutes.profile);
    });

    testWidgets('dash cam item opens DashCamSettingsScreen', (tester) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('dash_cam')));
      await tester.pumpAndSettle();
      expect(find.byType(DashCamSettingsScreen), findsOneWidget);
    });

    testWidgets('DTC lookup item opens /dtc-lookup', (tester) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('dtc_lookup')));
      await tester.pumpAndSettle();
      expect(_observer.pushedNames.last, AppRoutes.dtcLookup);
    });

    testWidgets('back arrow pops', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  group('logout', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tapVisible(tester, find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(find.text(tr('logout_confirm')), findsOneWidget);
      expect(find.text(tr('logout_confirm_msg')), findsOneWidget);
    }

    testWidgets('cancel closes the dialog and stays', (tester) async {
      await _pump(tester);
      await openDialog(tester);
      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('confirm clears the session and returns to the auth screen', (
      tester,
    ) async {
      _stored = {'auth_token': 't', 'auth_name': 'Jane'};
      await AppServices.instance.session.load();
      addTearDown(AppServices.instance.session.clear);
      await _pump(tester);
      await openDialog(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(tr('logout')),
        ),
      );
      await tester.pumpAndSettle();

      expect(AppServices.instance.session.isLoggedIn, isFalse);
      expect(_stored, isEmpty);
      expect(_observer.pushedNames.last, AppRoutes.auth);
      expect(find.byType(SettingsScreen), findsNothing);
      // Nothing to go "back" to after logging out.
      expect(find.text(launcherText), findsNothing);
    });

    testWidgets('profile card shows the signed-in user', (tester) async {
      _stored = {
        'auth_token': 't',
        'auth_name': 'Jane Tester',
        'auth_email': 'jane@example.com',
      };
      await AppServices.instance.session.load();
      addTearDown(AppServices.instance.session.clear);
      await _pump(tester);

      expect(find.text('Jane Tester'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
    });
  });

  // Independent re-check of the logout / profile / preferences fixes.
  group('double-check', () {
    /// A signed-in account with non-default preferences, all in the mocked
    /// secure storage the real [AppServices] reads.
    Future<void> seedAccount() async {
      _stored = {
        'auth_token': 'jwt-abc',
        'auth_user_id': 'u-1',
        'auth_role': 'customer',
        'auth_name': 'Jane Tester',
        'auth_email': 'jane@example.com',
        'auth_phone': '+962700000000',
        'auth_location': 'Amman',
        'pref_auto_scan': 'true',
        'pref_notifications': 'false',
        'pref_units': 'Imperial',
      };
      await AppServices.instance.session.load();
      addTearDown(AppServices.instance.session.clear);
    }

    Future<void> confirmLogout(WidgetTester tester, [Locale l = en]) async {
      await tapVisible(tester, find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(tr('logout', l)),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<bool> toggleStates(WidgetTester tester) => [
      for (var i = 0; i < 4; i++) _isOn(tester, i),
    ];

    Future<void> reopenSettings(WidgetTester tester) async {
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          );
      await tester.pumpAndSettle();
    }

    testWidgets('logout wipes token, profile and prefs, drops the socket, '
        'and leaves no way back into the app', (tester) async {
      await seedAccount();
      // Point the socket at a closed local port: never the deployed backend.
      ApiConfig.baseUrlOverride = 'http://127.0.0.1:9';
      addTearDown(() => ApiConfig.baseUrlOverride = null);
      final sockets = AppServices.instance.socketClient;
      sockets.connect();
      expect(() => sockets.socket, returnsNormally);

      final platform = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (c) async {
          platform.add(c);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(tester);
      expect(find.text('Jane Tester'), findsOneWidget);
      await confirmLogout(tester);

      final session = AppServices.instance.session;
      expect(session.isLoggedIn, isFalse);
      expect(session.token, isNull);
      expect(session.userId, isNull);
      expect(session.role, isNull);
      expect(session.name, isNull);
      expect(session.email, isNull);
      expect(session.phone, isNull);
      expect(session.location, isNull);
      // Secure storage holds nothing: no token, profile or preference.
      expect(_stored, isEmpty);
      // Socket disconnected (SocketClient drops its socket on disconnect).
      expect(() => sockets.socket, throwsStateError);

      expect(_observer.pushedNames.last, AppRoutes.auth);
      expect(find.text('route:${AppRoutes.auth}'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text(launcherText), findsNothing);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      expect(nav.canPop(), isFalse);

      // System back from the auth screen exits; it never re-enters the app.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('route:${AppRoutes.auth}'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text(launcherText), findsNothing);
      expect(
        platform.where((c) => c.method == 'SystemNavigator.pop'),
        isNotEmpty,
      );
    });

    testWidgets('logout also works from the Arabic UI', (tester) async {
      await seedAccount();
      await _pump(tester, locale: ar);
      await confirmLogout(tester, ar);
      expect(AppServices.instance.session.isLoggedIn, isFalse);
      expect(_stored, isEmpty);
      expect(find.text('route:${AppRoutes.auth}'), findsOneWidget);
      expectNoException(tester);
    });

    testWidgets('logout cancel keeps the session intact', (tester) async {
      await seedAccount();
      final before = Map.of(_stored);
      await _pump(tester);
      await tapVisible(tester, find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();
      expect(AppServices.instance.session.token, 'jwt-abc');
      expect(_stored, before);
    });

    testWidgets('saved preferences load on open, every change persists and '
        'survives a reopen', (tester) async {
      await seedAccount();
      await _pump(tester);
      // Seeded: notifications off, auto-scan on, units imperial.
      expect(toggleStates(tester), [false, true, true, true]);
      expect(find.text(tr('units_imperial')), findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tapVisible(tester, _toggles.at(i));
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, find.text(tr('units_imperial')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('units_metric')).last);
      await tester.pumpAndSettle();

      expect(_stored['pref_notifications'], 'true');
      expect(_stored['pref_auto_scan'], 'false');
      expect(_stored['pref_dark_mode'], 'false');
      expect(_stored['pref_sound_effects'], 'false');
      expect(_stored['pref_units'], 'Metric');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await reopenSettings(tester);
      expect(toggleStates(tester), [true, false, false, false]);
      expect(find.text(tr('units_metric')), findsOneWidget);
    });

    testWidgets('preferences reset to defaults after logout', (tester) async {
      await seedAccount();
      await _pump(tester);
      expect(toggleStates(tester), [false, true, true, true]);
      await confirmLogout(tester);

      await reopenSettings(tester);
      expect(toggleStates(tester), [true, false, true, true]);
      expect(find.text(tr('units_metric')), findsOneWidget);
      expect(find.text(tr('profile_guest')), findsOneWidget);
      expect(find.text('Jane Tester'), findsNothing);
    });

    testWidgets('corrupt stored preferences fall back to defaults', (
      tester,
    ) async {
      _stored = {
        'pref_notifications': 'yes',
        'pref_units': 'Furlongs',
        'pref_dark_mode': '',
      };
      await _pump(tester);
      expectNoException(tester);
      // Unparseable booleans read as false; unknown units → Metric.
      expect(find.text(tr('units_metric')), findsOneWidget);
      expect(find.text('Furlongs'), findsNothing);
    });

    for (final locale in [en, ar]) {
      testWidgets('guest card never shows a demo identity '
          '(${locale.languageCode})', (tester) async {
        await _pump(tester, locale: locale);
        expect(find.text(tr('profile_guest', locale)), findsOneWidget);
        expect(find.text(tr('profile_not_signed_in', locale)), findsOneWidget);
        expect(find.textContaining('John'), findsNothing);
        expect(find.textContaining('Doe'), findsNothing);
        expect(find.textContaining('@email.com'), findsNothing);
        // Initials avatar has no name to draw from.
        expect(find.text('JD'), findsNothing);
      });
    }

    testWidgets('signed-in card shows the user and their initials', (
      tester,
    ) async {
      await seedAccount();
      await _pump(tester);
      expect(find.text('Jane Tester'), findsOneWidget);
      expect(find.text('jane@example.com'), findsOneWidget);
      expect(find.text('JT'), findsOneWidget);
      expect(find.text(tr('profile_guest')), findsNothing);
    });

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), long account name', (tester) async {
          _stored = {
            'auth_token': 't',
            'auth_name': 'Maximiliana Alexandra Konstantinopoulou-Abdelrahman',
            'auth_email':
                'maximiliana.alexandra.konstantinopoulou@example-company.com',
          };
          await AppServices.instance.session.load();
          addTearDown(AppServices.instance.session.clear);
          await _pump(tester, locale: locale, size: size);
          expectNoException(tester);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expectNoException(tester);
        });
      }
    }

    testWidgets(
      'items with nothing behind them say so instead of a dead tap',
      (tester) async {
        await _pump(tester);
        for (final key in [
          'vehicle_profile',
          'data_privacy',
          'terms_of_service',
          'privacy_policy',
          'support',
        ]) {
          final pushedBefore = _observer.pushed.length;
          await tapVisible(tester, find.text(tr(key)));
          await tester.pumpAndSettle();
          final responded =
              _observer.pushed.length > pushedBefore ||
              find.byType(SnackBar).evaluate().isNotEmpty;
          expect(responded, isTrue, reason: key);
          // Close whatever opened before the next row.
          if (find.byType(SettingsScreen).evaluate().isEmpty ||
              find.byType(AlertDialog).evaluate().isNotEmpty) {
            await tester.pageBack();
            await tester.pumpAndSettle();
          }
          ScaffoldMessenger.of(
            tester.element(find.byType(SettingsScreen)),
          ).removeCurrentSnackBar();
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('Data & Privacy opens a summary of what the app stores and '
        'sends; the info-only rows explain they are not available', (
      tester,
    ) async {
      await _pump(tester);
      await tapVisible(tester, find.text(tr('data_privacy')));
      await tester.pumpAndSettle();
      for (final key in [
        'dp_secure_title',
        'dp_local_title',
        'dp_server_title',
        'dp_lookup_title',
        'dp_signout_title',
      ]) {
        expect(find.text(tr(key)), findsOneWidget, reason: key);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      for (final (row, message) in [
        ('vehicle_profile', 'vehicle_profile_unavailable'),
        ('terms_of_service', 'terms_unavailable'),
        ('privacy_policy', 'privacy_policy_unavailable'),
        ('support', 'support_unavailable'),
      ]) {
        await tapVisible(tester, find.text(tr(row)));
        await tester.pumpAndSettle();
        expect(find.text(tr(message)), findsOneWidget, reason: row);
        ScaffoldMessenger.of(
          tester.element(find.byType(SettingsScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
    });

    for (final locale in [en, ar]) {
      testWidgets('Data & Privacy: no overflow on a small phone '
          '(${locale.languageCode})', (tester) async {
        await _pump(tester, locale: locale, size: smallPhone);
        await tapVisible(tester, find.text(tr('data_privacy', locale)));
        await tester.pumpAndSettle();
        expectNoException(tester);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        expectNoException(tester);
        if (locale == ar) expect(englishLeaks(tester), isEmpty);
      });
    }
  });
}
