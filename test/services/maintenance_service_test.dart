import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/maintenance_service.dart';

const _itemsKey = 'maintenance_v1';
const _mileageKey = 'maintenance_mileage_v1';
const _ids = ['oil', 'tires', 'air', 'brakes', 'coolant', 'spark', 'belt'];

final svc = MaintenanceService.instance;

/// MaintenanceService is a singleton and load() does not reset items when no
/// data is saved, so tests reset it by loading an explicit "nothing logged"
/// record for every default item (plus any overrides).
Future<void> _resetService({
  double mileage = 0,
  Map<String, Map<String, dynamic>> saved = const {},
}) async {
  final all = <String, dynamic>{
    for (final id in _ids)
      id: {'lastMileageKm': null, 'lastServiceDate': null, 'notes': ''},
    ...saved,
  };
  SharedPreferences.setMockInitialValues({
    _itemsKey: jsonEncode(all),
    _mileageKey: mileage,
  });
  await svc.load();
}

MaintenanceItem _oil({double? lastKm, DateTime? lastDate}) => MaintenanceItem(
      id: 'oil',
      name: 'Oil Change',
      icon: '🛢️',
      intervalKm: 5000,
      intervalDays: 180,
      lastMileageKm: lastKm,
      lastServiceDate: lastDate,
    );

DateTime _daysAgo(int d) => DateTime.now().subtract(Duration(days: d));

MaintenanceItem _byId(String id) => svc.items.firstWhere((i) => i.id == id);

