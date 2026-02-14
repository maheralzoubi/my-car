import 'package:flutter/material.dart';

import '../../../../../core/constants/app_routes.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Map<String, dynamic>> warningLights = [
    {'icon': '⚠️', 'label': 'Check Engine', 'active': true},
    {'icon': '🔋', 'label': 'Battery', 'active': false},
    {'icon': '🛢️', 'label': 'Oil', 'active': false},
    {'icon': '🛞', 'label': 'ABS', 'active': true},
    {'icon': '🛡️', 'label': 'Airbag', 'active': false},
    {'icon': '🌡️', 'label': 'Temp', 'active': false},
    {'icon': '⛽', 'label': 'Fuel', 'active': false},
    {'icon': '💨', 'label': 'Exhaust', 'active': false},
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
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHealthCard(),
                      const SizedBox(height: 30),
                      _buildWarningLightsSection(),
                      const SizedBox(height: 30),
                      _buildQuickScanButton(),
                      const SizedBox(height: 20),
                      _buildVideoTutorialsCard(),
                      const SizedBox(height: 30),
                      _buildRecentScansSection(),
                      const SizedBox(height: 80),
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
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          // Vehicle info
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toyota Camry 2020',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE8EAED),
                      ),
                    ),
                    Text(
                      'VIN: 4T1B11HK...8901',
                      style: TextStyle(fontSize: 12, color: Color(0xFF00D9FF)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Connection status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.1),
              border: Border.all(color: const Color(0xFF00E676)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 12,
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
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.05),
            Colors.white.withOpacity(0.02),
          ],
        ),
        border: Border.all(color: const Color(0xFF00D9FF).withOpacity(0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vehicle Health',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE8EAED),
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00E676), Color(0xFF00D9FF)],
                ).createShader(bounds),
                child: const Text(
                  '78',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildIndicator('Engine', '98%', const Color(0xFF00E676)),
              _buildIndicator('Battery', '85%', const Color(0xFF00D9FF)),
              _buildIndicator('Brakes', '72%', const Color(0xFFFFD600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFFE8EAED).withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
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
            const Icon(Icons.warning_amber, color: Color(0xFFFF6B35), size: 20),
            const SizedBox(width: 10),
            const Text(
              'Warning Lights',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFFE8EAED),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
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
              ? const Color(0xFFFF6B35).withOpacity(0.1)
              : Colors.white.withOpacity(0.03),
          border: Border.all(
            color: active
                ? const Color(0xFFFF6B35)
                : Colors.white.withOpacity(0.1),
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              icon,
              style: TextStyle(
                fontSize: 28,
                color: active ? null : Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: active
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFFE8EAED).withOpacity(0.5),
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D9FF).withOpacity(0.3),
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
                  const Text(
                    'Quick Diagnostic Scan',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Scan your vehicle for issues',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 30,
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          border: Border.all(color: const Color(0xFF00D9FF).withOpacity(0.3)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF00D9FF).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_library,
                color: Color(0xFF00D9FF),
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Video Tutorials',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE8EAED),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Watch repair guides by code',
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFFE8EAED).withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF00D9FF),
              size: 16,
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
                const Icon(Icons.history, color: Color(0xFF00D9FF), size: 20),
                const SizedBox(width: 10),
                const Text(
                  'Recent Scans',
                  style: TextStyle(
                    fontSize: 18,
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
              child: const Text(
                'View All',
                style: TextStyle(color: Color(0xFF00D9FF), fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ...recentScans.map((scan) => _buildScanItem(scan)).toList(),
      ],
    );
  }

  Widget _buildScanItem(Map<String, dynamic> scan) {
    final isWarning = scan['status'] == 'warning';
    final statusColor = isWarning
        ? const Color(0xFFFF6B35)
        : const Color(0xFF00E676);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scan['date'],
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00D9FF),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  scan['result'],
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFE8EAED),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              border: Border.all(color: statusColor),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isWarning ? '${scan['codes']} Codes' : 'OK',
              style: TextStyle(
                fontSize: 11,
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
        color: const Color(0xFF0D0D0D).withOpacity(0.95),
        border: Border(
          top: BorderSide(color: const Color(0xFF00D9FF).withOpacity(0.2)),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 'Home', 0),
              _buildNavItem(Icons.search, 'Scan', 1),
              _buildNavItem(Icons.vpn_key, 'Smart Key', 2),
              _buildNavItem(Icons.history, 'History', 3),
              _buildNavItem(Icons.settings, 'Settings', 4),
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
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00D9FF).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF00D9FF)
                  : const Color(0xFFE8EAED).withOpacity(0.5),
              size: 24,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? const Color(0xFF00D9FF)
                    : const Color(0xFFE8EAED).withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
