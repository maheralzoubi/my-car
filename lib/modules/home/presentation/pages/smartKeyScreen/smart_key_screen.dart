import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';

class SmartKeyScreen extends StatefulWidget {
  const SmartKeyScreen({super.key});

  @override
  State<SmartKeyScreen> createState() => _SmartKeyScreenState();
}

class _SmartKeyScreenState extends State<SmartKeyScreen>
    with SingleTickerProviderStateMixin {
  bool isLocked = true;
  bool engineRunning = false;
  late AnimationController _pulseController;

  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);
  static const Color _orangeDark = Color(0xFFFF5722);
  static const Color _blueDark = Color(0xFF0066FF);

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
                    children: [
                      _buildCarImage(),
                      const SizedBox(height: 40),
                      _buildLockButton(),
                      const SizedBox(height: 20),
                      _buildUnlockButton(),
                      const SizedBox(height: 20),
                      _buildEngineButton(),
                      const SizedBox(height: 40),
                      _buildQuickActions(),
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
            'Smart Key',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _successGreen.withValues(alpha: 0.1),
              border: Border.all(color: _successGreen),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Connected',
                  style: TextStyle(
                    fontSize: 12,
                    color: _successGreen,
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

  Widget _buildCarImage() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: (isLocked ? AppColors.accentOrange : _successGreen)
                    .withValues(alpha: 0.3 + (_pulseController.value * 0.2)),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    Icons.directions_car,
                    size: 120,
                    color: AppColors.accentCyan.withValues(alpha: 0.5),
                  ),
                ),
                if (isLocked)
                  Center(
                    child: Icon(
                      Icons.lock,
                      size: 60,
                      color: AppColors.accentOrange,
                    ),
                  ),
                if (engineRunning)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _successGreen.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _successGreen,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.power_settings_new,
                        color: _successGreen,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLockButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          isLocked = true;
          engineRunning = false;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          gradient: isLocked
              ? const LinearGradient(
                  colors: [AppColors.accentOrange, _orangeDark],
                )
              : null,
          color: isLocked ? null : AppColors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: isLocked
                ? AppColors.transparent
                : AppColors.accentCyan.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isLocked
              ? [
                  BoxShadow(
                    color: AppColors.accentOrange.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock,
              color: isLocked ? AppColors.white : AppColors.textLight,
              size: 32,
            ),
            const SizedBox(width: 15),
            Text(
              'Lock',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isLocked ? AppColors.white : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockButton() {
    return GestureDetector(
      onTap: () {
        setState(() => isLocked = false);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          gradient: !isLocked
              ? const LinearGradient(
                  colors: [_successGreen, _successGreenDark],
                )
              : null,
          color: !isLocked ? null : AppColors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: !isLocked
                ? AppColors.transparent
                : AppColors.accentCyan.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: !isLocked
              ? [
                  BoxShadow(
                    color: _successGreen.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_open,
              color: !isLocked ? AppColors.white : AppColors.textLight,
              size: 32,
            ),
            const SizedBox(width: 15),
            Text(
              'Unlock',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: !isLocked ? AppColors.white : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineButton() {
    return GestureDetector(
      onTap: () {
        if (!isLocked) {
          setState(() => engineRunning = !engineRunning);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          gradient: engineRunning
              ? const LinearGradient(
                  colors: [AppColors.accentCyan, _blueDark],
                )
              : null,
          color: engineRunning ? null : AppColors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: engineRunning
                ? AppColors.transparent
                : AppColors.accentCyan.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: engineRunning
              ? [
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.power_settings_new,
              color: engineRunning
                  ? AppColors.white
                  : AppColors.textLight.withValues(
                      alpha: isLocked ? 0.3 : 1,
                    ),
              size: 32,
            ),
            const SizedBox(width: 15),
            Text(
              engineRunning ? 'Stop Engine' : 'Start Engine',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: engineRunning
                    ? AppColors.white
                    : AppColors.textLight.withValues(
                        alpha: isLocked ? 0.3 : 1,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textLight,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            _buildQuickAction(Icons.ac_unit, 'Climate', () {}),
            const SizedBox(width: 15),
            _buildQuickAction(Icons.local_parking, 'Find Car', () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            border: Border.all(
              color: AppColors.accentCyan.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.accentCyan, size: 32),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
