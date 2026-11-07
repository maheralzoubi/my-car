import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/app_services.dart';
import 'package:mycar/core/constants/app_routes.dart';
import 'package:mycar/core/bloc/locale/locale_bloc.dart';
import 'package:mycar/core/theme/app_theme.dart';
import 'package:mycar/core/widgets/app_button.dart';
import 'package:mycar/modules/home/presentation/pages/authScreen/auth_screen.dart';

import '../roadside/helpers/roadside_fakes.dart'
    show FakeHttpAdapter, FakeReply;
import 'helpers/screen_harness.dart';

// AuthScreen talks to the backend through AppServices.instance (not
// injectable), so the fakes sit at the transport level: the shared Dio's
// HttpClientAdapter and the secure-storage platform channel.

const _secureStorage = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

late FakeHttpAdapter _http;
late Map<String, String> _stored;

Future<void> _pump(
  WidgetTester tester, {
  Locale locale = en,
  Size size = phonePortrait,
  RecordingObserver? observer,
  ThemeData? theme,
}) => pumpScreen(
  tester,
  const AuthScreen(),
  locale: locale,
  size: size,
  observer: observer,
  theme: theme,
);

/// The fields of the visible form (only one form is shown at a time).
Finder get _fields => find.byType(TextFormField);

/// The visible form's primary button: 'auth_sign_in' on the sign-in form,
/// 'auth_create_account' on the sign-up form. (Each label also appears on
/// the secondary switch button of the *other* form, never on the same one.)
Finder _submit(String key, [Locale l = en]) =>
    find.widgetWithText(AppButton, tr(key, l));

