import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    if (OBDService.instance.isInitialized) {
      OBDService.instance.startPolling();
    }
  }

  @override
  void dispose() {
    OBDService.instance.stopPolling();
    super.dispose();
  }

  final List<Map<String, dynamic>> warningLights = [
    {'icon': '⚠️', 'label': 'check_engine', 'active': true},
    {'icon': '🔋', 'label': 'battery', 'active': false},
    {'icon': '🛢️', 'label': 'oil', 'active': false},
    {'icon': '🛞', 'label': 'abs', 'active': true},
    {'icon': '🛡️', 'label': 'airbag', 'active': false},
    {'icon': '🌡️', 'label': 'temp', 'active': false},
    {'icon': '⛽', 'label': 'fuel', 'active': false},
    {'icon': '💨', 'label': 'exhaust', 'active': false},
  ];

  final List<Map<String, dynamic>> recentScans = [
    {
      'date': 'Today, 2:30 PM',
      'result': '2 codes detected',
      'status': 'warning',
      'codes': 2,
    },
    {
      'date': 'Yesterday, 10:15 AM',
      'result': 'No issues found',
      'status': 'success',
      'codes': 0,
    },
    {
      'date': 'Jan 28, 4:20 PM',
      'result': '1 code detected',
      'status': 'warning',
      'codes': 1,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          // Vehicle info
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
                  child: Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 24.r,
                  ),
                ),
                SizedBox(width: 12.w),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Toyota Camry 2020',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE8EAED),
                        ),
                      ),
                      Text(
                        'VIN: 4T1B11HK...8901',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.sp, color: Color(0xFF00D9FF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Connection status
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
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCard() {
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
                  color: Color(0xFFE8EAED),
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00D9FF)],
                ).createShader(bounds),
                child: Text(
                  '78',
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
              _buildIndicator(context.tr('engine'), '98%', const Color(0xFF00E676)),
              _buildIndicator(context.tr('battery'), '85%', const Color(0xFF00D9FF)),
              _buildIndicator(context.tr('brakes'), '72%', const Color(0xFFFFD600)),
            ],
          ),
        ],
      ),
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
                    d.throttlePct != null
                        ? d.throttlePct!.toStringAsFixed(1)
                        : '--',
                    '%',
                    Icons.tune,
                    const Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 10.w),
                  _buildLiveTile(
                    'Fuel',
                    d.fuelLevelPct != null
                        ? d.fuelLevelPct!.toStringAsFixed(1)
                        : '--',
                    '%',
                    Icons.local_gas_station,
                    const Color(0xFFFF6B35),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(child: SizedBox()),
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
        ...recentScans.map((scan) => _buildScanItem(scan)),
      ],
    );
  }

  Widget _buildScanItem(Map<String, dynamic> scan) {
    final isWarning = scan['status'] == 'warning';
    final statusColor = isWarning
        ? const Color(0xFFFF6B35)
        : const Color(0xFF00E676);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(15.r),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(15.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scan['date'],
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Color(0xFF00D9FF),
                  ),
                ),
                SizedBox(height: 5.h),
                Text(
                  scan['result'],
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Color(0xFFE8EAED),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              border: Border.all(color: statusColor),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Text(
              isWarning ? '${scan['codes']} Codes' : 'OK',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
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
