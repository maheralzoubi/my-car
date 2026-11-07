import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/obd_service.dart';

// ── ELM327 / OBD device detection ────────────────────────────────────────────

/// Returns true if [name] matches a known OBD / ELM327 adapter pattern.
bool _isOBDDevice(String name) {
  final n = name.toLowerCase();
  const patterns = [
    'obd',
    'elm',
    'vlink',
    'v-link',
    'obdlink',
    'kiwi',
    'vgate',
    'icar',
    'carista',
    'veepeak',
    'bluedriver',
    'xtool',
    'launch',
    'autel',
    'odb',
    'scanmate',
  ];
  return patterns.any(n.contains);
}

// ── State machine ─────────────────────────────────────────────────────────────

enum _BtState {
  checkingPermission,
  permissionDenied,
  btOff,
  locationServicesOff, // Android < 12: GPS toggle must be ON for BLE to work
  scanning,
  connecting,
  initFailed,
  connected,
  connectionLost, // BLE link dropped mid-session
}

/// Localization key (title; subtitle = key + '_sub') per connect failure.
const _failureKeys = {
  OBDFailureReason.bleConnectFailed: 'obd_err_ble_failed',
  OBDFailureReason.bleTimeout: 'obd_err_ble_timeout',
  OBDFailureReason.noElmCharacteristic: 'obd_err_not_ble_elm',
  OBDFailureReason.adapterNotResponding: 'obd_err_adapter_silent',
  OBDFailureReason.ecuNotResponding: 'obd_err_ecu_silent',
  OBDFailureReason.noStandardObdData: 'obd_err_no_std_obd',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  _BtState _btState = _BtState.checkingPermission;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectingDevice;
  BluetoothDevice? _connectedDevice;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<OBDConnectionState>? _obdStateSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _obdStateSub = OBDService.instance.connectionStateStream.listen(
      _onObdState,
    );
    _initialize();
  }

  /// Follows the OBD link while this screen is up: a failed connect (also
  /// one started elsewhere) and a mid-session BLE drop.
  void _onObdState(OBDConnectionState state) {
    if (!mounted) return;
    if (state == OBDConnectionState.lost) {
      setState(() {
        _btState = _BtState.connectionLost;
        _connectingDevice = null;
      });
    } else if (state == OBDConnectionState.failed) {
      setState(() {
        _btState = _BtState.initFailed;
        _connectingDevice = null;
      });
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    try {
      // Request permissions FIRST — the adapterState stream fires immediately
      // with the current BT state, so the listener must not call _startScan()
      // before permissions exist or it will get a SecurityException on Android 12+.
      final granted = await _requestPermissions();
      if (!mounted) return;

      if (!granted) {
        setState(() => _btState = _BtState.permissionDenied);
        return;
      }

      // Opened after a mid-session drop: offer RECONNECT, not a rescan.
      final obd = OBDService.instance;
      if (obd.connectionState == OBDConnectionState.lost &&
          obd.lastDevice != null) {
        setState(() => _btState = _BtState.connectionLost);
      } else if (obd.isInitialized && obd.lastDevice != null) {
        // Opened from the connected dashboard to disconnect / switch: show the
        // live adapter as connected instead of rescanning (tapping it in a
        // fresh scan list would reconnect rather than disconnect).
        setState(() {
          _connectedDevice = obd.lastDevice;
          _btState = _BtState.connected;
        });
      }

      // Set up adapter-state watcher only after permissions are confirmed.
      _adapterSub?.cancel();
      _adapterSub = FlutterBluePlus.adapterState.listen((state) {
        if (!mounted) return;
        if (state == BluetoothAdapterState.on) {
          if (_btState != _BtState.scanning &&
              _btState != _BtState.connecting &&
              _btState != _BtState.connected &&
              _btState != _BtState.connectionLost) {
            _startScan();
          }
        } else if (state == BluetoothAdapterState.off) {
          setState(() {
            _btState = _BtState.btOff;
            _scanResults.clear();
          });
        }
      }, onError: (_) {});
      // The listener fires immediately when BT is ON, which calls _startScan().
      // If BT is OFF the listener sets btOff; user must enable BT then retry.
    } on UnsupportedError {
      if (mounted) setState(() => _btState = _BtState.btOff);
    } catch (_) {
      if (mounted) setState(() => _btState = _BtState.btOff);
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Location is required for BLE scanning on ALL Android versions:
      // - Android < 12: OS enforces it directly.
      // - Android 12+: required unless neverForLocation is set in the manifest,
      //   but neverForLocation causes silent empty scans on strict OEMs (Samsung,
      //   Pixel), so we removed it and always require location for compatibility.
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      return statuses.values.every((s) => s.isGranted || s.isLimited);
    }
    return true;
  }

  Future<void> _startScan() async {
    if (!mounted) return;
    try {
      // Location Services (GPS toggle) must be ON for BLE scans to return
      // results on Android — even if the permission is granted.
      if (Platform.isAndroid) {
        final svc = await Permission.location.serviceStatus;
        if (svc == ServiceStatus.disabled) {
          if (mounted) setState(() => _btState = _BtState.locationServicesOff);
          return;
        }
      }

      await FlutterBluePlus.stopScan();
      _scanSub?.cancel();

      setState(() {
        _btState = _BtState.scanning;
        _scanResults.clear();
        _connectingDevice = null;
      });

      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        if (!mounted) return;
        setState(() => _scanResults = results);
      }, onError: (_) {});

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } on UnsupportedError {
      if (mounted) setState(() => _btState = _BtState.btOff);
    } catch (_) {
      if (mounted) setState(() => _btState = _BtState.btOff);
    }
  }

  /// Passes the unconnected [device] straight to the obd2 adapter.
  /// [BluetoothAdapterOBD2.connect] handles BLE connect + ELM327 init.
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {} // not scanning / BT unavailable: connect anyway
    if (!mounted) return;
    setState(() {
      _btState = _BtState.connecting;
      _connectingDevice = device;
    });

    final ok = await OBDService.instance.initialize(device);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _btState = _BtState.connected;
        _connectedDevice = device;
      });
    } else {
      setState(() {
        _btState = _BtState.initFailed;
        _connectingDevice = null;
      });
    }
  }

  /// RETRY after a failed connect: the same adapter again (e.g. once the
  /// ignition is on), unless it can never work — then rescan.
  void _retry() {
    final obd = OBDService.instance;
    final device = obd.lastDevice;
    if (device != null &&
        obd.lastError?.reason != OBDFailureReason.noElmCharacteristic) {
      _connectToDevice(device);
    } else {
      _startScan();
    }
  }

  void _reconnect() {
    final device = OBDService.instance.lastDevice;
    device != null ? _connectToDevice(device) : _startScan();
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(
      ClipboardData(text: OBDService.instance.diagnosticReport()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('diagnostic_log_copied'))),
    );
  }

  Future<void> _shareLog() async {
    try {
      await Share.share(
        OBDService.instance.diagnosticReport(),
        subject: 'MyCar OBD diagnostic log',
      );
    } catch (_) {} // no share sheet available: Copy still works
  }

  Future<void> _disconnect() async {
    await OBDService.instance.disconnect();
    if (!mounted) return;
    setState(() {
      _connectedDevice = null;
      _connectingDevice = null;
    });
    _startScan();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _obdStateSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ── Status helpers ────────────────────────────────────────────────────────

  String _statusMessage(BuildContext ctx) {
    switch (_btState) {
      case _BtState.checkingPermission:
        return ctx.tr('checking_permissions');
      case _BtState.permissionDenied:
        return ctx.tr('bt_permission_required');
      case _BtState.btOff:
        return ctx.tr('please_turn_on_bt');
      case _BtState.locationServicesOff:
        return ctx.tr('location_services_required');
      case _BtState.scanning:
        return ctx.tr('searching_devices');
      case _BtState.connecting:
        final n = _connectingDevice?.platformName;
        final name = (n != null && n.isNotEmpty) ? n : ctx.tr('unknown_device');
        return '${ctx.tr('connecting_to')} $name...';
      case _BtState.initFailed:
        return ctx.tr(_failureKey);
      case _BtState.connectionLost:
        return ctx.tr('obd_connection_lost');
      case _BtState.connected:
        final n = _connectedDevice?.platformName;
        final name = (n != null && n.isNotEmpty)
            ? n
            : _connectedDevice?.remoteId.str ?? ctx.tr('unknown_device');
        return '${ctx.tr('connected_to')} $name';
    }
  }

  String _statusSubtitle(BuildContext ctx) {
    switch (_btState) {
      case _BtState.checkingPermission:
      case _BtState.connecting:
        return ctx.tr('please_wait');
      case _BtState.permissionDenied:
        return ctx.tr('go_to_settings_bt');
      case _BtState.btOff:
        return ctx.tr('enable_bluetooth');
      case _BtState.locationServicesOff:
        return ctx.tr('location_services_required_sub');
      case _BtState.scanning:
        return '${_scanResults.length} ${ctx.tr('devices_found_nearby')}';
      case _BtState.initFailed:
        return ctx.tr('${_failureKey}_sub');
      case _BtState.connectionLost:
        return ctx.tr('obd_connection_lost_sub');
      case _BtState.connected:
        return ctx.tr('tap_scan_vehicle');
    }
  }

  String get _failureKey =>
      _failureKeys[OBDService.instance.lastError?.reason] ?? 'obd_init_failed';

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
          child: Padding(
            padding: EdgeInsets.all(20.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                SizedBox(height: 40.h),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildTitle(context),
                        SizedBox(height: 30.h),
                        _buildStatusCard(context),
                        SizedBox(height: 30.h),
                        if (_btState == _BtState.scanning ||
                            _btState == _BtState.connecting ||
                            _btState == _BtState.initFailed ||
                            _btState == _BtState.connectionLost ||
                            _btState == _BtState.connected)
                          _buildDeviceList(context),
                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
                ),
                _buildActionButton(context),
                SizedBox(height: 12.h),
                _buildBottomText(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          context.tr('app_name'),
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.w900,
            color: AppColors.accentCyan,
            shadows: const [
              Shadow(color: AppColors.accentCyan, blurRadius: 20),
            ],
          ),
        ),
        Container(
          width: 40.w,
          height: 40.h,
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(color: AppColors.accentCyan),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: IconButton(
            icon: Icon(Icons.settings, color: AppColors.accentCyan, size: 20.r),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ),
      ],
    );
  }

  // ── Title ─────────────────────────────────────────────────────────────────

  Widget _buildTitle(BuildContext context) {
    return Column(
      children: [
        Text(
          context.tr('connect_to_vehicle'),
          style: TextStyle(
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          context.tr('select_obd_adapter'),
          style: TextStyle(
            fontSize: 14.sp,
            color: AppColors.accentCyan,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  // ── Status card ───────────────────────────────────────────────────────────

  Widget _buildStatusCard(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(30.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.white.withValues(alpha: 0.05),
            AppColors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        children: [
          _buildStatusIcon(),
          SizedBox(height: 20.h),
          Text(
            _statusMessage(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: _accentColor,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            _statusSubtitle(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
          ),
          ..._buildStatusExtras(context),
        ],
      ),
    );
  }

  /// Adapter details once connected; clone hint and diagnostic-log actions
  /// when connecting failed or the link dropped.
  List<Widget> _buildStatusExtras(BuildContext context) {
    final obd = OBDService.instance;
    if (_btState == _BtState.connected) {
      final info = obd.adapterInfo;
      final parts = [
        if (info?.version != null) info!.version!,
        if (info?.protocol != null) info!.protocol!,
      ];
      if (parts.isEmpty) return const [];
      return [
        SizedBox(height: 10.h),
        Text(
          parts.join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.sp,
            color: AppColors.accentCyan.withValues(alpha: 0.7),
          ),
        ),
      ];
    }
    if (_btState != _BtState.initFailed &&
        _btState != _BtState.connectionLost) {
      return const [];
    }
    final error = obd.lastError;
    return [
      if (_btState == _BtState.initFailed &&
          (error?.suggestsCloneAdapter ?? false)) ...[
        SizedBox(height: 12.h),
        Text(
          context
              .tr('obd_clone_hint')
              .replaceAll('{version}', error!.adapterVersion!),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.sp, color: AppColors.accentOrange),
        ),
      ],
      SizedBox(height: 12.h),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8.w,
        children: [
          TextButton.icon(
            onPressed: _copyLog,
            icon: Icon(Icons.copy, size: 16.r, color: AppColors.accentCyan),
            label: Text(
              context.tr('copy_diagnostic_log'),
              style: TextStyle(fontSize: 13.sp, color: AppColors.accentCyan),
            ),
          ),
          TextButton.icon(
            onPressed: _shareLog,
            icon: Icon(Icons.share, size: 16.r, color: AppColors.accentCyan),
            label: Text(
              context.tr('share_diagnostic_log'),
              style: TextStyle(fontSize: 13.sp, color: AppColors.accentCyan),
            ),
          ),
        ],
      ),
    ];
  }

  Color get _accentColor {
    switch (_btState) {
      case _BtState.connected:
        return AppColors.accentOrange;
      case _BtState.permissionDenied:
      case _BtState.btOff:
      case _BtState.locationServicesOff:
      case _BtState.initFailed:
      case _BtState.connectionLost:
        return Colors.redAccent;
      default:
        return AppColors.accentCyan;
    }
  }

  Widget _buildStatusIcon() {
    switch (_btState) {
      case _BtState.connected:
        return _iconCircle(Icons.bluetooth_connected, AppColors.accentOrange);

      case _BtState.permissionDenied:
        return _iconCircle(Icons.no_encryption, Colors.redAccent);

      case _BtState.btOff:
        return _iconCircle(Icons.bluetooth_disabled, Colors.redAccent);

      case _BtState.locationServicesOff:
        return _iconCircle(Icons.location_off, Colors.redAccent);

      case _BtState.initFailed:
        // The adapter answered — it's the car that stayed silent (an EV that
        // is on but shares no standard OBD-II data gets an EV icon).
        final icon = switch (OBDService.instance.lastError?.reason) {
          OBDFailureReason.ecuNotResponding => Icons.directions_car,
          OBDFailureReason.noStandardObdData => Icons.electric_car,
          _ => Icons.bluetooth_disabled,
        };
        return _iconCircle(icon, Colors.redAccent);

      case _BtState.connectionLost:
        return _iconCircle(Icons.link_off, Colors.redAccent);

      case _BtState.connecting:
        return SizedBox(
          width: 80.w,
          height: 80.h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                color: AppColors.accentCyan,
                strokeWidth: 2,
              ),
              Icon(
                Icons.settings_remote,
                size: 35.r,
                color: AppColors.accentCyan,
              ),
            ],
          ),
        );

      case _BtState.scanning:
      case _BtState.checkingPermission:
        return SizedBox(
          width: 120.w,
          height: 120.h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) {
                    final progress = (_pulseController.value + i * 0.33) % 1.0;
                    return Opacity(
                      opacity: 1.0 - progress,
                      child: Transform.scale(
                        scale: 0.5 + progress,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.accentCyan,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
              Container(
                width: 60.w,
                height: 60.h,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentCyan.withValues(alpha: 0.1),
                ),
                child: Icon(
                  Icons.bluetooth_searching,
                  size: 40.r,
                  color: AppColors.accentCyan,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _iconCircle(IconData icon, Color color) {
    return Container(
      width: 80.w,
      height: 80.h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(icon, size: 40.r, color: color),
    );
  }

  // ── Device list ───────────────────────────────────────────────────────────

  Widget _buildDeviceList(BuildContext context) {
    if (_scanResults.isEmpty && _btState == _BtState.scanning) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Text(
          context.tr('no_devices_found'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14.sp,
            color: AppColors.textLight.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // Connected without a scan in this screen (opened from the dashboard):
    // list the live adapter on its own so it can be tapped to disconnect.
    final connected = _connectedDevice;
    if (connected != null &&
        !_scanResults.any((r) => r.device.remoteId == connected.remoteId)) {
      return _buildDeviceItem(context, connected);
    }

    if (_scanResults.isEmpty) return const SizedBox.shrink();

    // OBD/ELM327 devices float to the top of the list.
    final sorted = [..._scanResults]
      ..sort((a, b) {
        final aObd = _isOBDDevice(a.device.platformName) ? 0 : 1;
        final bObd = _isOBDDevice(b.device.platformName) ? 0 : 1;
        return aObd.compareTo(bObd);
      });

    final obdCount = sorted
        .where((r) => _isOBDDevice(r.device.platformName))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.tr('available_devices'),
              style: TextStyle(
                fontSize: 12.sp,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                color: AppColors.accentCyan.withValues(alpha: 0.8),
              ),
            ),
            if (obdCount > 0) ...[
              SizedBox(width: 10.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  border: Border.all(color: const Color(0xFF00E676)),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  '$obdCount OBD',
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: const Color(0xFF00E676),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 12.h),
        ...sorted.map((r) => _buildDeviceItem(context, r.device, rssi: r.rssi)),
      ],
    );
  }

  Widget _buildDeviceItem(
    BuildContext context,
    BluetoothDevice device, {
    int? rssi,
  }) {
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : context.tr('unknown_device');
    final isObd = _isOBDDevice(device.platformName);
    final isConnecting = _connectingDevice?.remoteId == device.remoteId;
    final isConnected = _connectedDevice?.remoteId == device.remoteId;
    final isActive = isConnecting || isConnected;

    // OBD devices get a green accent; others use the standard cyan.
    final idleAccent = isObd
        ? const Color(0xFF00E676)
        : AppColors.accentCyan.withValues(alpha: 0.2);

    return GestureDetector(
      onTap: (_btState == _BtState.connecting || _btState == _BtState.connected)
          ? (isConnected ? _disconnect : null)
          : () => _connectToDevice(device),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: isConnected
              ? AppColors.accentOrange.withValues(alpha: 0.1)
              : isConnecting
              ? AppColors.accentCyan.withValues(alpha: 0.1)
              : isObd
              ? const Color(0xFF00E676).withValues(alpha: 0.05)
              : AppColors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: isConnected
                ? AppColors.accentOrange
                : isConnecting
                ? AppColors.accentCyan
                : idleAccent,
            width: isActive || isObd ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(15.r),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 46.w,
              height: 46.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isConnected
                      ? [AppColors.accentOrange, AppColors.backgroundDarkBlue]
                      : isObd
                      ? [const Color(0xFF00E676), AppColors.backgroundDarkBlue]
                      : [AppColors.accentCyan, AppColors.backgroundDarkBlue],
                ),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: AppColors.white,
                size: 22.r,
              ),
            ),
            SizedBox(width: 14.w),
            // Name + address + optional OBD badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textLight,
                          ),
                        ),
                      ),
                      if (isObd) ...[
                        SizedBox(width: 6.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF00E676,
                            ).withValues(alpha: 0.15),
                            border: Border.all(color: const Color(0xFF00E676)),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'ELM327',
                            style: TextStyle(
                              fontSize: 9.sp,
                              color: const Color(0xFF00E676),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    device.remoteId.str,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: AppColors.accentCyan.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            // Signal bars (unknown for an adapter connected before this screen)
            if (rssi != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildSignalBars(rssi),
                  SizedBox(height: 4.h),
                  Text(
                    '$rssi dBm',
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: AppColors.textLight.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalBars(int rssi) {
    final strength = rssi >= -60
        ? 3
        : rssi >= -75
        ? 2
        : 1;
    return Row(
      children: List.generate(3, (i) {
        final heights = [8.0, 12.0, 16.0];
        return Container(
          width: 4.w,
          height: heights[i].h,
          margin: EdgeInsets.only(left: 3.w),
          decoration: BoxDecoration(
            color: i < strength
                ? AppColors.accentCyan
                : AppColors.accentCyan.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2.r),
          ),
        );
      }),
    );
  }

  // ── Action button ─────────────────────────────────────────────────────────

  Widget _buildActionButton(BuildContext context) {
    final String label;
    final VoidCallback? onPressed;

    switch (_btState) {
      case _BtState.connected:
        label = context.tr('scan_vehicle');
        onPressed = () => Navigator.pop(context);
        break;
      case _BtState.permissionDenied:
        label = context.tr('open_settings_btn');
        onPressed = openAppSettings;
        break;
      case _BtState.btOff:
      case _BtState.locationServicesOff:
        label = context.tr('btn_retry');
        onPressed = _startScan;
        break;
      case _BtState.initFailed:
        label = context.tr('btn_retry');
        onPressed = _retry;
        break;
      case _BtState.connectionLost:
        label = context.tr('btn_reconnect');
        onPressed = _reconnect;
        break;
      case _BtState.scanning:
        label = context.tr('btn_scanning');
        onPressed = null;
        break;
      case _BtState.connecting:
        label = context.tr('btn_connecting');
        onPressed = null;
        break;
      case _BtState.checkingPermission:
        label = context.tr('btn_please_wait');
        onPressed = null;
        break;
    }

    return Container(
      width: double.infinity,
      height: 56.h,
      decoration: BoxDecoration(
        gradient: onPressed != null
            ? const LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentOrange],
              )
            : null,
        color: onPressed == null
            ? AppColors.white.withValues(alpha: 0.1)
            : null,
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: AppColors.accentCyan.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          disabledBackgroundColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }

  // ── Bottom hint ───────────────────────────────────────────────────────────

  Widget _buildBottomText(BuildContext context) {
    if (_btState == _BtState.scanning) {
      return GestureDetector(
        onTap: _startScan,
        child: Text(
          context.tr('tap_to_rescan'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.sp,
            color: AppColors.accentCyan.withValues(alpha: 0.7),
            decoration: TextDecoration.underline,
            decorationColor: AppColors.accentCyan.withValues(alpha: 0.7),
          ),
        ),
      );
    }
    return Text(
      context.tr('trouble_connecting'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13.sp,
        color: AppColors.textLight.withValues(alpha: 0.5),
      ),
    );
  }
}
