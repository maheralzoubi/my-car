import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';

class ParentModeScreen extends StatefulWidget {
  const ParentModeScreen({super.key});

  @override
  State<ParentModeScreen> createState() => _ParentModeScreenState();
}

class _ParentModeScreenState extends State<ParentModeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool locationTracking = true;
  bool speedAlerts = true;
  bool geoFence = false;
  int speedLimit = 100;

  // Simulated data
  int currentSpeed = 120;
  String location = 'Downtown';
  String driveTime = '2h 15m';
  String distance = '145km';
  String avgSpeed = '95km/h';

  static const Color _speedAlertRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundDark,
              AppColors.backgroundDarkBlue,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMapCard(),
                      const SizedBox(height: 25),
                      _buildStatsGrid(),
                      const SizedBox(height: 30),
                      _buildSettingsSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Parent Mode',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accentCyan.withValues(alpha: 0.1),
            AppColors.accentOrange.withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.15),
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 45,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4A90E2),
                    Color(0xFF7FB3D5),
                    Color(0xFFA9CCE3),
                  ],
                ),
              ),
            ),
            CustomPaint(
              size: const Size(double.infinity, double.infinity),
              painter: _MapGridPainter(),
            ),
            _buildCarMarker(),
            _buildSpeedBadge(),
            if (currentSpeed > speedLimit) _buildAlertBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildCarMarker() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + (_pulseController.value * 1.0),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.accentCyan
                          .withValues(alpha: 1 - _pulseController.value),
                      width: 3,
                    ),
                  ),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D9FF), Color(0xFF0066FF)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: AppColors.white,
                  size: 30,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpeedBadge() {
    return Positioned(
      top: 20,
      right: 20,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: _speedAlertRed,
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: _speedAlertRed.withValues(alpha: 0.4),
              blurRadius: 25,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currentSpeed.toString(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _speedAlertRed,
              ),
            ),
            const Text(
              'KM/H',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF666666),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertBadge() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _speedAlertRed,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: _speedAlertRed.withValues(alpha: 0.4),
              blurRadius: 25,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, color: AppColors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Speed Alert!',
              style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 15,
      mainAxisSpacing: 15,
      childAspectRatio: 1.3,
      children: [
        _buildStatCard('📍', 'Current Location', location),
        _buildStatCard('⏱️', 'Drive Time', driveTime),
        _buildStatCard('🛣️', 'Distance', distance),
        _buildStatCard('⚡', 'Avg Speed', avgSpeed),
      ],
    );
  }

  Widget _buildStatCard(String icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.accentCyan,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Tracking Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        _buildSettingCard(
          'Location Tracking',
          'Real-time GPS monitoring',
          locationTracking,
          (value) => setState(() => locationTracking = value),
        ),
        _buildSpeedLimitCard(),
        _buildSettingCard(
          'Speed Alerts',
          'Notify when limit is exceeded',
          speedAlerts,
          (value) => setState(() => speedAlerts = value),
        ),
        _buildSettingCard(
          'Geo-Fence',
          'Alert when leaving safe zone',
          geoFence,
          (value) => setState(() => geoFence = value),
        ),
      ],
    );
  }

  Widget _buildSettingCard(
    String title,
    String description,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          _buildToggleSwitch(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildSpeedLimitCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Speed Limit',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Alert when exceeded',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 80,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.accentCyan.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: AppColors.accentCyan,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '100',
                hintStyle: TextStyle(color: AppColors.accentCyan),
              ),
              onChanged: (value) {
                setState(() {
                  speedLimit = int.tryParse(value) ?? 100;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSwitch(bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 60,
        height: 32,
        decoration: BoxDecoration(
          gradient: value
              ? const LinearGradient(
                  colors: [_successGreen, _successGreenDark],
                )
              : null,
          color: value ? null : AppColors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    const spacing = 40.0;

    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
