import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/dtc_history_service.dart';

const _key = 'dtc_history_v1';
final svc = DtcHistoryService.instance;

Map<String, dynamic> _entryJson(DateTime at, double km, List<String> codes) =>
    DtcHistoryEntry(scannedAt: at, mileageKm: km, codes: codes).toJson();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await svc.clearHistory(); // singleton: wipe in-memory state too
  });

  // ── Model ──────────────────────────────────────────────────────────────────

  group('DtcHistoryEntry', () {
    test('splits confirmed vs pending (Mode 07, "~" prefix) codes', () {
      final e = DtcHistoryEntry(
        scannedAt: DateTime(2026, 1, 1),
        mileageKm: 1000,
        codes: const ['P0420', '~P0171', 'C0035', '~U0100'],
      );
      expect(e.hasCodes, isTrue);
      expect(e.confirmedCount, 2);
      expect(e.pendingCount, 2);
    });

    test('a clean scan has no codes and zero counts', () {
      final e = DtcHistoryEntry(
          scannedAt: DateTime(2026, 1, 1), mileageKm: 0, codes: const []);
      expect(e.hasCodes, isFalse);
      expect(e.confirmedCount, 0);
      expect(e.pendingCount, 0);
    });

    test('JSON round-trip preserves timestamp, mileage and raw codes', () {
      final at = DateTime(2026, 3, 4, 5, 6, 7, 8);
      final e = DtcHistoryEntry(
          scannedAt: at, mileageKm: 123456.7, codes: const ['~P0300', 'B0001']);
      final back = DtcHistoryEntry.fromJson(
          jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.scannedAt, at);
      expect(back.mileageKm, 123456.7);
      expect(back.codes, ['~P0300', 'B0001']);
    });

    test('fromJson accepts integer mileage', () {
      final e = DtcHistoryEntry.fromJson({
        'scannedAt': '2026-01-01T00:00:00.000',
        'mileageKm': 5000,
        'codes': <dynamic>[],
      });
      expect(e.mileageKm, 5000.0);
    });
  });

  // ── record ─────────────────────────────────────────────────────────────────

  group('record', () {
    test('adds an entry stamped with now, newest first', () async {
      final before = DateTime.now();
      await svc.record(codes: ['P0420'], mileageKm: 10000);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await svc.record(codes: ['~P0171'], mileageKm: 10050);

      final list = svc.entries;
      expect(list, hasLength(2));
      expect(list.first.codes, ['~P0171']);
      expect(list.first.mileageKm, 10050);
      expect(list.last.codes, ['P0420']);
      expect(list.last.scannedAt.isBefore(before), isFalse);
      expect(list.first.scannedAt.isBefore(list.last.scannedAt), isFalse);
    });

    test('records clean scans (empty code list) too', () async {
      await svc.record(codes: [], mileageKm: 500);
      expect(svc.entries.single.hasCodes, isFalse);
    });

    test('persists to SharedPreferences as JSON', () async {
      await svc.record(codes: ['P0420', '~P0300'], mileageKm: 777.5);
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString(_key)!) as List;
      expect(raw, hasLength(1));
      expect(raw.first['codes'], ['P0420', '~P0300']);
      expect(raw.first['mileageKm'], 777.5);
      expect(DateTime.tryParse(raw.first['scannedAt'] as String), isNotNull);
    });

    test('caps history at 50 entries, dropping the oldest', () async {
      for (var i = 0; i < 55; i++) {
        await svc.record(codes: ['P${(300 + i).toString().padLeft(4, '0')}'],
            mileageKm: i.toDouble());
      }
      expect(svc.entries, hasLength(50));
      expect(svc.entries.first.mileageKm, 54); // newest kept
      expect(svc.entries.last.mileageKm, 5); // entries 0–4 dropped

      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(_key)!) as List, hasLength(50));
    });

    test('entries list is unmodifiable', () async {
      await svc.record(codes: ['P0420'], mileageKm: 1);
      expect(() => svc.entries.clear(), throwsUnsupportedError);
    });
  });

  // ── load ───────────────────────────────────────────────────────────────────

  group('load', () {
    test('restores persisted entries sorted newest first', () async {
      final older = DateTime(2025, 12, 1);
      final newer = DateTime(2026, 2, 1);
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode([
          _entryJson(older, 1000, ['P0420']),
          _entryJson(newer, 2000, ['~P0171', 'U0100']),
        ]),
      });

      await svc.load();

      expect(svc.entries, hasLength(2));
      expect(svc.entries.first.scannedAt, newer);
      expect(svc.entries.first.pendingCount, 1);
      expect(svc.entries.first.confirmedCount, 1);
      expect(svc.entries.last.scannedAt, older);
    });

    test('record → restart → load round-trips', () async {
      await svc.record(codes: ['P0301', '~P0302'], mileageKm: 42);
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key)!;

      // Simulate a cold start: fresh storage with the same bytes, empty memory.
      SharedPreferences.setMockInitialValues({_key: stored});
      await svc.load();

      expect(svc.entries.single.codes, ['P0301', '~P0302']);
      expect(svc.entries.single.mileageKm, 42);
    });

    test('nothing stored → no entries, no throw', () async {
      await svc.load();
      expect(svc.entries, isEmpty);
    });

    test('corrupt JSON is ignored without throwing', () async {
      SharedPreferences.setMockInitialValues({_key: '[{"scannedAt": 42'});
      await expectLater(svc.load(), completes);
      expect(svc.entries, isEmpty);
    });

    test('a structurally wrong entry is ignored without throwing', () async {
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode([
          {'scannedAt': 'not-a-date', 'mileageKm': 1, 'codes': []},
        ]),
      });
      await expectLater(svc.load(), completes);
      expect(svc.entries, isEmpty);
    });

    test('one bad entry does not discard (or later overwrite) the rest',
        () async {
      final good = DateTime(2026, 2, 1);
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode([
          {'scannedAt': 'not-a-date', 'mileageKm': 1, 'codes': []},
          _entryJson(good, 2000, ['P0420']),
          'not-an-object',
          {'scannedAt': '2026-01-01T00:00:00.000', 'codes': []}, // no mileage
        ]),
      });

      await svc.load();
      expect(svc.entries.single.scannedAt, good);

      // The next scan is appended to the surviving history on disk.
      await svc.record(codes: ['P0171'], mileageKm: 2100);
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(_key)!) as List;
      expect(stored, hasLength(2));
      expect(stored.last['codes'], ['P0420']);
    });
  });

  // ── clearHistory ───────────────────────────────────────────────────────────

  group('clearHistory', () {
    test('empties memory and storage', () async {
      await svc.record(codes: ['P0420'], mileageKm: 1);
      await svc.clearHistory();

      expect(svc.entries, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_key), isFalse);

      // And stays empty after a reload.
      await svc.load();
      expect(svc.entries, isEmpty);
    });
  });
}
