import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DtcRepository {
  static const String _assetPath = 'assets/dtcmapping.json';

  // API key is injected at build time:
  //   flutter run  --dart-define=RAPID_API_KEY=your_key
  //   flutter build apk --dart-define=RAPID_API_KEY=your_key
  // Falls back to empty string — local DB still works without it.
  static const String _rapidApiHost = 'car-code.p.rapidapi.com';
  static const String _rapidApiKey = String.fromEnvironment(
    'RAPID_API_KEY',
    defaultValue: '22a1b7c57amsh63c535f661d2b59p13d5b2jsn5b7dd5ed7f95',
  );

  static const String _arPrefixKey = 'dtc_ar_';
  static const String _arAssetPath = 'assets/dtcmapping_ar.json';

  // Static so JSON is parsed once and shared across all DtcRepository instances.
  static Map<String, String>? _localCodes;
  static Map<String, String>? _arabicCodes;
  static SharedPreferences? _prefs;

  // In-memory cache for the current session — also static so all instances share it.
  static final Map<String, String> _arabicSessionCache = {};

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns an English or Arabic description for [code].
  ///
  /// Arabic translations are persisted to device storage after the first
  /// fetch so subsequent lookups (including offline) are instant.
  Future<String?> getDtcDescription(
    String code, {
    String languageCode = 'en',
  }) async {
    final normalized = code.trim().toUpperCase();
    final englishDesc = await _getEnglishDescription(normalized);
    if (englishDesc == null) return null;
    if (languageCode != 'ar') return englishDesc;
    // Use the code itself as the stable cache key — never hashCode.
    return _getArabic(englishDesc, cacheKey: normalized);
  }

  // ── English description ───────────────────────────────────────────────────

  Future<String?> _getEnglishDescription(String code) async {
    final local = await _loadLocalCodes();

    // Local hit — covers SAE P0/P2/P3, C, B, U ranges.
    final localHit = local[code];
    if (localHit != null && localHit.isNotEmpty) return localHit;

    // P1xxx codes are manufacturer-specific (SAE J2012).
    // P10xx is also in the P1 range and manufacturer-assigned, so the
    // whole P1xxx block is treated as manufacturer-specific when absent
    // from the local database.
    if (_isManufacturerSpecific(code)) {
      return _manufacturerLabel(code);
    }

    // For unknown SAE codes not yet in the local DB, try the online API.
    final online = await _hasNetwork().catchError((_) => false);
    if (!online) return null;

    try {
      return await _fetchFromApi(code);
    } catch (_) {
      return null;
    }
  }

  bool _isManufacturerSpecific(String code) =>
      code.length >= 2 && code[0] == 'P' && code[1] == '1';

  String _manufacturerLabel(String code) =>
      'Manufacturer-specific code ($code). Meaning varies by vehicle brand. '
      'Check your vehicle\'s service manual or dealer.';

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

  Future<String> _getArabic(String englishText, {required String cacheKey}) async {
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
    final prefs = await _loadPrefs();
    final prefKey = _arPrefixKey + cacheKey;
    final stored = prefs.getString(prefKey);
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

      final response = await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final translated =
            (body['responseData'] as Map?)?['translatedText'] as String?;

        if (translated != null &&
            translated.isNotEmpty &&
            translated != englishText) {
          await prefs.setString(prefKey, translated);
          _arabicSessionCache[cacheKey] = translated;
          return translated;
        }
      }
    } catch (_) {}

    return englishText; // Fallback: show English
  }

  // ── RapidAPI ──────────────────────────────────────────────────────────────

  Future<String?> _fetchFromApi(String code) async {
    if (_rapidApiKey.isEmpty) return null;

    final uri = Uri.https(_rapidApiHost, '/obd2/$code');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-rapidapi-host': _rapidApiHost,
        'x-rapidapi-key': _rapidApiKey,
      },
    );

    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic>) {
      return (body['description'] ?? body['meaning'] ?? body['message'])
          as String?;
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

  Future<bool> _hasNetwork() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }
}
