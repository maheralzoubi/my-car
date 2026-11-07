import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/core.dart';
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

  /// When the last successful scan finished (header subtitle).
  DateTime? _lastScan;

  /// Readiness card: per-monitor list expanded.
  bool _showMonitors = false;

  static const _filters = ['All', 'Engine', 'Chassis', 'Body', 'Network'];

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
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('  ${t('report_title')}');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('${t('report_date')}     : $dateStr');
    buf.writeln('${t('report_adapter')}  : $device');
    buf.writeln();

    // ── Fault codes ──────────────────────────────────────────────────────
    final confirmed = _dtcItems.where((i) => !i.isPending).toList();
    final pending = _dtcItems.where((i) => i.isPending).toList();

    buf.writeln(
      '── ${t('report_fault_codes').replaceAll('{n}', '${_dtcItems.length}')} ──────────────',
    );
    if (_dtcItems.isEmpty) {
      buf.writeln('  ${t('report_no_codes')}');
    } else {
      for (final item in confirmed) {
        buf.writeln(
          '  [${t('severity_${item.severity}').toUpperCase()}] ${item.code}',
        );
        buf.writeln('    ${item.description}');
        if (item.freezeFrame.isNotEmpty) {
          buf.writeln('    ${t('report_freeze_frame')}');
          item.freezeFrame.forEach(
            (k, v) => buf.writeln(
              '      ${_freezeFrameLabel(k)}: ${_freezeFrameValue(v)}',
            ),
          );
        }
      }
      if (pending.isNotEmpty) {
        buf.writeln();
        buf.writeln('  ${t('report_pending_codes')}');
        for (final item in pending) {
          buf.writeln(
            '  [${t('report_pending_tag')}] ${item.code}  ${item.description}',
          );
        }
      }
    }

    // ── Readiness monitors ───────────────────────────────────────────────
    if (_readiness != null && _readiness!.monitors.isNotEmpty) {
      buf.writeln();
      buf.writeln('── ${t('report_emissions')} ─────────────────────────');
      buf.writeln(
        '  ${t('report_mil_line').replaceAll('{state}', t(_readiness!.milOn ? 'report_on' : 'report_off')).replaceAll('{n}', '${_readiness!.dtcCount}')}',
      );
      for (final m in _readiness!.monitors) {
        final status = switch (m.status) {
          MonitorStatus.ready => '✓ ${t('monitor_ready')}',
          MonitorStatus.notReady => '✗ ${t('monitor_not_ready')}',
          MonitorStatus.notApplicable => '⬜ ${t('monitor_na')}',
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
    sensor(t('report_sensor_rpm'), d.rpm, t('report_unit_rpm'));
    sensor(t('report_sensor_speed'), d.speedKmh, t('unit_kmh'));
    sensor(t('report_sensor_coolant'), d.coolantTempC, '°C');
    sensor(t('report_sensor_load'), d.engineLoad, '%');
    sensor(t('report_sensor_throttle'), d.throttlePct, '%');
    sensor(t('report_sensor_fuel'), d.fuelLevelPct, '%');
    sensor(t('report_sensor_battery'), d.batteryVoltage, 'V');
    sensor(t('report_sensor_oil'), d.oilTempC, '°C');
    sensor(t('report_sensor_iat'), d.intakeAirTempC, '°C');
    sensor(bank('report_sensor_stft', 1), d.fuelTrimShortPct, '%');
    sensor(bank('report_sensor_ltft', 1), d.fuelTrimLongPct, '%');
    if (d.fuelTrimShortB2 != null) {
      sensor(bank('report_sensor_stft', 2), d.fuelTrimShortB2, '%');
    }
    if (d.fuelTrimLongB2 != null) {
      sensor(bank('report_sensor_ltft', 2), d.fuelTrimLongB2, '%');
    }
    String o2(int b, int s) =>
        t('report_sensor_o2').replaceAll('{b}', '$b').replaceAll('{s}', '$s');
    if (d.o2B1S1Voltage != null) sensor(o2(1, 1), d.o2B1S1Voltage, 'V');
    if (d.o2B1S2Voltage != null) sensor(o2(1, 2), d.o2B1S2Voltage, 'V');
    if (d.o2B2S1Voltage != null) sensor(o2(2, 1), d.o2B2S1Voltage, 'V');

    buf.writeln();
    buf.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buf.writeln(t('report_generated_by'));
    final subject = t('report_subject').replaceAll('{date}', dateStr);

    // Text-only share: shareXFiles asserts a non-empty file list.
    final box = shareContext.findRenderObject() as RenderBox?;
    await Share.share(
      buf.toString(),
      subject: subject,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
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

      final items = await Future.wait(
        codes.map((raw) async {
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
        }),
      );

      if (!mounted) return;
      setState(() {
        _dtcItems = items;
        _lastScan = DateTime.now();
      });

      // Record this scan in history and keep maintenance mileage in sync.
      final mileage = MaintenanceService.instance.currentMileageKm;
      await DtcHistoryService.instance.record(codes: codes, mileageKm: mileage);

      // Fetch freeze frame after the list is shown so it doesn't block rendering.
      // Mode 02 stores ONE snapshot shared by all confirmed codes.
      if (items.any((i) => !i.isPending)) {
        final ff = await OBDService.instance.getFreezeFrame();
        if (!mounted || ff.isEmpty) return;
        setState(() {
          _dtcItems = _dtcItems
              .map(
                (item) => item.isPending
                    ? item
                    : _DtcItem(
                        code: item.code,
                        description: item.description,
                        system: item.system,
                        severity: item.severity,
                        isPending: item.isPending,
                        freezeFrame: ff,
                      ),
              )
              .toList();
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

  /// Maps a code onto the app-wide [StatusLevel] so DTC severity looks the
  /// same on every screen. Pending (mode 07) codes read as info.
  StatusLevel _levelOf(_DtcItem item) {
    if (item.isPending) return StatusLevel.info;
    switch (item.severity) {
      case 'critical':
        return StatusLevel.critical;
      case 'info':
        return StatusLevel.info;
      default:
        return StatusLevel.warning;
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────

  List<_DtcItem> get _filtered {
    if (_selectedFilter == 'All') return _dtcItems;
    return _dtcItems.where((d) => d.system == _selectedFilter).toList();
  }

  int _countFor(String filter) => filter == 'All'
      ? _dtcItems.length
      : _dtcItems.where((d) => d.system == filter).length;

  bool get _busy => _loading || _clearing;

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openDetail(_DtcItem item) {
    Navigator.pushNamed(
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
        // Already localized: the detail screen shows it as-is.
        if (item.freezeFrame.isNotEmpty)
          'freeze_frame': <String, String>{
            for (final e in item.freezeFrame.entries)
              _freezeFrameLabel(e.key): _freezeFrameValue(e.value),
          },
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showList = !_loading && _errorMessage == null;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (showList) _buildFilters(),
            Expanded(child: _buildBody()),
            if (_errorMessage == null) _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final last = _lastScan;
    String? subtitle;
    if (last != null) {
      final time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(last),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      subtitle = context.tr('dtc_last_scan').replaceAll('{time}', time);
    }
    return ScreenHeader(
      title: context.tr('diagnostic_codes'),
      subtitle: subtitle,
      actions: [
        if (_dtcItems.isNotEmpty)
          Builder(
            builder: (shareContext) => HeaderAction(
              icon: Icons.share_outlined,
              tooltip: context.tr('export_report'),
              onPressed: () => _exportReport(shareContext),
            ),
          ),
        HeaderAction(
          icon: Icons.refresh_rounded,
          tooltip: context.tr('scan_again'),
          onPressed: _busy ? null : _fetchDtcs,
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 48.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space20.w,
          vertical: 6.h,
        ),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => SizedBox(width: AppSizes.space8.w),
        itemBuilder: (_, i) {
          final f = _filters[i];
          return AppFilterChip(
            label: _systemLabel(f),
            count: _countFor(f),
            selected: f == _selectedFilter,
            onTap: () => setState(() => _selectedFilter = f),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_errorMessage == 'not_connected') return _buildNotConnected();
    if (_errorMessage != null) return _buildError();
    final readiness = _readiness;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space20.w,
        AppSizes.space8.h,
        AppSizes.space20.w,
        AppSizes.space24.h,
      ),
      children: [
        if (_filtered.isEmpty) _buildEmpty() else _buildCodesCard(),
        if (readiness != null && readiness.monitors.isNotEmpty) ...[
          SizedBox(height: AppSizes.space16.h),
          _buildReadiness(readiness),
        ],
      ],
    );
  }

  Widget _buildLoading() {
    return EmptyState(
      icon: Icons.manage_search_rounded,
      iconColor: context.colors.primary,
      title: context.tr('reading_codes'),
      action: SizedBox.square(
        dimension: 24.r,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: context.colors.primary,
        ),
      ),
    );
  }

  Widget _buildNotConnected() {
    return EmptyState(
      icon: Icons.bluetooth_disabled_rounded,
      title: context.tr('no_obd_connected'),
      message: context.tr('connect_elm_first'),
      action: AppButton(
        label: context.tr('go_to_connection'),
        icon: Icons.bluetooth_searching_rounded,
        expand: false,
        onPressed: () =>
            Navigator.pushNamed(context, AppRoutes.connectionscreen),
      ),
    );
  }

  Widget _buildError() {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      iconColor: StatusLevel.critical.colorOf(context),
      title: context.tr('failed_read_codes'),
      action: AppButton(
        label: context.tr('retry'),
        icon: Icons.refresh_rounded,
        expand: false,
        onPressed: _fetchDtcs,
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSizes.space32.h),
      child: EmptyState(
        icon: Icons.check_circle_outline_rounded,
        iconColor: StatusLevel.ok.colorOf(context),
        title: context.tr('no_codes_found'),
        message: context.tr('no_stored_codes'),
      ),
    );
  }

  // ── Code list ─────────────────────────────────────────────────────────────

  /// One card: a summary strip, then one row per code split by hairlines.
  Widget _buildCodesCard() {
    final p = context.colors;
    final items = _filtered;
    final divider = Divider(height: 1, thickness: 1, color: p.border);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummary(),
          for (final item in items) ...[divider, _buildCodeRow(item)],
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final confirmed = _dtcItems.where((d) => !d.isPending).length;
    final pending = _dtcItems.where((d) => d.isPending).length;
    final critical = _dtcItems
        .where((d) => !d.isPending && d.severity == 'critical')
        .length;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space16.w,
        vertical: AppSizes.space12.h,
      ),
      child: Row(
        children: [
          _summaryItem(context.tr('dtc_confirmed'), confirmed, null),
          _summaryItem(context.tr('dtc_pending'), pending, null),
          _summaryItem(
            context.tr('severity_critical'),
            critical,
            critical > 0 ? StatusLevel.critical.colorOf(context) : null,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int count, Color? color) {
    final p = context.colors;
    return Expanded(
      child: Row(
        children: [
          Text(
            '$count',
            style: AppTextStyles.numeric(
              AppTextStyles.title,
            ).copyWith(color: color ?? p.text),
          ),
          SizedBox(width: 6.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label.copyWith(color: p.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeRow(_DtcItem item) {
    final p = context.colors;
    final level = _levelOf(item);
    final color = level.colorOf(context);
    return InkWell(
      onTap: () => _openDetail(item),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 64.h),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSizes.space16.w,
            14.h,
            AppSizes.space8.w,
            14.h,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBox(
                item.isPending ? Icons.hourglass_empty_rounded : level.icon,
                color: color,
                size: 36,
              ),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSizes.space8.w,
                      runSpacing: AppSizes.space4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.code,
                          style: AppTextStyles.numeric(
                            AppTextStyles.title,
                          ).copyWith(color: p.text),
                        ),
                        StatusBadge(
                          label: item.isPending
                              ? context.tr('dtc_pending')
                              : context.tr('severity_${item.severity}'),
                          level: level,
                        ),
                        Text(
                          _systemLabel(item.system),
                          style: AppTextStyles.caption.copyWith(color: p.muted),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSizes.space4.h),
                    Text(
                      item.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 22.r,
                  color: p.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Readiness ─────────────────────────────────────────────────────────────

  Widget _buildReadiness(ReadinessResult r) {
    final p = context.colors;
    final applicable = r.monitors.where((m) => m.isApplicable).toList();
    final ready = applicable.where((m) => m.isReady).length;
    final total = applicable.length;
    final level = total > 0 && ready == total
        ? StatusLevel.ok
        : StatusLevel.warning;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('emissions_readiness'),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
              SizedBox(width: AppSizes.space8.w),
              Flexible(
                child: StatusBadge(
                  label: context
                      .tr('dtc_monitors_ready')
                      .replaceAll('{ready}', '$ready')
                      .replaceAll('{total}', '$total'),
                  level: level,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusFull),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : ready / total,
              minHeight: 6.h,
              color: level.colorOf(context),
              backgroundColor: p.track,
            ),
          ),
          SizedBox(height: AppSizes.space12.h),
          Row(
            children: [
              StatusBadge(
                label: context.tr(r.milOn ? 'mil_on' : 'mil_off'),
                level: r.milOn ? StatusLevel.critical : StatusLevel.ok,
                showIcon: true,
              ),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Text(
                  r.dtcCount == 1
                      ? context.tr('dtc_stored_one')
                      : context
                            .tr('dtcs_stored')
                            .replaceAll('{n}', '${r.dtcCount}'),
                  style: AppTextStyles.label.copyWith(color: p.text2),
                ),
              ),
            ],
          ),
          if (_showMonitors) ...[
            SizedBox(height: AppSizes.space12.h),
            Divider(height: 1, thickness: 1, color: p.border),
            SizedBox(height: AppSizes.space4.h),
            for (final m in r.monitors) _monitorRow(m),
          ],
          SizedBox(height: AppSizes.space4.h),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              label: context.tr(
                _showMonitors ? 'dtc_hide_monitors' : 'dtc_show_monitors',
              ),
              icon: _showMonitors
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              onPressed: () => setState(() => _showMonitors = !_showMonitors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monitorRow(ReadinessMonitor m) {
    final p = context.colors;
    final (Color color, IconData icon, String label) = switch (m.status) {
      MonitorStatus.ready => (
        StatusLevel.ok.colorOf(context),
        Icons.check_circle_outline_rounded,
        context.tr('monitor_ready'),
      ),
      MonitorStatus.notReady => (
        StatusLevel.warning.colorOf(context),
        Icons.cancel_outlined,
        context.tr('monitor_not_ready'),
      ),
      MonitorStatus.notApplicable => (
        p.muted,
        Icons.remove_circle_outline_rounded,
        context.tr('monitor_na'),
      ),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Icon(icon, size: 18.r, color: color),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              _monitorLabel(m.name),
              style: AppTextStyles.label.copyWith(
                color: m.isApplicable ? p.text : p.muted,
              ),
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          Text(label, style: AppTextStyles.label.copyWith(color: color)),
        ],
      ),
    );
  }

  // ── Bottom actions ────────────────────────────────────────────────────────

  Widget _buildActions() {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space20.w,
        AppSizes.space8.h,
        AppSizes.space20.w,
        AppSizes.space12.h,
      ),
      child: Row(
        children: [
          if (_dtcItems.isNotEmpty) ...[
            Expanded(
              child: AppButton.secondary(
                label: context.tr('dtc_clear_codes_action'),
                icon: Icons.delete_outline_rounded,
                isLoading: _clearing,
                onPressed: _busy ? null : _showClearDialog,
              ),
            ),
            SizedBox(width: AppSizes.space12.w),
          ],
          Expanded(
            child: AppButton(
              label: context.tr('scan_again'),
              icon: Icons.refresh_rounded,
              onPressed: _busy ? null : _fetchDtcs,
            ),
          ),
        ],
      ),
    );
  }

  // ── Clear codes dialog ────────────────────────────────────────────────────

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('clear_codes')),
        content: Text(context.tr('clear_codes_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _clearCodes();
            },
            // Destructive action.
            style: TextButton.styleFrom(
              foregroundColor: StatusLevel.critical.colorOf(context),
            ),
            child: Text(context.tr('clear')),
          ),
        ],
      ),
    );
  }
}
