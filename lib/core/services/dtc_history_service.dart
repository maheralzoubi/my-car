import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ──────────────────────────────────────────────────────────────────────

class DtcHistoryEntry {
  final DateTime scannedAt;
  final double mileageKm;
  final List<String> codes; // raw codes including '~' pending prefix

  const DtcHistoryEntry({
    required this.scannedAt,
    required this.mileageKm,
    required this.codes,
  });

  bool get hasCodes => codes.isNotEmpty;
  int get confirmedCount => codes.where((c) => !c.startsWith('~')).length;
  int get pendingCount   => codes.where((c) =>  c.startsWith('~')).length;

  Map<String, dynamic> toJson() => {
        'scannedAt':  scannedAt.toIso8601String(),
        'mileageKm':  mileageKm,
        'codes':      codes,
      };

  factory DtcHistoryEntry.fromJson(Map<String, dynamic> j) => DtcHistoryEntry(
        scannedAt:  DateTime.parse(j['scannedAt'] as String),
        mileageKm:  (j['mileageKm'] as num).toDouble(),
        codes:      List<String>.from(j['codes'] as List),
      );
}

// ── Service ────────────────────────────────────────────────────────────────────

class DtcHistoryService {
  DtcHistoryService._();
  static final DtcHistoryService instance = DtcHistoryService._();

  static const _prefKey  = 'dtc_history_v1';
  static const _maxEntries = 50;

  List<DtcHistoryEntry> _entries = [];
  List<DtcHistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      // Skip unreadable entries one by one: dropping the whole list here
      // would let the next record() overwrite every good entry on disk.
      final parsed = <DtcHistoryEntry>[];
      for (final e in list) {
        try {
          parsed.add(DtcHistoryEntry.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }
      _entries = parsed..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    } catch (_) {}
  }

  /// Record a completed scan. Call this from the diagnostic screen after fetching DTCs.
  Future<void> record({
    required List<String> codes,
    required double mileageKm,
  }) async {
    final entry = DtcHistoryEntry(
      scannedAt: DateTime.now(),
      mileageKm: mileageKm,
      codes: codes,
    );
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) _entries = _entries.take(_maxEntries).toList();
    await _save();
  }

  Future<void> clearHistory() async {
    _entries = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }
}
