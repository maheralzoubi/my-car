import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/alert_service.dart';
import '../../../../../core/services/dtc_repository.dart';
import '../../../../../core/services/maintenance_service.dart';
import '../../../../../core/services/obd_service.dart';
import '../../../../../core/services/trip_service.dart';
import '../../../../../core/services/vin_decoder.dart';
import '../shell/app_shell.dart';
import 'obd_gauge.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // "All parameters" list under the live tiles (collapsed by default).
  bool _showAllParams = false;

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

  // One entry per lamp, in grid order (icons: [_lampIcons]).
  List<Map<String, dynamic>> warningLights = [
    for (final label in _lampIcons.keys)
      {'label': label, 'active': false, 'codes': <String>[]},
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
        _sensorWarnings['temp'] =
            d.coolantTempC != null && d.coolantTempC! >= 105;
        // Fuel: warn if fuel level ≤ 10 %.
        _sensorWarnings['fuel'] =
            d.fuelLevelPct != null && d.fuelLevelPct! <= 10;
        // Battery: warn if system voltage < 11.5 V (charging / battery fault).
        _sensorWarnings['battery'] =
            d.batteryVoltage != null && d.batteryVoltage! < 11.5;
        // Oil: warn if oil temperature > 130 °C (oil degrading / overheating).
        _sensorWarnings['oil'] = d.oilTempC != null && d.oilTempC! > 130;
        // Intake air > 60 °C = heat soak / intercooler failure (turbo engines).
        _sensorWarnings['check_engine'] =
            (_sensorWarnings['check_engine'] ?? false) ||
            (d.rpm != null && d.rpm! > 6500) ||
            (d.intakeAirTempC != null && d.intakeAirTempC! > 60);
        // Fuel trim: severe deviation > ±25 % indicates rich/lean fault.
        _sensorWarnings['fuel_trim'] =
            (d.fuelTrimShortPct != null && d.fuelTrimShortPct!.abs() > 25) ||
            (d.fuelTrimLongPct != null && d.fuelTrimLongPct!.abs() > 25) ||
            (d.fuelTrimShortB2 != null && d.fuelTrimShortB2!.abs() > 25) ||
            (d.fuelTrimLongB2 != null && d.fuelTrimLongB2!.abs() > 25);
        // Service: mirror the maintenance-due flag into sensor warnings.
        _sensorWarnings['service'] = MaintenanceService.instance.dueCount > 0;
        // Throttle: stuck open if > 90 % at idle (RPM < 1000).
        _sensorWarnings['throttle'] =
            d.throttlePct != null &&
            d.throttlePct! > 90 &&
            d.rpm != null &&
            d.rpm! < 1000;
        // Timing: heavy knock retard (< -10°) = ECU protecting engine from damage.
        _sensorWarnings['check_engine'] =
            (_sensorWarnings['check_engine'] ?? false) ||
            (d.timingAdvanceDeg != null && d.timingAdvanceDeg! < -10);
        // MAF/MAP: overboost > 200 kPa on turbo engines.
        _sensorWarnings['maf_sensor'] =
            (_sensorWarnings['maf_sensor'] ?? false) ||
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
    final codes = rawCodes
        .map((c) => c.startsWith('~') ? c.substring(1) : c)
        .toList();
    final pendingCount = rawCodes.where((c) => c.startsWith('~')).length;

    List<String> codesFor(bool Function(String) test) =>
        codes.where(test).toList();

    // Prefixes owned by specific lights — excluded from the generic check-engine list.
    const specificPrefixes = [
      'P056', 'P057', 'P115', // battery
      'P052', 'P053', // oil
      'P011', 'P012', 'P025', // temp
      'P008', 'P009', 'P046', // fuel
      'P042', 'P043', 'P044', 'P045', // exhaust
      'P07', 'P08', // transmission
      'P030', 'P032', 'P033', 'P034', 'P035', // misfire / ignition
      'P013', 'P014', 'P015', 'P016', // o2_sensor
      'P017', 'P018', // fuel_trim
      'P020', 'P021', // injector
      'P010', // maf_sensor
      'P040', 'P041', // egr
      'P21', // throttle / TAC
      'P022', 'P023', 'P024', // fuel_pressure
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

    bool isAbsCode(String c) => c.startsWith('C00');
    bool isTractionCode(String c) => c.startsWith('C01') && !isSteeringCode(c);

    setState(() {
      _scanningDtcs = false;
      _confirmedDtcs = codes.length - pendingCount;
      _pendingDtcs = pendingCount;
      warningLights = [
        // Check engine: residual P-codes not shown under any dedicated light.
        {
          'label': 'check_engine',
          'codes': codesFor((c) => c.startsWith('P') && !isSpecific(c)),
          'active': codes.any((c) => c.startsWith('P') && !isSpecific(c)),
        },
        {
          'label': 'battery',
          'codes': codesFor((c) => _matchPrefix(c, ['P056', 'P057', 'P115'])),
          'active': codes.any((c) => _matchPrefix(c, ['P056', 'P057', 'P115'])),
        },
        {
          'label': 'oil',
          'codes': codesFor((c) => _matchPrefix(c, ['P052', 'P053'])),
          'active': codes.any((c) => _matchPrefix(c, ['P052', 'P053'])),
        },
        {
          'label': 'abs',
          'codes': codesFor(isAbsCode),
          'active': codes.any(isAbsCode),
        },
        {
          'label': 'airbag',
          'codes': codesFor((c) => c.startsWith('B00')),
          'active': codes.any((c) => c.startsWith('B00')),
        },
        {
          'label': 'temp',
          'codes': codesFor((c) => _matchPrefix(c, ['P011', 'P012', 'P025'])),
          'active': codes.any((c) => _matchPrefix(c, ['P011', 'P012', 'P025'])),
        },
        {
          'label': 'fuel',
          'codes': codesFor((c) => _matchPrefix(c, ['P008', 'P009', 'P046'])),
          'active': codes.any((c) => _matchPrefix(c, ['P008', 'P009', 'P046'])),
        },
        {
          'label': 'exhaust',
          'codes': codesFor(
            (c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045']),
          ),
          'active': codes.any(
            (c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045']),
          ),
        },
        {
          'label': 'transmission',
          'codes': codesFor((c) => _matchPrefix(c, ['P07', 'P08'])),
          'active': codes.any((c) => _matchPrefix(c, ['P07', 'P08'])),
        },
        {
          'label': 'misfire',
          'codes': codesFor(
            (c) => _matchPrefix(c, ['P030', 'P032', 'P033', 'P034', 'P035']),
          ),
          'active': codes.any(
            (c) => _matchPrefix(c, ['P030', 'P032', 'P033', 'P034', 'P035']),
          ),
        },
        {
          'label': 'o2_sensor',
          'codes': codesFor(
            (c) => _matchPrefix(c, ['P013', 'P014', 'P015', 'P016']),
          ),
          'active': codes.any(
            (c) => _matchPrefix(c, ['P013', 'P014', 'P015', 'P016']),
          ),
        },
        {
          'label': 'fuel_trim',
          'codes': codesFor((c) => _matchPrefix(c, ['P017', 'P018'])),
          'active': codes.any((c) => _matchPrefix(c, ['P017', 'P018'])),
        },
        {
          'label': 'injector',
          'codes': codesFor((c) => _matchPrefix(c, ['P020', 'P021'])),
          'active': codes.any((c) => _matchPrefix(c, ['P020', 'P021'])),
        },
        {
          'label': 'maf_sensor',
          'codes': codesFor((c) => _matchPrefix(c, ['P010'])),
          'active': codes.any((c) => _matchPrefix(c, ['P010'])),
        },
        {
          'label': 'network',
          'codes': codesFor((c) => c.startsWith('U')),
          'active': codes.any((c) => c.startsWith('U')),
        },
        {
          'label': 'service',
          'codes': <String>[],
          'active': MaintenanceService.instance.dueCount > 0,
        },
        {
          'label': 'traction',
          'codes': codesFor(isTractionCode),
          'active': codes.any(isTractionCode),
        },
        {
          'label': 'steering',
          'codes': codesFor(isSteeringCode),
          'active': codes.any(isSteeringCode),
        },
        {
          'label': 'egr',
          'codes': codesFor((c) => _matchPrefix(c, ['P040', 'P041'])),
          'active': codes.any((c) => _matchPrefix(c, ['P040', 'P041'])),
        },
        {
          'label': 'throttle',
          'codes': codesFor((c) => _matchPrefix(c, ['P21'])),
          'active': codes.any((c) => _matchPrefix(c, ['P21'])),
        },
        {
          'label': 'fuel_pressure',
          'codes': codesFor((c) => _matchPrefix(c, ['P022', 'P023', 'P024'])),
          'active': codes.any((c) => _matchPrefix(c, ['P022', 'P023', 'P024'])),
        },
        {'label': 'mil', 'codes': <String>[], 'active': readiness.milOn},
        {
          'label': 'body',
          'codes': codesFor((c) => c.startsWith('B') && !c.startsWith('B00')),
          'active': codes.any((c) => c.startsWith('B') && !c.startsWith('B00')),
        },
      ];
    });
  }

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

  // ── Navigation ─────────────────────────────────────────────────────────────

  bool get _connected => OBDService.instance.isInitialized;

  /// Switches to [tab] in the bottom-navigation shell, or pushes [route] when
  /// the dashboard is shown on its own (pushed from the service hub, tests).
  void _goTab(AppTab tab, String route) {
    final shell = AppShell.maybeOf(context);
    if (shell != null) {
      shell.goTo(tab);
    } else {
      Navigator.pushNamed(context, route);
    }
  }

  void _openScan() => _goTab(AppTab.diagnose, AppRoutes.diagnosticCodes);
  void _openRoadside() => _goTab(AppTab.roadside, AppRoutes.roadside);
  void _openHistory() => _goTab(AppTab.history, AppRoutes.history);
  void _openSettings() => _goTab(AppTab.profile, AppRoutes.settings);
  void _push(String route) => Navigator.pushNamed(context, route);

  /// Some localized labels (drive-score bands) carry an emoji; the UI shows
  /// the words only.
  static final RegExp _emoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]',
    unicode: true,
  );
  static String _plain(String s) => s.replaceAll(_emoji, '').trim();

  // Material icons for the warning lamps (keyed by lamp label, in grid order).
  static const Map<String, IconData> _lampIcons = {
    'check_engine': Icons.warning_amber_rounded,
    'battery': Icons.battery_alert_rounded,
    'oil': Icons.oil_barrel_outlined,
    'abs': Icons.album_outlined,
    'airbag': Icons.airline_seat_recline_normal_rounded,
    'temp': Icons.thermostat_rounded,
    'fuel': Icons.local_gas_station_outlined,
    'exhaust': Icons.air_rounded,
    'transmission': Icons.settings_outlined,
    'misfire': Icons.local_fire_department_outlined,
    'o2_sensor': Icons.sensors_rounded,
    'fuel_trim': Icons.tune_rounded,
    'injector': Icons.opacity_rounded,
    'maf_sensor': Icons.wind_power_outlined,
    'network': Icons.lan_outlined,
    'service': Icons.handyman_outlined,
    'traction': Icons.waves_rounded,
    'steering': Icons.trip_origin_rounded,
    'egr': Icons.recycling_rounded,
    'throttle': Icons.speed_rounded,
    'fuel_pressure': Icons.water_drop_outlined,
    'mil': Icons.error_outline_rounded,
    'body': Icons.lightbulb_outline_rounded,
  };

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
        // Inside AppShell the dashboard stays mounted while another tab is
        // showing; that tab's Back returns to Home (the shell handles it), so
        // the exit hint must only react when Home is the visible tab.
        // TickerMode (set by the shell on hidden tabs) still reflects the tab
        // that was visible when Back was pressed, even if the shell's own
        // handler already switched to Home during this same pop.
        if (!TickerMode.getValuesNotifier(context).value.enabled) return;
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
      // No bottom bar here: AppShell provides the app's navigation.
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        AppSizes.space20.w,
                        AppSizes.space4.h,
                        AppSizes.space20.w,
                        AppSizes.space32.h,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _connected ? _buildHealthCard() : _buildConnectCard(),
                          if (MaintenanceService.instance.dueCount > 0) ...[
                            SizedBox(height: AppSizes.space12.h),
                            _buildMaintenanceAlert(),
                          ],
                          SizedBox(height: AppSizes.space24.h),
                          _buildLiveDataSection(),
                          if (TripService.instance.isRunning) ...[
                            SizedBox(height: AppSizes.space12.h),
                            _buildTripCard(),
                          ],
                          SizedBox(height: AppSizes.space24.h),
                          _buildServicesSection(),
                          SizedBox(height: AppSizes.space24.h),
                          _buildWarningLightsSection(),
                          if (_connected || _vin != null) ...[
                            SizedBox(height: AppSizes.space24.h),
                            _buildVehicleSection(),
                          ],
                          SizedBox(height: AppSizes.space24.h),
                          _buildRecentScansSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── In-app alert overlay ────────────────────────────────────
            if (_activeAlert != null) _buildAlertOverlay(_activeAlert!),
          ],
        ),
      ),
    );
  }

  // ── Header: greeting + vehicle name, adapter action ─────────────────────────

  String get _greeting {
    final h = DateTime.now().hour;
    return context.tr(
      h < 12
          ? 'dash_greeting_morning'
          : h < 18
          ? 'dash_greeting_afternoon'
          : 'dash_greeting_evening',
    );
  }

  /// VinDecoder reports undeterminable fields as [VinDecoder.unknown].
  String _vinField(String key, String unknownKey) {
    final value = _vinInfo[key] ?? '';
    return value == VinDecoder.unknown ? context.tr(unknownKey) : value;
  }

  /// "Maker  •  year" from the VIN, the raw VIN, or "My car".
  String get _vehicleName {
    if (_vin == null) return context.tr('dash_my_car');
    final manufacturer = _vinField('manufacturer', 'vin_unknown');
    final year = _vinField('year', 'vin_year_unknown');
    return manufacturer.isNotEmpty ? '$manufacturer  •  $year' : _vin!;
  }

  Widget _buildHeader() {
    final p = context.colors;
    final canPop = Navigator.canPop(context);
    final inShell = AppShell.maybeOf(context) != null;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        canPop ? AppSizes.space8.w : AppSizes.space20.w,
        AppSizes.space12.h,
        AppSizes.space16.w,
        AppSizes.space12.h,
      ),
      child: Row(
        children: [
          if (canPop) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: p.text,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.maybePop(context),
            ),
            SizedBox(width: AppSizes.space4.w),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    _vehicleName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headline.copyWith(color: p.text),
                  ),
                ),
              ],
            ),
          ),
          // Outside the shell (pushed from the hub) there is no Profile tab.
          if (!inShell) ...[
            SizedBox(width: AppSizes.space8.w),
            HeaderAction(
              icon: Icons.settings_outlined,
              tooltip: context.tr('settings'),
              onPressed: _openSettings,
            ),
          ],
          SizedBox(width: AppSizes.space8.w),
          HeaderAction(
            icon: _connected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_rounded,
            color: _connected ? p.primary : null,
            tooltip: context.tr('dash_adapter'),
            onPressed: _openConnectionScreen,
          ),
        ],
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
    final p = context.colors;
    final s = _healthScore;
    if (s >= 70) return p.ok;
    if (s >= 50) return p.warn;
    return p.crit;
  }

  // ── Health card (connected) ───────────────────────────────────────────────

  Widget _buildHealthCard() {
    final p = context.colors;
    final confirmed = _confirmedDtcs;
    final pending = _pendingDtcs;
    return AppCard(
      padding: EdgeInsets.all(AppSizes.space16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _HealthRing(score: _healthScore, color: _healthColor),
              SizedBox(width: AppSizes.space16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('vehicle_health'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.text2,
                      ),
                    ),
                    Text(
                      _healthLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title.copyWith(color: p.text),
                    ),
                    SizedBox(height: AppSizes.space4.h),
                    _buildLinkStatus(),
                  ],
                ),
              ),
            ],
          ),
          if (confirmed > 0 || pending > 0) ...[
            SizedBox(height: AppSizes.space16.h),
            _buildCodesRow(confirmed, pending),
          ],
          SizedBox(height: AppSizes.space16.h),
          AppButton(
            label: context.tr('quick_scan'),
            icon: Icons.monitor_heart_outlined,
            onPressed: _openScan,
          ),
        ],
      ),
    );
  }

  /// "Connected" pill + adapter name. Opens the adapter screen, the place to
  /// disconnect or switch adapters.
  Widget _buildLinkStatus() {
    final p = context.colors;
    return InkWell(
      onTap: _openConnectionScreen,
      borderRadius: BorderRadius.circular(AppSizes.radiusSm.r),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 44.h),
        child: Row(
          children: [
            StatusBadge(
              label: context.tr('connected'),
              level: StatusLevel.ok,
              showIcon: true,
            ),
            SizedBox(width: AppSizes.space8.w),
            Flexible(
              child: Text(
                OBDService.instance.connectedDeviceName ??
                    context.tr('dash_adapter'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: p.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Warn-soft "N codes need attention" row; opens the codes screen.
  Widget _buildCodesRow(int confirmed, int pending) {
    final p = context.colors;
    final text = context
        .tr(
          confirmed == 0
              ? (pending == 1
                    ? 'dash_pending_only_one'
                    : 'dash_pending_only_many')
              : confirmed == 1
              ? 'dash_fault_code_n'
              : 'dash_fault_codes_n',
        )
        .replaceAll('{n}', '${confirmed == 0 ? pending : confirmed}');
    return Material(
      color: p.warnSoft,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openScan,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 44.h),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSizes.space12.w,
              AppSizes.space8.h,
              AppSizes.space8.w,
              AppSizes.space8.h,
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: p.warn, size: 18.r),
                SizedBox(width: AppSizes.space8.w),
                Expanded(
                  child: Text(
                    text,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.warn,
                    ),
                  ),
                ),
                // Pending (mode 07) codes: not confirmed faults yet.
                if (confirmed > 0 && pending > 0) ...[
                  SizedBox(width: AppSizes.space8.w),
                  Text(
                    context
                        .tr('dash_pending_codes_n')
                        .replaceAll('{n}', '$pending'),
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.warn,
                    ),
                  ),
                ],
                Icon(Icons.chevron_right_rounded, color: p.warn, size: 20.r),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Not connected: offer "Connect" ────────────────────────────────────────

  Widget _buildConnectCard() {
    return AppCard(
      onTap: _openConnectionScreen,
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space16.w,
        vertical: AppSizes.space24.h,
      ),
      child: EmptyState(
        icon: Icons.bluetooth_disabled_rounded,
        title: context.tr('obd_not_connected'),
        message: context.tr('dash_connect_for_health'),
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: context.tr('dash_connect'),
              icon: Icons.bluetooth_searching_rounded,
              onPressed: _openConnectionScreen,
            ),
            SizedBox(height: AppSizes.space8.h),
            AppButton.secondary(
              label: context.tr('quick_scan'),
              icon: Icons.monitor_heart_outlined,
              onPressed: _openScan,
            ),
          ],
        ),
      ),
    );
  }

  // ── Maintenance due ───────────────────────────────────────────────────────

  Widget _buildMaintenanceAlert() {
    final p = context.colors;
    final count = MaintenanceService.instance.dueCount;
    return AppCard(
      accent: p.warn,
      onTap: () => _push(AppRoutes.maintenance),
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space12.w,
        AppSizes.space12.h,
        AppSizes.space8.w,
        AppSizes.space12.h,
      ),
      child: Row(
        children: [
          IconBox(Icons.build_outlined, color: p.warn, size: 36),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Text(
              context
                  .tr(
                    count == 1
                        ? 'dash_maintenance_due_one'
                        : 'dash_maintenance_due_many',
                  )
                  .replaceAll('{n}', '$count'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w600,
                color: p.warn,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.warn, size: 20.r),
        ],
      ),
    );
  }

  // ── Alert overlay ─────────────────────────────────────────────────────────

  Widget _buildAlertOverlay(OBDAlert alert) {
    final p = context.colors;
    final isCritical = alert.severity == AlertSeverity.critical;
    final tone = isCritical ? p.crit : p.warn;
    final radius = BorderRadius.circular(AppSizes.radiusLg.r);
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSizes.space12.r),
          child: Material(
            color: p.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: tone),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _activeAlert = null),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space12.w,
                  AppSizes.space12.h,
                  AppSizes.space12.w,
                  AppSizes.space12.h,
                ),
                child: Row(
                  children: [
                    IconBox(
                      isCritical
                          ? Icons.error_outline_rounded
                          : Icons.warning_amber_rounded,
                      color: tone,
                    ),
                    SizedBox(width: AppSizes.space12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.title,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: p.text,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            alert.message,
                            style: AppTextStyles.label.copyWith(
                              fontWeight: FontWeight.w400,
                              color: p.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSizes.space8.w),
                    Icon(Icons.close_rounded, color: p.muted, size: 20.r),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Live data ─────────────────────────────────────────────────────────────

  Widget _buildLiveDataSection() {
    return StreamBuilder<OBDLiveData>(
      stream: OBDService.instance.liveDataStream,
      initialData: OBDService.instance.currentData,
      builder: (context, snapshot) {
        final d = snapshot.data ?? const OBDLiveData();
        final p = context.colors;
        final gap = SizedBox(width: AppSizes.space12.w);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              context.tr('live_data'),
              trailing: _connected
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Live-link indicator.
                        ExcludeSemantics(
                          child: Container(
                            width: 8.r,
                            height: 8.r,
                            decoration: BoxDecoration(
                              color: p.ok,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        SizedBox(width: AppSizes.space8.w),
                        SectionLink(
                          label: context.tr('dash_see_graph'),
                          onTap: () => _push(AppRoutes.liveGraph),
                        ),
                      ],
                    )
                  : null,
            ),
            Row(
              children: [
                Expanded(
                  child: OBDGauge(
                    value: d.speedKmh,
                    label: context.tr('dash_speed'),
                    unit: 'km/h',
                    icon: Icons.speed_rounded,
                  ),
                ),
                gap,
                Expanded(
                  child: OBDGauge(
                    value: d.rpm,
                    label: context.tr('engine'),
                    unit: 'rpm',
                    icon: Icons.av_timer_rounded,
                    dangerAt: 6500,
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSizes.space12.h),
            Row(
              children: [
                Expanded(
                  child: OBDGauge(
                    value: d.coolantTempC,
                    label: context.tr('dash_coolant'),
                    unit: '°C',
                    icon: Icons.thermostat_rounded,
                    dangerAt: 105,
                  ),
                ),
                gap,
                Expanded(
                  child: OBDGauge(
                    value: d.batteryVoltage,
                    label: context.tr('battery'),
                    unit: 'V',
                    icon: Icons.battery_charging_full_rounded,
                    decimals: 1,
                    dangerBelow: 11.5,
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSizes.space12.h),
            _buildMoreParams(d),
          ],
        );
      },
    );
  }

  /// Every other live parameter, collapsed by default behind "All parameters".
  Widget _buildMoreParams(OBDLiveData d) {
    final p = context.colors;
    final rows = _showAllParams ? _paramRows(d) : const <Widget>[];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _showAllParams,
            child: InkWell(
              key: const ValueKey('dash_more_params'),
              onTap: () => setState(() => _showAllParams = !_showAllParams),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: 48.h),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.space16.w),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, color: p.text2, size: 20.r),
                      SizedBox(width: AppSizes.space12.w),
                      Expanded(
                        child: Text(
                          context.tr(
                            _showAllParams
                                ? 'dash_fewer_params'
                                : 'dash_more_params',
                          ),
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w500,
                            color: p.text,
                          ),
                        ),
                      ),
                      Icon(
                        _showAllParams
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: p.muted,
                        size: 22.r,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          for (final row in rows) ...[
            Divider(
              height: 1,
              thickness: 1,
              indent: AppSizes.space16.w,
              color: p.border,
            ),
            row,
          ],
        ],
      ),
    );
  }

  List<Widget> _paramRows(OBDLiveData d) {
    final p = context.colors;
    String f1(double? v) => v != null ? v.toStringAsFixed(1) : '--';
    // Diesels (and some petrol cars) report the pedal, not a throttle plate.
    final usePedal =
        _isDiesel || (d.throttlePct == null && d.acceleratorPedalPct != null);
    final iat = d.intakeAirTempC;
    return [
      _param(
        context.tr('dash_air_temp'),
        iat != null ? '${iat.toStringAsFixed(0)}°C' : '--',
        tone: iat != null && iat > 60 ? p.crit : null,
      ),
      if (usePedal)
        _param(context.tr('accel_pedal'), f1(d.acceleratorPedalPct), unit: '%')
      else
        _param(context.tr('throttle'), f1(d.throttlePct), unit: '%'),
      _param(context.tr('fuel'), f1(d.fuelLevelPct), unit: '%'),
      _param(context.tr('dash_engine_load'), f1(d.engineLoad), unit: '%'),
      _param(
        context.tr('dash_map'),
        d.mapKpa != null ? '${d.mapKpa!.toStringAsFixed(0)} kPa' : '--',
      ),
      // Diesel: rail pressure + oil temp instead of timing / fuel trims.
      if (_isDiesel) ...[
        _railPressureParam(d.fuelRailPressureKpa),
        _oilTempParam(d.oilTempC),
      ] else ...[
        _timingParam(d.timingAdvanceDeg),
        // GDI petrol engines may report rail pressure too.
        if (d.fuelRailPressureKpa != null)
          _railPressureParam(d.fuelRailPressureKpa),
        _fuelTrimParam('STFT B1', d.fuelTrimShortPct),
        _fuelTrimParam('LTFT B1', d.fuelTrimLongPct),
        _oilTempParam(d.oilTempC),
      ],
      // Fuel trim bank 2 (V6/V8).
      if (d.fuelTrimShortB2 != null || d.fuelTrimLongB2 != null) ...[
        _fuelTrimParam('STFT B2', d.fuelTrimShortB2),
        _fuelTrimParam('LTFT B2', d.fuelTrimLongB2),
      ],
      // O2 sensors (diesel: only if it reports any).
      if (!_isDiesel ||
          d.o2B1S1Voltage != null ||
          d.lambdaB1S1 != null ||
          d.o2B1S2Voltage != null) ...[
        // Wide-band upstream sensors report λ instead of volts.
        if (d.o2B1S1Voltage == null && d.lambdaB1S1 != null)
          _lambdaParam('O2 B1S1', d.lambdaB1S1!)
        else
          _o2Param('O2 B1S1', d.o2B1S1Voltage),
        _o2Param('O2 B1S2', d.o2B1S2Voltage),
        _o2Param('O2 B2S1', d.o2B2S1Voltage),
      ],
    ];
  }

  /// One parameter row: label, then value (+ unit). [tone] is a status color,
  /// used only when the reading is out of its normal range.
  Widget _param(String label, String value, {String unit = '', Color? tone}) {
    final p = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 44.h),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space16.w,
          vertical: AppSizes.space8.h,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(color: p.text2),
              ),
            ),
            SizedBox(width: AppSizes.space12.w),
            // Value + unit read left-to-right in Arabic too ("18.0 %").
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    style: AppTextStyles.numeric(AppTextStyles.body).copyWith(
                      fontWeight: FontWeight.w600,
                      color: tone ?? (value == '--' ? p.muted : p.text),
                    ),
                  ),
                  if (unit.isNotEmpty && value != '--') ...[
                    SizedBox(width: AppSizes.space4.w),
                    Text(
                      unit,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.text2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fuel trim: normal ±10 %, moderate ±20 % (warn), severe beyond (crit).
  Widget _fuelTrimParam(String label, double? value) {
    final p = context.colors;
    final Color? tone = value == null || value.abs() <= 10
        ? null
        : value.abs() <= 20
        ? p.warn
        : p.crit;
    final prefix = value != null && value > 0 ? '+' : '';
    return _param(
      label,
      value != null ? '$prefix${value.toStringAsFixed(1)}' : '--',
      unit: '%',
      tone: tone,
    );
  }

  Widget _o2Param(String label, double? voltage) {
    // O2 sensor voltage 0–1.275 V.
    // < 0.1 V  = lean   (or sensor cold/dead)
    // 0.1–0.9  = cycling — healthy, engine controlling fuel properly
    // > 0.9 V  = rich
    // ~0.45 V  = stuck — sensor dead or lazy
    final p = context.colors;
    if (voltage == null) return _param(label, '--');
    final Color? tone;
    if (voltage < 0.1 || voltage > 0.9) {
      tone = p.warn; // lean / rich
    } else if ((voltage - 0.45).abs() < 0.05) {
      tone = p.crit; // stuck ~0.45 V → dead sensor
    } else {
      tone = null; // cycling normally
    }
    return _param(label, '${voltage.toStringAsFixed(2)}V', tone: tone);
  }

  Widget _timingParam(double? deg) {
    // Normal advance (≥ 0°). Light retard (-5 to 0°): warn. Heavy knock
    // retard (< -5°): crit — the ECU is protecting the engine from damage.
    final p = context.colors;
    final Color? tone = deg == null || deg >= 0
        ? null
        : deg >= -5
        ? p.warn
        : p.crit;
    final prefix = deg != null && deg > 0 ? '+' : '';
    return _param(
      context.tr('timing'),
      deg != null ? '$prefix${deg.toStringAsFixed(1)}°' : '--',
      tone: tone,
    );
  }

  Widget _oilTempParam(double? oilTempC) {
    final p = context.colors;
    return _param(
      context.tr('dash_oil_temp'),
      oilTempC != null ? '${oilTempC.toStringAsFixed(0)}°C' : '--',
      tone: oilTempC != null && oilTempC > 130 ? p.crit : null,
    );
  }

  // Fuel rail gauge pressure, shown in MPa (common-rail diesel: ~25–35 MPa
  // at idle, up to ~200 MPa under load; GDI petrol: ~4–20 MPa).
  Widget _railPressureParam(double? kpa) => _param(
    context.tr('rail_pressure'),
    kpa != null ? (kpa / 1000).toStringAsFixed(1) : '--',
    unit: 'MPa',
  );

  Widget _lambdaParam(String label, double lambda) {
    // Wide-band sensor equivalence ratio: 1.00 = stoichiometric.
    // Petrol closed loop holds ~0.97–1.03; outside that it runs rich (< 1)
    // or lean (> 1). Diesels run lean (λ well above 1) by design.
    final p = context.colors;
    final normal = _isDiesel || (lambda - 1).abs() <= 0.03;
    return _param(
      label,
      'λ ${lambda.toStringAsFixed(2)}',
      tone: normal ? null : p.warn,
    );
  }

  // ── Trip computer card ────────────────────────────────────────────────────

  Widget _buildTripCard() {
    final p = context.colors;
    final trip = TripService.instance;
    final elapsed = trip.elapsed;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final timeStr = h > 0 ? '$h:$m:$s' : '$m:$s';
    final scoreTone = _driveScoreColor(trip.driveScore);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBox(Icons.route_rounded, size: 36),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Text(
                  context.tr('dash_trip_computer'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title.copyWith(color: p.text),
                ),
              ),
              SizedBox(width: AppSizes.space8.w),
              AppButton.ghost(
                label: context.tr('dash_reset'),
                onPressed: () => setState(() => trip.reset()),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          Row(
            children: [
              _tripStat(
                context.tr('dash_distance'),
                '${trip.distanceKm.toStringAsFixed(1)} km',
              ),
              _tripStat(context.tr('dash_time'), timeStr),
              _tripStat(
                context.tr('dash_avg_speed'),
                '${trip.avgSpeedKmh.toStringAsFixed(0)} km/h',
              ),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          Row(
            children: [
              _tripStat(
                context.tr('dash_fuel_used'),
                '${trip.fuelUsedL.toStringAsFixed(2)} L',
              ),
              _tripStat(
                context.tr('dash_efficiency'),
                trip.fuelEfficiencyL100km > 0
                    ? '${trip.fuelEfficiencyL100km.toStringAsFixed(1)} L/100km'
                    : '--',
              ),
              const Spacer(),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          Divider(height: 1, thickness: 1, color: p.border),
          SizedBox(height: AppSizes.space12.h),
          // ── Drive score ──────────────────────────────────────────────
          // Label column takes the free space (and ellipsizes); the score
          // keeps its natural width, so the row never overflows the card.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('drive_score'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: p.text2,
                      ),
                    ),
                    Text(
                      _driveScoreLabel(trip.driveScore),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scoreTone,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSizes.space8.w),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '${trip.driveScore}',
                      style: AppTextStyles.headline.copyWith(color: scoreTone),
                    ),
                    Text(
                      ' / 100',
                      style: AppTextStyles.label.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Same bands as TripService.driveScoreLabel, localized (without emoji).
  String _driveScoreLabel(int score) {
    if (score >= 85) return _plain(context.tr('dash_drive_eco'));
    if (score >= 65) return _plain(context.tr('dash_drive_normal'));
    if (score >= 45) return _plain(context.tr('dash_drive_sporty'));
    return _plain(context.tr('dash_drive_aggressive'));
  }

  Color _driveScoreColor(int score) {
    final p = context.colors;
    if (score >= 65) return p.ok;
    if (score >= 45) return p.warn;
    return p.crit;
  }

  Widget _tripStat(String label, String value) {
    final p = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(color: p.text2),
          ),
          SizedBox(height: 2.h),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: AppTextStyles.numeric(
              AppTextStyles.body,
            ).copyWith(fontWeight: FontWeight.w600, color: p.text),
          ),
        ],
      ),
    );
  }

  // ── Services ──────────────────────────────────────────────────────────────

  Widget _buildServicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('dash_services')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _service(
              Icons.local_shipping_outlined,
              context.tr('dash_svc_roadside'),
              _openRoadside,
            ),
            _service(
              Icons.build_rounded,
              context.tr('dash_svc_maintenance'),
              () => _push(AppRoutes.maintenance),
            ),
            _service(
              Icons.key_rounded,
              context.tr('smart_key'),
              () => _push(AppRoutes.smartKey),
            ),
            _service(
              Icons.play_circle_outline_rounded,
              context.tr('dash_svc_tutorials'),
              () => _push(AppRoutes.videoTutorials),
            ),
          ],
        ),
      ],
    );
  }

  Widget _service(IconData icon, String label, VoidCallback onTap) {
    final p = context.colors;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.space4.w,
              vertical: AppSizes.space4.h,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52.r,
                  height: 52.r,
                  decoration: BoxDecoration(
                    color: p.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.border),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: p.text, size: 22.r),
                ),
                SizedBox(height: AppSizes.space8.h),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label.copyWith(color: p.text2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Warning lights: lit lamps on the page, the full grid in a sheet ───────

  /// A lamp lights from a DTC match OR from a live sensor threshold. The
  /// service lamp follows the maintenance tracker directly, so it stays
  /// current after the user logs a service.
  bool _lampOn(Map<String, dynamic> light) {
    final label = light['label'] as String;
    if (label == 'service') return MaintenanceService.instance.dueCount > 0;
    return (light['active'] as bool) || (_sensorWarnings[label] ?? false);
  }

  Widget _buildWarningLightsSection() {
    final p = context.colors;
    final lit = warningLights.where(_lampOn).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('warning_lights'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_scanningDtcs)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSizes.space8.w),
                  child: SizedBox.square(
                    dimension: 18.r,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_connected)
                IconButton(
                  onPressed: _fetchDtcsAndUpdateLights,
                  tooltip: context.tr('dash_recheck_lamps'),
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: p.primary,
                    size: 20.r,
                  ),
                ),
              SectionLink(
                label: context.tr('dash_see_all'),
                onTap: _showAllLampsSheet,
              ),
            ],
          ),
        ),
        if (lit.isEmpty)
          AppCard(
            child: Row(
              children: [
                _connected
                    ? IconBox(
                        Icons.check_circle_outline_rounded,
                        color: p.ok,
                        size: 36,
                      )
                    : const IconBox.neutral(
                        Icons.lightbulb_outline_rounded,
                        size: 36,
                      ),
                SizedBox(width: AppSizes.space12.w),
                Expanded(
                  child: Text(
                    context.tr(
                      _connected ? 'dash_lamps_off' : 'dash_lamps_unknown',
                    ),
                    style: AppTextStyles.body.copyWith(color: p.text2),
                  ),
                ),
              ],
            ),
          )
        else
          AppCard(
            key: const ValueKey('dash_lit_lamps'),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < lit.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: AppSizes.space16.w,
                      color: p.border,
                    ),
                  _litLampRow(lit[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _litLampRow(Map<String, dynamic> light) {
    final p = context.colors;
    final label = light['label'] as String;
    final codes = light['codes'] as List<String>;
    return InkWell(
      onTap: codes.isNotEmpty
          ? () => _showDtcBottomSheet(context, label, codes)
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 52.h),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSizes.space16.w,
            AppSizes.space8.h,
            AppSizes.space12.w,
            AppSizes.space8.h,
          ),
          child: Row(
            children: [
              IconBox(_lampIcons[label]!, color: p.warn, size: 32),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr(label),
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: p.text,
                      ),
                    ),
                    if (codes.isNotEmpty)
                      Text(
                        '${codes.length} ${context.tr(codes.length == 1 ? 'code_detected' : 'codes_detected')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: p.text2,
                        ),
                      ),
                  ],
                ),
              ),
              if (codes.isNotEmpty)
                Icon(Icons.chevron_right_rounded, color: p.muted, size: 22.r),
            ],
          ),
        ),
      ),
    );
  }

  /// "See all": every lamp, lit ones in the warning color.
  void _showAllLampsSheet() {
    final lamps = [for (final l in warningLights) (l, _lampOn(l))];
    // Background, top corners and drag handle come from the sheet theme.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final p = sheetCtx.colors;
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  0,
                  AppSizes.space20.w,
                  AppSizes.space12.h,
                ),
                child: Text(
                  sheetCtx.tr('warning_lights'),
                  style: AppTextStyles.title.copyWith(color: p.text),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsetsDirectional.fromSTEB(
                    AppSizes.space16.w,
                    0,
                    AppSizes.space16.w,
                    AppSizes.space24.h,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: AppSizes.space8.w,
                    mainAxisSpacing: AppSizes.space8.h,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: lamps.length,
                  itemBuilder: (_, i) {
                    final (light, on) = lamps[i];
                    final label = light['label'] as String;
                    final codes = light['codes'] as List<String>;
                    return Material(
                      color: on ? p.warnSoft : p.surface2,
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: on && codes.isNotEmpty
                            ? () => _showDtcBottomSheet(sheetCtx, label, codes)
                            : null,
                        child: Padding(
                          padding: EdgeInsets.all(AppSizes.space4.r),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _lampIcons[label],
                                color: on ? p.warn : p.muted,
                                size: 24.r,
                              ),
                              SizedBox(height: AppSizes.space8.h),
                              Text(
                                sheetCtx.tr(label),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption.copyWith(
                                  color: on ? p.warn : p.text2,
                                  fontWeight: on
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDtcBottomSheet(BuildContext ctx, String label, List<String> codes) {
    final repo = _dtcRepo;
    final langCode = Localizations.localeOf(ctx).languageCode;
    final isArabic = langCode == 'ar';

    // Background, top corners and drag handle come from the sheet theme.
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final p = sheetCtx.colors;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  0,
                  AppSizes.space20.w,
                  AppSizes.space16.h,
                ),
                child: Row(
                  children: [
                    IconBox(_lampIcons[label]!, color: p.warn),
                    SizedBox(width: AppSizes.space12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheetCtx.tr(label),
                            style: AppTextStyles.title.copyWith(color: p.text),
                          ),
                          Text(
                            '${codes.length} ${sheetCtx.tr(codes.length == 1 ? 'code_detected' : 'codes_detected')}',
                            style: AppTextStyles.label.copyWith(
                              fontWeight: FontWeight.w400,
                              color: p.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: p.border),
              // Code list
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.space16.w,
                    vertical: AppSizes.space12.h,
                  ),
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
        );
      },
    );
  }

  // ── Vehicle: adapter + VIN ────────────────────────────────────────────────

  Widget _buildVehicleSection() {
    String? vinLine;
    if (_vin != null) {
      final country = _localizedCountry(_vinField('country', 'vin_unknown'));
      vinLine = country.isNotEmpty ? '$country  •  VIN: $_vin' : 'VIN: $_vin';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('dash_vehicle')),
        SettingsGroup(
          children: [
            if (_connected)
              SettingsTile(
                leading: const IconBox.neutral(
                  Icons.bluetooth_connected_rounded,
                ),
                title: context.tr('dash_adapter'),
                subtitle: context.tr('dash_manage_adapter'),
                onTap: _openConnectionScreen,
              ),
            if (vinLine != null)
              SettingsTile(
                leading: const IconBox.neutral(Icons.badge_outlined),
                title: context.tr('dash_vehicle_id'),
                subtitle: vinLine,
              ),
          ],
        ),
      ],
    );
  }

  /// VinDecoder's English country name, in Arabic when the UI is Arabic
  /// (falls back to the English name for countries not listed).
  String _localizedCountry(String country) {
    if (Localizations.localeOf(context).languageCode != 'ar') return country;
    return _arCountryNames[country] ?? country;
  }

  // ── Recent scans → History ────────────────────────────────────────────────

  Widget _buildRecentScansSection() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('recent_scans'),
          trailing: SectionLink(
            label: context.tr('history'),
            onTap: _openHistory,
          ),
        ),
        AppCard(
          onTap: _openHistory,
          child: Row(
            children: [
              const IconBox.neutral(Icons.history_rounded, size: 36),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Text(
                  context.tr('no_scans_yet'),
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Health score ring ────────────────────────────────────────────────────────

class _HealthRing extends StatelessWidget {
  const _HealthRing({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Semantics(
      label: '${context.tr('vehicle_health')} $score / 100',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 64.r,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: score / 100,
                strokeWidth: 6.r,
                strokeCap: StrokeCap.round,
                backgroundColor: p.track,
                color: color,
              ),
            ),
            Text(
              '$score',
              style: AppTextStyles.numeric(
                AppTextStyles.title,
              ).copyWith(fontWeight: FontWeight.w700, color: p.text),
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
    final en = await widget.repo.getDtcDescription(
      widget.code,
      languageCode: 'en',
    );
    String? ar;
    if (widget.isArabic) {
      ar = await widget.repo.getDtcDescription(widget.code, languageCode: 'ar');
    }
    if (!mounted) return;
    setState(() {
      _enDesc = en;
      _arDesc = ar;
      _loading = false;
    });
  }

  void _openYoutube() {
    final query = Uri.encodeComponent('${widget.code} car fix how to');
    final url = Uri.parse(
      'https://www.youtube.com/results?search_query=$query',
    );
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final descStyle = AppTextStyles.label.copyWith(
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: p.text,
    );
    return AppCard(
      margin: EdgeInsetsDirectional.only(bottom: AppSizes.space12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code + fix-video link
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSizes.space8.w,
                  vertical: AppSizes.space4.h,
                ),
                decoration: BoxDecoration(
                  color: p.warnSoft,
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm.r),
                ),
                // DTC codes are always Latin, so letter-spacing is safe.
                child: Text(
                  widget.code,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: p.warn,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _openYoutube,
                icon: Icon(Icons.play_circle_outline_rounded, size: 18.r),
                label: Text(context.tr('dash_fix_video')),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space8.h),
          // Description
          if (_loading)
            Row(
              children: [
                SizedBox.square(
                  dimension: 14.r,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: AppSizes.space8.w),
                Text(
                  context.tr('dash_loading_desc'),
                  style: descStyle.copyWith(color: p.muted),
                ),
              ],
            )
          else ...[
            // English description always shown
            Text(_enDesc ?? context.tr('dash_no_desc'), style: descStyle),
            // Arabic description shown below when app is in Arabic
            if (widget.isArabic && _arDesc != null && _arDesc != _enDesc) ...[
              SizedBox(height: AppSizes.space8.h),
              Divider(height: 1, thickness: 1, color: p.border),
              SizedBox(height: AppSizes.space8.h),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(_arDesc!, style: descStyle),
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
