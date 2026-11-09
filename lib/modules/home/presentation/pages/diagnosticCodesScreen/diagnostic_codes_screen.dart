import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_history_service.dart';
import '../../../../../core/services/dtc_repository.dart';
import '../../../../../core/services/maintenance_service.dart';
import '../../../../../core/services/obd_service.dart';

// ── DTC view model ─────────────────────────────────────────────────────────────

class _DtcItem {
  final String code;
  final String description;
  final String system;
  final String severity;
  final bool isPending; // true = mode 07 code, not yet confirmed by ECU
  final Map<String, String> freezeFrame; // sensor snapshot when fault occurred

  const _DtcItem({
    required this.code,
    required this.description,
    required this.system,
    required this.severity,
    this.isPending = false,
    this.freezeFrame = const {},
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class DiagnosticCodesScreen extends StatefulWidget {
  /// Inject a custom [DtcRepository] (useful in tests to avoid real I/O).
  final DtcRepository? repository;

  const DiagnosticCodesScreen({super.key, this.repository});

  @override
  State<DiagnosticCodesScreen> createState() => _DiagnosticCodesScreenState();
}

class _DiagnosticCodesScreenState extends State<DiagnosticCodesScreen> {
  late final DtcRepository _repo = widget.repository ?? DtcRepository();

  bool _loading = false;
  bool _clearing = false;
  String? _errorMessage;
  List<_DtcItem> _dtcItems = [];
  String _selectedFilter = 'All';
  ReadinessResult? _readiness;

  static const _filters = ['All', 'Engine', 'Chassis', 'Body', 'Network'];

  static const Color _colCritical = Color(0xFFFF1744);
  static const Color _colWarning = Color(0xFFFF6B35);
  static const Color _colInfo = Color(0xFFFFD600);

  @override
  void initState() {
    super.initState();
    _fetchDtcs();
    _fetchMonitors();
  }

  Future<void> _fetchMonitors() async {
    if (!OBDService.instance.isInitialized) return;
    final monitors = await OBDService.instance.getReadinessMonitors();
    if (!mounted) return;
    setState(() => _readiness = monitors);
  }

  // ── Export report ─────────────────────────────────────────────────────────

  Future<void> _exportReport(BuildContext shareContext) async {
    String t(String key) => context.tr(key);
    final d = OBDService.instance.currentData;
    final device =
        OBDService.instance.connectedDeviceName ?? t('report_default_adapter');
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-'
        '${now.day.toString().padLeft(2,'0')} '
        '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    final buf = StringBuffer();
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('  ${t('report_title')}');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('${t('report_date')}     : $dateStr');
    buf.writeln('${t('report_adapter')}  : $device');
    buf.writeln();

    // ── Fault codes ──────────────────────────────────────────────────────
    final confirmed = _dtcItems.where((i) => !i.isPending).toList();
    final pending   = _dtcItems.where((i) =>  i.isPending).toList();

    buf.writeln('── ${t('report_fault_codes').replaceAll('{n}', '${_dtcItems.length}')} ──────────────');
    if (_dtcItems.isEmpty) {
      buf.writeln('  ${t('report_no_codes')}');
    } else {
      for (final item in confirmed) {
        buf.writeln('  [${t('severity_${item.severity}').toUpperCase()}] ${item.code}');
        buf.writeln('    ${item.description}');
        if (item.freezeFrame.isNotEmpty) {
          buf.writeln('    ${t('report_freeze_frame')}');
          item.freezeFrame.forEach((k, v) => buf.writeln(
              '      ${_freezeFrameLabel(k)}: ${_freezeFrameValue(v)}'));
        }
      }
      if (pending.isNotEmpty) {
        buf.writeln();
        buf.writeln('  ${t('report_pending_codes')}');
        for (final item in pending) {
          buf.writeln('  [${t('report_pending_tag')}] ${item.code}  ${item.description}');
        }
      }
    }

    // ── Readiness monitors ───────────────────────────────────────────────
    if (_readiness != null && _readiness!.monitors.isNotEmpty) {
      buf.writeln();
      buf.writeln('── ${t('report_emissions')} ─────────────────────────');
      buf.writeln('  ${t('report_mil_line')
          .replaceAll('{state}', t(_readiness!.milOn ? 'report_on' : 'report_off'))
          .replaceAll('{n}', '${_readiness!.dtcCount}')}');
      for (final m in _readiness!.monitors) {
        final status = switch (m.status) {
          MonitorStatus.ready          => '✓ ${t('monitor_ready')}',
          MonitorStatus.notReady       => '✗ ${t('monitor_not_ready')}',
          MonitorStatus.notApplicable  => '⬜ ${t('monitor_na')}',
        };
        buf.writeln('  $status  ${_monitorLabel(m.name)}');
      }
    }

    // ── Live sensor readings ─────────────────────────────────────────────
    buf.writeln();
    buf.writeln('── ${t('report_live_sensors')} ────────────────────────');
    void sensor(String label, double? v, String unit) {
      final val = v != null ? '${v.toStringAsFixed(1)} $unit' : t('monitor_na');
      buf.writeln('  $label: $val');
    }
    String bank(String key, int n) => t(key).replaceAll('{n}', '$n');
    sensor(t('report_sensor_rpm'),      d.rpm,              t('report_unit_rpm'));
    sensor(t('report_sensor_speed'),    d.speedKmh,         t('unit_kmh'));
    sensor(t('report_sensor_coolant'),  d.coolantTempC,     '°C');
    sensor(t('report_sensor_load'),     d.engineLoad,       '%');
    sensor(t('report_sensor_throttle'), d.throttlePct,      '%');
    sensor(t('report_sensor_fuel'),     d.fuelLevelPct,     '%');
    sensor(t('report_sensor_battery'),  d.batteryVoltage,   'V');
    sensor(t('report_sensor_oil'),      d.oilTempC,         '°C');
    sensor(t('report_sensor_iat'),      d.intakeAirTempC,   '°C');
    sensor(bank('report_sensor_stft', 1), d.fuelTrimShortPct, '%');
    sensor(bank('report_sensor_ltft', 1), d.fuelTrimLongPct,  '%');
    if (d.fuelTrimShortB2 != null) sensor(bank('report_sensor_stft', 2), d.fuelTrimShortB2, '%');
    if (d.fuelTrimLongB2  != null) sensor(bank('report_sensor_ltft', 2), d.fuelTrimLongB2,  '%');
    String o2(int b, int s) => t('report_sensor_o2')
        .replaceAll('{b}', '$b')
        .replaceAll('{s}', '$s');
    if (d.o2B1S1Voltage   != null) sensor(o2(1, 1),      d.o2B1S1Voltage,   'V');
    if (d.o2B1S2Voltage   != null) sensor(o2(1, 2),      d.o2B1S2Voltage,   'V');
    if (d.o2B2S1Voltage   != null) sensor(o2(2, 1),      d.o2B2S1Voltage,   'V');

    buf.writeln();
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln(t('report_generated_by'));
    final subject = t('report_subject').replaceAll('{date}', dateStr);

    // Text-only share: shareXFiles asserts a non-empty file list.
    final box = shareContext.findRenderObject() as RenderBox?;
    await Share.share(
      buf.toString(),
      subject: subject,
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  /// Localized name of a readiness monitor (the adapter reports English).
  String _monitorLabel(String name) {
    const keys = {
      'Misfire': 'monitor_misfire',
      'Fuel System': 'monitor_fuel_system',
      'Components': 'monitor_components',
      'Catalyst': 'monitor_catalyst',
      'Heated Catalyst': 'monitor_heated_catalyst',
      'Evap System': 'monitor_evap',
      'Secondary Air': 'monitor_secondary_air',
      'A/C System': 'monitor_ac',
      'O2 Sensor': 'monitor_o2',
      'O2 Sensor Heater': 'monitor_o2_heater',
      'EGR / VVT': 'monitor_egr_vvt',
      'NMHC Catalyst': 'monitor_nmhc',
      'NOx / SCR': 'monitor_nox_scr',
      'Boost Pressure': 'monitor_boost',
      'Exhaust Gas Sensor': 'monitor_exhaust_sensor',
      'PM Filter': 'monitor_pm_filter',
    };
    final key = keys[name];
    return key == null ? name : context.tr(key);
  }

  /// Localized freeze-frame label (the adapter reports English keys).
  String _freezeFrameLabel(String name) {
    const keys = {
      'RPM': 'report_sensor_rpm',
      'Speed': 'report_sensor_speed',
      'Coolant': 'report_sensor_coolant',
      'Engine Load': 'report_sensor_load',
      'Air Temp': 'report_sensor_iat',
      'Throttle': 'report_sensor_throttle',
      'Fuel Trim': 'ff_fuel_trim',
      'MAP': 'ff_map',
    };
    final key = keys[name];
    return key == null ? name : context.tr(key);
  }

  /// Localizes the unit suffix of a freeze-frame value ("850 rpm" …).
  String _freezeFrameValue(String value) {
    const units = {
      ' rpm': 'report_unit_rpm',
      ' km/h': 'unit_kmh',
      ' kPa': 'unit_kpa',
    };
    for (final e in units.entries) {
      if (value.endsWith(e.key)) {
        return '${value.substring(0, value.length - e.key.length)} '
            '${context.tr(e.value)}';
      }
    }
    return value;
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _fetchDtcs() async {
    if (!OBDService.instance.isInitialized) {
      setState(() {
        _errorMessage = 'not_connected';
        _dtcItems = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final codes = await OBDService.instance.getDtcs();
      if (!mounted) return;

      final isArabic = Localizations.localeOf(context).languageCode == 'ar';
      final lang = isArabic ? 'ar' : 'en';
      final noDescription = context.tr('dtc_no_description');

      final items = await Future.wait(codes.map((raw) async {
        // Codes prefixed with '~' are mode-07 pending codes.
        final isPending = raw.startsWith('~');
        final code = isPending ? raw.substring(1) : raw;
        final desc = await _repo.getDtcDescription(code, languageCode: lang);
        return _DtcItem(
          code: code,
          // Never repeat the bare code as its own description.
          description: (desc == null || desc.trim().isEmpty)
              ? noDescription
              : desc,
          system: _systemFromCode(code),
          severity: _severityFromCode(code),
          isPending: isPending,
        );
      }));

      if (!mounted) return;
      setState(() => _dtcItems = items);

      // Record this scan in history and keep maintenance mileage in sync.
      final mileage = MaintenanceService.instance.currentMileageKm;
      await DtcHistoryService.instance.record(codes: codes, mileageKm: mileage);

      // Fetch freeze frame after the list is shown so it doesn't block rendering.
      // Mode 02 stores ONE snapshot shared by all confirmed codes.
      if (items.any((i) => !i.isPending)) {
        final ff = await OBDService.instance.getFreezeFrame();
        if (!mounted || ff.isEmpty) return;
        setState(() {
          _dtcItems = _dtcItems.map((item) =>
            item.isPending ? item :
            _DtcItem(
              code: item.code,
              description: item.description,
              system: item.system,
              severity: item.severity,
              isPending: item.isPending,
              freezeFrame: ff,
            ),
          ).toList();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'fetch_error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearCodes() async {
    setState(() => _clearing = true);
    final ok = await OBDService.instance.clearDtcs();
    if (!mounted) return;
    if (ok) {
      // Re-scan immediately to confirm all codes were erased.
      await _fetchDtcs();
      if (mounted) setState(() => _clearing = false);
    } else {
      setState(() => _clearing = false);
      // Most often the ECU refused mode 04 ("7F 04 22", conditions not
      // correct) because the engine is running — tell the user how to retry.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('failed_clear_codes_hint')),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  // ── DTC metadata helpers ──────────────────────────────────────────────────

  String _systemFromCode(String code) {
    if (code.isEmpty) return 'Unknown';
    switch (code[0].toUpperCase()) {
      case 'P':
        return 'Engine';
      case 'C':
        return 'Chassis';
      case 'B':
        return 'Body';
      case 'U':
        return 'Network';
      default:
        return 'Unknown';
    }
  }

  String _severityFromCode(String code) {
    if (code.length < 2) return 'warning';
    // P0xxx/C0xxx/B0xxx/U0xxx = SAE standard = treat as critical
    // P1xxx/C1xxx etc = manufacturer specific = info
    final digit = code.length > 1 ? code[1] : '0';
    if (digit == '0') return 'critical';
    if (digit == '1') return 'info';
    return 'warning';
  }

  /// Localized label for an internal system / filter id ('All', 'Engine', …).
  String _systemLabel(String system) {
    switch (system) {
      case 'All':
        return context.tr('all');
      case 'Engine':
        return context.tr('engine');
      case 'Chassis':
        return context.tr('system_chassis');
      case 'Body':
        return context.tr('body');
      case 'Network':
        return context.tr('network');
      default:
        return context.tr('system_unknown');
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return _colCritical;
      case 'info':
        return _colInfo;
      default:
        return _colWarning;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error;
      case 'info':
        return Icons.info;
      default:
        return Icons.warning;
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────

  List<_DtcItem> get _filtered {
    if (_selectedFilter == 'All') return _dtcItems;
    return _dtcItems.where((d) => d.system == _selectedFilter).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.backgroundDark, AppColors.backgroundDarkBlue],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (!_loading && _errorMessage == null) _buildSummary(),
              if (_readiness != null && _readiness!.monitors.isNotEmpty) _buildReadinessMonitors(),
              _buildFilters(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Flexible(
            child: Text(
              context.tr('diagnostic_codes'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ),
          const Spacer(),
          if (_loading || _clearing)
            Padding(
              padding: EdgeInsetsDirectional.only(end: 8.w),
              child: SizedBox(
                width: 20.r,
                height: 20.r,
                child: CircularProgressIndicator(
                  color: AppColors.accentCyan,
                  strokeWidth: 2,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.accentCyan),
            onPressed: _loading ? null : _fetchDtcs,
          ),
          if (_dtcItems.isNotEmpty) ...[
            Builder(
              builder: (shareContext) => IconButton(
                icon: Icon(Icons.share_outlined, color: AppColors.accentCyan),
                onPressed: () => _exportReport(shareContext),
                tooltip: context.tr('export_report'),
              ),
            ),
            IconButton(
              icon: Icon(Icons.clear_all, color: AppColors.accentCyan),
              onPressed: _clearing ? null : _showClearDialog,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final confirmed = _dtcItems.where((d) => !d.isPending).length;
    final pending   = _dtcItems.where((d) =>  d.isPending).length;
    final critical  = _dtcItems.where((d) => d.severity == 'critical').length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.white.withValues(alpha: 0.05),
            AppColors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
            color: AppColors.accentCyan.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem(context.tr('dtc_confirmed'), confirmed, _colCritical),
          _summaryItem(context.tr('dtc_pending'), pending, const Color(0xFFFFD600)),
          _summaryItem(context.tr('severity_critical'), critical, _colWarning),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 32.sp,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        SizedBox(height: 5.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: AppColors.textLight.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildReadinessMonitors() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.03),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rtl, color: AppColors.accentCyan, size: 16.r),
              SizedBox(width: 8.w),
              Text(
                context.tr('emissions_readiness'),
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentCyan,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // MIL + DTC count row
          Row(
            children: [
              _milBadge(_readiness!.milOn),
              SizedBox(width: 10.w),
              Text(
                _readiness!.dtcCount == 1
                    ? context.tr('dtc_stored_one')
                    : context.tr('dtcs_stored')
                        .replaceAll('{n}', '${_readiness!.dtcCount}'),
                style: TextStyle(fontSize: 12.sp, color: AppColors.textLight.withValues(alpha: 0.7)),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // Monitor rows — two per line
          ...(() {
            final monitors = _readiness!.monitors;
            final rows = <Widget>[];
            for (var i = 0; i < monitors.length; i += 2) {
              rows.add(Row(
                children: [
                  Expanded(child: _monitorTile(monitors[i])),
                  SizedBox(width: 8.w),
                  if (i + 1 < monitors.length)
                    Expanded(child: _monitorTile(monitors[i + 1]))
                  else
                    const Expanded(child: SizedBox()),
                ],
              ));
              if (i + 2 < monitors.length) rows.add(SizedBox(height: 6.h));
            }
            return rows;
          })(),
        ],
      ),
    );
  }

  Widget _milBadge(bool on) {
    final color = on ? const Color(0xFFFF1744) : const Color(0xFF00E676);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: color, size: 13.r),
          SizedBox(width: 4.w),
          Text(
            context.tr(on ? 'mil_on' : 'mil_off'),
            style: TextStyle(fontSize: 11.sp, color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _monitorTile(ReadinessMonitor m) {
    final Color color;
    final IconData icon;
    final String label;
    switch (m.status) {
      case MonitorStatus.ready:
        color = const Color(0xFF00E676);
        icon  = Icons.check_circle;
        label = context.tr('monitor_ready');
        break;
      case MonitorStatus.notReady:
        color = const Color(0xFFFF6B35);
        icon  = Icons.cancel;
        label = context.tr('monitor_not_ready');
        break;
      case MonitorStatus.notApplicable:
        color = Colors.white24;
        icon  = Icons.remove_circle_outline;
        label = context.tr('monitor_na');
        break;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14.r),
          SizedBox(width: 6.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _monitorLabel(m.name),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.textLight.withValues(alpha: m.isApplicable ? 0.9 : 0.4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 9.sp, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 50.h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 5.h),
        itemCount: _filters.length,
        itemBuilder: (_, i) {
          final f = _filters[i];
          final sel = f == _selectedFilter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = f),
            child: Container(
              margin: EdgeInsetsDirectional.only(end: 10.w),
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        colors: [AppColors.accentCyan, AppColors.accentOrange])
                    : null,
                color: sel ? null : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: sel
                      ? AppColors.transparent
                      : AppColors.accentCyan.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(25.r),
              ),
              child: Center(
                child: Text(
                  _systemLabel(f),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: sel ? AppColors.white : AppColors.textLight,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_errorMessage == 'not_connected') return _buildNotConnected();
    if (_errorMessage != null) return _buildError();
    if (_filtered.isEmpty) return _buildEmpty();
    return _buildList();
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.accentCyan),
          SizedBox(height: 20.h),
          Text(
            context.tr('reading_codes'),
            style: TextStyle(fontSize: 14.sp, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnected() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled,
              size: 80.r, color: Colors.redAccent.withValues(alpha: 0.5)),
          SizedBox(height: 20.h),
          Text(
            context.tr('no_obd_connected'),
            style: TextStyle(fontSize: 18.sp, color: AppColors.textLight),
          ),
          SizedBox(height: 10.h),
          Text(
            context.tr('connect_elm_first'),
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.connectionscreen),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
            ),
            child: Text(context.tr('go_to_connection')),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 80.r, color: Colors.redAccent.withValues(alpha: 0.5)),
          SizedBox(height: 20.h),
          Text(
            context.tr('failed_read_codes'),
            style: TextStyle(fontSize: 18.sp, color: AppColors.textLight),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: _fetchDtcs,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
            ),
            child: Text(context.tr('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 80.r,
              color: const Color(0xFF00E676).withValues(alpha: 0.5)),
          SizedBox(height: 20.h),
          Text(
            context.tr('no_codes_found'),
            style: TextStyle(fontSize: 18.sp, color: AppColors.textLight),
          ),
          SizedBox(height: 8.h),
          Text(
            context.tr('no_stored_codes'),
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: EdgeInsets.all(20.r),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _buildCodeItem(_filtered[i], i),
    );
  }

  Widget _buildCodeItem(_DtcItem item, int index) {
    final color = _severityColor(item.severity);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + index * 80),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(40 * (1 - v), 0), child: child),
      ),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.codeDetail,
          arguments: {
            'code': item.code,
            'title': item.description,
            'title_ar': item.description,
            'severity': item.severity,
            'system': item.system,
            'system_ar': _systemLabel(item.system),
            'description': item.description,
            'description_ar': item.description,
            'pending': item.isPending,
          },
        ),
        child: Container(
          margin: EdgeInsets.only(bottom: 15.h),
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.03),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _codeChip(item.code, color),
                  SizedBox(width: 10.w),
                  _systemChip(item.system),
                  if (item.isPending) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFFFFD600)),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        context.tr('dtc_pending'),
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: const Color(0xFFFFD600),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(_severityIcon(item.severity), color: color, size: 24.r),
                ],
              ),
              SizedBox(height: 12.h),
              Text(
                item.description,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textLight.withValues(alpha: 0.85),
                  height: 1.4,
                ),
              ),
              // Freeze frame snapshot ────────────────────────────────────────
              if (item.freezeFrame.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.all(12.r),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: AppColors.accentCyan.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              color: AppColors.accentCyan, size: 13.r),
                          SizedBox(width: 5.w),
                          Text(
                            context.tr('freeze_frame_title'),
                            style: TextStyle(
                              fontSize: 10.sp,
                              color: AppColors.accentCyan,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 6.h,
                        children: item.freezeFrame.entries.map((e) =>
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: AppColors.accentCyan.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(
                              '${_freezeFrameLabel(e.key)}: '
                              '${_freezeFrameValue(e.value)}',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: AppColors.textLight.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ).toList(),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    context.tr('view_details'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 5.w),
                  Icon(Icons.arrow_forward,
                      color: AppColors.accentCyan, size: 16.r),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeChip(String code, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _systemChip(String system) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.accentCyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        _systemLabel(system),
        style: TextStyle(
          fontSize: 11.sp,
          color: AppColors.accentCyan,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Clear codes dialog ────────────────────────────────────────────────────

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text(context.tr('clear_codes'),
            style: const TextStyle(color: AppColors.textLight)),
        content: Text(
          context.tr('clear_codes_content'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel'),
                style: const TextStyle(color: AppColors.accentCyan)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearCodes();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text(context.tr('clear')),
          ),
        ],
      ),
    );
  }
}
