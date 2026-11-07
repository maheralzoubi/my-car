import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DtcRepository {
  static const String _assetPath = 'assets/dtcmapping.json';

  // The RapidAPI key is injected at build time and is never committed:
  //   flutter run  --dart-define=RAPID_API_KEY=your_key
  //   flutter build apk --dart-define=RAPID_API_KEY=your_key
  // Without it the online lookup is skipped — the bundled ~6,250-code
  // database (and the manufacturer / generic SAE labels) still work.
  static const String _rapidApiHost = 'car-code.p.rapidapi.com';
  static const String _rapidApiKeyFromEnv = String.fromEnvironment(
    'RAPID_API_KEY',
  );

  static const String _arPrefixKey = 'dtc_ar_';
  static const String _enPrefixKey = 'dtc_en_';
  static const String _arAssetPath = 'assets/dtcmapping_ar.json';

  // Static so JSON is parsed once and shared across all DtcRepository instances.
  static Map<String, String>? _localCodes;
  static Map<String, String>? _arabicCodes;
  static SharedPreferences? _prefs;

  // In-memory caches for the current session — also static so all instances
  // share them.
  static final Map<String, String> _arabicSessionCache = {};
  static final Map<String, String> _onlineEnglishCache = {};

  // ── Network plumbing (overridable in tests) ─────────────────────────────

  static http.Client _httpClient = http.Client();
  static String? _rapidApiKeyOverride;
  static Duration _requestTimeout = const Duration(seconds: 6);

  static String get _rapidApiKey => _rapidApiKeyOverride ?? _rapidApiKeyFromEnv;

  /// Replaces the HTTP client used for the RapidAPI and MyMemory lookups.
  @visibleForTesting
  static set httpClient(http.Client client) => _httpClient = client;

  /// Overrides the build-time RAPID_API_KEY (`null` restores it).
  @visibleForTesting
  static set rapidApiKeyOverride(String? key) => _rapidApiKeyOverride = key;

  /// Per-request timeout for both online lookups.
  @visibleForTesting
  static set requestTimeout(Duration timeout) => _requestTimeout = timeout;

  /// Drops every static cache (parsed JSON, SharedPreferences instance,
  /// session caches) so each test starts from a cold repository.
  @visibleForTesting
  static void resetCaches() {
    _localCodes = null;
    _arabicCodes = null;
    _prefs = null;
    _arabicSessionCache.clear();
    _onlineEnglishCache.clear();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns an English or Arabic description for [code].
  ///
  /// * Manufacturer-controlled codes (P1xxx, P3000–P33FF, B1/B2, C1/C2,
  ///   U1/U2) always get the localized manufacturer-specific label: their
  ///   meaning differs per brand, so the bundled text (written for other
  ///   brands, mostly Ford/GM) is not shown as the description — see
  ///   [getOtherBrandHint].
  /// * SAE-defined codes come from the bundled database, then a previous or
  ///   live online lookup, and otherwise a localized generic category label
  ///   (see [genericSaeLabel]) — a well-formed code never yields null.
  /// * Malformed input returns null.
  ///
  /// Online results (English from RapidAPI, Arabic from MyMemory) are
  /// persisted to device storage after the first fetch so subsequent lookups
  /// (including offline) are instant.
  Future<String?> getDtcDescription(
    String code, {
    String languageCode = 'en',
  }) async {
    final normalized = code.trim().toUpperCase();
    // Never describe (or send to the remote API) garbage / path fragments.
    if (!_dtcPattern.hasMatch(normalized)) return null;

    if (_isManufacturerSpecific(normalized)) {
      return manufacturerLabel(normalized, languageCode: languageCode);
    }

    final englishDesc = await _getEnglishDescription(normalized);
    if (englishDesc == null) {
      return genericSaeLabel(normalized, languageCode: languageCode);
    }
    if (languageCode != 'ar') return englishDesc;
    // Use the code itself as the stable cache key — never hashCode.
    return _getArabic(englishDesc, cacheKey: normalized);
  }

  /// What the bundled database says a manufacturer-range [code] means on
  /// other brands (the entries were written mostly for Ford/GM), labelled as
  /// such — e.g. "On some brands (often Ford/GM) this code means: …".
  ///
  /// Returns null for SAE-defined or malformed codes and for manufacturer
  /// codes the database has no entry for. Never use it as the description.
  Future<String?> getOtherBrandHint(
    String code, {
    String languageCode = 'en',
  }) async {
    final normalized = code.trim().toUpperCase();
    if (!_isManufacturerSpecific(normalized)) return null;
    final arabic = languageCode == 'ar';
    final text = arabic
        ? (await _loadArabicCodes())[normalized]
        : (await _loadLocalCodes())[normalized];
    if (text == null || text.isEmpty) return null;
    return arabic
        ? 'لدى بعض العلامات التجارية (غالباً فورد/جنرال موتورز) يعني هذا '
              'الرمز: $text'
        : 'On some brands (often Ford/GM) this code means: $text';
  }

  // ── English description ───────────────────────────────────────────────────

  // SAE J2012 code shape: system letter, 0–3, three hex digits.
  static final RegExp _dtcPattern = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');

  /// SAE-defined codes only (manufacturer ranges are handled by the caller).
  Future<String?> _getEnglishDescription(String code) async {
    final local = await _loadLocalCodes();

    // Local hit — covers SAE P0 (incl. hybrid P0A00–P0C87), P2, P34+, C, B, U.
    final localHit = local[code];
    if (localHit != null && localHit.isNotEmpty) return localHit;

    // A previous online lookup — session cache, then device storage.
    final cached = _onlineEnglishCache[code];
    if (cached != null) return cached;
    final stored = await _readPref(_enPrefixKey + code);
    if (stored != null && stored.isNotEmpty) {
      _onlineEnglishCache[code] = stored;
      return stored;
    }

    // For unknown SAE codes not yet in the local DB, try the online API.
    final online = await _hasNetwork().catchError((_) => false);
    if (!online) return null;

    try {
      final fetched = await _fetchFromApi(code);
      if (fetched != null) {
        _onlineEnglishCache[code] = fetched;
        await _writePref(_enPrefixKey + code, fetched);
      }
      return fetched;
    } catch (_) {
      return null; // timeout, socket error, malformed JSON
    }
  }

  // SAE J2012 manufacturer-controlled blocks: P1xxx, P3000–P33FF,
  // B1xxx/B2xxx, C1xxx/C2xxx, U1xxx/U2xxx. Everything else is SAE-defined.
  static final RegExp _manufacturerRanges = RegExp(
    r'^(?:P1[0-9A-F]{3}|P3[0-3][0-9A-F]{2}|[BCU][12][0-9A-F]{3})$',
  );

  bool _isManufacturerSpecific(String code) =>
      _manufacturerRanges.hasMatch(code);

  /// Localized label for a manufacturer-controlled [code] (Arabic when
  /// [languageCode] is 'ar', English otherwise).
  static String manufacturerLabel(String code, {String languageCode = 'en'}) =>
      languageCode == 'ar'
      ? 'رمز خاص بالشركة المصنعة ($code). يختلف معناه حسب العلامة '
            'التجارية للمركبة. راجع دليل الخدمة الخاص بمركبتك أو الوكيل.'
      : 'Manufacturer-specific code ($code). Meaning varies by vehicle '
            'brand. Check your vehicle\'s service manual or dealer.';

  // SAE J2012 hybrid/EV propulsion block P0A00–P0DFF.
  static final RegExp _hybridBlock = RegExp(r'^P0[A-D]');

  /// Localized fallback for a well-formed SAE-defined [code] with no bundled,
  /// stored or online description: names the code's SAE J2012 category.
  static String genericSaeLabel(String code, {String languageCode = 'en'}) {
    final arabic = languageCode == 'ar';
    final String category;
    if (_hybridBlock.hasMatch(code)) {
      category = arabic
          ? 'رمز نظام الدفع الهجين/الكهربائي'
          : 'Hybrid/EV propulsion system code';
    } else {
      category = switch (code[0]) {
        'P' =>
          arabic
              ? 'رمز مجموعة الدفع (المحرك/ناقل الحركة)'
              : 'Powertrain (engine/transmission) code',
        'C' => arabic ? 'رمز نظام الشاسيه' : 'Chassis system code',
        'B' => arabic ? 'رمز نظام الهيكل' : 'Body system code',
        _ =>
          arabic
              ? 'رمز شبكة الاتصال بين الوحدات'
              : 'Network communication code',
      };
    }
    return arabic
        ? '$category ($code). الوصف غير متوفر دون اتصال بالإنترنت — راجع '
              'دليل الخدمة الخاص بمركبتك.'
        : '$category ($code). Description not available offline — check '
              'your vehicle\'s service manual.';
  }

  // ── Arabic translation ────────────────────────────────────────────────────

  Future<Map<String, String>> _loadArabicCodes() async {
    if (_arabicCodes != null) return _arabicCodes!;
    try {
      final jsonStr = await rootBundle.loadString(_arAssetPath);
      final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
      _arabicCodes = raw.map((k, v) => MapEntry(k.toUpperCase(), v.toString()));
    } catch (_) {
      _arabicCodes = {}; // file missing — fall through to runtime translation
    }
    return _arabicCodes!;
  }

  // At least one letter from the Arabic Unicode block.
  static final RegExp _arabicScript = RegExp(r'[؀-ۿ]');

  Future<String> _getArabic(
    String englishText, {
    required String cacheKey,
  }) async {
    // 1. In-memory session cache.
    if (_arabicSessionCache.containsKey(cacheKey)) {
      return _arabicSessionCache[cacheKey]!;
    }

    // 2. Bundled Arabic JSON — automotive-accurate, works fully offline.
    final arCodes = await _loadArabicCodes();
    final bundled = arCodes[cacheKey];
    if (bundled != null && bundled.isNotEmpty) {
      _arabicSessionCache[cacheKey] = bundled;
      return bundled;
    }

    // 3. Persistent on-device cache for codes not in the bundled file.
    final prefKey = _arPrefixKey + cacheKey;
    final stored = await _readPref(prefKey);
    if (stored != null && stored.isNotEmpty) {
      _arabicSessionCache[cacheKey] = stored;
      return stored;
    }

    // 4. Fetch from MyMemory as last resort and persist for future offline use.
    final online = await _hasNetwork().catchError((_) => false);
    if (!online) return englishText;

    try {
      final uri = Uri.parse(
        'https://api.mymemory.translated.net/get'
        '?q=${Uri.encodeComponent(englishText)}&langpair=en|ar',
      );

      final response = await _httpClient.get(uri).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        Object? translated;
        if (body is Map<String, dynamic> && _myMemoryOk(body)) {
          final data = body['responseData'];
          if (data is Map) translated = data['translatedText'];
        }

        // Only persist something that is actually Arabic — MyMemory reports
        // quota/rate-limit errors as HTTP 200 with an English warning in
        // translatedText, and that must never be cached as the translation.
        if (translated is String &&
            translated.trim().isNotEmpty &&
            translated.trim() != englishText &&
            _arabicScript.hasMatch(translated)) {
          final text = translated.trim();
          await _writePref(prefKey, text);
          _arabicSessionCache[cacheKey] = text;
          return text;
        }
      }
    } catch (_) {}

    return englishText; // Fallback: show English
  }

  /// MyMemory signals failures in the body: `responseStatus` (int or string)
  /// other than 200 — e.g. 429 when the daily quota is used up — or
  /// `quotaFinished: true`.
  static bool _myMemoryOk(Map<String, dynamic> body) {
    final status = body['responseStatus'];
    if (status != null && '$status' != '200') return false;
    return body['quotaFinished'] != true;
  }

  // ── RapidAPI ──────────────────────────────────────────────────────────────

  Future<String?> _fetchFromApi(String code) async {
    final apiKey = _rapidApiKey;
    if (apiKey.isEmpty) return null;

    final uri = Uri.https(_rapidApiHost, '/obd2/$code');
    final response = await _httpClient
        .get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-rapidapi-host': _rapidApiHost,
            'x-rapidapi-key': apiKey,
          },
        )
        .timeout(_requestTimeout);

    // 401/403 (bad key), 404, 429 (rate limit), 5xx → no description.
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    // car-code returns {"code", "definition", "cause"}; older/alternate
    // payloads used "description" / "meaning". RapidAPI's own gateway errors
    // come back as {"message": ...}, which is deliberately not read.
    for (final field in const ['definition', 'description', 'meaning']) {
      final value = body[field];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, String>> _loadLocalCodes() async {
    if (_localCodes != null) return _localCodes!;
    final jsonStr = await rootBundle.loadString(_assetPath);
    final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
    _localCodes = raw.map((k, v) => MapEntry(k.toUpperCase(), v.toString()));
    return _localCodes!;
  }

  Future<SharedPreferences> _loadPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // Storage is a cache: a failing plugin must never break a lookup.
  Future<String?> _readPref(String key) async {
    try {
      return (await _loadPrefs()).getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePref(String key, String value) async {
    try {
      await (await _loadPrefs()).setString(key, value);
    } catch (_) {}
  }

  Future<bool> _hasNetwork() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }
}
