import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/modules/home/presentation/pages/profileScreen/edit_profile_screen.dart';

import 'helpers/screen_harness.dart';

const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');
const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// In-memory secure storage behind the real [AppServices.instance.session].
late Map<String, String> _stored;

/// When set, every secure-storage write fails with this error.
PlatformException? _writeError;

/// The signed-in account the screen edits (the only way to reach it in the
/// app is from the profile of a logged-in user).
const _account = {
  'auth_token': 'jwt-abc',
  'auth_user_id': 'u-1',
  'auth_role': 'customer',
  'auth_name': 'Jane Tester',
  'auth_email': 'jane@example.com',
  'auth_phone': '+962700000000',
};

Future<void> _signIn([Map<String, String> account = _account]) async {
  _stored.addAll(account);
  await AppServices.instance.session.load();
}

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  bool pushed = false,
}) => pumpScreen(
  tester,
  const EditProfileScreen(),
  locale: locale,
  size: size,
  pushed: pushed,
);

/// Form fields, in order: name, email, phone, location.
Finder get _fields => find.byType(TextFormField);

String? _text(WidgetTester tester, int i) =>
    tester.widget<TextFormField>(_fields.at(i)).controller?.text;

Future<void> _save(WidgetTester tester, [Locale l = en]) async {
  await tapVisible(tester, find.text(tr('save_changes', l)));
}

/// Saves and waits out the minimum spinner time until the result dialog.
Future<void> _saveAndSettle(WidgetTester tester, [Locale l = en]) async {
  await _save(tester, l);
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

List<MethodCall> _mockPicker(
  WidgetTester tester,
  Future<Object?> Function(MethodCall) reply,
) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_imagePicker, (
    c,
  ) {
    calls.add(c);
    return reply(c);
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _imagePicker,
      null,
    ),
  );
  return calls;
}

Future<void> _openPasswordDialog(WidgetTester tester, [Locale l = en]) async {
  await tapVisible(tester, find.text(tr('update_your_password', l)));
  await tester.pumpAndSettle();
}