/// Taps the secondary "Create an account" button under the sign-in form.
Future<void> _openSignup(WidgetTester tester, [Locale l = en]) async {
  final toSignup = find.widgetWithText(AppButton, tr('auth_create_account', l));
  await tester.ensureVisible(toSignup);
  await tester.tap(toSignup);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  setUp(() {
    _http = FakeHttpAdapter();
    AppServices.instance.apiClient.dio.httpClientAdapter = _http;
    _stored = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
          final args = (call.arguments as Map?) ?? {};
          switch (call.method) {
            case 'write':
              _stored[args['key'] as String] = args['value'] as String;
            case 'read':
              return _stored[args['key']];
            case 'deleteAll':
              _stored.clear();
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
      testWidgets('renders the login tab (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        expectNoException(tester);

        // Was: CARDIAG wordmark, tagline and LOGIN / SIGN UP tabs. The
        // redesign shows a title + subtitle, and a secondary button under
        // the form switches to sign-up.
        expect(find.text(tr('welcome_back', locale)), findsOneWidget);
        expect(find.text(tr('auth_welcome_subtitle', locale)), findsOneWidget);
        expect(find.text(tr('auth_new_to', locale)), findsOneWidget);
        expect(
          find.widgetWithText(AppButton, tr('auth_create_account', locale)),
          findsOneWidget,
        );
        expect(find.text(tr('email', locale)), findsOneWidget);
        expect(find.text(tr('password', locale)), findsOneWidget);
        expect(find.text(tr('forgot_password', locale)), findsOneWidget);
        expect(_submit('auth_sign_in', locale), findsOneWidget);
        expect(
          directionAt(tester, find.byType(AuthScreen)),
          locale == ar ? TextDirection.rtl : TextDirection.ltr,
        );
      });

      testWidgets('renders the sign-up tab (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale);
        await _openSignup(tester, locale);
        expectNoException(tester);

        for (final key in [
          'full_name',
          'email',
          'phone',
          'password',
          'confirm_password',
        ]) {
          expect(find.text(tr(key, locale)), findsOneWidget, reason: key);
        }
        expect(_submit('auth_create_account', locale), findsOneWidget);
        expect(find.text(tr('join_cardiag', locale)), findsOneWidget);
        // The secondary button switches back to sign-in.
        expect(_submit('auth_sign_in', locale), findsOneWidget);
        await tester.ensureVisible(_submit('auth_sign_in', locale));
        await tester.tap(_submit('auth_sign_in', locale));
        await tester.pumpAndSettle();
        expect(find.text(tr('welcome_back', locale)), findsOneWidget);
        expect(_fields, findsNWidgets(2));
      });

      testWidgets('light theme, both forms (${locale.languageCode})', (
        tester,
      ) async {
        await _pump(tester, locale: locale, theme: AppTheme.light);
        expectNoException(tester);
        await _openSignup(tester, locale);
        expectNoException(tester);
        expect(_fields, findsNWidgets(5));
      });
    }

    testWidgets('language switch asks the app to change locale', (
      tester,
    ) async {
      final bloc = LocaleBloc();
      addTearDown(bloc.close);
      await pumpScreen(
        tester,
        BlocProvider.value(value: bloc, child: const AuthScreen()),
      );
      // English UI offers Arabic by its own name.
      await tester.ensureVisible(find.text('العربية'));
      await tester.tap(find.text('العربية'));
      await tester.pump();
      expect(bloc.state.locale.languageCode, 'ar');
    });

    testWidgets('language switch without an app locale bloc is a no-op', (
      tester,
    ) async {
      await _pump(tester, locale: ar);
      await tester.ensureVisible(find.text('English'));
      await tester.tap(find.text('English'));
      await tester.pump();
      expectNoException(tester);
    });

    testWidgets('small phone, Arabic, both tabs: no overflow', (tester) async {
      await _pump(tester, locale: ar, size: smallPhone);
      expectNoException(tester);
      await _openSignup(tester, ar);
      expectNoException(tester);
    });

    testWidgets('Arabic UI shows no untranslated English copy', (tester) async {
      await _pump(tester, locale: ar);
      // 'English' is the language switch, named in its own language.
      expect(englishLeaks(tester, allow: {'English'}), isEmpty);
      await _openSignup(tester, ar);
      expect(englishLeaks(tester, allow: {'English'}), isEmpty);
    });
  });

  group('login validation', () {
    testWidgets('empty form shows both errors and sends nothing', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(_submit('auth_sign_in'));
      await tester.pump();

      expect(find.text(tr('enter_email')), findsOneWidget);
      expect(find.text(tr('enter_password')), findsOneWidget);
      expect(_http.requests, isEmpty);
    });

    testWidgets('email without @ is rejected', (tester) async {
      await _pump(tester);
      await tester.enterText(_fields.at(0), 'driver.example.com');
      await tester.enterText(_fields.at(1), 'secret1');
      await tester.tap(_submit('auth_sign_in'));
      await tester.pump();

      expect(find.text(tr('invalid_email')), findsOneWidget);
      expect(_http.requests, isEmpty);
    });

    testWidgets('errors are localized in Arabic', (tester) async {
      await _pump(tester, locale: ar);
      await tester.tap(_submit('auth_sign_in', ar));
      await tester.pump();
      expect(find.text(tr('enter_email', ar)), findsOneWidget);
      expectNoException(tester);
    });

    testWidgets('password visibility toggles', (tester) async {
      await _pump(tester);
      EditableText field() => tester.widget<EditableText>(
        find.descendant(of: _fields.at(1), matching: find.byType(EditableText)),
      );

      expect(field().obscureText, isTrue);
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pump();
      expect(field().obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('login request', () {
    Future<void> fillAndSubmit(WidgetTester tester) async {
      await tester.enterText(_fields.at(0), '  driver@example.com ');
      await tester.enterText(_fields.at(1), 'secret1');
      await tester.tap(_submit('auth_sign_in'));
      await tester.pump();
    }

    testWidgets('server error is shown in a snackbar; stays on auth', (
      tester,
    ) async {
      _http.reply('POST', '/auth/login', 401, {
        'message': 'Invalid credentials',
      });
      final observer = RecordingObserver();
      await _pump(tester, observer: observer);
      await fillAndSubmit(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Invalid credentials'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(observer.pushedNames, isNot(contains(AppRoutes.shell)));
      // Button is usable again.
      expect(
        tester.widget<AppButton>(_submit('auth_sign_in')).onPressed,
        isNotNull,
      );

      final req = _http.requests.single;
      expect(req.method, 'POST');
      expect(req.body, {
        'email': 'driver@example.com',
        'password': 'secret1',
        'role': 'customer',
      });
    });

    testWidgets('shows a spinner and disables the button while waiting', (
      tester,
    ) async {
      _http.on('POST', '/auth/login', (_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return FakeReply(401, {'message': 'nope'});
      });
      await _pump(tester);
      await fillAndSubmit(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final button = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(AppButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<AppButton>(button).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('network failure message is localized in Arabic', (
      tester,
    ) async {
      _http.on(
        'POST',
        '/auth/login',
        (o) => throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        ),
      );
      await _pump(tester, locale: ar);
      await tester.enterText(_fields.at(0), 'driver@example.com');
      await tester.enterText(_fields.at(1), 'secret1');
      await tester.tap(_submit('auth_sign_in', ar));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(englishLeaks(tester, allow: {'English'}), isEmpty);
    });
  });

  group('sign-up validation', () {
    testWidgets('empty form shows every required-field error', (tester) async {
      await _pump(tester);
      await _openSignup(tester);
      await tester.ensureVisible(_submit('auth_create_account'));
      await tester.tap(_submit('auth_create_account'));
      await tester.pump();

      expect(find.text(tr('enter_full_name')), findsOneWidget);
      expect(find.text(tr('enter_email')), findsOneWidget);
      expect(find.text(tr('enter_phone')), findsOneWidget);
      expect(find.text(tr('enter_password')), findsOneWidget);
      expect(find.text(tr('confirm_your_password')), findsOneWidget);
      expect(_http.requests, isEmpty);
    });

    Future<void> fill(
      WidgetTester tester, {
      String password = 'secret1',
      String confirm = 'secret1',
    }) async {
      // Only the visible form is in the tree: the sign-up form owns these
      // five.
      final f = _fields;
      final n = f.evaluate().length;
      final base = n - 5;
      await tester.enterText(f.at(base + 0), 'Jane Tester');
      await tester.enterText(f.at(base + 1), 'jane@example.com');
      await tester.enterText(f.at(base + 2), '+962700000000');
      await tester.enterText(f.at(base + 3), password);
      await tester.enterText(f.at(base + 4), confirm);
      await tester.ensureVisible(_submit('auth_create_account'));
      await tester.tap(_submit('auth_create_account'));
      await tester.pump();
    }

    testWidgets('short password is rejected', (tester) async {
      await _pump(tester);
      await _openSignup(tester);
      await fill(tester, password: '123', confirm: '123');
      expect(find.text(tr('password_too_short')), findsOneWidget);
      expect(_http.requests, isEmpty);
    });

    testWidgets('mismatched confirmation is rejected', (tester) async {
      await _pump(tester);
      await _openSignup(tester);
      await fill(tester, confirm: 'secret2');
      expect(find.text(tr('passwords_do_not_match')), findsOneWidget);
      expect(_http.requests, isEmpty);
    });

    testWidgets('server rejection is shown in a snackbar', (tester) async {
      _http.reply('POST', '/auth/register', 409, {
        'message': 'Email already in use',
      });
      await _pump(tester);
      await _openSignup(tester);
      await fill(tester);
      await tester.pumpAndSettle();

      expect(find.text('Email already in use'), findsOneWidget);
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(_http.requests.single.body, {
        'email': 'jane@example.com',
        'password': 'secret1',
        'role': 'customer',
        'name': 'Jane Tester',
        'phone': '+962700000000',
      });
    });
  });

  group('forgot password', () {
    // Was 'opens a reset flow' (any pushed route). The backend has no
    // password-reset endpoint, so the correct behaviour is an honest
    // explanation, not a reset flow; the test now pins that down.
    for (final locale in [en, ar]) {
      testWidgets('explains that reset is unavailable '
          '(${locale.languageCode})', (tester) async {
        final observer = RecordingObserver();
        await _pump(tester, locale: locale, observer: observer);
        final before = observer.pushed.length;
        await tester.tap(find.text(tr('forgot_password', locale)));
        await tester.pumpAndSettle();

        expect(observer.pushed.length, greaterThan(before));
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(tr('forgot_password_title', locale)), findsOneWidget);
        expect(
          find.text(tr('forgot_password_unavailable', locale)),
          findsOneWidget,
        );
        // Nothing is sent and no "email sent" style success is claimed.
        expect(_http.requests, isEmpty);
        if (locale == ar) expect(englishLeaks(tester, allow: {'English'}), isEmpty);

        await tester.tap(find.text(tr('ok', locale)));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(AuthScreen), findsOneWidget);
      });
    }
  });

  // Independent re-check of the "malformed auth response" fix: whatever
  // the server sends, the user sees a localized message, the session stays
  // empty and nothing crashes.
  group('double-check', () {
    /// Answers every request with [raw] as-is (no JSON encoding).
    void serveRaw(int status, String raw, {String contentType = 'json'}) {
      AppServices.instance.apiClient.dio.httpClientAdapter = _RawAdapter(
        status,
        raw,
        contentType == 'json' ? Headers.jsonContentType : contentType,
      );
    }

    Future<void> login(WidgetTester tester, Locale l) async {
      await tester.enterText(_fields.at(0), 'driver@example.com');
      await tester.enterText(_fields.at(1), 'secret1');
      await tester.tap(_submit('auth_sign_in', l));
      await tester.pumpAndSettle();
    }

    void expectRejected(WidgetTester tester, String key, Locale l) {
      expectNoException(tester);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(tr(key, l)),
        ),
        findsOneWidget,
        reason: key,
      );
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(AppServices.instance.session.isLoggedIn, isFalse);
      expect(AppServices.instance.session.token, isNull);
      expect(_stored, isEmpty);
      expect(
        tester.widget<AppButton>(_submit('auth_sign_in', l)).onPressed,
        isNotNull,
      );
      if (l == ar) expect(englishLeaks(tester, allow: {'English'}), isEmpty);
    }

    const user = {
      'id': 'u-1',
      'name': 'Jane',
      'email': 'jane@example.com',
      'phone': '+962700000000',
    };

    final cases = <(String, int, String, String, String)>[
      // name, status, body, content type, expected l10n key
      (
        'truncated JSON',
        200,
        '{"accessToken": "abc", "user": {',
        'json',
        'auth_err_generic',
      ),
      ('empty object', 200, '{}', 'json', 'auth_err_bad_response'),
      ('JSON array', 200, '[]', 'json', 'auth_err_bad_response'),
      ('JSON null', 200, 'null', 'json', 'auth_err_bad_response'),
      ('empty body', 200, '', 'json', 'auth_err_bad_response'),
      (
        'plain-text body',
        200,
        'OK',
        'text/plain; charset=utf-8',
        'auth_err_bad_response',
      ),
      (
        'numeric token',
        200,
        jsonEncode({'accessToken': 123, 'user': user}),
        'json',
        'auth_err_bad_response',
      ),
      (
        'empty token',
        200,
        jsonEncode({'accessToken': '', 'user': user}),
        'json',
        'auth_err_bad_response',
      ),
      (
        'user is a string',
        200,
        jsonEncode({'accessToken': 'abc', 'user': 'u-1'}),
        'json',
        'auth_err_bad_response',
      ),
      (
        'numeric user id',
        200,
        jsonEncode({
          'accessToken': 'abc',
          'user': {...user, 'id': 7},
        }),
        'json',
        'auth_err_bad_response',
      ),
      (
        'missing email',
        200,
        jsonEncode({
          'accessToken': 'abc',
          'user': {'id': 'u-1', 'name': 'Jane'},
        }),
        'json',
        'auth_err_bad_response',
      ),
      (
        '502 HTML error page',
        502,
        '<html><body>Bad Gateway</body></html>',
        'text/html',
        'auth_err_server',
      ),
      ('401 without message', 401, '{}', 'json', 'auth_err_unauthorized'),
      (
        '400 with blank message',
        400,
        '{"message": "  "}',
        'json',
        'auth_err_generic',
      ),
    ];

    for (final (name, status, body, type, key) in cases) {
      for (final locale in [en, ar]) {
        testWidgets('login, $name → $key (${locale.languageCode})', (
          tester,
        ) async {
          serveRaw(status, body, contentType: type);
          await _pump(tester, locale: locale);
          await login(tester, locale);
          expectRejected(tester, key, locale);
        });
      }
    }

    for (final locale in [en, ar]) {
      testWidgets('sign-up with a malformed reply is rejected the same way '
          '(${locale.languageCode})', (tester) async {
        serveRaw(201, '{"accessToken": "abc"}');
        await _pump(tester, locale: locale);
        await _openSignup(tester, locale);
        final f = _fields;
        final base = f.evaluate().length - 5;
        await tester.enterText(f.at(base + 0), 'Jane Tester');
        await tester.enterText(f.at(base + 1), 'jane@example.com');
        await tester.enterText(f.at(base + 2), '+962700000000');
        await tester.enterText(f.at(base + 3), 'secret1');
        await tester.enterText(f.at(base + 4), 'secret1');
        await tester.ensureVisible(_submit('auth_create_account', locale));
        await tester.tap(_submit('auth_create_account', locale));
        await tester.pumpAndSettle();

        expectNoException(tester);
        expect(find.text(tr('auth_err_bad_response', locale)), findsOneWidget);
        expect(AppServices.instance.session.isLoggedIn, isFalse);
        expect(_stored, isEmpty);
        if (locale == ar) expect(englishLeaks(tester, allow: {'English'}), isEmpty);
      });
    }

    for (final (type, key) in [
      (DioExceptionType.connectionTimeout, 'auth_err_timeout'),
      (DioExceptionType.receiveTimeout, 'auth_err_timeout'),
      (DioExceptionType.connectionError, 'auth_err_offline'),
      (DioExceptionType.badCertificate, 'auth_err_tls'),
    ]) {
      testWidgets('transport failure ${type.name} → $key (ar)', (tester) async {
        _http.on(
          'POST',
          '/auth/login',
          (o) => throw DioException(requestOptions: o, type: type),
        );
        await _pump(tester, locale: ar);
        await login(tester, ar);
        expectRejected(tester, key, ar);
      });
    }

    for (final locale in [en, ar]) {
      for (final size in [phonePortrait, smallPhone]) {
        testWidgets('no overflow ${size.width.toInt()}x${size.height.toInt()} '
            '(${locale.languageCode}), both tabs with errors', (tester) async {
          await _pump(tester, locale: locale, size: size);
          await tester.tap(_submit('auth_sign_in', locale));
          await tester.pumpAndSettle();
          expectNoException(tester);
          await _openSignup(tester, locale);
          await tester.ensureVisible(_submit('auth_create_account', locale));
          await tester.tap(_submit('auth_create_account', locale));
          await tester.pumpAndSettle();
          expectNoException(tester);
        });
      }
    }
  });
}

/// Serves one canned reply verbatim, so bodies that are not valid JSON can
/// reach the auth repository.
class _RawAdapter implements HttpClientAdapter {
  _RawAdapter(this.status, this.body, this.contentType);

  final int status;
  final String body;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