void main() {
  // ── MaintenanceItem: pure due/overdue maths ────────────────────────────────

  group('MaintenanceItem.overdueKm', () {
    test('is distance since service minus interval', () {
      final item = _oil(lastKm: 10000);
      expect(item.overdueKm(14000), -1000); // 1000 km left
      expect(item.overdueKm(15000), 0); // exactly at interval
      expect(item.overdueKm(16000), 1000); // 1000 km overdue
    });

    test('is 0 when no service mileage is logged', () {
      expect(_oil().overdueKm(123456), 0);
    });
  });

  group('MaintenanceItem.overdueDays', () {
    test('is days since service minus interval', () {
      expect(_oil(lastDate: _daysAgo(100)).overdueDays(), -80);
      expect(_oil(lastDate: _daysAgo(180)).overdueDays(), 0);
      expect(_oil(lastDate: _daysAgo(200)).overdueDays(), 20);
    });

    test('is 0 when no service date is logged', () {
      expect(_oil().overdueDays(), 0);
    });
  });

  group('MaintenanceItem.isDue (due-soon window: 200 km / 7 days)', () {
    test('km: 201 km before interval is not due, 200 km before is due', () {
      final item = _oil(lastKm: 10000, lastDate: DateTime.now());
      expect(item.isDue(14799), isFalse);
      expect(item.isDue(14800), isTrue);
      expect(item.isDue(15000), isTrue);
    });

    test('days: 8 days before interval is not due, 7 days before is due', () {
      expect(_oil(lastKm: 0, lastDate: _daysAgo(172)).isDue(0), isFalse);
      expect(_oil(lastKm: 0, lastDate: _daysAgo(173)).isDue(0), isTrue);
    });

    test('is due when EITHER distance or time is near the limit', () {
      // Low km but old date → due by time.
      expect(_oil(lastKm: 10000, lastDate: _daysAgo(179)).isDue(10100), isTrue);
      // Recent date but high km → due by distance.
      expect(
          _oil(lastKm: 10000, lastDate: DateTime.now()).isDue(14900), isTrue);
      // Neither.
      expect(
          _oil(lastKm: 10000, lastDate: _daysAgo(30)).isDue(11000), isFalse);
    });

    test(
      'an item with no service history is not reported as due',
      () {
        expect(_oil().isDue(50000), isFalse);
        expect(_oil().hasHistory, isFalse);
      },
    );

    test('mileage-only history is judged by distance alone', () {
      // Unknown date must not make it "due by time".
      expect(_oil(lastKm: 10000).isDue(11000), isFalse);
      expect(_oil(lastKm: 10000).isDue(14800), isTrue);
      expect(_oil(lastKm: 10000).isOverdue(15001), isTrue);
      expect(_oil(lastKm: 10000).hasHistory, isTrue);
    });

    test('date-only history is judged by time alone', () {
      // Unknown mileage must not make it "due by distance".
      expect(_oil(lastDate: _daysAgo(30)).isDue(999999), isFalse);
      expect(_oil(lastDate: _daysAgo(175)).isDue(0), isTrue);
      expect(_oil(lastDate: _daysAgo(181)).isOverdue(0), isTrue);
      expect(_oil(lastDate: _daysAgo(30)).hasHistory, isTrue);
    });
  });

  group('MaintenanceItem.isOverdue', () {
    test('km: exactly at the interval is not overdue; beyond it is', () {
      final item = _oil(lastKm: 10000, lastDate: DateTime.now());
      expect(item.isOverdue(15000), isFalse);
      expect(item.isOverdue(15000.5), isTrue);
    });

    test('days: exactly at the interval is not overdue; a day later is', () {
      expect(_oil(lastKm: 0, lastDate: _daysAgo(180)).isOverdue(0), isFalse);
      expect(_oil(lastKm: 0, lastDate: _daysAgo(181)).isOverdue(0), isTrue);
    });

    test('never-serviced item is not overdue', () {
      expect(_oil().isOverdue(999999), isFalse);
    });

    test('overdue implies due', () {
      final item = _oil(lastKm: 0, lastDate: DateTime.now());
      expect(item.isOverdue(6000), isTrue);
      expect(item.isDue(6000), isTrue);
    });
  });

  group('MaintenanceItem serialisation', () {
    test('copyWith keeps unspecified fields', () {
      final d = DateTime(2025, 1, 2);
      final item = _oil(lastKm: 100, lastDate: d).copyWith(notes: 'synthetic');
      expect(item.lastMileageKm, 100);
      expect(item.lastServiceDate, d);
      expect(item.notes, 'synthetic');
      expect(item.intervalKm, 5000);
    });

    test('toJson / fromDefaults round-trip', () {
      final d = DateTime(2025, 6, 1, 10, 30);
      final saved = _oil(lastKm: 42000.5, lastDate: d)
          .copyWith(notes: '5W-30')
          .toJson();
      final restored =
          MaintenanceItem.fromDefaults(_oil(), jsonDecode(jsonEncode(saved)));
      expect(restored.lastMileageKm, 42000.5);
      expect(restored.lastServiceDate, d);
      expect(restored.notes, '5W-30');
      expect(restored.intervalKm, 5000);
    });

    test('fromDefaults accepts integer mileage and tolerates a bad date', () {
      final r = MaintenanceItem.fromDefaults(_oil(), {
        'lastMileageKm': 30000,
        'lastServiceDate': 'not-a-date',
        'notes': null,
      });
      expect(r.lastMileageKm, 30000.0);
      expect(r.lastServiceDate, isNull);
      expect(r.notes, '');
    });
  });

  // ── MaintenanceService ─────────────────────────────────────────────────────

  group('MaintenanceService defaults', () {
    setUp(() => _resetService());

    test('exposes the 7 default items with sensible intervals', () {
      expect(svc.items.map((i) => i.id), _ids);
      expect(_byId('oil').intervalKm, 5000);
      expect(_byId('oil').intervalDays, 180);
      expect(_byId('belt').intervalKm, 80000);
      for (final i in svc.items) {
        expect(i.intervalKm, greaterThan(0));
        expect(i.intervalDays, greaterThan(0));
      }
    });

    test('items list is unmodifiable', () {
      expect(() => svc.items.add(_oil()), throwsUnsupportedError);
    });
  });

  group('MaintenanceService mileage', () {
    setUp(() => _resetService());

    test('setMileage stores and persists the odometer', () async {
      await svc.setMileage(52340.5);
      expect(svc.currentMileageKm, 52340.5);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(_mileageKey), 52340.5);
    });

    test('addMileage accumulates trip distance and persists', () async {
      await svc.setMileage(1000);
      await svc.addMileage(12.3);
      await svc.addMileage(0.7);
      expect(svc.currentMileageKm, closeTo(1013, 1e-9));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(_mileageKey), closeTo(1013, 1e-9));
    });

    test('load() reads persisted mileage; missing value → 0', () async {
      await _resetService(mileage: 88000);
      expect(svc.currentMileageKm, 88000);

      SharedPreferences.setMockInitialValues({});
      await svc.load();
      expect(svc.currentMileageKm, 0);
    });
  });

  group('MaintenanceService.logService', () {
    setUp(() => _resetService(mileage: 60000));

    test('stamps current mileage, today and notes on the item only',
        () async {
      final before = DateTime.now();
      await svc.logService('oil', notes: 'Synthetic 5W-30');

      final oil = _byId('oil');
      expect(oil.lastMileageKm, 60000);
      expect(oil.lastServiceDate, isNotNull);
      expect(oil.lastServiceDate!.isBefore(before), isFalse);
      expect(oil.notes, 'Synthetic 5W-30');

      expect(_byId('tires').lastMileageKm, isNull);
      expect(_byId('tires').lastServiceDate, isNull);
    });

    test('persists so a fresh load() restores it', () async {
      await svc.logService('brakes', notes: 'pads');
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(_itemsKey)!) as Map;
      expect(saved['brakes']['lastMileageKm'], 60000);
      expect(saved['brakes']['notes'], 'pads');

      // Simulate app restart with what was written.
      SharedPreferences.setMockInitialValues({
        _itemsKey: prefs.getString(_itemsKey)!,
        _mileageKey: 60000.0,
      });
      await svc.load();
      expect(_byId('brakes').lastMileageKm, 60000);
      expect(_byId('brakes').notes, 'pads');
      expect(_byId('brakes').lastServiceDate, isNotNull);
    });

    test('logged item is no longer due, and becomes due 200 km early',
        () async {
      await svc.logService('oil');
      expect(_byId('oil').isDue(svc.currentMileageKm), isFalse);

      await svc.setMileage(64799);
      expect(_byId('oil').isDue(svc.currentMileageKm), isFalse);
      await svc.setMileage(64800);
      expect(_byId('oil').isDue(svc.currentMileageKm), isTrue);
      expect(_byId('oil').isOverdue(svc.currentMileageKm), isFalse);
      await svc.setMileage(65001);
      expect(_byId('oil').isOverdue(svc.currentMileageKm), isTrue);
    });

    test('unknown item id is a no-op', () async {
      await svc.logService('turbo');
      expect(svc.items.every((i) => i.lastServiceDate == null), isTrue);
    });
  });

  group('MaintenanceService.dueCount', () {
    test('counts logged items inside their due window', () async {
      await _resetService(mileage: 20000);
      for (final id in _ids) {
        await svc.logService(id);
      }
      expect(svc.dueCount, 0);

      await svc.setMileage(24800); // oil: 200 km left
      expect(svc.dueCount, 1);

      await svc.setMileage(30000); // oil overdue, tires exactly at 10 000
      expect(svc.dueCount, 2);

      await svc.setMileage(100000); // everything past interval
      expect(svc.dueCount, _ids.length);
    });

    test('an item is overdue by time alone even when km is fine', () async {
      await _resetService(mileage: 1000, saved: {
        'coolant': {
          'lastMileageKm': 1000,
          'lastServiceDate': _daysAgo(1100).toIso8601String(),
          'notes': '',
        },
      });
      // 0 km driven since service, but 1100 days > 1095-day interval.
      expect(_byId('coolant').isDue(svc.currentMileageKm), isTrue);
      expect(_byId('coolant').isOverdue(svc.currentMileageKm), isTrue);
    });

    test(
      'fresh install with no service history reports nothing due',
      () async {
        await _resetService(mileage: 15000);
        expect(svc.dueCount, 0);
      },
    );

    test('only logged items count; the rest stay unknown', () async {
      await _resetService(mileage: 15000, saved: {
        'oil': {
          'lastMileageKm': 9000, // 6000 km ago → overdue
          'lastServiceDate': _daysAgo(10).toIso8601String(),
          'notes': '',
        },
      });
      expect(svc.dueCount, 1);
    });
  });

  group('MaintenanceService.load error handling', () {
    test('corrupt JSON does not throw and keeps mileage', () async {
      await _resetService();
      SharedPreferences.setMockInitialValues({
        _itemsKey: '{not json',
        _mileageKey: 5000.0,
      });
      await svc.load();
      expect(svc.currentMileageKm, 5000);
      expect(svc.items, hasLength(_ids.length));
    });

    test('unknown saved ids are ignored; missing ids keep defaults', () async {
      await _resetService();
      SharedPreferences.setMockInitialValues({
        _itemsKey: jsonEncode({
          'oil': {
            'lastMileageKm': 1234,
            'lastServiceDate': null,
            'notes': 'x',
          },
          'flux_capacitor': {'lastMileageKm': 1},
        }),
      });
      await svc.load();
      expect(svc.items.map((i) => i.id), _ids);
      expect(_byId('oil').lastMileageKm, 1234);
      expect(_byId('tires').lastMileageKm, isNull);
    });
  });
}
