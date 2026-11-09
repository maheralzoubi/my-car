import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/alert_service.dart';
import '../../../../../core/services/dtc_repository.dart';
import '../../../../../core/services/maintenance_service.dart';
import '../../../../../core/services/obd_service.dart';
import '../../../../../core/services/trip_service.dart';
import '../../../../../core/services/vin_decoder.dart';
import 'obd_gauge.dart';

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
  final Map<String, bool> _sensorWarnings = {};
  StreamSubscription<OBDLiveData>? _liveWarningSub;

  // Trip computer
  StreamSubscription<OBDLiveData>? _tripSub;

  // VIN
  String? _vin;
  Map<String, String> _vinInfo = {};

  // In-app alert overlay
  OBDAlert? _activeAlert;
  StreamSubscription<OBDAlert>? _alertSub;

  // Link state: a mid-session Bluetooth drop must flip the header to the
  // "not connected" banner instead of leaving stale live data on screen.
  StreamSubscription<OBDConnectionState>? _connSub;

  // Bumped on every successful (re)connect, so returning from the adapter
  // screen can tell a new link (restart the session) from the same one.
  int _connectEpoch = 0;

  // Fault codes from the last scan: confirmed (mode 03) and pending (mode
  // 07, '~'-prefixed). The health card counts codes, not lit lamps.
  int _confirmedDtcs = 0;
  int _pendingDtcs = 0;

  // MIL (Check Engine Lamp) hardware status from mode-01 readiness monitors.
  bool _milOn = false;

  // Compression-ignition engine (readiness PID 0101): diesels have no
  // throttle plate, timing advance, fuel trims or narrow-band O2, so the
  // live grid shows pedal / rail pressure instead of tiles stuck at '--'.
  bool _isDiesel = false;

  // Tracks how many km of the current trip have already been committed to
  // MaintenanceService — prevents double-counting across commits.
  double _committedKm = 0;

  List<Map<String, dynamic>> warningLights = [
    {'icon': '⚠️', 'label': 'check_engine', 'active': false, 'codes': <String>[]},
    {'icon': '🔋', 'label': 'battery',      'active': false, 'codes': <String>[]},
    {'icon': '🛢️', 'label': 'oil',          'active': false, 'codes': <String>[]},
    {'icon': '🛞', 'label': 'abs',           'active': false, 'codes': <String>[]},
    {'icon': '🛡️', 'label': 'airbag',       'active': false, 'codes': <String>[]},
    {'icon': '🌡️', 'label': 'temp',          'active': false, 'codes': <String>[]},
    {'icon': '⛽', 'label': 'fuel',           'active': false, 'codes': <String>[]},
    {'icon': '💨', 'label': 'exhaust',        'active': false, 'codes': <String>[]},
    {'icon': '🔄', 'label': 'transmission',  'active': false, 'codes': <String>[]},
    {'icon': '💥', 'label': 'misfire',        'active': false, 'codes': <String>[]},
    {'icon': '🔌', 'label': 'o2_sensor',     'active': false, 'codes': <String>[]},
    {'icon': '📊', 'label': 'fuel_trim',     'active': false, 'codes': <String>[]},
    {'icon': '💉', 'label': 'injector',      'active': false, 'codes': <String>[]},
    {'icon': '🌬️', 'label': 'maf_sensor',     'active': false, 'codes': <String>[]},
    {'icon': '📡', 'label': 'network',          'active': false, 'codes': <String>[]},
    {'icon': '🔧', 'label': 'service',          'active': false, 'codes': <String>[]},
    {'icon': '🔵', 'label': 'traction',         'active': false, 'codes': <String>[]},
    {'icon': '🚗', 'label': 'steering',         'active': false, 'codes': <String>[]},
    {'icon': '🌀', 'label': 'egr',              'active': false, 'codes': <String>[]},
    {'icon': '⚡', 'label': 'throttle',         'active': false, 'codes': <String>[]},
    {'icon': '💧', 'label': 'fuel_pressure',   'active': false, 'codes': <String>[]},
    {'icon': '🔴', 'label': 'mil',             'active': false, 'codes': <String>[]},
    {'icon': '💡', 'label': 'body',            'active': false, 'codes': <String>[]},
  ];

  @override
  void initState() {
    super.initState();
    MaintenanceService.instance.load();
    _startPollingIfConnected();
    _connSub = OBDService.instance.connectionStateStream.listen((s) {
      if (s == OBDConnectionState.connected) _connectEpoch++;
      if (mounted) setState(() {});
    });
  }

  /// Opens the adapter screen (connect / switch / disconnect) and re-syncs
  /// the dashboard with whatever link the user left behind.
  void _openConnectionScreen() {
    final wasConnected = OBDService.instance.isInitialized;
    final epoch = _connectEpoch;
    Navigator.pushNamed(context, AppRoutes.connectionscreen).then((_) {
      if (!mounted) return;
      final connected = OBDService.instance.isInitialized;
      if (connected && (!wasConnected || epoch != _connectEpoch)) {
        // New link (first connect, reconnect or another adapter): start a
        // fresh session — polling, DTC/readiness scan, VIN, trip, alerts.
        _startPollingIfConnected();
      } else if (connected) {
        // Same link: just make sure live polling is running.
        OBDService.instance.startPolling();
      }
      setState(() {});
    });
  }

  // The dashboard's route animation for "covered by another route". When
  // the route on top is popped it settles back to dismissed, and the
  // dashboard rebuilds so whatever that screen changed (maintenance items →
  // the due banner and service lamp) shows even with no live data arriving
  // to trigger a rebuild — however that screen was opened.
  Animation<double>? _coverAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cover = ModalRoute.of(context)?.secondaryAnimation;
    if (cover != _coverAnimation) {
      _coverAnimation?.removeStatusListener(_onCoverStatus);
      _coverAnimation = cover?..addStatusListener(_onCoverStatus);
    }
  }

  void _onCoverStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  void _startPollingIfConnected() {
    if (OBDService.instance.isInitialized) {
      OBDService.instance.startPolling();
      _fetchDtcsAndUpdateLights();
      _subscribeSensorThresholds();
      _startTripTracking();
      _fetchVin();
      _startAlerts();
    }
  }

  void _startAlerts() {
    AlertService.instance.startMonitoring();
    _alertSub?.cancel();
    _alertSub = AlertService.instance.alerts.listen((alert) {
      if (!mounted) return;
      setState(() => _activeAlert = alert);
      // Auto-dismiss warning alerts after 6 s; critical stay until tapped.
      if (alert.severity == AlertSeverity.warning) {
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted && _activeAlert?.id == alert.id) {
            setState(() => _activeAlert = null);
          }
        });
      }
    });
  }

  // ── Trip computer ──────────────────────────────────────────────────────────

  void _startTripTracking() {
    TripService.instance.start();
    _committedKm = 0;
    _tripSub?.cancel();
    _tripSub = OBDService.instance.liveDataStream.listen((d) {
      TripService.instance.addSample(d);
      // Commit to maintenance odometer every 1 km so it survives app crashes.
      final uncommitted = TripService.instance.distanceKm - _committedKm;
      if (uncommitted >= 1.0) {
        MaintenanceService.instance.addMileage(uncommitted);
        _committedKm = TripService.instance.distanceKm;
      }
      if (mounted) setState(() {});
    });
  }

  // ── VIN ────────────────────────────────────────────────────────────────────

  Future<void> _fetchVin() async {
    final vin = await OBDService.instance.getVin();
    if (!mounted || vin == null) return;
    setState(() {
      _vin = vin;
      _vinInfo = VinDecoder.decode(vin);
    });
  }

  void _subscribeSensorThresholds() {
    _liveWarningSub?.cancel();
    _liveWarningSub = OBDService.instance.liveDataStream.listen((d) {
      if (!mounted) return;
      setState(() {
        // Temp: warn if coolant ≥ 105 °C (overheating).
        _sensorWarnings['temp']         = d.coolantTempC   != null && d.coolantTempC!   >= 105;
        // Fuel: warn if fuel level ≤ 10 %.
        _sensorWarnings['fuel']         = d.fuelLevelPct   != null && d.fuelLevelPct!   <= 10;
        // Battery: warn if system voltage < 11.5 V (charging / battery fault).
        _sensorWarnings['battery']      = d.batteryVoltage != null && d.batteryVoltage! < 11.5;
        // Oil: warn if oil temperature > 130 °C (oil degrading / overheating).
        _sensorWarnings['oil']          = d.oilTempC       != null && d.oilTempC!       > 130;
        // Intake air > 60 °C = heat soak / intercooler failure (turbo engines).
        _sensorWarnings['check_engine'] = (_sensorWarnings['check_engine'] ?? false) ||
            (d.rpm != null && d.rpm! > 6500) ||
            (d.intakeAirTempC != null && d.intakeAirTempC! > 60);
        // Fuel trim: severe deviation > ±25 % indicates rich/lean fault.
        _sensorWarnings['fuel_trim'] =
            (d.fuelTrimShortPct != null && d.fuelTrimShortPct!.abs() > 25) ||
            (d.fuelTrimLongPct  != null && d.fuelTrimLongPct!.abs()  > 25) ||
            (d.fuelTrimShortB2  != null && d.fuelTrimShortB2!.abs()  > 25) ||
            (d.fuelTrimLongB2   != null && d.fuelTrimLongB2!.abs()   > 25);
        // Service: mirror the maintenance-due flag into sensor warnings.
        _sensorWarnings['service'] = MaintenanceService.instance.dueCount > 0;
        // Throttle: stuck open if > 90 % at idle (RPM < 1000).
        _sensorWarnings['throttle'] = d.throttlePct != null &&
            d.throttlePct! > 90 &&
            d.rpm != null && d.rpm! < 1000;
        // Timing: heavy knock retard (< -10°) = ECU protecting engine from damage.
        _sensorWarnings['check_engine'] = (_sensorWarnings['check_engine'] ?? false) ||
            (d.timingAdvanceDeg != null && d.timingAdvanceDeg! < -10);
        // MAF/MAP: overboost > 200 kPa on turbo engines.
        _sensorWarnings['maf_sensor'] = (_sensorWarnings['maf_sensor'] ?? false) ||
            (d.mapKpa != null && d.mapKpa! > 200);
        // MIL: reflect hardware lamp status fetched from readiness monitors.
        _sensorWarnings['mil'] = _milOn;
      });
    });
  }

  Future<void> _fetchDtcsAndUpdateLights() async {
    if (!OBDService.instance.isInitialized) return;
    if (!mounted) return;
    setState(() => _scanningDtcs = true);

    final rawCodes = await OBDService.instance.getDtcs();
    if (!mounted) return;

    // Fetch MIL (Check Engine Lamp) hardware state from mode-01 readiness byte.
    final readiness = await OBDService.instance.getReadinessMonitors();
    if (!mounted) return;
    setState(() {
      _milOn = readiness.milOn;
      _isDiesel = readiness.compressionIgnition;
    });

    // Strip the '~' pending prefix so matching works the same for both
    // confirmed (mode 03) and pending (mode 07) codes.
    final codes = rawCodes.map((c) => c.startsWith('~') ? c.substring(1) : c).toList();
    final pendingCount = rawCodes.where((c) => c.startsWith('~')).length;

    List<String> codesFor(bool Function(String) test) =>
        codes.where(test).toList();

    // Prefixes owned by specific lights — excluded from the generic check-engine list.
    const specificPrefixes = [
      'P056', 'P057', 'P115',                        // battery
      'P052', 'P053',                                 // oil
      'P011', 'P012', 'P025',                        // temp
      'P008', 'P009', 'P046',                        // fuel
      'P042', 'P043', 'P044', 'P045',                // exhaust
      'P07', 'P08',                                   // transmission
      'P030', 'P032', 'P033', 'P034', 'P035',        // misfire / ignition
      'P013', 'P014', 'P015', 'P016',                // o2_sensor
      'P017', 'P018',                                 // fuel_trim
      'P020', 'P021',                                 // injector
      'P010',                                         // maf_sensor
      'P040', 'P041',                                 // egr
      'P21',                                          // throttle / TAC
      'P022', 'P023', 'P024',                        // fuel_pressure
    ];
    bool isSpecific(String c) =>
        _matchPrefix(c, specificPrefixes) || c.startsWith('U');

    // C-code helpers. Only SAE-generic chassis codes (C0xxx) have a fixed
    // meaning; C1xxx/C2xxx are manufacturer-specific (Chery C1201 is an ABS
    // valve, others use C12xx for anything), so they light no subsystem lamp
    // — they still count as fault codes on the health card.
    //   C00xx          ABS / wheel-speed
    //   C01xx          traction / ESC (except the steering-angle codes)
    //   C0190–C0195    steering-angle sensor (C0196–C0199 are yaw rate → ESC)
    //   C0350–C0377    EPS solenoid, steering position / torque, EPS motor
    //                  (C0379 is a drive-shaft speed sensor)
    //   C0450          steering-assist actuator (C0455–C0478 are brake
    //                  fluid / pad wear / suspension / roll control)
    //   C0710          steering position signal
    // Ranges follow the bundled DTC descriptions the user reads, so the lamp
    // never contradicts the code's own text.
    bool isSteeringCode(String c) {
      if (c.length != 5 || !c.startsWith('C0')) return false;
      final n = int.tryParse(c.substring(2), radix: 16);
      if (n == null) return false;
      return (n >= 0x190 && n <= 0x195) ||
          (n >= 0x350 && n <= 0x377) ||
          n == 0x450 ||
          n == 0x710;
    }
    bool isAbsCode(String c)      => c.startsWith('C00');
    bool isTractionCode(String c) => c.startsWith('C01') && !isSteeringCode(c);

    setState(() {
      _scanningDtcs = false;
      _confirmedDtcs = codes.length - pendingCount;
      _pendingDtcs = pendingCount;
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
          'codes': codesFor(isAbsCode),
          'active': codes.any(isAbsCode)},
        {'icon': '🛡️', 'label': 'airbag',
          'codes': codesFor((c) => c.startsWith('B00')),
          'active': codes.any((c) => c.startsWith('B00'))},
        {'icon': '🌡️', 'label': 'temp',
          'codes': codesFor((c) => _matchPrefix(c, ['P011', 'P012', 'P025'])),
          'active': codes.any((c) => _matchPrefix(c, ['P011', 'P012', 'P025']))},
        {'icon': '⛽', 'label': 'fuel',
          'codes': codesFor((c) => _matchPrefix(c, ['P008', 'P009', 'P046'])),
          'active': codes.any((c) => _matchPrefix(c, ['P008', 'P009', 'P046']))},
        {'icon': '💨', 'label': 'exhaust',
          'codes': codesFor((c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045'])),
          'active': codes.any((c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045']))},
        {'icon': '🔄', 'label': 'transmission',
          'codes': codesFor((c) => _matchPrefix(c, ['P07', 'P08'])),
          'active': codes.any((c) => _matchPrefix(c, ['P07', 'P08']))},
        {'icon': '💥', 'label': 'misfire',
          'codes': codesFor((c) => _matchPrefix(c, ['P030', 'P032', 'P033', 'P034', 'P035'])),
          'active': codes.any((c) => _matchPrefix(c, ['P030', 'P032', 'P033', 'P034', 'P035']))},
        {'icon': '🔌', 'label': 'o2_sensor',
          'codes': codesFor((c) => _matchPrefix(c, ['P013', 'P014', 'P015', 'P016'])),
          'active': codes.any((c) => _matchPrefix(c, ['P013', 'P014', 'P015', 'P016']))},
        {'icon': '📊', 'label': 'fuel_trim',
          'codes': codesFor((c) => _matchPrefix(c, ['P017', 'P018'])),
          'active': codes.any((c) => _matchPrefix(c, ['P017', 'P018']))},
        {'icon': '💉', 'label': 'injector',
          'codes': codesFor((c) => _matchPrefix(c, ['P020', 'P021'])),
          'active': codes.any((c) => _matchPrefix(c, ['P020', 'P021']))},
        {'icon': '🌬️', 'label': 'maf_sensor',
          'codes': codesFor((c) => _matchPrefix(c, ['P010'])),
          'active': codes.any((c) => _matchPrefix(c, ['P010']))},
        {'icon': '📡', 'label': 'network',
          'codes': codesFor((c) => c.startsWith('U')),
          'active': codes.any((c) => c.startsWith('U'))},
        {'icon': '🔧', 'label': 'service',
          'codes': <String>[],
          'active': MaintenanceService.instance.dueCount > 0},
        {'icon': '🔵', 'label': 'traction',
          'codes': codesFor(isTractionCode),
          'active': codes.any(isTractionCode)},
        {'icon': '🚗', 'label': 'steering',
          'codes': codesFor(isSteeringCode),
          'active': codes.any(isSteeringCode)},
        {'icon': '🌀', 'label': 'egr',
          'codes': codesFor((c) => _matchPrefix(c, ['P040', 'P041'])),
          'active': codes.any((c) => _matchPrefix(c, ['P040', 'P041']))},
        {'icon': '⚡', 'label': 'throttle',
          'codes': codesFor((c) => _matchPrefix(c, ['P21'])),
          'active': codes.any((c) => _matchPrefix(c, ['P21']))},
        {'icon': '💧', 'label': 'fuel_pressure',
          'codes': codesFor((c) => _matchPrefix(c, ['P022', 'P023', 'P024'])),
          'active': codes.any((c) => _matchPrefix(c, ['P022', 'P023', 'P024']))},
        {'icon': '🔴', 'label': 'mil',
          'codes': <String>[],
          'active': readiness.milOn},
        {'icon': '💡', 'label': 'body',
          'codes': codesFor((c) => c.startsWith('B') && !c.startsWith('B00')),
          'active': codes.any((c) => c.startsWith('B') && !c.startsWith('B00'))},
      ];
    });
  }

  /// Lamps whose codes live in modules a standard OBD-II scan (modes 03/07,
  /// answered by the engine / transmission computers) does not reach. They
  /// light up when the engine computer happens to report one of their codes;
  /// otherwise they show "N/A" — never a plain "off" that reads as OK.
  static const Set<String> _notStandardObdLamps = {
    'airbag',
    'abs',
    'traction',
    'steering',
    'body',
  };

  bool _matchPrefix(String code, List<String> prefixes) =>
      prefixes.any((p) => code.startsWith(p));

  @override
  void dispose() {
    // Flush any sub-1 km remainder before the trip is destroyed.
    final remaining = TripService.instance.distanceKm - _committedKm;
    if (remaining > 0.01) {
      MaintenanceService.instance.addMileage(remaining);
    }
    OBDService.instance.stopPolling();
    TripService.instance.stop();
    AlertService.instance.stopMonitoring();
    _liveWarningSub?.cancel();
    _tripSub?.cancel();
    _alertSub?.cancel();
    _connSub?.cancel();
    _coverAnimation?.removeStatusListener(_onCoverStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The service hub pushes the dashboard ("You can switch between services
    // anytime"), so Back returns there — and disposing the dashboard stops
    // live polling while keeping the adapter link. Only when the dashboard
    // is the root route does Back mean "exit the app" (double-press).
    return PopScope(
      canPop: Navigator.canPop(context),
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
        body: Stack(
          children: [
            Container(
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
                      if (_vin != null) _buildVinCard(),
                      if (_vin != null) SizedBox(height: 16.h),
                      if (MaintenanceService.instance.dueCount > 0) _buildMaintenanceAlert(),
                      if (MaintenanceService.instance.dueCount > 0) SizedBox(height: 16.h),
                      _buildHealthCard(),
                      SizedBox(height: 20.h),
                      _buildLiveDataSection(),
                      SizedBox(height: 20.h),
                      if (TripService.instance.isRunning) _buildTripCard(),
                      if (TripService.instance.isRunning) SizedBox(height: 20.h),
                      SizedBox(height: 10.h),
                      _buildWarningLightsSection(),
                      SizedBox(height: 30.h),
                      _buildQuickScanButton(),
                      SizedBox(height: 20.h),
                      _buildMaintenanceCard(),
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
            // ── In-app alert overlay ────────────────────────────────────
            if (_activeAlert != null)
              _buildAlertOverlay(_activeAlert!),
          ],
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

  // The whole header (adapter name, "Connected" pill, chevron) opens the
  // adapter screen, the only place to disconnect or switch adapters.
  Widget _buildConnectedHeader() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openConnectionScreen,
      child: Row(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        OBDService.instance.connectedDeviceName ??
                            context.tr('dash_adapter'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE8EAED),
                        ),
                      ),
                      Text(
                        context.tr('dash_manage_adapter'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: const Color(0xFFE8EAED).withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
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
          SizedBox(width: 6.w),
          Icon(
            Icons.arrow_forward_ios,
            color: const Color(0xFF00E676).withValues(alpha: 0.7),
            size: 14.r,
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedBanner() {
    return GestureDetector(
      onTap: _openConnectionScreen,
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

  /// 0–100 score from the number of problems: lit DTC lamps or confirmed
  /// codes, whichever is larger (manufacturer-specific codes light no lamp
  /// but are still faults).
  int get _healthScore {
    final lamps = warningLights.where((l) => l['active'] == true).length;
    final active = lamps > _confirmedDtcs ? lamps : _confirmedDtcs;
    if (active == 0) return 100;
    if (active == 1) return 80;
    if (active == 2) return 60;
    if (active <= 4) return 40;
    return 20;
  }

  String get _healthLabel {
    final s = _healthScore;
    if (s >= 90) return context.tr('dash_health_excellent');
    if (s >= 70) return context.tr('dash_health_good');
    if (s >= 50) return context.tr('dash_health_fair');
    if (s >= 30) return context.tr('dash_health_poor');
    return context.tr('dash_health_critical');
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

  // ── Alert overlay ─────────────────────────────────────────────────────────

  Widget _buildAlertOverlay(OBDAlert alert) {
    final isCritical = alert.severity == AlertSeverity.critical;
    final bgColor    = isCritical ? const Color(0xFFFF1744) : const Color(0xFFFF6B35);

    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: GestureDetector(
          onTap: () => setState(() => _activeAlert = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.all(12.r),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(color: bgColor.withValues(alpha: 0.6),
                    blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isCritical ? Icons.warning_rounded : Icons.info_rounded,
                  color: Colors.white, size: 28.r,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alert.title,
                          style: TextStyle(
                              fontSize: 15.sp, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      SizedBox(height: 3.h),
                      Text(alert.message,
                          style: TextStyle(
                              fontSize: 12.sp, color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
                Icon(Icons.close, color: Colors.white.withValues(alpha: 0.7), size: 18.r),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── VIN card ──────────────────────────────────────────────────────────────

  Widget _buildVinCard() {
    // VinDecoder reports undeterminable fields as VinDecoder.unknown.
    String field(String key, String unknownKey) {
      final value = _vinInfo[key] ?? '';
      return value == VinDecoder.unknown ? context.tr(unknownKey) : value;
    }
    final manufacturer = field('manufacturer', 'vin_unknown');
    final year         = field('year', 'vin_year_unknown');
    final country      = _localizedCountry(field('country', 'vin_unknown'));
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car, color: const Color(0xFF00D9FF), size: 22.r),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manufacturer.isNotEmpty ? '$manufacturer  •  $year' : _vin ?? '',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8EAED),
                  ),
                ),
                if (country.isNotEmpty)
                  Text(
                    '$country  •  VIN: $_vin',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: const Color(0xFF00D9FF).withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// VinDecoder's English country name, in Arabic when the UI is Arabic
  /// (falls back to the English name for countries not listed).
  String _localizedCountry(String country) {
    if (Localizations.localeOf(context).languageCode != 'ar') return country;
    return _arCountryNames[country] ?? country;
  }

  // ── Maintenance alert ─────────────────────────────────────────────────────

  Widget _buildMaintenanceAlert() {
    final count = MaintenanceService.instance.dueCount;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.maintenance),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD600).withValues(alpha: 0.08),
          border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Row(
          children: [
            Icon(Icons.build_outlined, color: const Color(0xFFFFD600), size: 18.r),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                context
                    .tr(count == 1
                        ? 'dash_maintenance_due_one'
                        : 'dash_maintenance_due_many')
                    .replaceAll('{n}', '$count'),
                style: TextStyle(
                  fontSize: 13.sp,
                  color: const Color(0xFFFFD600),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: const Color(0xFFFFD600), size: 12.r),
          ],
        ),
      ),
    );
  }

  // ── Trip computer card ────────────────────────────────────────────────────

  Widget _buildTripCard() {
    final trip = TripService.instance;
    final elapsed = trip.elapsed;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = h > 0 ? '$h:$m:$s' : '$m:$s';

    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: const Color(0xFF00E676), size: 18.r),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  context.tr('dash_trip_computer'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8EAED),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () => setState(() => trip.reset()),
                child: Text(
                  context.tr('dash_reset'),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF00E676).withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              _tripStat(context.tr('dash_distance'), '${trip.distanceKm.toStringAsFixed(1)} km', const Color(0xFF00D9FF)),
              _tripStat(context.tr('dash_time'), timeStr, const Color(0xFF00E676)),
              _tripStat(context.tr('dash_avg_speed'), '${trip.avgSpeedKmh.toStringAsFixed(0)} km/h', const Color(0xFFFFD600)),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              _tripStat(context.tr('dash_fuel_used'), '${trip.fuelUsedL.toStringAsFixed(2)} L', const Color(0xFFFF6B35)),
              _tripStat(
                context.tr('dash_efficiency'),
                trip.fuelEfficiencyL100km > 0
                    ? '${trip.fuelEfficiencyL100km.toStringAsFixed(1)} L/100km'
                    : '--',
                const Color(0xFF9C27B0),
              ),
              Expanded(child: SizedBox()),
            ],
          ),
          SizedBox(height: 12.h),
          // ── Drive score ──────────────────────────────────────────────
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: _driveScoreColor(trip.driveScore).withValues(alpha: 0.1),
              border: Border.all(
                  color: _driveScoreColor(trip.driveScore).withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(12.r),
            ),
            // Label column takes the free space (and ellipsizes); the score
            // keeps its natural width, so the row never overflows the card.
            child: Row(
              children: [
                Text('🏎️', style: TextStyle(fontSize: 20.sp)),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('drive_score'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.sp,
                              color: const Color(0xFFE8EAED).withValues(alpha: 0.55))),
                      Text(_driveScoreLabel(trip.driveScore),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: _driveScoreColor(trip.driveScore))),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Text('${trip.driveScore}',
                    style: TextStyle(fontSize: 32.sp, fontWeight: FontWeight.w900,
                        color: _driveScoreColor(trip.driveScore))),
                Text(' / 100',
                    style: TextStyle(fontSize: 12.sp,
                        color: const Color(0xFFE8EAED).withValues(alpha: 0.4))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Same bands as TripService.driveScoreLabel, localized.
  String _driveScoreLabel(int score) {
    if (score >= 85) return context.tr('dash_drive_eco');
    if (score >= 65) return context.tr('dash_drive_normal');
    if (score >= 45) return context.tr('dash_drive_sporty');
    return context.tr('dash_drive_aggressive');
  }

  Color _driveScoreColor(int score) {
    if (score >= 85) return const Color(0xFF00E676);
    if (score >= 65) return const Color(0xFF00D9FF);
    if (score >= 45) return const Color(0xFFFFD600);
    return const Color(0xFFFF1744);
  }

  Widget _tripStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10.sp,
                  color: const Color(0xFFE8EAED).withValues(alpha: 0.55))),
          SizedBox(height: 2.h),
          Text(value,
              style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }

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
        final confirmed = _confirmedDtcs;
        final pending   = _pendingDtcs;

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
                Flexible(
                  child: Text(
                    context.tr('vehicle_health'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE8EAED),
                    ),
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
            if (confirmed > 0 || pending > 0) ...[
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
                    Expanded(
                      child: Text(
                        context
                            .tr(confirmed == 0
                                ? (pending == 1
                                    ? 'dash_pending_only_one'
                                    : 'dash_pending_only_many')
                                : confirmed == 1
                                    ? 'dash_fault_code_n'
                                    : 'dash_fault_codes_n')
                            .replaceAll('{n}', '${confirmed == 0 ? pending : confirmed}'),
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: const Color(0xFFFF6B35),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Pending (mode 07) codes: not confirmed faults yet.
                    if (confirmed > 0 && pending > 0) ...[
                      SizedBox(width: 6.w),
                      Text(
                        context
                            .tr('dash_pending_codes_n')
                            .replaceAll('{n}', '$pending'),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: const Color(0xFFFFD600),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                _buildMetricTile(Icons.directions_car, context.tr('dash_speed'),  speedStr,   const Color(0xFF00E676)),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                _buildMetricTile(Icons.thermostat,   context.tr('dash_coolant'), coolantStr, const Color(0xFFFFD600)),
                SizedBox(width: 10.w),
                _buildMetricTile(Icons.local_gas_station, context.tr('fuel'), fuelStr,   const Color(0xFFFF6B35)),
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
                    context.tr('dash_connect_for_health'),
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
            _buildMetricTile(Icons.directions_car, context.tr('dash_speed'),  '--', Colors.white24),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            _buildMetricTile(Icons.thermostat,   context.tr('dash_coolant'), '--', Colors.white24),
            SizedBox(width: 10.w),
            _buildMetricTile(Icons.local_gas_station, context.tr('fuel'), '--', Colors.white24),
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
                  Expanded(
                    child: Text(
                      context.tr('live_data'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EAED),
                      ),
                    ),
                  ),
                  if (OBDService.instance.isInitialized) ...[
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, AppRoutes.liveGraph),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D9FF).withValues(alpha: 0.1),
                          border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.show_chart, color: const Color(0xFF00D9FF), size: 13.r),
                            SizedBox(width: 4.w),
                            Text(context.tr('graph'), style: TextStyle(fontSize: 11.sp, color: const Color(0xFF00D9FF), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Container(
                      width: 8.w, height: 8.h,
                      decoration: const BoxDecoration(
                          color: Color(0xFF00E676), shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 12.h),
              // ── Arc gauges: RPM + Speed ──────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OBDGauge(
                      value: d.rpm,
                      max: 8000,
                      label: 'RPM',
                      unit: 'rpm',
                      color: const Color(0xFF00D9FF),
                      dangerAt: 6500,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: OBDGauge(
                      value: d.speedKmh,
                      max: 240,
                      label: context.tr('dash_speed'),
                      unit: 'km/h',
                      color: const Color(0xFF00E676),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              // ── Coolant tile (stays as number) ───────────────────────────
              Row(
                children: [
                  _buildLiveTile(
                    context.tr('dash_coolant'),
                    d.coolantTempC != null ? d.coolantTempC!.toStringAsFixed(0) : '--',
                    '°C',
                    Icons.thermostat,
                    d.coolantTempC != null && d.coolantTempC! >= 105
                        ? const Color(0xFFFF1744)
                        : const Color(0xFFFFD600),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    context.tr('dash_air_temp'),
                    d.intakeAirTempC != null ? '${d.intakeAirTempC!.toStringAsFixed(0)}°C' : '--',
                    '',
                    Icons.air,
                    d.intakeAirTempC != null && d.intakeAirTempC! > 60
                        ? const Color(0xFFFF1744)
                        : const Color(0xFF00D9FF),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    context.tr('battery'),
                    d.batteryVoltage != null ? '${d.batteryVoltage!.toStringAsFixed(1)}V' : '--',
                    '',
                    Icons.battery_charging_full,
                    d.batteryVoltage != null && d.batteryVoltage! < 11.5
                        ? const Color(0xFFFF1744)
                        : const Color(0xFF00E676),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              Row(
                children: [
                  // Diesels (and some petrol cars) report the pedal, not a
                  // throttle plate.
                  if (_isDiesel ||
                      (d.throttlePct == null && d.acceleratorPedalPct != null))
                    _buildLiveTile(
                      context.tr('accel_pedal'),
                      d.acceleratorPedalPct != null
                          ? d.acceleratorPedalPct!.toStringAsFixed(1)
                          : '--',
                      '%',
                      Icons.tune,
                      const Color(0xFFFF6B35),
                    )
                  else
                    _buildLiveTile(
                      context.tr('throttle'),
                      d.throttlePct != null ? d.throttlePct!.toStringAsFixed(1) : '--',
                      '%',
                      Icons.tune,
                      const Color(0xFFFF6B35),
                    ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    context.tr('fuel'),
                    d.fuelLevelPct != null ? d.fuelLevelPct!.toStringAsFixed(1) : '--',
                    '%',
                    Icons.local_gas_station,
                    const Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    context.tr('dash_engine_load'),
                    d.engineLoad != null ? d.engineLoad!.toStringAsFixed(1) : '--',
                    '%',
                    Icons.settings,
                    const Color(0xFF9C27B0),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              SizedBox(height: 10.h),
              // ── MAP + Timing advance (diesel: rail pressure + oil temp) ──
              Row(
                children: [
                  _buildLiveTile(
                    context.tr('dash_map'),
                    d.mapKpa != null ? '${d.mapKpa!.toStringAsFixed(0)} kPa' : '--',
                    '',
                    Icons.compress,
                    const Color(0xFF00BCD4),
                  ),
                  SizedBox(width: 10.w),
                  if (_isDiesel) ...[
                    _buildRailPressureTile(d.fuelRailPressureKpa),
                    SizedBox(width: 10.w),
                    _buildOilTempTile(d.oilTempC),
                  ] else ...[
                    _buildTimingTile(d.timingAdvanceDeg),
                    SizedBox(width: 10.w),
                    // GDI petrol engines may report rail pressure too.
                    if (d.fuelRailPressureKpa != null)
                      _buildRailPressureTile(d.fuelRailPressureKpa)
                    else
                      Expanded(child: SizedBox()),
                  ],
                ],
              ),
              // ── Fuel trim Bank 1 + oil temp (petrol only) ────────────────
              if (!_isDiesel) ...[
                SizedBox(height: 10.h),
                Row(
                  children: [
                    _buildFuelTrimTile('STFT B1', d.fuelTrimShortPct, ''),
                    SizedBox(width: 10.w),
                    _buildFuelTrimTile('LTFT B1', d.fuelTrimLongPct, ''),
                    SizedBox(width: 10.w),
                    _buildOilTempTile(d.oilTempC),
                  ],
                ),
              ],
              // ── Fuel trim Bank 2 (V6/V8) ─────────────────────────────────
              if (d.fuelTrimShortB2 != null || d.fuelTrimLongB2 != null) ...[
                SizedBox(height: 10.h),
                Row(
                  children: [
                    _buildFuelTrimTile('STFT B2', d.fuelTrimShortB2, ''),
                    SizedBox(width: 10.w),
                    _buildFuelTrimTile('LTFT B2', d.fuelTrimLongB2, ''),
                    SizedBox(width: 10.w),
                    Expanded(child: SizedBox()),
                  ],
                ),
              ],
              // ── O2 sensor voltages (diesel: only if it reports any) ──────
              if (!_isDiesel ||
                  d.o2B1S1Voltage != null ||
                  d.lambdaB1S1 != null ||
                  d.o2B1S2Voltage != null) ...[
                SizedBox(height: 10.h),
                Row(
                  children: [
                    // Wide-band upstream sensors report λ instead of volts.
                    if (d.o2B1S1Voltage == null && d.lambdaB1S1 != null)
                      _buildLambdaTile('O2 B1S1', d.lambdaB1S1!)
                    else
                      _buildO2Tile('O2 B1S1', d.o2B1S1Voltage),
                    SizedBox(width: 10.w),
                    _buildO2Tile('O2 B1S2', d.o2B1S2Voltage),
                    SizedBox(width: 10.w),
                    _buildO2Tile('O2 B2S1', d.o2B2S1Voltage),
                  ],
                ),
              ],
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

  // Fuel trim tile: colour-codes the value (green = normal, red = lean/rich).
  Widget _buildFuelTrimTile(String label, double? value, String tooltip) {
    final hasValue = value != null;
    final color = hasValue
        ? (value.abs() <= 10
            ? const Color(0xFF00E676)   // normal ±10 %
            : value.abs() <= 20
                ? const Color(0xFFFFD600) // moderate ±20 %
                : const Color(0xFFFF1744)) // severe > 20 %
        : Colors.white24;
    final prefix = hasValue && value > 0 ? '+' : '';
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(Icons.track_changes, color: color, size: 18.r),
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
              hasValue ? '$prefix${value.toStringAsFixed(1)}' : '--',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              '%',
              style: TextStyle(fontSize: 9.sp, color: color.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildO2Tile(String label, double? voltage) {
    // O2 sensor voltage 0–1.275 V.
    // < 0.1 V  = lean   (or sensor cold/dead)
    // 0.1–0.9  = cycling — healthy, engine controlling fuel properly
    // > 0.9 V  = rich
    // ~0.45 V  = stuck — sensor dead or lazy
    Color color;
    String status;
    if (voltage == null) {
      color = Colors.white24;
      status = '--';
    } else if (voltage < 0.1) {
      color = const Color(0xFFFFD600); // lean
      status = '${voltage.toStringAsFixed(2)}V';
    } else if (voltage > 0.9) {
      color = const Color(0xFFFF6B35); // rich
      status = '${voltage.toStringAsFixed(2)}V';
    } else if ((voltage - 0.45).abs() < 0.05) {
      color = const Color(0xFFFF1744); // stuck ~0.45V → dead sensor
      status = '${voltage.toStringAsFixed(2)}V';
    } else {
      color = const Color(0xFF00E676); // cycling normally
      status = '${voltage.toStringAsFixed(2)}V';
    }

    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(Icons.sensors, color: color, size: 18.r),
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
              status,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingTile(double? deg) {
    // Green: normal advance (> 0°). Yellow: light retard (-5 to 0°).
    // Red: heavy knock retard (< -5°) — ECU protecting engine from damage.
    Color color;
    if (deg == null) {
      color = Colors.white24;
    } else if (deg >= 0) {
      color = const Color(0xFF00E676);
    } else if (deg >= -5) {
      color = const Color(0xFFFFD600);
    } else {
      color = const Color(0xFFFF1744);
    }
    final prefix = deg != null && deg > 0 ? '+' : '';
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(Icons.flash_on, color: color, size: 18.r),
            SizedBox(height: 6.h),
            Text(context.tr('timing'),
                style: TextStyle(
                    fontSize: 10.sp,
                    color: const Color(0xFFE8EAED).withValues(alpha: 0.6))),
            SizedBox(height: 4.h),
            Text(
              deg != null ? '$prefix${deg.toStringAsFixed(1)}°' : '--',
              style: TextStyle(
                  fontSize: 15.sp, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOilTempTile(double? oilTempC) {
    return _buildLiveTile(
      context.tr('dash_oil_temp'),
      oilTempC != null ? '${oilTempC.toStringAsFixed(0)}°C' : '--',
      '',
      Icons.oil_barrel,
      oilTempC != null && oilTempC > 130
          ? const Color(0xFFFF1744)
          : const Color(0xFF00E676),
    );
  }

  // Fuel rail gauge pressure, shown in MPa (common-rail diesel: ~25–35 MPa
  // at idle, up to ~200 MPa under load; GDI petrol: ~4–20 MPa).
  Widget _buildRailPressureTile(double? kpa) {
    return _buildLiveTile(
      context.tr('rail_pressure'),
      kpa != null ? (kpa / 1000).toStringAsFixed(1) : '--',
      'MPa',
      Icons.water_drop,
      const Color(0xFF00BCD4),
    );
  }

  Widget _buildLambdaTile(String label, double lambda) {
    // Wide-band sensor equivalence ratio: 1.00 = stoichiometric.
    // Petrol closed loop holds ~0.97–1.03; outside that it runs rich (< 1)
    // or lean (> 1). Diesels run lean (λ well above 1) by design.
    final Color color;
    if (_isDiesel || (lambda - 1).abs() <= 0.03) {
      color = const Color(0xFF00E676);
    } else if (lambda < 1) {
      color = const Color(0xFFFF6B35); // rich
    } else {
      color = const Color(0xFFFFD600); // lean
    }
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Icon(Icons.sensors, color: color, size: 18.r),
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
              'λ ${lambda.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: color,
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
        if (OBDService.instance.isInitialized) ...[
          SizedBox(height: 12.h),
          Row(
            key: const ValueKey('dash_lamps_limited_note'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: const Color(0xFF00D9FF),
                size: 16.r,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  context.tr('dash_lamps_limited_body'),
                  style: TextStyle(
                    fontSize: 11.sp,
                    height: 1.4,
                    color: const Color(0xFFE8EAED).withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildWarningLight(String icon, String label, bool dtcActive, List<String> codes) {
    // Light activates from a DTC match OR from a live sensor threshold.
    // The service light follows the maintenance tracker directly, so it
    // stays current after the user logs a service.
    final sensorActive = _sensorWarnings[label] ?? false;
    final active = label == 'service'
        ? MaintenanceService.instance.dueCount > 0
        : dtcActive || sensorActive;
    // Not reachable by a standard scan and nothing reported: "N/A", not OK.
    final unreadable =
        !active &&
        OBDService.instance.isInitialized &&
        _notStandardObdLamps.contains(label);
    return GestureDetector(
      key: unreadable ? ValueKey('dash_lamp_na_$label') : null,
      onTap: active && codes.isNotEmpty
          ? () => _showDtcBottomSheet(context, icon, label, codes)
          : unreadable
          ? () => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(context.tr('dash_lamps_limited_body'))),
            )
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
                // Smaller on "N/A" tiles so the extra line fits the square.
                fontSize: unreadable ? 20.sp : 28.sp,
                color: active ? null : Colors.grey,
              ),
            ),
            SizedBox(height: unreadable ? 4.h : 8.h),
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
            if (unreadable)
              Text(
                context.tr('dash_lamp_na'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8.sp,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF00D9FF).withValues(alpha: 0.8),
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
                          '${codes.length} ${ctx.tr(codes.length == 1 ? 'code_detected' : 'codes_detected')}',
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

  // Permanent entry to the maintenance tracker — the due banner only shows
  // once a logged service falls due, which needs the tracker first.
  Widget _buildMaintenanceCard() {
    const accent = Color(0xFFFFD600);
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.maintenance),
      child: Container(
        padding: EdgeInsets.all(20.r),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Row(
          children: [
            Container(
              width: 50.w,
              height: 50.h,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.car_repair, color: accent, size: 28.r),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('maintenance_tracker'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE8EAED),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    context.tr('dash_maintenance_sub'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: const Color(0xFFE8EAED).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: accent, size: 16.r),
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
            Flexible(
              child: Row(
                children: [
                  Icon(Icons.history, color: Color(0xFF00D9FF), size: 20.r),
                  SizedBox(width: 10.w),
                  Flexible(
                    child: Text(
                      context.tr('recent_scans'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EAED),
                      ),
                    ),
                  ),
                ],
              ),
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
        // Home is this screen; the other tabs are pushed on top of it.
        final route = switch (index) {
          1 => AppRoutes.diagnosticCodes,
          2 => AppRoutes.smartKey,
          3 => AppRoutes.history,
          4 => AppRoutes.settings,
          _ => null,
        };
        setState(() => _selectedIndex = index);
        if (route == null) return;
        // Highlight the tab while its screen is up, then give the highlight
        // back to Home when the user returns to the dashboard.
        Navigator.pushNamed(context, route).then((_) {
          if (mounted) setState(() => _selectedIndex = 0);
        });
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

/// Arabic names for the countries [VinDecoder] reports (keyed by its English
/// name). Countries not listed fall back to the English name.
const Map<String, String> _arCountryNames = {
  'China': 'الصين',
  'Japan': 'اليابان',
  'South Korea': 'كوريا الجنوبية',
  'United States': 'الولايات المتحدة',
  'Canada': 'كندا',
  'Mexico': 'المكسيك',
  'Germany': 'ألمانيا',
  'United Kingdom': 'المملكة المتحدة',
  'France': 'فرنسا',
  'Italy': 'إيطاليا',
  'Spain': 'إسبانيا',
  'Portugal': 'البرتغال',
  'Netherlands': 'هولندا',
  'Belgium': 'بلجيكا',
  'Luxembourg': 'لوكسمبورغ',
  'Switzerland': 'سويسرا',
  'Austria': 'النمسا',
  'Czech Republic': 'التشيك',
  'Slovakia': 'سلوفاكيا',
  'Slovenia': 'سلوفينيا',
  'Hungary': 'المجر',
  'Poland': 'بولندا',
  'Romania': 'رومانيا',
  'Bulgaria': 'بلغاريا',
  'Serbia': 'صربيا',
  'Croatia': 'كرواتيا',
  'Greece': 'اليونان',
  'Russia': 'روسيا',
  'Belarus': 'بيلاروسيا',
  'Ukraine': 'أوكرانيا',
  'Sweden': 'السويد',
  'Norway': 'النرويج',
  'Finland': 'فنلندا',
  'Denmark': 'الدنمارك',
  'Ireland': 'أيرلندا',
  'Turkey': 'تركيا',
  'India': 'الهند',
  'Pakistan': 'باكستان',
  'Bangladesh': 'بنغلاديش',
  'Thailand': 'تايلاند',
  'Malaysia': 'ماليزيا',
  'Indonesia': 'إندونيسيا',
  'Philippines': 'الفلبين',
  'Vietnam': 'فيتنام',
  'Singapore': 'سنغافورة',
  'Taiwan': 'تايوان',
  'Hong Kong': 'هونغ كونغ',
  'Iran': 'إيران',
  'Iraq': 'العراق',
  'Israel': 'إسرائيل',
  'Jordan': 'الأردن',
  'Saudi Arabia': 'السعودية',
  'United Arab Emirates': 'الإمارات العربية المتحدة',
  'Uzbekistan': 'أوزبكستان',
  'Kazakhstan': 'كازاخستان',
  'Egypt': 'مصر',
  'Morocco': 'المغرب',
  'Algeria': 'الجزائر',
  'Tunisia': 'تونس',
  'Libya': 'ليبيا',
  'South Africa': 'جنوب أفريقيا',
  'Nigeria': 'نيجيريا',
  'Kenya': 'كينيا',
  'Australia': 'أستراليا',
  'New Zealand': 'نيوزيلندا',
  'Brazil': 'البرازيل',
  'Argentina': 'الأرجنتين',
  'Chile': 'تشيلي',
  'Colombia': 'كولومبيا',
};