Finder get _passwordFields => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(loadAppFonts);

  setUp(() async {
    _stored = {};
    _writeError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
          final args = (call.arguments as Map?) ?? {};
          switch (call.method) {
            case 'read':
              return _stored[args['key']];
            case 'write':
              if (_writeError != null) throw _writeError!;
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
    await _signIn();
  });

  tearDown(() async {
    _writeError = null;
    await AppServices.instance.session.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  group('rendering', () {
    for (final locale in [en, ar]) {
      testWidgets('renders at phone size (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        for (final key in [
          'edit_profile',
          'full_name',
          'email_address',
          'phone',
          'location_label',
          'security',
          'change_password',
          'save_changes',
        ]) {
          expect(find.text(tr(key, locale)), findsWidgets, reason: key);
        }
        expect(_fields, findsNWidgets(4));
        expect(
          directionAt(tester, find.byType(EditProfileScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('small phone, Arabic: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
    });

    testWidgets('fields are pre-filled from the signed-in user', (
      tester,
    ) async {
      await _pump(tester);
      expect(_text(tester, 0), 'Jane Tester');
      expect(_text(tester, 1), 'jane@example.com');
      expect(_text(tester, 2), '+962700000000');
      expect(_text(tester, 3), isEmpty);
      expect(_text(tester, 0), isNot('John Doe'));
    });
  });

  group('validation', () {
    testWidgets('empty name is rejected', (tester) async {
      await _pump(tester);
      await tester.enterText(_fields.at(0), '');
      await _save(tester);

      expect(find.text(tr('please_enter_name')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('email without @ is rejected', (tester) async {
      await _pump(tester);
      await tester.enterText(_fields.at(1), 'not-an-email');
      await _save(tester);
      expect(find.text(tr('invalid_email')), findsOneWidget);
    });

    testWidgets('empty email and phone are rejected', (tester) async {
      await _pump(tester);
      await tester.enterText(_fields.at(1), '');
      await tester.enterText(_fields.at(2), '');
      await _save(tester);
      expect(find.text(tr('please_enter_email')), findsOneWidget);
      expect(find.text(tr('please_enter_phone')), findsOneWidget);
    });

    testWidgets('validation messages are localized in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      await tester.enterText(_fields.at(0), '');
      await _save(tester, ar);
      expect(find.text(tr('please_enter_name', ar)), findsOneWidget);
      expectNoException(tester);
    });
  });

  group('save', () {
    // Stale until the verifier pass: it ran with no session, so the
    // pre-filled email/phone were empty, validation failed and no spinner
    // ever appeared. With a signed-in user the flow runs as in the app.
    testWidgets('valid form: spinner, success dialog, done pops back', (
      tester,
    ) async {
      await _pump(tester, pushed: true);
      await tester.enterText(_fields.at(0), 'Jane Tester');
      await _save(tester);

      // Button shows a spinner and is disabled while saving.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(tr('success')), findsOneWidget);
      expect(find.text(tr('profile_updated')), findsOneWidget);
      // Honest about where it went: no profile endpoint on the backend.
      expect(find.text(tr('profile_saved_on_device')), findsOneWidget);

      await tester.tap(find.text(tr('done')));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text(launcherText), findsOneWidget);
    });

    testWidgets('leaving while saving does not throw', (tester) async {
      await _pump(tester, pushed: true);
      await _save(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expectNoException(tester);
      expect(find.text(tr('success')), findsNothing);
    });

    testWidgets('saved changes are kept', (tester) async {
      await _pump(tester, pushed: true);
      await tester.enterText(_fields.at(0), 'Jane Q. Tester');
      await tester.enterText(_fields.at(3), 'Irbid');
      await _saveAndSettle(tester);
      await tester.tap(find.text(tr('done')));
      await tester.pumpAndSettle();

      await _pump(tester);
      expect(_text(tester, 0), 'Jane Q. Tester');
      expect(_text(tester, 3), 'Irbid');
    });
  });

  group('change password', () {
    testWidgets('opens a dialog with three password fields; cancel closes', (
      tester,
    ) async {
      await _pump(tester);
      await _openPasswordDialog(tester);

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(_passwordFields, findsNWidgets(3));
      expect(find.text(tr('current_password')), findsOneWidget);
      expect(find.text(tr('new_password')), findsOneWidget);
      expect(find.text(tr('confirm_new_password')), findsOneWidget);

      await tester.tap(find.text(tr('cancel')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });

    testWidgets('mismatched passwords are rejected', (tester) async {
      await _pump(tester);
      await _openPasswordDialog(tester);

      await tester.enterText(_passwordFields.at(0), 'old-secret');
      await tester.enterText(_passwordFields.at(1), 'new-secret-1');
      await tester.enterText(_passwordFields.at(2), 'new-secret-2');
      await tester.tap(find.text(tr('update')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(tr('passwords_do_not_match')), findsOneWidget);
    });
  });

  group('avatar', () {
    testWidgets('camera button opens the picture options sheet', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();

      expect(find.text(tr('change_profile_picture')), findsOneWidget);
      expect(find.text(tr('take_photo')), findsOneWidget);
      expect(find.text(tr('choose_from_gallery')), findsOneWidget);
      expect(find.text(tr('remove_photo')), findsOneWidget);

      await tester.tap(find.text(tr('remove_photo')));
      await tester.pumpAndSettle();
      expect(find.text(tr('change_profile_picture')), findsNothing);
    });

    testWidgets('"choose from gallery" opens the image picker', (tester) async {
      final calls = _mockPicker(tester, (_) async => null);

      await _pump(tester);
      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('choose_from_gallery')));
      await tester.pumpAndSettle();
      expect(calls, isNotEmpty);
    });
  });

  group('navigation', () {
    testWidgets('close button pops', (tester) async {
      await _pump(tester, pushed: true);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text(launcherText), findsOneWidget);
    });
  });

  // Independent re-check of the edit-profile fixes.
  group('double-check', () {
    testWidgets('save writes the trimmed profile to the session and secure '
        'storage, and leaves the token alone', (tester) async {
      await _pump(tester, pushed: true);
      await tester.enterText(_fields.at(0), '  Jane Q. Tester  ');
      await tester.enterText(_fields.at(1), ' jq@example.com ');
      await tester.enterText(_fields.at(2), ' +962799999999 ');
      await tester.enterText(_fields.at(3), ' Irbid ');
      await _saveAndSettle(tester);

      final s = AppServices.instance.session;
      expect(s.name, 'Jane Q. Tester');
      expect(s.email, 'jq@example.com');
      expect(s.phone, '+962799999999');
      expect(s.location, 'Irbid');
      expect(s.token, 'jwt-abc');
      expect(_stored['auth_name'], 'Jane Q. Tester');
      expect(_stored['auth_email'], 'jq@example.com');
      expect(_stored['auth_phone'], '+962799999999');
      expect(_stored['auth_location'], 'Irbid');
      expect(_stored['auth_token'], 'jwt-abc');
    });

    testWidgets('clearing the location removes it from storage', (
      tester,
    ) async {
      await _signIn({..._account, 'auth_location': 'Amman'});
      await _pump(tester, pushed: true);
      expect(_text(tester, 3), 'Amman');
      await tester.enterText(_fields.at(3), '   ');
      await _saveAndSettle(tester);
      expect(AppServices.instance.session.location, isNull);
      expect(_stored.containsKey('auth_location'), isFalse);
    });

    testWidgets('success dialog is honest in Arabic too (no English)', (
      tester,
    ) async {
      await _pump(tester, locale: ar, pushed: true);
      await _saveAndSettle(tester, ar);
      expect(find.text(tr('profile_saved_on_device', ar)), findsOneWidget);
      // The user's own data (Latin name/email) is allowed.
      expect(
        englishLeaks(
          tester,
          allow: {'Jane', 'Tester', 'jane', 'example', 'com'},
        ),
        isEmpty,
      );
    });

    testWidgets(
      'a save that could not be persisted is not reported as saved',
      (tester) async {
        _writeError = PlatformException(code: 'keystore', message: 'locked');
        await _pump(tester, pushed: true);
        await tester.enterText(_fields.at(0), 'Jane Q. Tester');
        await _saveAndSettle(tester);
        expect(find.text(tr('profile_saved_on_device')), findsNothing);
        expect(find.text(tr('success')), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(tr('profile_save_failed')),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a valid password change says "not available" — no fake '
        'success, nothing stored', (tester) async {
      final before = Map.of(_stored);
      await _pump(tester);
      await _openPasswordDialog(tester);
      // The dialog says up front that it can't be applied.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(tr('password_change_unavailable')),
        ),
        findsOneWidget,
      );
      await tester.enterText(_passwordFields.at(0), 'old-secret');
      await tester.enterText(_passwordFields.at(1), 'new-secret');
      await tester.enterText(_passwordFields.at(2), 'new-secret');
      await tester.tap(find.text(tr('update')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(tr('password_change_unavailable')),
        ),
        findsOneWidget,
      );
      expect(find.text(tr('success')), findsNothing);
      expect(_stored, before);
    });

    for (final (pw, confirm, key) in [
      ('', '', 'fill_all_password_fields'),
      ('12345', '12345', 'password_too_short'),
    ]) {
      testWidgets('password dialog rejects "$pw" → $key (ar)', (tester) async {
        await _pump(tester, locale: ar);
        await _openPasswordDialog(tester, ar);
        await tester.enterText(_passwordFields.at(0), pw.isEmpty ? '' : 'old');
        await tester.enterText(_passwordFields.at(1), pw);
        await tester.enterText(_passwordFields.at(2), confirm);
        await tester.tap(find.text(tr('update', ar)));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(tr(key, ar)), findsOneWidget);
        expect(englishLeaks(tester), isEmpty);
      });
    }

    testWidgets('cancelling the photo picker changes nothing', (tester) async {
      _mockPicker(tester, (_) async => null);
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('choose_from_gallery')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(AppServices.instance.profilePhoto.photo.value, isNull);
      expect(find.text('JT'), findsOneWidget);
    });

    testWidgets('a failing camera reports a localized error (ar)', (
      tester,
    ) async {
      final calls = _mockPicker(
        tester,
        (_) async => throw PlatformException(code: 'camera_access_denied'),
      );
      await _pump(tester, locale: ar);
      await tester.tap(find.byIcon(Icons.camera_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr('take_photo', ar)));
      await tester.pumpAndSettle();
      expect(calls.single.arguments['source'], 0); // camera
      expect(find.text(tr('photo_pick_failed', ar)), findsOneWidget);
      expect(AppServices.instance.profilePhoto.photo.value, isNull);
      expectNoException(tester);
    });

    for (final locale in [en, ar]) {
      testWidgets('guest sees empty fields, never a demo identity '
          '(${locale.languageCode})', (tester) async {
        await AppServices.instance.session.clear();
        await _pump(tester, locale: locale);
        for (var i = 0; i < 4; i++) {
          expect(_text(tester, i), isEmpty, reason: 'field $i');
        }
        expect(find.textContaining('John'), findsNothing);
        expect(find.textContaining('Doe'), findsNothing);
        expect(find.text('?'), findsOneWidget); // initials placeholder
        if (locale == ar) expect(englishLeaks(tester), isEmpty);
      });
    }

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}) with validation errors shown', (
          tester,
        ) async {
          await _pump(tester, locale: locale, size: size);
          for (var i = 0; i < 3; i++) {
            await tester.enterText(_fields.at(i), '');
          }
          await _save(tester, locale);
          await tester.pumpAndSettle();
          expectNoException(tester);
          expect(find.text(tr('please_enter_name', locale)), findsOneWidget);
        });
      }
    }
  });
}
