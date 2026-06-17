import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
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

  List<Map<String, dynamic>> warningLights = [
    {'icon': '⚠️', 'label': 'check_engine', 'active': false},
    {'icon': '🔋', 'label': 'battery', 'active': false},
    {'icon': '🛢️', 'label': 'oil', 'active': false},
    {'icon': '🛞', 'label': 'abs', 'active': false},
    {'icon': '🛡️', 'label': 'airbag', 'active': false},
    {'icon': '🌡️', 'label': 'temp', 'active': false},
    {'icon': '⛽', 'label': 'fuel', 'active': false},
    {'icon': '💨', 'label': 'exhaust', 'active': false},
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
    }
  }

  Future<void> _fetchDtcsAndUpdateLights() async {
    if (!OBDService.instance.isInitialized) return;
    if (!mounted) return;
    setState(() => _scanningDtcs = true);

    final codes = await OBDService.instance.getDtcs();
    if (!mounted) return;

    setState(() {
      _scanningDtcs = false;
      warningLights = [
        {'icon': '⚠️', 'label': 'check_engine', 'active': codes.any((c) => c.startsWith('P'))},
        {'icon': '🔋', 'label': 'battery',      'active': codes.any((c) => _matchPrefix(c, ['P056', 'P057', 'P115']))},
        {'icon': '🛢️', 'label': 'oil',          'active': codes.any((c) => _matchPrefix(c, ['P052', 'P053']))},
        {'icon': '🛞', 'label': 'abs',           'active': codes.any((c) => c.startsWith('C'))},
        {'icon': '🛡️', 'label': 'airbag',       'active': codes.any((c) => c.startsWith('B'))},
        {'icon': '🌡️', 'label': 'temp',          'active': codes.any((c) => _matchPrefix(c, ['P011', 'P012', 'P025']))},
        {'icon': '⛽', 'label': 'fuel',           'active': codes.any((c) => _matchPrefix(c, ['P008', 'P009', 'P046']))},
        {'icon': '💨', 'label': 'exhaust',        'active': codes.any((c) => _matchPrefix(c, ['P042', 'P043', 'P044', 'P045']))},
      ];
    });
  }

  bool _matchPrefix(String code, List<String> prefixes) =>
      prefixes.any((p) => code.startsWith(p));

  @override
  void dispose() {
    OBDService.instance.stopPolling();
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

  Widget _buildHealthCard() {
    return StreamBuilder<OBDLiveData>(
      stream: OBDService.instance.liveDataStream,
      initialData: OBDService.instance.currentData,
      builder: (context, snapshot) {
        final d = snapshot.data ?? const OBDLiveData();
        final loadStr = d.engineLoad != null ? '${d.engineLoad!.toStringAsFixed(0)}%' : '--';
        final rpmStr = d.rpm != null ? d.rpm!.toStringAsFixed(0) : '--';
        final coolantStr = d.coolantTempC != null ? '${d.coolantTempC!.toStringAsFixed(0)}°C' : '--';
        return Container(
          padding: EdgeInsets.all(25.r),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('vehicle_health'),
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE8EAED),
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00E676), Color(0xFF00D9FF)],
                    ).createShader(bounds),
                    child: Text(
                      loadStr,
                      style: TextStyle(
                        fontSize: 36.sp,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Row(
                children: [
                  _buildIndicator('Engine Load', loadStr, const Color(0xFF00E676)),
                  _buildIndicator('RPM', rpmStr, const Color(0xFF00D9FF)),
                  _buildIndicator('Coolant', coolantStr, const Color(0xFFFFD600)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIndicator(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(15.r),
        margin: EdgeInsets.only(right: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          children: [
            Container(
              width: 40.w,
              height: 40.h,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: color, size: 20.r),
            ),
            SizedBox(height: 8.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                color: const Color(0xFFE8EAED).withValues(alpha: 0.7),
              ),
            ),
            SizedBox(height: 5.h),
            Text(
              value,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: color,
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
                    d.speedKmh != null ? '${d.speedKmh}' : '--',
                    'km/h',
                    Icons.speed,
                    const Color(0xFF00E676),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    'Coolant',
                    d.coolantTempC != null ? '${d.coolantTempC}' : '--',
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
              light['icon'],
              light['label'],
              light['active'],
            );
          },
        ),
      ],
    );
  }

  Widget _buildWarningLight(String icon, String label, bool active) {
    return GestureDetector(
      onTap: () {
        // Navigate to code details
      },
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
