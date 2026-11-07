import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/modules/home/presentation/pages/profileScreen/profile_screen.dart';

import 'helpers/screen_harness.dart';

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

late Map<String, String> _stored;

Future<void> _signIn(Map<String, String> account) async {
  _stored.addAll(account);
  await AppServices.instance.session.load();
}

/// Seeds [n] completed scans in the on-device DTC history.
void _seedScans(int n) {
  SharedPreferences.setMockInitialValues({
    'dtc_history_v1': jsonEncode([
      for (var i = 0; i < n; i++)
        {
          'scannedAt': DateTime(2026, 1, 1 + i).toIso8601String(),
          'mileageKm': 1000.0 + i,
          'codes': i.isEven ? ['P0420'] : <String>[],
        },
    ]),
  });
}

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
  RecordingObserver? observer,
}) async {
  await pumpScreen(
    tester,
    const ProfileScreen(),
    locale: locale,
    size: size,
    pushed: pushed,
    observer: observer,
  );
  // Scan history loads asynchronously.
  await tester.pump();
}

Finder _statValue(String labelKey, [Locale l = en]) {
  final label = find.text(tr(labelKey, l));
  return find.descendant(
    of: find.ancestor(of: label, matching: find.byType(Column)).first,
    matching: find.byType(Text),
  );
}

