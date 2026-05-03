import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class DtcRepository {
  static const String _assetPath = 'assets/dtcmapping.json';

  // TODO: move key/host to secure config for production
  static const String _rapidApiHost = 'car-code.p.rapidapi.com';
  static const String _rapidApiKey =
      '22a1b7c57amsh63c535f661d2b59p13d5b2jsn5b7dd5ed7f95';

  Map<String, String>? _localCodes;

  // Cache to avoid re-translating the same text
  final Map<String, String> _arabicCache = {};

  Future<Map<String, String>> _loadLocalCodes() async {
    if (_localCodes != null) return _localCodes!;

    final jsonStr = await rootBundle.loadString(_assetPath);
    final Map<String, dynamic> raw =
        jsonDecode(jsonStr) as Map<String, dynamic>;
    _localCodes = raw.map(
      (k, v) => MapEntry(k.toString().toUpperCase(), v.toString()),
    );
    return _localCodes!;
  }

  Future<bool> _hasNetwork() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.mobile) ||
        result.contains(ConnectivityResult.wifi) ||
        result.contains(ConnectivityResult.ethernet);
  }

  /// Returns a description for [code].
  ///
  /// Pass [languageCode] = 'ar' to get an Arabic description.
  /// Arabic descriptions are translated from English via the MyMemory API
  /// and cached for the lifetime of this instance.
  Future<String?> getDtcDescription(
    String code, {
    String languageCode = 'en',
  }) async {
    final englishDesc = await _getEnglishDescription(code);
    if (englishDesc == null) return null;
    if (languageCode != 'ar') return englishDesc;
    return _translateToArabic(englishDesc);
  }

  // ─── Internal ────────────────────────────────────────────────────────────

  Future<String?> _getEnglishDescription(String code) async {
    final normalized = code.trim().toUpperCase();
    final local = await _loadLocalCodes();

    final online = await _hasNetwork().catchError((_) => false);

    if (!online) return local[normalized];

    final localHit = local[normalized];
    if (localHit != null && localHit.isNotEmpty) return localHit;

    try {
      final apiDescription = await _fetchFromApi(normalized);
      return apiDescription ?? local[normalized];
    } catch (_) {
      return local[normalized];
    }
  }

  Future<String?> _fetchFromApi(String code) async {
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
      if (body['description'] is String) return body['description'] as String;
      if (body['meaning'] is String) return body['meaning'] as String;
      if (body['message'] is String) return body['message'] as String;
    }

    return null;
  }

  /// Translates [text] from English to Arabic using the free MyMemory API.
  /// Falls back to the original English text if translation fails.
  Future<String> _translateToArabic(String text) async {
    if (_arabicCache.containsKey(text)) return _arabicCache[text]!;

    try {
      final uri = Uri.parse(
        'https://api.mymemory.translated.net/get'
        '?q=${Uri.encodeComponent(text)}&langpair=en|ar',
      );

      final response =
          await http.get(uri).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final translated =
            (body['responseData'] as Map?)?['translatedText'] as String?;

        if (translated != null &&
            translated.isNotEmpty &&
            translated != text) {
          _arabicCache[text] = translated;
          return translated;
        }
      }
    } catch (_) {}

    // Fallback: return original English text
    return text;
  }
}
