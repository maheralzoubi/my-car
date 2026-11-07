import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/core.dart';
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

class _ConnectionScreenState extends State<ConnectionScreen> {
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

  bool get _showsDeviceList =>
      _btState == _BtState.scanning ||
      _btState == _BtState.connecting ||
      _btState == _BtState.initFailed ||
      _btState == _BtState.connectionLost ||
      _btState == _BtState.connected;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: context.tr('connect_to_vehicle'),
              subtitle: context.tr('select_obd_adapter'),
              actions: [
                HeaderAction(
                  icon: Icons.settings_outlined,
                  tooltip: context.tr('settings'),
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.settings),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  AppSizes.space8.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusCard(context),
                    if (_showsDeviceList) ...[
                      SizedBox(height: AppSizes.space24.h),
                      _buildDeviceList(context),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSizes.space20.w,
                AppSizes.space8.h,
                AppSizes.space20.w,
                AppSizes.space12.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildActionButton(context),
                  SizedBox(height: AppSizes.space8.h),
                  _buildBottomHint(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status card ───────────────────────────────────────────────────────────

  /// Status tone: blue while working, green once connected, amber when the
  /// phone needs a setting changed, red when the link failed or dropped.
  StatusLevel get _level {
    switch (_btState) {
      case _BtState.connected:
        return StatusLevel.ok;
      case _BtState.permissionDenied:
      case _BtState.btOff:
      case _BtState.locationServicesOff:
        return StatusLevel.warning;
      case _BtState.initFailed:
      case _BtState.connectionLost:
        return StatusLevel.critical;
      case _BtState.checkingPermission:
      case _BtState.scanning:
      case _BtState.connecting:
        return StatusLevel.info;
    }
  }

  IconData get _statusIcon {
    switch (_btState) {
      case _BtState.connected:
        return Icons.bluetooth_connected_rounded;
      case _BtState.permissionDenied:
        return Icons.lock_outline_rounded;
      case _BtState.btOff:
        return Icons.bluetooth_disabled_rounded;
      case _BtState.locationServicesOff:
        return Icons.location_off_outlined;
      case _BtState.initFailed:
        // The adapter answered — it's the car that stayed silent (an EV that
        // is on but shares no standard OBD-II data gets an EV icon).
        return switch (OBDService.instance.lastError?.reason) {
          OBDFailureReason.ecuNotResponding => Icons.directions_car,
          OBDFailureReason.noStandardObdData => Icons.electric_car,
          _ => Icons.bluetooth_disabled_rounded,
        };
      case _BtState.connectionLost:
        return Icons.link_off_rounded;
      case _BtState.connecting:
        return Icons.settings_remote_outlined;
      case _BtState.scanning:
      case _BtState.checkingPermission:
        return Icons.bluetooth_searching_rounded;
    }
  }

  bool get _isBusy =>
      _btState == _BtState.checkingPermission ||
      _btState == _BtState.scanning ||
      _btState == _BtState.connecting;

  Widget _buildStatusCard(BuildContext context) {
    final p = context.colors;
    return AppCard(
      padding: EdgeInsets.all(AppSizes.space20.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBox(_statusIcon, color: _level.colorOf(context), size: 48),
              SizedBox(width: AppSizes.space16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusMessage(context),
                      style: AppTextStyles.title.copyWith(color: p.text),
                    ),
                    SizedBox(height: AppSizes.space4.h),
                    Text(
                      _statusSubtitle(context),
                      style: AppTextStyles.body.copyWith(color: p.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isBusy) ...[
            SizedBox(height: AppSizes.space16.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              child: LinearProgressIndicator(
                minHeight: 4.h,
                color: p.primary,
                backgroundColor: p.track,
              ),
            ),
          ],
          ..._buildStatusExtras(context),
        ],
      ),
    );
  }

  /// Adapter details once connected; clone hint and diagnostic-log actions
  /// when connecting failed or the link dropped.
  List<Widget> _buildStatusExtras(BuildContext context) {
    final p = context.colors;
    final obd = OBDService.instance;
    if (_btState == _BtState.connected) {
      final info = obd.adapterInfo;
      final parts = [
        if (info?.version != null) info!.version!,
        if (info?.protocol != null) info!.protocol!,
      ];
      if (parts.isEmpty) return const [];
      return [
        SizedBox(height: AppSizes.space16.h),
        Divider(height: 1, thickness: 1, color: p.border),
        SizedBox(height: AppSizes.space12.h),
        Row(
          children: [
            Icon(Icons.memory_rounded, size: 18.r, color: p.muted),
            SizedBox(width: AppSizes.space8.w),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: AppTextStyles.numeric(
                  AppTextStyles.label,
                ).copyWith(fontWeight: FontWeight.w400, color: p.text2),
              ),
            ),
          ],
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
        SizedBox(height: AppSizes.space16.h),
        Container(
          padding: EdgeInsets.all(AppSizes.space12.r),
          decoration: BoxDecoration(
            color: p.warnSoft,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 18.r, color: p.warn),
              SizedBox(width: AppSizes.space8.w),
              Expanded(
                child: Text(
                  context
                      .tr('obd_clone_hint')
                      .replaceAll('{version}', error!.adapterVersion!),
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      SizedBox(height: AppSizes.space16.h),
      Wrap(
        spacing: AppSizes.space8.w,
        runSpacing: AppSizes.space8.h,
        children: [
          AppButton.secondary(
            label: context.tr('copy_diagnostic_log'),
            icon: Icons.copy_rounded,
            onPressed: _copyLog,
            compact: true,
            expand: false,
          ),
          AppButton.secondary(
            label: context.tr('share_diagnostic_log'),
            icon: Icons.ios_share_rounded,
            onPressed: _shareLog,
            compact: true,
            expand: false,
          ),
        ],
      ),
    ];
  }

  // ── Device list ───────────────────────────────────────────────────────────

  Widget _buildDeviceList(BuildContext context) {
    final p = context.colors;
    if (_scanResults.isEmpty && _btState == _BtState.scanning) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.space8.h),
        child: Text(
          context.tr('no_devices_found'),
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: p.text2),
        ),
      );
    }

    // Connected without a scan in this screen (opened from the dashboard):
    // list the live adapter on its own so it can be tapped to disconnect.
    final connected = _connectedDevice;
    if (connected != null &&
        !_scanResults.any((r) => r.device.remoteId == connected.remoteId)) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: _buildDeviceItem(context, connected),
      );
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('available_devices'),
          trailing: obdCount > 0
              ? StatusBadge(label: '$obdCount OBD', level: StatusLevel.info)
              : null,
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: AppSizes.space16.w,
                    endIndent: AppSizes.space16.w,
                    color: p.border,
                  ),
                _buildDeviceItem(
                  context,
                  sorted[i].device,
                  rssi: sorted[i].rssi,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceItem(
    BuildContext context,
    BluetoothDevice device, {
    int? rssi,
  }) {
    final p = context.colors;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : context.tr('unknown_device');
    final isObd = _isOBDDevice(device.platformName);
    final isConnecting = _connectingDevice?.remoteId == device.remoteId;
    final isConnected = _connectedDevice?.remoteId == device.remoteId;

    final Widget leading = isConnected
        ? IconBox(Icons.bluetooth_connected_rounded, color: p.ok)
        : isObd || isConnecting
        ? const IconBox(Icons.bluetooth_rounded)
        : const IconBox.neutral(Icons.bluetooth_rounded, size: 40);

    return InkWell(
      onTap: (_btState == _BtState.connecting || _btState == _BtState.connected)
          ? (isConnected ? _disconnect : null)
          : () => _connectToDevice(device),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 64.h),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSizes.space16.w,
            vertical: AppSizes.space12.h,
          ),
          child: Row(
            children: [
              leading,
              SizedBox(width: AppSizes.space12.w),
              // Name + address
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      device.remoteId.str,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.numeric(
                        AppTextStyles.caption,
                      ).copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSizes.space8.w),
              // Signal (unknown for an adapter connected before this screen)
              if (rssi != null) ...[
                _buildSignal(context, rssi),
                SizedBox(width: AppSizes.space8.w),
              ],
              if (isObd)
                const StatusBadge(label: 'OBD', level: StatusLevel.info),
              // The connected adapter stays the "connecting" one after
              // success, so check connected first.
              if (isConnected) ...[
                SizedBox(width: AppSizes.space8.w),
                Icon(Icons.check_circle_rounded, size: 20.r, color: p.ok),
              ] else if (isConnecting) ...[
                SizedBox(width: AppSizes.space8.w),
                SizedBox.square(
                  dimension: 18.r,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: p.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Three bars over the dBm reading.
  Widget _buildSignal(BuildContext context, int rssi) {
    final p = context.colors;
    final strength = rssi >= -60
        ? 3
        : rssi >= -75
        ? 2
        : 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            const heights = [6.0, 10.0, 14.0];
            return Container(
              width: 4.w,
              height: heights[i].h,
              margin: EdgeInsetsDirectional.only(start: 2.w),
              decoration: BoxDecoration(
                color: i < strength ? p.primary : p.track,
                borderRadius: BorderRadius.circular(2.r),
              ),
            );
          }),
        ),
        SizedBox(height: 2.h),
        Text(
          '$rssi dBm',
          style: AppTextStyles.numeric(
            AppTextStyles.caption,
          ).copyWith(color: p.muted),
        ),
      ],
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

    return AppButton(label: label, onPressed: onPressed);
  }

  // ── Bottom hint ───────────────────────────────────────────────────────────

  Widget _buildBottomHint(BuildContext context) {
    if (_btState == _BtState.scanning) {
      return Center(
        child: AppButton.ghost(
          label: context.tr('tap_to_rescan'),
          icon: Icons.refresh_rounded,
          onPressed: _startScan,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSizes.space8.h),
      child: Text(
        context.tr('trouble_connecting'),
        textAlign: TextAlign.center,
        style: AppTextStyles.label.copyWith(
          fontWeight: FontWeight.w400,
          color: context.colors.text2,
        ),
      ),
    );
  }
}