// Stat values are rich text (value + optional unit), so read the span too.
List<String> _texts(WidgetTester tester, Finder f) => tester
    .widgetList<Text>(f)
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    _stored = {};
    _seedScans(0);
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
          }
          return null;
        });
  });

  tearDown(() async {
    await AppServices.instance.session.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('lays out at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);
      });

      testWidgets('renders every section (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);

        for (final key in [
          'my_profile',
          'edit_profile',
          'activity_stats',
          'total_scans',
          'videos_watched',
          'saved_codes',
          'personal_information',
          'email',
          'location_label',
          'member_since',
          'my_vehicles',
          'achievements',
        ]) {
          expect(find.text(tr(key, locale)), findsWidgets, reason: key);
        }
        expect(
          directionAt(tester, find.byType(ProfileScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('small phone, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    for (final locale in [en, ar]) {
      testWidgets('light theme renders, scrolled through '
          '(${locale.languageCode})', (tester) async {
        _seedScans(2);
        await pumpScreen(
          tester,
          const ProfileScreen(),
          locale: locale,
          theme: AppTheme.light,
        );
        await tester.pump();
        expectNoException(tester);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();
        expectNoException(tester);
      });
    }

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      expect(englishLeaks(tester), isEmpty);
    });

    testWidgets('shows the signed-in user', (tester) async {
      await _signIn({
        'auth_token': 't',
        'auth_name': 'Jane Tester',
        'auth_email': 'jane@example.com',
        'auth_phone': '+962700000000',
      });

      await _pump(tester);
      expect(find.text('Jane Tester'), findsOneWidget);
      // Header card + personal information row.
      expect(find.text('jane@example.com'), findsNWidgets(2));
      expect(find.text('John Doe'), findsNothing);
    });
  });

  group('navigation', () {
    testWidgets('edit profile button opens /edit-profile', (tester) async {
      final observer = RecordingObserver();
      await _pump(tester, observer: observer);

      await tapVisible(tester, find.text(tr('edit_profile')));
      await tester.pumpAndSettle();
      expect(observer.pushedNames.last, AppRoutes.editProfile);
      expect(find.text('route:${AppRoutes.editProfile}'), findsOneWidget);
    });

    testWidgets('back arrow pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  // Independent re-check of the "real data only" profile fix.
  group('double-check', () {
    for (final locale in [en, ar]) {
      testWidgets('guest: no demo identity, honest placeholders '
          '(${locale.languageCode})', (tester) async {
        await _pump(tester, locale: locale);

        expect(find.text(tr('profile_guest', locale)), findsOneWidget);
        // Email, phone and location.
        expect(find.text(tr('profile_not_set', locale)), findsNWidgets(3));
        // No account creation date in the login response.
        expect(find.text(tr('profile_not_available', locale)), findsOneWidget);
        expect(find.text(tr('profile_no_vehicles', locale)), findsOneWidget);
        for (final demo in [
          'John',
          'Doe',
          'San Francisco',
          'January 2024',
          'miles',
          'Toyota',
          'Honda',
          'Camry',
          'Civic',
        ]) {
          expect(find.textContaining(demo), findsNothing, reason: demo);
        }
        // Scans come from the (empty) history; the untracked stats say so.
        expect(
          _texts(tester, _statValue('total_scans', locale)),
          contains('0'),
        );
        expect(
          _texts(tester, _statValue('videos_watched', locale)),
          contains('—'),
        );
        expect(
          _texts(tester, _statValue('saved_codes', locale)),
          contains('—'),
        );
        expect(find.text('?'), findsOneWidget); // initials placeholder
      });
    }

    testWidgets('signed-in: every field comes from the session', (
      tester,
    ) async {
      await _signIn({
        'auth_token': 't',
        'auth_name': 'Jane Tester',
        'auth_email': 'jane@example.com',
        'auth_phone': '+962700000000',
        'auth_location': 'Irbid',
      });
      await _pump(tester);
      expect(find.text('Jane Tester'), findsOneWidget);
      // Header card + personal information row.
      expect(find.text('jane@example.com'), findsNWidgets(2));
      expect(find.text('+962700000000'), findsOneWidget);
      expect(find.text('Irbid'), findsOneWidget);
      expect(find.text('JT'), findsOneWidget);
      expect(find.text(tr('profile_not_set')), findsNothing);
      expect(find.text(tr('profile_guest')), findsNothing);
    });

    testWidgets('total scans counts the DTC history; "First Scan" unlocks', (
      tester,
    ) async {
      _seedScans(3);
      await _pump(tester, size: const Size(390, 2000));
      expect(_texts(tester, _statValue('total_scans')), contains('3'));
      // The unlocked badge is drawn fully opaque, the locked ones dimmed.
      final firstScan = find.ancestor(
        of: find.text(tr('ach_first_scan')),
        matching: find.byType(Column),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(of: firstScan.first, matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, 1.0);
      final locked = find.ancestor(
        of: find.text(tr('ach_pro_user')),
        matching: find.byType(Column),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: locked.first, matching: find.byType(Opacity)),
            )
            .opacity,
        lessThan(1.0),
      );
    });

    testWidgets('no scans: "First Scan" stays locked', (tester) async {
      await _pump(tester, size: const Size(390, 2000));
      final firstScan = find.ancestor(
        of: find.text(tr('ach_first_scan')),
        matching: find.byType(Column),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: firstScan.first,
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        lessThan(1.0),
      );
    });

    testWidgets('returning from edit profile shows the edited name', (
      tester,
    ) async {
      await _signIn({'auth_token': 't', 'auth_name': 'Jane Tester'});
      await _pump(tester);
      await tapVisible(tester, find.text(tr('edit_profile')));
      await tester.pumpAndSettle();

      // What EditProfileScreen does on save.
      await AppServices.instance.session.updateProfile(
        name: 'Jane Q. Tester',
        email: 'jq@example.com',
        phone: '+962799999999',
      );
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.text('Jane Q. Tester'), findsOneWidget);
      // Header card + personal information row.
      expect(find.text('jq@example.com'), findsNWidgets(2));
      expect(find.text('Jane Tester'), findsNothing);
    });

    testWidgets('a guest avatar is not badged as verified', (tester) async {
      await _pump(tester);
      expect(find.text(tr('profile_guest')), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsNothing);
    });

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), long data, 50 scans', (tester) async {
          _seedScans(50);
          await _signIn({
            'auth_token': 't',
            'auth_name': 'Maximiliana Alexandra Konstantinopoulou-Abdelrahman',
            'auth_email':
                'maximiliana.alexandra.konstantinopoulou@example-company.com',
            'auth_phone': '+962 7 9999 9999 ext. 12345',
            'auth_location': 'Al Jubeiha, Amman, Jordan — near the university',
          });
          await _pump(tester, locale: locale, size: size);
          expectNoException(tester);
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -4000),
          );
          await tester.pumpAndSettle();
          expectNoException(tester);
          // The badge strip scrolls sideways without overflowing.
          await tester.drag(
            find.text(tr('ach_first_scan', locale)),
            Offset(locale == ar ? 600 : -600, 0),
          );
          await tester.pumpAndSettle();
          expectNoException(tester);
        });
      }
    }
  });
}
