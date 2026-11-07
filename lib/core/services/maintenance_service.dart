import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ── Model ──────────────────────────────────────────────────────────────────────

class MaintenanceItem {
  final String id;
  final String name;
  final String icon;
  final int intervalKm;
  final int intervalDays;
  final double? lastMileageKm;
  final DateTime? lastServiceDate;
  final String notes;

  const MaintenanceItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.intervalKm,
    required this.intervalDays,
    this.lastMileageKm,
    this.lastServiceDate,
    this.notes = '',
  });

  // Distance overdue (positive = overdue by that many km).
  double overdueKm(double currentMileage) {
    if (lastMileageKm == null) return 0;
    return (currentMileage - lastMileageKm!) - intervalKm;
  }

  // Days overdue (positive = overdue).
  int overdueDays() {
    if (lastServiceDate == null) return 0;
    final daysSince = DateTime.now().difference(lastServiceDate!).inDays;
    return daysSince - intervalDays;
  }

  /// True once a service has been logged. Without history the due state is
  /// unknown — the 0 returned by [overdueKm]/[overdueDays] is not "on time".
  bool get hasHistory => lastMileageKm != null || lastServiceDate != null;

  bool isDue(double currentMileage) =>
      (lastMileageKm != null && overdueKm(currentMileage) >= -200) ||
      (lastServiceDate != null && overdueDays() >= -7);

  bool isOverdue(double currentMileage) =>
      (lastMileageKm != null && overdueKm(currentMileage) > 0) ||
      (lastServiceDate != null && overdueDays() > 0);

  MaintenanceItem copyWith({
    double? lastMileageKm,
    DateTime? lastServiceDate,
    String? notes,
  }) =>
      MaintenanceItem(
        id: id,
        name: name,
        icon: icon,
        intervalKm: intervalKm,
        intervalDays: intervalDays,
        lastMileageKm: lastMileageKm ?? this.lastMileageKm,
        lastServiceDate: lastServiceDate ?? this.lastServiceDate,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'lastMileageKm': lastMileageKm,
        'lastServiceDate': lastServiceDate?.toIso8601String(),
        'notes': notes,
      };

  static MaintenanceItem fromDefaults(MaintenanceItem defaults, Map<String, dynamic> json) =>
      defaults.copyWith(
        lastMileageKm: (json['lastMileageKm'] as num?)?.toDouble(),
        lastServiceDate: json['lastServiceDate'] != null
            ? DateTime.tryParse(json['lastServiceDate'] as String)
            : null,
        notes: json['notes'] as String? ?? '',
      );
}

// ── Service ────────────────────────────────────────────────────────────────────

class MaintenanceService {
  MaintenanceService._();
  static final MaintenanceService instance = MaintenanceService._();

  static const _prefKey = 'maintenance_v1';
  static const _mileageKey = 'maintenance_mileage_v1';

  // Default items — user logs actual service dates/mileage against these.
  static final List<MaintenanceItem> _defaults = [
    const MaintenanceItem(id: 'oil',     name: 'Oil Change',       icon: '🛢️', intervalKm: 5000,  intervalDays: 180),
    const MaintenanceItem(id: 'tires',   name: 'Tire Rotation',    icon: '🛞', intervalKm: 10000, intervalDays: 365),
    const MaintenanceItem(id: 'air',     name: 'Air Filter',       icon: '💨', intervalKm: 20000, intervalDays: 730),
    const MaintenanceItem(id: 'brakes',  name: 'Brake Inspection', icon: '🛑', intervalKm: 20000, intervalDays: 365),
    const MaintenanceItem(id: 'coolant', name: 'Coolant Flush',    icon: '🌡️', intervalKm: 40000, intervalDays: 1095),
    const MaintenanceItem(id: 'spark',   name: 'Spark Plugs',      icon: '⚡', intervalKm: 30000, intervalDays: 1095),
    const MaintenanceItem(id: 'belt',    name: 'Timing Belt',      icon: '⚙️', intervalKm: 80000, intervalDays: 1825),
  ];

  List<MaintenanceItem> _items = List.from(_defaults);
  double _currentMileageKm = 0;

  List<MaintenanceItem> get items => List.unmodifiable(_items);
  double get currentMileageKm => _currentMileageKm;

  /// Logged items inside their due window. Never-serviced items don't count.
  int get dueCount => _items.where((i) => i.isDue(_currentMileageKm)).length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentMileageKm = prefs.getDouble(_mileageKey) ?? 0;
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _items = _defaults.map((d) {
          final saved = map[d.id] as Map<String, dynamic>?;
          return saved != null ? MaintenanceItem.fromDefaults(d, saved) : d;
        }).toList();
      } catch (_) {}
    }
  }

  Future<void> addMileage(double km) async {
    _currentMileageKm += km;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_mileageKey, _currentMileageKm);
  }

  Future<void> setMileage(double km) async {
    _currentMileageKm = km;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_mileageKey, _currentMileageKm);
  }

  Future<void> logService(String itemId, {String notes = ''}) async {
    _items = _items.map((item) {
      if (item.id != itemId) return item;
      return item.copyWith(
        lastMileageKm: _currentMileageKm,
        lastServiceDate: DateTime.now(),
        notes: notes,
      );
    }).toList();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {for (final i in _items) i.id: i.toJson()};
    await prefs.setString(_prefKey, jsonEncode(map));
  }
}
