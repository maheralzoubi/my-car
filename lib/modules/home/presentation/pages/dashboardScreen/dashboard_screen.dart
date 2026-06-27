import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_repository.dart';
import '../../../../../core/services/obd_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  DateTime? _lastBackPressTime;
  bool _scanningDtcs = false;
  final _dtcRepo = DtcRepository();

  // Sensor-threshold warnings updated in real-time from live OBD data.
  // Key = warning light label, value = true when threshold exceeded.
  final Map<String, bool> _sensorWarnings = {};
  StreamSubscription<OBDLiveData>? _liveWarningSub;

  List<Map<String, dynamic>> warningLights = [
    {'icon': '⚠️', 'label': 'check_engine', 'active': false, 'codes': <String>[]},
    {'icon': '🔋', 'label': 'battery',      'active': false, 'codes': <String>[]},
    {'icon': '🛢️', 'label': 'oil',          'active': false, 'codes': <String>[]},
    {'icon': '🛞', 'label': 'abs',           'active': false, 'codes': <String>[]},
    {'icon': '🛡️', 'label': 'airbag',       'active': false, 'codes': <String>[]},
    {'icon': '🌡️', 'label': 'temp',          'active': false, 'codes': <String>[]},
    {'icon': '⛽', 'label': 'fuel',           'active': false, 'codes': <String>[]},
    {'icon': '💨', 'label': 'exhaust',        'active': false, 'codes': <String>[]},
  ];

  @override
  void initState() {
    super.initState();
    _startPollingIfConnected();
  }

  void _startPollingIfConnected() {
    if (OBDService.instance.isInitialized) {
      OBDService.instance.startPolling();
      _fetchDtcsAndUpdateLights();
      _subscribeSensorThresholds();
    }
  }

  void _subscribeSensorThresholds() {
    _liveWarningSub?.cancel();
    _liveWarningSub = OBDService.instance.liveDataStream.listen((d) {
      if (!mounted) return;
      setState(() {
        // Temp: warn if coolant ≥ 105 °C (overheating range).
        _sensorWarnings['temp']    = d.coolantTempC != null && d.coolantTempC! >= 105;
        // Fuel: warn if fuel level ≤ 10 %.
        _sensorWarnings['fuel']    = d.fuelLevelPct != null && d.fuelLevelPct! <= 10;
        // Battery: warn if system voltage < 11.5 V (charging / battery fault).
        _sensorWarnings['battery'] = d.batteryVoltage != null && d.batteryVoltage! < 11.5;
      });
    });
  }

  Future<void> _fetchDtcsAndUpdateLights() async {
    if (!OBDService.instance.isInitialized) return;
    if (!mounted) return;
    setState(() => _scanningDtcs = true);

    final rawCodes = await OBDService.instance.getDtcs();
    if (!mounted) return;

    // Strip the '~' pending prefix so matching works the same for both
    // confirmed (mode 03) and pending (mode 07) codes.
    final codes = rawCodes.map((c) => c.startsWith('~') ? c.substring(1) : c).toList();

    List<String> codesFor(bool Function(String) test) =>
        codes.where(test).toList();

    // Prefixes owned by specific lights — excluded from the generic check-engine list.
    const specificPrefixes = [
      'P056', 'P057', 'P115',        // battery
      'P052', 'P053',                 // oil
      'P011', 'P012', 'P025',        // temp
      'P008', 'P009', 'P046',        // fuel
      'P042', 'P043', 'P044', 'P045', // exhaust
    ];
    bool isSpecific(String c) => _matchPrefix(c, specificPrefixes);

    setState(() {
      _scanningDtcs = false;
      warningLights = [
        // Check engine: residual P-codes not shown under any dedicated light.
        {'icon': '⚠️', 'label': 'check_engine',
          'codes': codesFor((c) => c.startsWith('P') && !isSpecific(c)),
          'active': codes.any((c) => c.startsWith('P') && !isSpecific(c))},
        {'icon': '🔋', 'label': 'battery',
          'codes': codesFor((c) => _matchPrefix(c, ['P056', 'P057', 'P115'])),
          'active': codes.any((c) => _matchPrefix(c, ['P056', 'P057', 'P115']))},
        {'icon': '🛢️', 'label': 'oil',
          'codes': codesFor((c) => _matchPrefix(c, ['P052', 'P053'])),
          'active': codes.any((c) => _matchPrefix(c, ['P052', 'P053']))},
        {'icon': '🛞', 'label': 'abs',
          'codes': codesFor((c) => c.startsWith('C')),
          'active': codes.any((c) => c.startsWith('C'))},
        {'icon': '🛡️', 'label': 'airbag',
          'codes': codesFor((c) => c.startsWith('B')),
          'active': codes.any((c) => c.startsWith('B'))},
        {'icon': '🌡️', 'label': 'temp',
          'codes': codesFor((c) => _matchPrefix(c, ['P011', 'P012', 'P025'])),
          'active': codes.any((c) => _matchPrefix(c, ['P011', 'P012', 'P025']))},
        {'icon': '⛽', 'label': 'fuel',
          'codes': codesFor((c) => _matchPrefix(c, ['P008', 'P009', 'P046'])),
          'active': codes.any((c) => _matchPrefix(c, ['P008', 'P009', 'P046']))},
        {'icon': '💨', 'label': 'exhaust',
          'codes': codesFor((c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045'])),
          'active': codes.any((c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045']))},
      ];
    });
  }

  bool _matchPrefix(String code, List<String> prefixes) =>
      prefixes.any((p) => code.startsWith(p));

  @override
  void dispose() {
    OBDService.instance.stopPolling();
    _liveWarningSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime != null &&
            now.difference(_lastBackPressTime!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
        } else {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('press_back_to_exit')),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Scaffold(
        body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0D0D), Color(0xFF0A1929)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHealthCard(),
                      SizedBox(height: 20.h),
                      _buildLiveDataSection(),
                      SizedBox(height: 30.h),
                      _buildWarningLightsSection(),
                      SizedBox(height: 30.h),
                      _buildQuickScanButton(),
                      SizedBox(height: 20.h),
                      _buildVideoTutorialsCard(),
                      SizedBox(height: 30.h),
                      _buildRecentScansSection(),
                      SizedBox(height: 80.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildHeader() {
    final isConnected = OBDService.instance.isInitialized;
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: isConnected ? _buildConnectedHeader() : _buildDisconnectedBanner(),
    );
  }

  Widget _buildConnectedHeader() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.h,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.directions_car, color: Colors.white, size: 24.r),
              ),
              SizedBox(width: 12.w),
              Flexible(
                child: Text(
                  OBDService.instance.connectedDeviceName ?? 'OBD-II Adapter',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8EAED),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.1),
            border: Border.all(color: const Color(0xFF00E676)),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8.w,
                height: 8.h,
                decoration: const BoxDecoration(
                  color: Color(0xFF00E676),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                context.tr('connected'),
                style: TextStyle(
                  fontSize: 12.sp,
                  color: const Color(0xFF00E676),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnectedBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.connectionscreen).then((_) {
          if (mounted) {
            _startPollingIfConnected();
            setState(() {});
            _fetchDtcsAndUpdateLights();
          }
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
          border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: const Color(0xFFFF6B35), size: 22.r),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('obd_not_connected'),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFF6B35),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    context.tr('tap_to_connect'),
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: const Color(0xFFFF6B35), size: 14.r),
          ],
        ),
      ),
    );
  }

  // ── Health score helpers ──────────────────────────────────────────────────

  /// 0–100 score derived from active DTC count.
  int get _healthScore {
    final active = warningLights.where((l) => l['active'] == true).length;
    if (active == 0) return 100;
    if (active == 1) return 80;
    if (active == 2) return 60;
    if (active <= 4) return 40;
    return 20;
  }

  String get _healthLabel {
    final s = _healthScore;
    if (s >= 90) return 'Excellent';
    if (s >= 70) return 'Good';
    if (s >= 50) return 'Fair';
    if (s >= 30) return 'Poor';
    return 'Critical';
  }

  Color get _healthColor {
    final s = _healthScore;
    if (s >= 90) return const Color(0xFF00E676);
    if (s >= 70) return const Color(0xFF00D9FF);
    if (s >= 50) return const Color(0xFFFFD600);
    if (s >= 30) return const Color(0xFFFF6B35);
    return Colors.redAccent;
  }

  // ── Card ──────────────────────────────────────────────────────────────────

  Widget _buildHealthCard() {
    final connected = OBDService.instance.isInitialized;

    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: connected
              ? _healthColor.withValues(alpha: 0.4)
              : const Color(0xFF00D9FF).withValues(alpha: 0.15),
        ),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: connected ? _buildHealthConnected() : _buildHealthDisconnected(),
    );
  }

  Widget _buildHealthConnected() {
    return StreamBuilder<OBDLiveData>(
      stream: OBDService.instance.liveDataStream,
      initialData: OBDService.instance.currentData,
      builder: (context, snapshot) {
        final d = snapshot.data ?? const OBDLiveData();
        final score   = _healthScore;
        final label   = _healthLabel;
        final hColor  = _healthColor;
        final activeDtcs = warningLights.where((l) => l['active'] == true).length;

        final rpmStr     = d.rpm != null          ? d.rpm!.toStringAsFixed(0)               : '--';
        final speedStr   = d.speedKmh != null     ? '${d.speedKmh!.toStringAsFixed(0)} km/h' : '--';
        final coolantStr = d.coolantTempC != null  ? '${d.coolantTempC!.toStringAsFixed(0)}°C' : '--';
        final fuelStr    = d.fuelLevelPct != null  ? '${d.fuelLevelPct!.toStringAsFixed(0)}%'  : '--';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('vehicle_health'),
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8EAED),
                  ),
                ),
                // Score badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: hColor.withValues(alpha: 0.15),
                    border: Border.all(color: hColor),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.favorite, color: hColor, size: 13.r),
                      SizedBox(width: 5.w),
                      Text(
                        '$score%  $label',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: hColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Health bar ──────────────────────────────────────────────────
            SizedBox(height: 14.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(4.r),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 6.h,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(hColor),
              ),
            ),

            // ── DTC alert ───────────────────────────────────────────────────
            if (activeDtcs > 0) ...[
              SizedBox(height: 10.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: const Color(0xFFFF6B35), size: 14.r),
                    SizedBox(width: 6.w),
                    Text(
                      '$activeDtcs active fault ${activeDtcs == 1 ? 'code' : 'codes'} detected',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: const Color(0xFFFF6B35),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Live metrics grid ────────────────────────────────────────────
            SizedBox(height: 16.h),
            Row(
              children: [
                _buildMetricTile(Icons.speed,        'RPM',     rpmStr,     const Color(0xFF00D9FF)),
                SizedBox(width: 10.w),
                _buildMetricTile(Icons.directions_car,'Speed',  speedStr,   const Color(0xFF00E676)),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                _buildMetricTile(Icons.thermostat,   'Coolant', coolantStr, const Color(0xFFFFD600)),
                SizedBox(width: 10.w),
                _buildMetricTile(Icons.local_gas_station,'Fuel', fuelStr,   const Color(0xFFFF6B35)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildHealthDisconnected() {
    return Column(
      children: [
        SizedBox(height: 8.h),
        Row(
          children: [
            Container(
              width: 48.w,
              height: 48.h,
              decoration: BoxDecoration(
                color: const Color(0xFF00D9FF).withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF00D9FF).withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.bluetooth_searching,
                  color: const Color(0xFF00D9FF), size: 24.r),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('vehicle_health'),
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE8EAED),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Connect your OBD-II adapter to see live vehicle health data.',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: const Color(0xFFE8EAED).withValues(alpha: 0.5),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        // Placeholder metric tiles
        Row(
          children: [
            _buildMetricTile(Icons.speed,        'RPM',     '--', Colors.white24),
            SizedBox(width: 10.w),
            _buildMetricTile(Icons.directions_car,'Speed',  '--', Colors.white24),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            _buildMetricTile(Icons.thermostat,   'Coolant', '--', Colors.white24),
            SizedBox(width: 10.w),
            _buildMetricTile(Icons.local_gas_station,'Fuel','--', Colors.white24),
          ],
        ),
        SizedBox(height: 8.h),
      ],
    );
  }

  Widget _buildMetricTile(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18.r),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: const Color(0xFFE8EAED).withValues(alpha: 0.55),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: color == Colors.white24
                          ? const Color(0xFFE8EAED).withValues(alpha: 0.2)
                          : color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveDataSection() {
    return StreamBuilder<OBDLiveData>(
      stream: OBDService.instance.liveDataStream,
      initialData: OBDService.instance.currentData,
      builder: (context, snapshot) {
        final d = snapshot.data ?? const OBDLiveData();
        return Container(
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: const Color(0xFF00D9FF).withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.speed, color: Color(0xFF00D9FF), size: 20.r),
                  SizedBox(width: 8.w),
                  Text(
                    'Live Data',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8EAED),
                    ),
                  ),
                  const Spacer(),
                  if (OBDService.instance.isInitialized)
                    Container(
                      width: 8.w,
                      height: 8.h,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              SizedBox(height: 16.h),
              Row(
                children: [
                  _buildLiveTile(
                    'RPM',
                    d.rpm != null ? d.rpm!.toStringAsFixed(0) : '--',
                    'rpm',
                    Icons.rotate_right,
                    const Color(0xFF00D9FF),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    'Speed',
                    d.speedKmh != null ? d.speedKmh!.toStringAsFixed(0) : '--',
                    'km/h',
                    Icons.speed,
                    const Color(0xFF00E676),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    'Coolant',
                    d.coolantTempC != null ? d.coolantTempC!.toStringAsFixed(0) : '--',
                    '°C',
                    Icons.thermostat,
                    const Color(0xFFFFD600),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  _buildLiveTile(
                    'Throttle',
                    d.throttlePct != null ? d.throttlePct!.toStringAsFixed(1) : '--',
                    '%',
                    Icons.tune,
                    const Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    'Fuel',
                    d.fuelLevelPct != null ? d.fuelLevelPct!.toStringAsFixed(1) : '--',
                    '%',
                    Icons.local_gas_station,
                    const Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    'Engine Load',
                    d.engineLoad != null ? d.engineLoad!.toStringAsFixed(1) : '--',
                    '%',
                    Icons.settings,
                    const Color(0xFF9C27B0),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveTile(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18.r),
            SizedBox(height: 6.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.sp,
                color: const Color(0xFFE8EAED).withValues(alpha: 0.6),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              value,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              unit,
              style: TextStyle(
                fontSize: 9.sp,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningLightsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber, color: Color(0xFFFF6B35), size: 20.r),
            SizedBox(width: 10.w),
            Text(
              context.tr('warning_lights'),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8EAED),
              ),
            ),
            const Spacer(),
            if (_scanningDtcs)
              SizedBox(
                width: 18.r,
                height: 18.r,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF00D9FF),
                ),
              )
            else if (OBDService.instance.isInitialized)
              GestureDetector(
                onTap: _fetchDtcsAndUpdateLights,
                child: Icon(Icons.refresh, color: const Color(0xFF00D9FF), size: 20.r),
              ),
          ],
        ),
        SizedBox(height: 15.h),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: warningLights.length,
          itemBuilder: (context, index) {
            final light = warningLights[index];
            return _buildWarningLight(
              light['icon'] as String,
              light['label'] as String,
              light['active'] as bool,
              light['codes'] as List<String>,
            );
          },
        ),
      ],
    );
  }

  Widget _buildWarningLight(String icon, String label, bool dtcActive, List<String> codes) {
    // Light activates from a DTC match OR from a live sensor threshold.
    final sensorActive = _sensorWarnings[label] ?? false;
    final active = dtcActive || sensorActive;
    return GestureDetector(
      onTap: active && codes.isNotEmpty
          ? () => _showDtcBottomSheet(context, icon, label, codes)
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFFF6B35).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: active
                ? const Color(0xFFFF6B35)
                : Colors.white.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(15.r),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 28.sp,
                color: active ? null : Colors.grey,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              context.tr(label),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.sp,
                color: active
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFFE8EAED).withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDtcBottomSheet(
    BuildContext ctx,
    String icon,
    String label,
    List<String> codes,
  ) {
    final repo = _dtcRepo;
    final langCode = Localizations.localeOf(ctx).languageCode;
    final isArabic = langCode == 'ar';

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            border: Border.all(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
                child: Row(
                  children: [
                    Text(icon, style: TextStyle(fontSize: 28.sp)),
                    SizedBox(width: 12.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ctx.tr(label),
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFF6B35),
                          ),
                        ),
                        Text(
                          '${codes.length} ${codes.length == 1 ? 'code' : 'codes'} detected',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Code list
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  itemCount: codes.length,
                  itemBuilder: (_, i) => _DtcDetailCard(
                    code: codes[i],
                    repo: repo,
                    langCode: langCode,
                    isArabic: isArabic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickScanButton() {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.diagnosticCodes);
      },
      child: Container(
        padding: EdgeInsets.all(20.r),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
          ),
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D9FF).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('quick_scan'),
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Text(
                    context.tr('run_diagnostics'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 50.w,
              height: 50.h,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 30.r,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoTutorialsCard() {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.videoTutorials);
      },
      child: Container(
        padding: EdgeInsets.all(20.r),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          children: [
            Container(
              width: 50.w,
              height: 50.h,
              decoration: BoxDecoration(
                color: const Color(0xFF00D9FF).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.video_library,
                color: Color(0xFF00D9FF),
                size: 28.r,
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('video_tutorials'),
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8EAED),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    context.tr('learn_to_fix'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: const Color(0xFFE8EAED).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF00D9FF),
              size: 16.r,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentScansSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Color(0xFF00D9FF), size: 20.r),
                SizedBox(width: 10.w),
                Text(
                  context.tr('recent_scans'),
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE8EAED),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/history');
              },
              child: Text(
                context.tr('history'),
                style: TextStyle(color: Color(0xFF00D9FF), fontSize: 14.sp),
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        Container(
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(15.r),
          ),
          child: Center(
            child: Text(
              context.tr('no_scans_yet'),
              style: TextStyle(
                fontSize: 14.sp,
                color: const Color(0xFFE8EAED).withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D).withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: const Color(0xFF00D9FF).withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          child: Row(
            children: [
              Expanded(child: _buildNavItem(Icons.home, context.tr('home'), 0)),
              Expanded(child: _buildNavItem(Icons.search, context.tr('scan'), 1)),
              Expanded(child: _buildNavItem(Icons.vpn_key, context.tr('smart_key'), 2)),
              Expanded(child: _buildNavItem(Icons.history, context.tr('history'), 3)),
              Expanded(child: _buildNavItem(Icons.settings, context.tr('settings'), 4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });

        // Navigate based on index
        switch (index) {
          case 0:
            // Already on home (dashboard)
            break;
          case 1:
            Navigator.pushNamed(context, AppRoutes.diagnosticCodes);
            break;
          case 2:
            Navigator.pushNamed(context, AppRoutes.smartKey);
            break;
          case 3:
            Navigator.pushNamed(context, AppRoutes.history);
            break;
          case 4:
            Navigator.pushNamed(context, AppRoutes.settings);
            break;
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00D9FF).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF00D9FF)
                  : const Color(0xFFE8EAED).withValues(alpha: 0.5),
              size: 24.r,
            ),
            SizedBox(height: 5.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                color: isSelected
                    ? const Color(0xFF00D9FF)
                    : const Color(0xFFE8EAED).withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Per-code card shown inside the DTC bottom sheet ──────────────────────────

class _DtcDetailCard extends StatefulWidget {
  const _DtcDetailCard({
    required this.code,
    required this.repo,
    required this.langCode,
    required this.isArabic,
  });

  final String code;
  final DtcRepository repo;
  final String langCode;
  final bool isArabic;

  @override
  State<_DtcDetailCard> createState() => _DtcDetailCardState();
}

class _DtcDetailCardState extends State<_DtcDetailCard> {
  String? _enDesc;
  String? _arDesc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final en = await widget.repo.getDtcDescription(widget.code, languageCode: 'en');
    String? ar;
    if (widget.isArabic) {
      ar = await widget.repo.getDtcDescription(widget.code, languageCode: 'ar');
    }
    if (!mounted) return;
    setState(() {
      _enDesc = en ?? 'No description available.';
      _arDesc = ar;
      _loading = false;
    });
  }

  void _openYoutube() {
    final query = Uri.encodeComponent('${widget.code} car fix how to');
    final url = Uri.parse('https://www.youtube.com/results?search_query=$query');
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 14.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: const Color(0xFFFF6B35).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code badge + YouTube button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFFFF6B35)),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  widget.code,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFFF6B35),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _openYoutube,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    border: Border.all(color: Colors.red.shade400),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.play_circle_fill, color: Colors.red.shade400, size: 16.r),
                      SizedBox(width: 5.w),
                      Text(
                        'YouTube Fix',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // Description
          if (_loading)
            Row(
              children: [
                SizedBox(
                  width: 14.r, height: 14.r,
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00D9FF)),
                ),
                SizedBox(width: 10.w),
                Text(
                  'Loading description...',
                  style: TextStyle(fontSize: 13.sp, color: Colors.white38),
                ),
              ],
            )
          else ...[
            // English description always shown
            Text(
              _enDesc!,
              style: TextStyle(fontSize: 13.sp, color: const Color(0xFFE8EAED), height: 1.5),
            ),
            // Arabic description shown below when app is in Arabic
            if (widget.isArabic && _arDesc != null && _arDesc != _enDesc) ...[
              SizedBox(height: 8.h),
              const Divider(color: Colors.white12, height: 1),
              SizedBox(height: 8.h),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  _arDesc!,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: const Color(0xFF00D9FF),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
