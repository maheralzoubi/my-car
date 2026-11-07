import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/dtc_repository.dart';

// DtcRepository depends on:
//   * rootBundle  — the real assets/dtcmapping*.json (bundled by flutter test)
//   * connectivity_plus — mocked below; defaults to "offline"
//   * http — an injected MockClient; by default it answers HTTP 400 and
//     records every request so tests can assert what was (not) sent.
//   * SharedPreferences — mocked and reset before every test.
//
// Static caches are dropped with DtcRepository.resetCaches() in setUp, so
// tests are independent of execution order.

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

const _rapidHost = 'car-code.p.rapidapi.com';
const _myMemoryHost = 'api.mymemory.translated.net';

// SAE-defined codes that are NOT in the bundled database (the hybrid block
// is bundled up to P0C87; P0D2x battery-charger codes are not).
const _onlineCode = 'P0D27';
const _onlineCode2 = 'P0D28';

String _mfr(String code) => DtcRepository.manufacturerLabel(code);
String _mfrAr(String code) =>
    DtcRepository.manufacturerLabel(code, languageCode: 'ar');
String _generic(String code) => DtcRepository.genericSaeLabel(code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DtcRepository repo;
  List<String> network = ['none'];
  final requests = <http.Request>[];

  // Replaceable per test; default mirrors a failing remote.
  Future<http.Response> Function(http.Request) handler =
      (_) async => http.Response('', 400);

  void connectivityOnline(bool online) => network = [online ? 'wifi' : 'none'];

  List<http.Request> requestsTo(String host) =>
      requests.where((r) => r.url.host == host).toList();

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, (call) async {
      if (call.method == 'check') return network;
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    DtcRepository.rapidApiKeyOverride = null;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      // A previously-fetched Arabic translation for a manufacturer code.
      'dtc_ar_P1002': 'رمز خاص بالشركة المصنعة',
    });
    DtcRepository.resetCaches();
    requests.clear();
    handler = (_) async => http.Response('', 400);
    DtcRepository.httpClient = MockClient((request) {
      requests.add(request);
      return handler(request);
    });
    DtcRepository.rapidApiKeyOverride = 'test-key';
    DtcRepository.requestTimeout = const Duration(seconds: 6);
    network = ['none'];
    repo = DtcRepository();
  });

  http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  // MyMemory's response shape; failures still come back as HTTP 200.
  http.Response myMemory(String translated,
          {Object status = 200, bool? quotaFinished}) =>
      json({
        'responseData': {'translatedText': translated, 'match': 0.85},
        'responseStatus': status,
        if (quotaFinished != null) 'quotaFinished': quotaFinished,
      });

  // ── English lookups ────────────────────────────────────────────────────────

  group('English lookup — SAE codes in the local DB', () {
    test('powertrain P0xxx codes return the SAE J2012 description', () async {
      expect(await repo.getDtcDescription('P0420'),
          'Catalyst System Efficiency Below Threshold (Bank 1)');
      expect(await repo.getDtcDescription('P0171'), 'System Too Lean (Bank 1)');
      expect(await repo.getDtcDescription('P0300'),
          'Random/Multiple Cylinder Misfire Detected');
      expect(
          await repo.getDtcDescription('P0301'), 'Cylinder 1 Misfire Detected');
    });

    test('chassis (C), body (B) and network (U) codes resolve', () async {
      expect(await repo.getDtcDescription('C0035'), contains('ABS'));
      expect(await repo.getDtcDescription('B0001'), contains('Squib'));
      expect(await repo.getDtcDescription('U0100'),
          'Lost Communication With ECM/PCM A');
    });

    test('P2xxx and P3xxx codes in the DB resolve', () async {
      expect(await repo.getDtcDescription('P2096'),
          'Post Catalyst Fuel Trim System Too Lean Bank 1');
      expect(await repo.getDtcDescription('P3000'), isNotEmpty);
    });

    test('lookup is case-insensitive and ignores surrounding whitespace',
        () async {
      const expected = 'Catalyst System Efficiency Below Threshold (Bank 1)';
      expect(await repo.getDtcDescription('p0420'), expected);
      expect(await repo.getDtcDescription('  P0420\n'), expected);
      expect(await repo.getDtcDescription('\tp0420 '), expected);
    });

    test('non-"ar" language codes return English', () async {
      expect(await repo.getDtcDescription('P0171', languageCode: 'fr'),
          'System Too Lean (Bank 1)');
      expect(await repo.getDtcDescription('P0171', languageCode: 'EN'),
          'System Too Lean (Bank 1)');
    });

    test('separate instances share the parsed DB (static cache)', () async {
      final a = await DtcRepository().getDtcDescription('P0420');
      final b = await DtcRepository().getDtcDescription('P0420');
      expect(a, b);
      expect(a, isNotNull);
    });

    test('local hits never touch the network', () async {
      connectivityOnline(true);
      await repo.getDtcDescription('P0420');
      await repo.getDtcDescription('P0420', languageCode: 'ar');
      expect(requests, isEmpty);
    });

    test('P0395–P0399 carry the SAE J2012 cylinder-1 pressure sensor text',
        () async {
      expect(await repo.getDtcDescription('P0395'),
          'Cylinder 1 Pressure Sensor Circuit');
      expect(await repo.getDtcDescription('P0397'),
          'Cylinder 1 Pressure Sensor Circuit Low');
      expect(await repo.getDtcDescription('P0398'),
          'Cylinder 1 Pressure Sensor Circuit High');
      expect(await repo.getDtcDescription('P0399'),
          'Cylinder 1 Pressure Sensor Circuit Intermittent/Erratic');
      expect(await repo.getDtcDescription('P0397', languageCode: 'ar'),
          'دائرة مستشعر ضغط الأسطوانة 1 منخفضة');
    });
  });

  group('English lookup — manufacturer-specific codes', () {
    test('manufacturer-range codes in the DB get the label, not the DB text',
        () async {
      // The DB holds other brands' meanings (mostly Ford/GM) for these.
      for (final (code, foreign) in [
        ('P1101', 'MAF Sensor'), // Ford
        ('P1745', 'Line Pressure'), // Ford
        ('U1101', 'J1850'), // Ford SCP bus
        ('U1012', 'J1850'),
        ('B1300', ''),
        ('C1201', ''),
        ('P3000', 'HV Battery'), // P3000–P33FF block
      ]) {
        final desc = await repo.getDtcDescription(code);
        expect(desc, _mfr(code), reason: code);
        if (foreign.isNotEmpty) {
          expect(desc, isNot(contains(foreign)), reason: code);
        }
      }
    });

    test('P1xxx absent from the DB returns a manufacturer-specific label',
        () async {
      final desc = await repo.getDtcDescription('P1000');
      expect(desc, isNotNull);
      expect(desc, contains('Manufacturer-specific'));
      expect(desc, contains('P1000'));
    });

    test('the English label text is unchanged', () {
      expect(
          _mfr('P1545'),
          'Manufacturer-specific code (P1545). Meaning varies by vehicle '
          'brand. Check your vehicle\'s service manual or dealer.');
    });

    test('manufacturer label works offline (no network needed)', () async {
      network = ['none'];
      expect(await repo.getDtcDescription('p1fff'),
          contains('Manufacturer-specific code (P1FFF)'));
    });

    test(
      'C1xxx / U1xxx absent from the DB are labelled manufacturer-specific',
      () async {
        // SAE J2012: B1/B2, C1/C2, U1/U2 (like P1) are manufacturer-controlled.
        expect(await repo.getDtcDescription('C1999'),
            contains('Manufacturer-specific'));
        expect(await repo.getDtcDescription('U1999'),
            contains('Manufacturer-specific'));
      },
    );

    test('every manufacturer-controlled range is labelled offline', () async {
      network = ['none'];
      for (final code in [
        'B1FFF', 'B2FFF', 'C1FFF', 'C2FFF', 'U1FFF', 'U2FFF', // body/chassis/net
        'P30FF', 'P33FF', 'P1000', 'P3000', 'U1101', // P1 / P3000–P33FF
      ]) {
        expect(await repo.getDtcDescription(code),
            contains('Manufacturer-specific code ($code)'),
            reason: code);
      }
    });

    test('SAE-controlled neighbours are not labelled manufacturer-specific',
        () async {
      network = ['none'];
      // P34xx+, B3/C3/U3 and B0/C0/U0 are SAE-defined.
      for (final code in ['P34FF', 'P3FFF', 'B3FFF', 'C3FFF', 'U0FFF']) {
        final desc = await repo.getDtcDescription(code);
        expect(desc, _generic(code), reason: code);
        expect(desc, isNot(contains('Manufacturer-specific')), reason: code);
      }
      // SAE codes in the DB keep their DB text.
      expect(await repo.getDtcDescription('P3400'),
          'Cylinder Deactivation System Bank 1');
    });

    test('malformed P1-prefixed input is not labelled', () async {
      expect(await repo.getDtcDescription('P1'), isNull);
      expect(await repo.getDtcDescription('P1ZZZ'), isNull);
    });

    test('manufacturer codes never query the network, even online', () async {
      connectivityOnline(true);
      await repo.getDtcDescription('P1FFF');
      await repo.getDtcDescription('U1101', languageCode: 'ar');
      expect(requests, isEmpty);
    });
  });

  group('Arabic manufacturer-specific label', () {
    test('is Arabic, names the code, and has no English text', () async {
      for (final code in ['B1000', 'C1000', 'P1545', 'U1101', 'P3001']) {
        final desc = await repo.getDtcDescription(code, languageCode: 'ar');
        expect(desc, _mfrAr(code), reason: code);
        expect(desc, contains(code), reason: code);
        expect(desc, matches(RegExp('[؀-ۿ]')), reason: code);
        expect(desc, isNot(contains('Manufacturer-specific')), reason: code);
      }
    });

    test('works offline and online without any request', () async {
      network = ['none'];
      expect(await repo.getDtcDescription('P1003', languageCode: 'ar'),
          _mfrAr('P1003'));
      connectivityOnline(true);
      expect(await repo.getDtcDescription('P1004', languageCode: 'ar'),
          _mfrAr('P1004'));
      expect(requests, isEmpty);
    });

    test('non-"ar" languages get the English label', () async {
      expect(await repo.getDtcDescription('P1004', languageCode: 'fr'),
          _mfr('P1004'));
    });
  });

  group('getOtherBrandHint', () {
    test('labels the DB text of a manufacturer code as another brand\'s',
        () async {
      final en = await repo.getOtherBrandHint('u1101');
      expect(en, startsWith('On some brands (often Ford/GM) this code means: '));
      expect(en, contains('J1850'));

      final ar = await repo.getOtherBrandHint('U1101', languageCode: 'ar');
      expect(ar, startsWith('لدى بعض العلامات التجارية'));
      expect(ar, matches(RegExp('[؀-ۿ]')));
    });

    test('null for SAE, unknown manufacturer and malformed codes', () async {
      expect(await repo.getOtherBrandHint('P0420'), isNull);
      expect(await repo.getOtherBrandHint('P0A80'), isNull);
      expect(await repo.getOtherBrandHint('P1FFF'), isNull);
      expect(await repo.getOtherBrandHint('HELLO'), isNull);
    });
  });

  group('Hybrid / EV codes (P0A00–P0DFF)', () {
    test('bundled SAE J2012 descriptions, offline, EN and AR', () async {
      network = ['none'];
      expect(await repo.getDtcDescription('P0A80'),
          'Replace Hybrid Battery Pack');
      expect(await repo.getDtcDescription('P0A7F'),
          'Hybrid Battery Pack Deterioration');
      expect(await repo.getDtcDescription('P0AA6'),
          'Hybrid Battery Voltage System Isolation Fault');
      expect(await repo.getDtcDescription('P0A94'), 'DC/DC Converter Performance');
      expect(await repo.getDtcDescription('P0A0F'), 'Engine Failed to Start');
      expect(await repo.getDtcDescription('P0C87'),
          'Hybrid Battery Temperature Sensor G/H Correlation');
      expect(await repo.getDtcDescription('P0A80', languageCode: 'ar'),
          'استبدال حزمة بطارية الهجين');
      expect(requests, isEmpty);
    });

    test('every P0A00–P0DFF code has a non-blank description offline',
        () async {
      network = ['none'];
      for (var n = 0xA00; n <= 0xDFF; n++) {
        final code = 'P${n.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        for (final lang in ['en', 'ar']) {
          final d = await repo.getDtcDescription(code, languageCode: lang);
          expect(d, isNotNull, reason: '$code/$lang');
          expect(d!.trim(), isNotEmpty, reason: '$code/$lang');
          if (lang == 'ar') {
            expect(d, matches(RegExp('[؀-ۿ]')), reason: code);
          }
        }
      }
      expect(requests, isEmpty);
    });

    test('codes past the bundled block get the hybrid category label',
        () async {
      network = ['none'];
      expect(await repo.getDtcDescription('P0D27'),
          'Hybrid/EV propulsion system code (P0D27). Description not '
          'available offline — check your vehicle\'s service manual.');
      final ar = await repo.getDtcDescription('P0D27', languageCode: 'ar');
      expect(ar, startsWith('رمز نظام الدفع الهجين/الكهربائي (P0D27)'));
    });
  });

  group('English lookup — unknown codes and error handling', () {
    test('unknown SAE code offline → localized generic category label',
        () async {
      network = ['none'];
      expect(await repo.getDtcDescription('U3000'), _generic('U3000'));
      expect(_generic('U3000'), startsWith('Network communication code'));
      expect(await repo.getDtcDescription('C3FFF'),
          startsWith('Chassis system code (C3FFF)'));
      expect(await repo.getDtcDescription('B3FFF'),
          startsWith('Body system code (B3FFF)'));
      expect(await repo.getDtcDescription('P2FFF'),
          startsWith('Powertrain (engine/transmission) code (P2FFF)'));
      expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode));
      expect(await repo.getDtcDescription('U3000', languageCode: 'ar'),
          DtcRepository.genericSaeLabel('U3000', languageCode: 'ar'));
      expect(requests, isEmpty);
    });

    test('empty / garbage input returns null without throwing', () async {
      expect(await repo.getDtcDescription(''), isNull);
      expect(await repo.getDtcDescription('   '), isNull);
      expect(await repo.getDtcDescription('HELLO'), isNull);
    });

    test('garbage input is never sent to the remote API', () async {
      connectivityOnline(true);
      for (final input in ['HELLO', 'P04201', 'P0/../X', 'X0420', 'P4000']) {
        expect(await repo.getDtcDescription(input), isNull, reason: input);
        expect(await repo.getDtcDescription(input, languageCode: 'ar'), isNull,
            reason: input);
      }
      expect(requests, isEmpty);
    });

    test('connectivity plugin failure is treated as offline', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_connectivityChannel, (call) async {
        throw PlatformException(code: 'boom');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_connectivityChannel, (call) async {
          if (call.method == 'check') return network;
          return null;
        });
      });

      expect(await repo.getDtcDescription('U3001'), _generic('U3001'));
      // Local hits are unaffected.
      expect(await repo.getDtcDescription('P0420'), isNotNull);
      expect(requests, isEmpty);
    });

    test('online but remote API failing (non-200) → generic label', () async {
      connectivityOnline(true);
      expect(await repo.getDtcDescription('U3002'), _generic('U3002'));
      expect(requestsTo(_rapidHost), hasLength(1));
    });
  });

  // ── RapidAPI (online English) ──────────────────────────────────────────────

  group('RapidAPI online lookup', () {
    test('fetches the definition with the configured host and key', () async {
      connectivityOnline(true);
      handler = (_) async => json({
            'code': _onlineCode,
            'definition': 'Hybrid Battery Pack Cooling Fan 1 Circuit',
            'cause': ['Fan motor'],
          });

      expect(await repo.getDtcDescription(_onlineCode),
          'Hybrid Battery Pack Cooling Fan 1 Circuit');

      final req = requestsTo(_rapidHost).single;
      expect(req.method, 'GET');
      expect(req.url.toString(), 'https://$_rapidHost/obd2/$_onlineCode');
      expect(req.headers['x-rapidapi-host'], _rapidHost);
      expect(req.headers['x-rapidapi-key'], 'test-key');
    });

    test('normalises the code before building the request URL', () async {
      connectivityOnline(true);
      handler = (_) async => json({'definition': 'X'});
      await repo.getDtcDescription('  p0d27 ');
      expect(requestsTo(_rapidHost).single.url.path, '/obd2/$_onlineCode');
    });

    test('accepts "description" / "meaning" payloads and trims them',
        () async {
      connectivityOnline(true);
      handler = (req) async => req.url.path.endsWith(_onlineCode)
          ? json({'description': '  Desc text  '})
          : json({'meaning': 'Meaning text'});

      expect(await repo.getDtcDescription(_onlineCode), 'Desc text');
      expect(await repo.getDtcDescription(_onlineCode2), 'Meaning text');
    });

    test('a gateway {"message": ...} body is not shown as a description',
        () async {
      connectivityOnline(true);
      handler = (_) async =>
          json({'message': 'You are not subscribed to this API.'});
      expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode));
    });

    test('caches the result for the session (one request only)', () async {
      connectivityOnline(true);
      handler = (_) async => json({'definition': 'Cached definition'});

      expect(await repo.getDtcDescription(_onlineCode), 'Cached definition');
      expect(await DtcRepository().getDtcDescription(_onlineCode),
          'Cached definition');
      expect(requestsTo(_rapidHost), hasLength(1));
    });

    test('persists the result and reuses it offline after a restart',
        () async {
      connectivityOnline(true);
      handler = (_) async => json({'definition': 'Persisted definition'});
      await repo.getDtcDescription(_onlineCode);

      expect((await prefs()).getString('dtc_en_$_onlineCode'),
          'Persisted definition');

      // Cold start, no network.
      DtcRepository.resetCaches();
      connectivityOnline(false);
      requests.clear();
      expect(await DtcRepository().getDtcDescription(_onlineCode),
          'Persisted definition');
      expect(requests, isEmpty);
    });

    test('rate-limit (429) → generic label, nothing cached', () async {
      connectivityOnline(true);
      handler = (_) async =>
          json({'message': 'Too many requests'}, 429);
      expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode));
      expect((await prefs()).getString('dtc_en_$_onlineCode'), isNull);

      // Once the limit lifts the next lookup goes back online and succeeds.
      handler = (_) async => json({'definition': 'After rate limit'});
      expect(await repo.getDtcDescription(_onlineCode), 'After rate limit');
      expect(requestsTo(_rapidHost), hasLength(2));
    });

    test('auth / server errors (401, 403, 500) → generic label', () async {
      connectivityOnline(true);
      for (final status in [401, 403, 500]) {
        handler = (_) async => json({'definition': 'ignored'}, status);
        expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode),
            reason: '$status');
      }
    });

    test('malformed or unexpected JSON → generic label', () async {
      connectivityOnline(true);
      for (final body in [
        '{"definition": "trunc',
        '<html>Bad gateway</html>',
        '["P0A80", "definition"]',
        '{"definition": 42}',
        '{"definition": "   "}',
        '{}',
        '',
      ]) {
        handler = (_) async => http.Response(body, 200);
        expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode),
            reason: body);
      }
      expect((await prefs()).getString('dtc_en_$_onlineCode'), isNull);
    });

    test('a hanging request times out → generic label', () async {
      connectivityOnline(true);
      DtcRepository.requestTimeout = const Duration(milliseconds: 50);
      final never = Completer<http.Response>();
      handler = (_) => never.future;

      final sw = Stopwatch()..start();
      expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a transport error (ClientException) → generic label', () async {
      connectivityOnline(true);
      handler = (_) async => throw http.ClientException('socket closed');
      expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode));
    });

    test('without an API key no request is made', () async {
      connectivityOnline(true);
      DtcRepository.rapidApiKeyOverride = '';
      handler = (_) async => json({'definition': 'should not be fetched'});
      expect(await repo.getDtcDescription(_onlineCode), _generic(_onlineCode));
      expect(requests, isEmpty);
    });
  });

  // ── Arabic lookups ─────────────────────────────────────────────────────────

  group('Arabic lookup', () {
    test('returns the bundled Arabic translation for a known code', () async {
      expect(await repo.getDtcDescription('P0420', languageCode: 'ar'),
          'نظام المحول الحفازي كفاءة أقل من الحد المسموح (البنك 1)');
    });

    test('Arabic lookup normalises the code the same way as English',
        () async {
      expect(await repo.getDtcDescription(' p0171 ', languageCode: 'ar'),
          'نظام خليط فقير جداً (البنك 1)');
    });

    test('repeated Arabic lookups are stable (session cache)', () async {
      final first = await repo.getDtcDescription('U0100', languageCode: 'ar');
      final second = await repo.getDtcDescription('U0100', languageCode: 'ar');
      expect(first, second);
      expect(first, isNot('Lost Communication With ECM/PCM A'));
    });

    test('unknown SAE code gets the Arabic generic label offline', () async {
      network = ['none'];
      final desc = await repo.getDtcDescription('U3003', languageCode: 'ar');
      expect(desc,
          DtcRepository.genericSaeLabel('U3003', languageCode: 'ar'));
      expect(desc, matches(RegExp('[؀-ۿ]')));
      expect(desc, contains('U3003'));
    });

    test('a stale stored translation never overrides the manufacturer label',
        () async {
      // setUp stores dtc_ar_P1002 (written by older app versions).
      connectivityOnline(true);
      expect(await repo.getDtcDescription('P1002', languageCode: 'ar'),
          _mfrAr('P1002'));
      expect(requests, isEmpty);
    });

    test('uses a persisted on-device translation when not bundled', () async {
      await (await prefs()).setString('dtc_en_P0D31', 'Online definition');
      await (await prefs()).setString('dtc_ar_P0D31', 'ترجمة محفوظة');
      connectivityOnline(true);
      expect(await repo.getDtcDescription('P0D31', languageCode: 'ar'),
          'ترجمة محفوظة');
      expect(requests, isEmpty);
    });

    test('online English with no translation offline → English text',
        () async {
      await (await prefs()).setString('dtc_en_P0D32', 'Online definition');
      network = ['none'];
      expect(await repo.getDtcDescription('P0D32', languageCode: 'ar'),
          'Online definition');
    });
  });

  // ── MyMemory (online Arabic) ───────────────────────────────────────────────

  group('MyMemory translation', () {
    const arabic = 'دائرة مروحة تبريد حزمة البطارية الهجينة 1';

    // RapidAPI answers [def]; [mm] answers the MyMemory request.
    const def = 'Battery Charger Input Voltage Too Low';
    Future<http.Response> Function(http.Request) english(
            Future<http.Response> Function() mm) =>
        (req) => req.url.host == _rapidHost
            ? Future.value(json({'definition': def}))
            : mm();

    test('online English → MyMemory Arabic, persisted and cached', () async {
      connectivityOnline(true);
      handler = (req) async => req.url.host == _rapidHost
          ? json({'definition': 'Hybrid Battery Pack Cooling Fan 1 Circuit'})
          : myMemory(' $arabic ');

      expect(await repo.getDtcDescription(_onlineCode, languageCode: 'ar'),
          arabic);

      final mm = requestsTo(_myMemoryHost).single;
      expect(mm.url.path, '/get');
      expect(mm.url.queryParameters['q'],
          'Hybrid Battery Pack Cooling Fan 1 Circuit');
      expect(mm.url.queryParameters['langpair'], 'en|ar');

      final p = await prefs();
      expect(p.getString('dtc_ar_$_onlineCode'), arabic);
      expect(p.getString('dtc_en_$_onlineCode'),
          'Hybrid Battery Pack Cooling Fan 1 Circuit');

      // Session cache: no further requests in either language.
      expect(await repo.getDtcDescription(_onlineCode, languageCode: 'ar'),
          arabic);
      expect(await repo.getDtcDescription(_onlineCode),
          'Hybrid Battery Pack Cooling Fan 1 Circuit');
      expect(requests, hasLength(2));
    });

    test('manufacturer labels are never sent for translation', () async {
      connectivityOnline(true);
      handler = (_) async => myMemory('رمز خاص بالشركة المصنعة (P1FFE)');
      expect(await repo.getDtcDescription('P1FFE', languageCode: 'ar'),
          _mfrAr('P1FFE'));
      expect(requests, isEmpty);
      expect((await prefs()).getString('dtc_ar_P1FFE'), isNull);
    });

    test('persisted translation is reused offline after a restart', () async {
      connectivityOnline(true);
      handler = (req) async => req.url.host == _rapidHost
          ? json({'definition': 'Hybrid Battery Pack Cooling Fan 1 Circuit'})
          : myMemory(arabic);
      await repo.getDtcDescription(_onlineCode, languageCode: 'ar');

      DtcRepository.resetCaches();
      connectivityOnline(false);
      requests.clear();
      handler = (_) async => fail('no request expected while offline');

      expect(
          await DtcRepository()
              .getDtcDescription(_onlineCode, languageCode: 'ar'),
          arabic);
      expect(requests, isEmpty);
    });

    test('quota warning (HTTP 200, responseStatus 429) is not persisted',
        () async {
      connectivityOnline(true);
      handler = english(() async => myMemory(
            'MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR '
            'TODAY. NEXT AVAILABLE IN 10 HOURS',
            status: 429,
            quotaFinished: true,
          ));

      expect(await repo.getDtcDescription('P0D33', languageCode: 'ar'), def);
      expect((await prefs()).getString('dtc_ar_P0D33'), isNull);

      // Not session-cached either: once quota resets it translates.
      handler = english(() async => myMemory('ترجمة (P0D33)'));
      expect(await repo.getDtcDescription('P0D33', languageCode: 'ar'),
          'ترجمة (P0D33)');
    });

    test('string responseStatus errors ("403") fall back to English',
        () async {
      connectivityOnline(true);
      handler = english(() async =>
          myMemory("'AR' IS AN INVALID TARGET LANGUAGE", status: '403'));
      expect(await repo.getDtcDescription('P0D34', languageCode: 'ar'), def);
      expect((await prefs()).getString('dtc_ar_P0D34'), isNull);
    });

    test('quotaFinished: true with Arabic text is still rejected', () async {
      connectivityOnline(true);
      handler = english(() async => myMemory('نص', quotaFinished: true));
      expect(await repo.getDtcDescription('P0D35', languageCode: 'ar'), def);
    });

    test('HTTP 429 rate limit falls back to English, nothing persisted',
        () async {
      connectivityOnline(true);
      handler = english(() async => http.Response('Too Many Requests', 429));
      expect(await repo.getDtcDescription('P0D36', languageCode: 'ar'), def);
      expect((await prefs()).getString('dtc_ar_P0D36'), isNull);
    });

    test('malformed JSON falls back to English', () async {
      connectivityOnline(true);
      for (final body in [
        '{"responseData": ',
        '[]',
        '{"responseData": "nope", "responseStatus": 200}',
        '{"responseData": {"translatedText": 7}, "responseStatus": 200}',
      ]) {
        handler = english(() async => http.Response(body, 200));
        expect(await repo.getDtcDescription('P0D37', languageCode: 'ar'), def,
            reason: body);
      }
      expect((await prefs()).getString('dtc_ar_P0D37'), isNull);
    });

    test('echoed or non-Arabic "translations" are not persisted', () async {
      connectivityOnline(true);
      for (final t in [def, '', 'BATTERY CHARGER']) {
        handler = english(() async => myMemory(t));
        expect(await repo.getDtcDescription('P0D38', languageCode: 'ar'), def,
            reason: t);
      }
      expect((await prefs()).getString('dtc_ar_P0D38'), isNull);
    });

    test('a hanging translation request times out → English', () async {
      connectivityOnline(true);
      DtcRepository.requestTimeout = const Duration(milliseconds: 50);
      final never = Completer<http.Response>();
      handler = english(() => never.future);

      expect(await repo.getDtcDescription('P0D39', languageCode: 'ar'), def);
    });
  });

  // ── Cache isolation ────────────────────────────────────────────────────────

  group('resetCaches', () {
    test('drops the session caches so storage is consulted again', () async {
      connectivityOnline(true);
      handler = (req) async => req.url.host == _rapidHost
          ? json({'definition': 'Online definition'})
          : myMemory('ترجمة أولى');
      expect(await repo.getDtcDescription('P0D3A', languageCode: 'ar'),
          'ترجمة أولى');

      // Change storage behind the repository's back.
      await (await prefs()).setString('dtc_ar_P0D3A', 'ترجمة ثانية');
      expect(await repo.getDtcDescription('P0D3A', languageCode: 'ar'),
          'ترجمة أولى', reason: 'still served from the session cache');

      DtcRepository.resetCaches();
      expect(await repo.getDtcDescription('P0D3A', languageCode: 'ar'),
          'ترجمة ثانية');
    });
  });

  // ── Bundled data integrity ─────────────────────────────────────────────────

  group('bundled DTC databases', () {
    late String enRaw;
    late String arRaw;
    late Map<String, dynamic> en;
    late Map<String, dynamic> ar;

    final dtcKey = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');
    final manufacturer = RegExp(
        r'^(?:P1[0-9A-F]{3}|P3[0-3][0-9A-F]{2}|[BCU][12][0-9A-F]{3})$');
    final arabicLetter = RegExp(r'[؀-ۿ]');

    setUpAll(() async {
      enRaw = await rootBundle.loadString('assets/dtcmapping.json');
      arRaw = await rootBundle.loadString('assets/dtcmapping_ar.json');
      en = jsonDecode(enRaw) as Map<String, dynamic>;
      ar = jsonDecode(arRaw) as Map<String, dynamic>;
    });

    test('contains the ~6,250 codes the app advertises', () {
      expect(en.length, greaterThanOrEqualTo(6249));
    });

    test('SAE hybrid/EV block P0A00–P0C87 is complete in EN and AR', () {
      final missing = <String>[];
      for (var n = 0xA00; n <= 0xC87; n++) {
        final code = 'P${n.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        if (!en.containsKey(code) || !ar.containsKey(code)) missing.add(code);
      }
      expect(missing, isEmpty);
      expect(en['P0A00'],
          'Motor Electronics Coolant Temperature Sensor Circuit');
      expect(en['P0AFF'],
          'System Voltage Too Low for Voltage Step Down Conversion');
      expect(en['P0B00'],
          'Auxiliary Transmission Fluid Pump Motor Phase U Current');
      expect(en['P0C00'], 'Drive Motor A Current Low');
    });

    test('hybrid entries keep their sensor/phase letters in Arabic', () {
      // "Voltage Sense Q" ↔ "استشعار الجهد Q", "Phase U" ↔ "الطور U", etc.
      final letter = RegExp(r'\b(?:Sense|Sensor|Motor|Phase|Fan) ([A-Z1-3])\b');
      final bad = [
        for (final code in en.keys.where((k) => k.compareTo('P0A00') >= 0 &&
            k.compareTo('P0DFF') <= 0))
          for (final m in letter.allMatches(en[code] as String))
            if (!(ar[code] as String).contains(m[1]!)) code,
      ];
      expect(bad, isEmpty);
    });

    test('every key is a well-formed SAE J2012 DTC (e.g. P0420)', () {
      for (final db in [en, ar]) {
        expect(db.keys.where((k) => !dtcKey.hasMatch(k)).toList(), isEmpty);
      }
    });

    test('covers all four systems: P, C, B, U', () {
      for (final p in ['P', 'C', 'B', 'U']) {
        expect(en.keys.any((k) => k.startsWith(p)), isTrue, reason: p);
      }
    });

    test('English and Arabic files have exactly the same codes', () {
      expect(en.keys.where((k) => !ar.containsKey(k)).toList(), isEmpty);
      expect(ar.keys.where((k) => !en.containsKey(k)).toList(), isEmpty);
    });

    test('no duplicate keys in the raw JSON (jsonDecode hides them)', () {
      final keyLine = RegExp(r'^\s*"([^"]+)"\s*:', multiLine: true);
      for (final (name, raw, db) in [('en', enRaw, en), ('ar', arRaw, ar)]) {
        final seen = <String>{};
        final dupes = [
          for (final m in keyLine.allMatches(raw))
            if (!seen.add(m.group(1)!)) m.group(1),
        ];
        expect(dupes, isEmpty, reason: name);
        expect(seen.length, db.length, reason: name);
      }
    });

    test('every description is a non-empty, trimmed, single-line string', () {
      for (final (name, db) in [('en', en), ('ar', ar)]) {
        final bad = [
          for (final e in db.entries)
            if (e.value is! String ||
                (e.value as String).trim().isEmpty ||
                e.value != (e.value as String).trim() ||
                (e.value as String).contains('  ') ||
                RegExp(r'[\x00-\x1F]').hasMatch(e.value as String))
              e.key,
        ];
        expect(bad, isEmpty, reason: name);
      }
    });

    test('no scraping artefacts (leading punctuation, merged code lists)', () {
      final leadingPunct = RegExp(r'^[,;:./-]');
      final otherCode = RegExp(r'\b[PCBU][0-3][0-9A-F]{3}\b');
      for (final (name, db) in [('en', en), ('ar', ar)]) {
        final bad = [
          for (final e in db.entries)
            if (leadingPunct.hasMatch(e.value as String) ||
                otherCode.hasMatch(e.value as String))
              e.key,
        ];
        expect(bad, isEmpty, reason: name);
      }
    });

    test('every Arabic description is actually written in Arabic', () {
      final untranslated = [
        for (final e in ar.entries)
          if (!arabicLetter.hasMatch(e.value as String)) e.key,
      ];
      expect(untranslated, isEmpty);
    });

    // Latin text that may stay in an Arabic description: standard acronyms
    // and units that Arabic automotive text normally keeps in Latin, plus
    // single capital letters (and A/B, U-V-W groups) that identify a sensor,
    // circuit, bus, bank, motor or phase. Everything else — "Insufficient",
    // "Passenger", "Injector", ... — is a half-translated leftover.
    const latinAllowed = {
      'EGR', 'EVAP', 'MAF', 'MAP', 'O2', 'A/F', 'PCM', 'ECM', 'TCM', 'BCM',
      'ABS', 'ESC', 'ESP', 'EPS', 'TCS', 'CAN', 'LIN', 'SCP', 'J1850',
      'J1979', 'ISO', 'SAE', 'VSS', 'IAT', 'ECT', 'TPS', 'APP', 'CKP', 'CMP',
      'VVT', 'DPF', 'SCR', 'NOx', 'HO2S', 'PCV', 'IAC', 'DTC', 'OBD', 'OBDII',
      'MIL', 'A/C', 'HVAC', 'SRS', 'ECU', 'EBCM', 'RPM', 'rpm', 'kPa', 'km',
      'mph', 'V', 'DC', 'LED', 'GPS', 'USB', 'VIN', 'RAM', 'ROM', 'EEPROM',
      'KAM', 'NVM', 'PWM', 'CVT', '4WD', 'AWD', 'HC', 'PRNDL', 'FlexRay',
      'MOST', 'LCD', 'TPMS', 'PATS', 'ID', 'EV', 'HV', 'ACC', 'PTO',
    };
    // English words that must be translated even when written in CAPITALS.
    const capsWords = {
      'LAMP', 'OUTPUT', 'CIRCUIT', 'BEAM', 'ANTI', 'LOW', 'HIGH', 'PARK',
      'HORN', 'DOME', 'SWITCH', 'SHORT', 'TO', 'GROUND', 'CORNER', 'SIDE',
      'REPEATER', 'UNDERHOOD', 'COURTESY', 'STEERING', 'RADIO', 'PRESENT',
      'INPUT', 'SIGNAL', 'BRAKE', 'THEFT', 'AIR', 'RF', 'LF', 'RR', 'LR',
      'OPEN', 'FAULT', 'FAILURE', 'SENSOR', 'MODULE', 'VALVE', 'MOTOR',
      'RELAY', 'BATTERY', 'POWER', 'DOOR', 'SEAT', 'FRONT', 'REAR', 'LEFT',
      'RIGHT', 'ON', 'OFF', 'AND', 'OR', 'FOR', 'WITH', 'NOT', 'NO', 'OF',
      'THE', 'IN', 'AT', 'BY', 'ERROR', 'DATA', 'MISSING', 'INVALID', 'SPEED',
    };
    final latinWord = RegExp(r'(?<![A-Za-z0-9])[0-9]*[A-Za-z][A-Za-z0-9/+\-]*');
    final identifierLetters = RegExp(r'^[A-Z](?:[/-][A-Z])*$');
    bool allowedPart(String w) =>
        latinAllowed.contains(w) || identifierLetters.hasMatch(w);

    // Latin words in [arText] that are neither allowed nor (for
    // manufacturer codes, whose texts use proprietary abbreviations such as
    // IMCC or DPFE) an all-caps abbreviation copied verbatim from [enText].
    List<String> strayLatin(String arText, String enText,
            {bool manufacturerCode = false}) =>
        [
          for (final m in latinWord.allMatches(arText))
            if (!allowedPart(m[0]!) &&
                !m[0]!
                    .split(RegExp(r'[/-]'))
                    .where((p) => p.isNotEmpty)
                    .every(allowedPart) &&
                !(manufacturerCode &&
                    m[0] == m[0]!.toUpperCase() &&
                    !capsWords.contains(m[0]) &&
                    RegExp('(?<![A-Za-z0-9])${RegExp.escape(m[0]!)}'
                            r'(?![A-Za-z0-9])')
                        .hasMatch(enText)))
              m[0]!,
        ];

    test('the Latin-word check catches half-translated text', () {
      // P0401 as it used to ship, next to its fixed translation.
      expect(strayLatin('إعادة تدوير غاز العادم تدفق Insufficient مكتشف',
              'Exhaust Gas Recirculation Flow Insufficient Detected'),
          ['Insufficient']);
      expect(
          strayLatin(
              'تم اكتشاف تدفق غير كافٍ في نظام إعادة تدوير غازات العادم (EGR)',
              'Exhaust Gas Recirculation Flow Insufficient Detected'),
          isEmpty);
      expect(strayLatin('مستشعر O2 (البنك 1 المستشعر 2) A/B U-V-W 4WD', ''),
          isEmpty);
      expect(strayLatin('عطل IMCC', 'IMCC Circuit Malfunction'), ['IMCC']);
      expect(
          strayLatin('عطل IMCC', 'IMCC Circuit Malfunction',
              manufacturerCode: true),
          isEmpty);
      expect(
          strayLatin('خرج OUTPUT', 'Chime OUTPUT Request',
              manufacturerCode: true),
          ['OUTPUT']);
    });

    test('SAE-generic Arabic descriptions contain no untranslated English',
        () {
      // P0, P2, P34–P3F, C0, B0, U0 and U3: the codes shown as the main
      // description on the code screen.
      final sae = RegExp(r'^(?:P0|P2|P3[4-9A-F]|C0|B0|U0|U3)');
      final bad = [
        for (final e in ar.entries)
          if (sae.hasMatch(e.key) &&
              strayLatin(e.value as String, en[e.key] as String).isNotEmpty)
            '${e.key}: ${strayLatin(e.value as String, en[e.key] as String)}',
      ];
      expect(bad, isEmpty);
      expect(ar['P0401'],
          'تم اكتشاف تدفق غير كافٍ في نظام إعادة تدوير غازات العادم (EGR)');
    });

    test('manufacturer Arabic descriptions contain no untranslated English',
        () {
      final bad = [
        for (final e in ar.entries)
          if (manufacturer.hasMatch(e.key) &&
              strayLatin(e.value as String, en[e.key] as String,
                      manufacturerCode: true)
                  .isNotEmpty)
            e.key,
      ];
      expect(bad, isEmpty);
    });

    // Same-system SAE-defined codes sharing one description are copy/paste
    // errors (e.g. P0365 used to repeat P0390's "Bank 2"). These pairs were
    // found by this scan but could not be verified against SAE J2012 with
    // confidence; each listed code duplicates an earlier one. Fix the data
    // and drop the code from this set.
    const unverifiedDuplicates = {
      'B0132', 'B0133', 'B0187', 'B0188', 'B0194', 'B0195', 'B0205', 'B0206',
      'B0207', 'B0217', 'C0056', 'P2605', 'P2633', 'P2634', 'P2900', 'P2119',
      'P2153', 'P2626', 'P2627', 'P2628', 'P2629', 'P2630', 'P2631', 'P2350',
      'P2351', 'P2352', 'P2353', 'P2354', 'P2355', 'P2356', 'P2357', 'P2358',
      'P2359', 'P2360', 'P2361', 'P2362', 'P2363', 'P2364', 'P2365', 'U0073',
      'U0077', 'U0078', 'U0079', 'U0122', 'U0260', 'U0262', 'U0264', 'U0265',
      'U0266', 'U0267', 'U0268', 'U0269', 'U0270', 'U0271', 'U0272', 'U0273',
      'U0274', 'U0275',
    };

    test('SAE-defined codes in one system do not share a description', () {
      final firstSeen = <String, String>{};
      final dupes = <String>[];
      for (final e in en.entries) {
        final code = e.key;
        final desc = (e.value as String).toLowerCase();
        if (manufacturer.hasMatch(code) || desc == 'iso/sae reserved') continue;
        final k = '${code[0]}|$desc';
        final earlier = firstSeen[k];
        if (earlier == null) {
          firstSeen[k] = code;
        } else if (!unverifiedDuplicates.contains(code)) {
          dupes.add('$earlier=$code');
        }
      }
      expect(dupes, isEmpty);
    });

    test('the unverified-duplicate list only names real duplicates', () {
      final counts = <String, int>{};
      for (final e in en.entries) {
        final k = '${e.key[0]}|${(e.value as String).toLowerCase()}';
        counts[k] = (counts[k] ?? 0) + 1;
      }
      final stale = [
        for (final code in unverifiedDuplicates)
          if (!en.containsKey(code) ||
              counts['${code[0]}|${(en[code] as String).toLowerCase()}']! < 2)
            code,
      ];
      expect(stale, isEmpty, reason: 'fixed — remove from the list');
    });

    test('EN/AR pairs agree on bank and sensor numbers', () {
      // "(Bank 2)" in English must be "البنك 2" in Arabic, etc.
      final enBank = RegExp(r'Bank (\d)');
      final arBank = RegExp(r'البنك (\d)');
      final mismatched = [
        for (final code in en.keys)
          if (enBank.allMatches(en[code] as String).map((m) => m[1]).join() !=
              arBank.allMatches(ar[code] as String).map((m) => m[1]).join())
            code,
      ];
      expect(mismatched, isEmpty);
    });
  });
}
