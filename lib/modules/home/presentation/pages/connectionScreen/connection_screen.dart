import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({Key? key}) : super(key: key);

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool isScanning = true;
  String? selectedDevice;

  final List<Map<String, dynamic>> devices = [
    {
      'name': 'OBD-II ELM327',
      'type': 'Bluetooth',
      'status': 'Nearby',
      'signal': 3,
      'icon': Icons.bluetooth,
    },
    {
      'name': 'VGATE iCar Pro',
      'type': 'WiFi',
      'status': 'Available',
      'signal': 2,
      'icon': Icons.wifi,
    },
  ];

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
            colors: [AppColors.backgroundDark, AppColors.backgroundDarkBlue],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 40),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildTitle(),
                        const SizedBox(height: 30),
                        _buildStatusCard(),
                        const SizedBox(height: 30),
                        _buildDeviceList(),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // Fixed bottom: Scan vehicle button + help text
                _buildScanButton(),
                const SizedBox(height: 12),
                _buildHelpText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'CARDIAG',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.accentCyan,
            shadows: [Shadow(color: AppColors.accentCyan, blurRadius: 20)],
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(color: AppColors.accentCyan),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.settings,
              color: AppColors.accentCyan,
              size: 20,
            ),
            onPressed: () {
              // Navigate to settings
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Text(
          'Connect to Vehicle',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'SELECT OBD-II ADAPTER',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.accentCyan,
            fontWeight: FontWeight.w300,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.white.withValues(alpha: 0.05),
            AppColors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulse rings
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
                // Bluetooth icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentCyan.withValues(alpha: 0.1),
                  ),
                  child: const Icon(
                    Icons.bluetooth_searching,
                    size: 40,
                    color: AppColors.accentCyan,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Searching for devices...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.accentCyan,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Make sure Bluetooth is enabled',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: devices.asMap().entries.map((entry) {
        final index = entry.key;
        final device = entry.value;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 500 + (index * 100)),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(50 * (1 - value), 0),
                child: child,
              ),
            );
          },
          child: _buildDeviceItem(device),
        );
      }).toList(),
    );
  }

  Widget _buildDeviceItem(Map<String, dynamic> device) {
    final isSelected = selectedDevice == device['name'];

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedDevice = device['name'];
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentCyan.withValues(alpha: 0.1)
              : AppColors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: isSelected
                ? AppColors.accentCyan
                : AppColors.accentCyan.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            // Device icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.backgroundDarkBlue],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(device['icon'], color: AppColors.white, size: 24),
            ),
            const SizedBox(width: 15),
            // Device info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device['name'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${device['type']} • ${device['status']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.accentCyan.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Signal strength
            _buildSignalStrength(device['signal']),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalStrength(int strength) {
    return Row(
      children: List.generate(3, (index) {
        final isActive = index < strength;
        final heights = [8.0, 12.0, 16.0];

        return Container(
          width: 4,
          height: heights[index],
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.accentCyan
                : AppColors.accentCyan.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildScanButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accentCyan, AppColors.accentOrange],
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentCyan.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.dashboard);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: const Text(
          'SCAN VEHICLE',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildHelpText() {
    return Text(
      'Having trouble connecting? Check our troubleshooting guide',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        color: AppColors.textLight.withValues(alpha: 0.5),
      ),
    );
  }
}
