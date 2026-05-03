import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';

enum _BtState {
  checkingPermission,
  permissionDenied,
  btOff,
  scanning,
  connecting,
  connected,
}

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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _initialize();
  }

  Future<void> _initialize() async {
    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((adapterState) {
      if (!mounted) return;
      if (adapterState == BluetoothAdapterState.on) {
        if (_btState != _BtState.scanning &&
            _btState != _BtState.connecting &&
            _btState != _BtState.connected) {
          _startScan();
        }
      } else if (adapterState == BluetoothAdapterState.off) {
        setState(() {
          _btState = _BtState.btOff;
          _scanResults.clear();
        });
      }
    });

    final granted = await _requestPermissions();
    if (!mounted) return;

    if (!granted) {
      setState(() => _btState = _BtState.permissionDenied);
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (!mounted) return;

    if (adapterState != BluetoothAdapterState.on) {
      setState(() => _btState = _BtState.btOff);
      return;
    }

    _startScan();
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
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
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    setState(() {
      _btState = _BtState.scanning;
      _scanResults.clear();
      _connectingDevice = null;
    });

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() => _scanResults = results);
    }, onError: (_) {});

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();

    setState(() {
      _btState = _BtState.connecting;
      _connectingDevice = device;
    });

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _btState = _BtState.connected;
        _connectedDevice = device;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _btState = _BtState.scanning;
        _connectingDevice = null;
      });
      _startScan();
    }
  }

  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
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
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ─── Computed status strings (use context.tr in build phase) ─────────────

  String _statusMessage(BuildContext ctx) {
    switch (_btState) {
      case _BtState.checkingPermission:
        return ctx.tr('checking_permissions');
      case _BtState.permissionDenied:
        return ctx.tr('bt_permission_required');
      case _BtState.btOff:
        return ctx.tr('please_turn_on_bt');
      case _BtState.scanning:
        return ctx.tr('searching_devices');
      case _BtState.connecting:
        final n = _connectingDevice?.platformName;
        final name =
            (n != null && n.isNotEmpty) ? n : ctx.tr('unknown_device');
        return '${ctx.tr('connecting_to')} $name...';
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
      case _BtState.scanning:
        return '${_scanResults.length} ${ctx.tr('devices_found_nearby')}';
      case _BtState.connected:
        return ctx.tr('tap_scan_vehicle');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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

  // ─── Header ───────────────────────────────────────────────────────────────

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
            shadows: const [Shadow(color: AppColors.accentCyan, blurRadius: 20)],
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
            icon: Icon(
              Icons.settings,
              color: AppColors.accentCyan,
              size: 20.r,
            ),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
        ),
      ],
    );
  }

  // ─── Title ────────────────────────────────────────────────────────────────

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

  // ─── Status card ──────────────────────────────────────────────────────────

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
        ],
      ),
    );
  }

  Color get _accentColor {
    switch (_btState) {
      case _BtState.connected:
        return AppColors.accentOrange;
      case _BtState.permissionDenied:
      case _BtState.btOff:
        return Colors.redAccent;
      default:
        return AppColors.accentCyan;
    }
  }

  Widget _buildStatusIcon() {
    if (_btState == _BtState.connected) {
      return Container(
        width: 80.w,
        height: 80.h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accentOrange.withValues(alpha: 0.1),
          border: Border.all(color: AppColors.accentOrange, width: 2),
        ),
        child: Icon(
          Icons.bluetooth_connected,
          size: 40.r,
          color: AppColors.accentOrange,
        ),
      );
    }

    if (_btState == _BtState.permissionDenied || _btState == _BtState.btOff) {
      return Container(
        width: 80.w,
        height: 80.h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.redAccent.withValues(alpha: 0.1),
          border: Border.all(color: Colors.redAccent, width: 2),
        ),
        child: Icon(
          _btState == _BtState.btOff
              ? Icons.bluetooth_disabled
              : Icons.no_encryption,
          size: 40.r,
          color: Colors.redAccent,
        ),
      );
    }

    if (_btState == _BtState.connecting) {
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
            Icon(Icons.bluetooth, size: 35.r, color: AppColors.accentCyan),
          ],
        ),
      );
    }

    return SizedBox(
      width: 120.w,
      height: 120.h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final delay = index * 0.33;
                final progress = (_pulseController.value + delay) % 1.0;
                return Opacity(
                  opacity: 1.0 - progress,
                  child: Transform.scale(
                    scale: 0.5 + (progress * 1.0),
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

  // ─── Device list ──────────────────────────────────────────────────────────

  Widget _buildDeviceList(BuildContext context) {
    if (_scanResults.isEmpty) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        SizedBox(height: 12.h),
        ..._scanResults.map((r) => _buildDeviceItem(context, r)),
      ],
    );
  }

  Widget _buildDeviceItem(BuildContext context, ScanResult result) {
    final device = result.device;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : context.tr('unknown_device');
    final isConnecting = _connectingDevice?.remoteId == device.remoteId;
    final isConnected = _connectedDevice?.remoteId == device.remoteId;
    final isActive = isConnecting || isConnected;

    return GestureDetector(
      onTap:
          (_btState == _BtState.connecting || _btState == _BtState.connected)
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
              : AppColors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: isConnected
                ? AppColors.accentOrange
                : isConnecting
                ? AppColors.accentCyan
                : AppColors.accentCyan.withValues(alpha: 0.2),
            width: isActive ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(15.r),
        ),
        child: Row(
          children: [
            Container(
              width: 46.w,
              height: 46.h,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isConnected
                      ? [AppColors.accentOrange, AppColors.backgroundDarkBlue]
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildSignalBars(result.rssi),
                SizedBox(height: 4.h),
                Text(
                  '${result.rssi} dBm',
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
    final strength = rssi >= -60 ? 3 : rssi >= -75 ? 2 : 1;
    return Row(
      children: List.generate(3, (index) {
        final isActive = index < strength;
        final heights = [8.0, 12.0, 16.0];
        return Container(
          width: 4.w,
          height: heights[index].h,
          margin: EdgeInsets.only(left: 3.w),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accentCyan
                : AppColors.accentCyan.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2.r),
          ),
        );
      }),
    );
  }

  // ─── Action button ────────────────────────────────────────────────────────

  Widget _buildActionButton(BuildContext context) {
    final String label;
    final VoidCallback? onPressed;

    switch (_btState) {
      case _BtState.connected:
        label = context.tr('scan_vehicle');
        onPressed = () => Navigator.pushNamed(context, AppRoutes.dashboard);
        break;
      case _BtState.permissionDenied:
        label = context.tr('open_settings_btn');
        onPressed = openAppSettings;
        break;
      case _BtState.btOff:
        label = context.tr('btn_retry');
        onPressed = _initialize;
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

  // ─── Bottom hint text ─────────────────────────────────────────────────────

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
