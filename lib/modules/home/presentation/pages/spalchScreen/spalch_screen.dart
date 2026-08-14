import 'dart:async';
import 'dart:math' show cos, sin;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _carController;
  late AnimationController _titleController;
  late AnimationController _loadingController;
  late AnimationController _scanController;
  late AnimationController _glowController;

  late Animation<double> _carScale;
  late Animation<double> _carOpacity;
  late Animation<double> _carRotation;
  late Animation<double> _carSlideX; // 1 = off-screen right, 0 = center
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleOpacity;
  late Animation<double> _scanPosition;

  @override
  void initState() {
    super.initState();

    // Car zoom animation
    _carController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _carScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _carController,
        curve: const Cubic(0.34, 1.56, 0.64, 1),
      ),
    );

    _carOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _carController, curve: const Interval(0.0, 0.6)),
    );

    _carRotation = Tween<double>(
      begin: -0.15,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _carController, curve: Curves.easeOut));

    // Car slide in from right (off-screen → center)
    _carSlideX = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _carController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    // Title animation
    _titleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _titleController, curve: Curves.easeOut));

    _titleOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_titleController);

    // Loading animation
    _loadingController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    // Scan line animation
    _scanController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _scanPosition = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    // Glow pulse
    _glowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    // Start animations
    _startAnimations();

    // Navigate after 5 seconds, skipping auth if already logged in
    Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final isLoggedIn = AppServices.instance.session.isLoggedIn;
      Navigator.pushReplacementNamed(
        context,
        isLoggedIn ? AppRoutes.modeSelection : AppRoutes.auth,
      );
    });
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _carController.forward();

    await Future.delayed(const Duration(milliseconds: 1800));
    _titleController.forward();
  }

  @override
  void dispose() {
    _carController.dispose();
    _titleController.dispose();
    _loadingController.dispose();
    _scanController.dispose();
    _glowController.dispose();
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
        child: Stack(
          children: [
            // Grid background
            _buildGridBackground(),

            // Glow pulse
            _buildGlowPulse(),

            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Car animation
                  _buildCarAnimation(),
                  SizedBox(height: 40.h),

                  // Title
                  _buildTitleAnimation(),
                  SizedBox(height: 60.h),

                  // Loading indicator
                  _buildLoadingIndicator(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridBackground() {
    return Positioned.fill(child: CustomPaint(painter: GridPainter()));
  }

  Widget _buildGlowPulse() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final scale = 0.8 + (_glowController.value * 0.4);
        final opacity = (1 - _glowController.value) * 0.15;

        return Center(
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 400.w,
              height: 400.h,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accentCyan.withValues(alpha: opacity),
                    AppColors.transparent,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCarAnimation() {
    final screenWidth = MediaQuery.of(context).size.width;
    return AnimatedBuilder(
      animation: _carController,
      builder: (context, child) {
        return Transform.translate(
          // Car enters from right: start off-screen (slideX=1), end at center (slideX=0)
          offset: Offset(screenWidth * _carSlideX.value, 0),
          child: Transform.scale(
            scale: _carScale.value,
            child: Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_carRotation.value),
              alignment: Alignment.center,
              child: Opacity(
                opacity: _carOpacity.value,
                child: SizedBox(
                  width: 300.w,
                  height: 200.h,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(300.w, 200.h),
                        painter: CarPainter(),
                      ),
                      _buildScanLine(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScanLine() {
    return AnimatedBuilder(
      animation: _scanPosition,
      builder: (context, child) {
        final opacity = _scanPosition.value < 0.1 || _scanPosition.value > 0.9
            ? 0.0
            : 0.7;

        return Positioned(
          top: _scanPosition.value * 200.h,
          left: 0,
          right: 0,
          child: Opacity(
            opacity: opacity,
            child: Container(
              height: 2.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppColors.transparent,
                    AppColors.accentCyan,
                    AppColors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.7),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitleAnimation() {
    return SlideTransition(
      position: _titleSlide,
      child: FadeTransition(
        opacity: _titleOpacity,
        child: Column(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.accentCyan, AppColors.textLight],
              ).createShader(bounds),
              child: Text(
                'CARDIAG',
                style: TextStyle(
                  fontSize: 56.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: AppColors.white,
                  shadows: const [
                    Shadow(color: AppColors.accentCyan, blurRadius: 20),
                    Shadow(color: AppColors.accentCyan, blurRadius: 40),
                  ],
                ),
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'PROFESSIONAL DIAGNOSTICS',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w300,
                letterSpacing: 4,
                color: AppColors.accentCyan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return FadeTransition(
      opacity: _titleOpacity,
      child: Column(
        children: [
          SizedBox(
            width: 300.w,
            height: 4.h,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                AnimatedBuilder(
                  animation: _loadingController,
                  builder: (context, child) {
                    return Align(
                      alignment: Alignment(
                        -1 + 2 * _loadingController.value,
                        0,
                      ),
                      child: Container(
                        width: 100.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.accentOrange,
                              AppColors.accentCyan,
                              AppColors.accentOrange,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentCyan.withValues(
                                alpha: 0.5,
                              ),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: 15.h),
          Text(
            'INITIALIZING SYSTEM...',
            style: TextStyle(
              fontSize: 12.sp,
              letterSpacing: 2,
              color: AppColors.textLight,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

// Grid Background Painter
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentCyan.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const spacing = 50.0;

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

// Modern car side-view (sleek sedan / EV style)
class CarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 400;
    final scaleY = size.height / 200;

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [AppColors.accentCyan, AppColors.backgroundDarkBlue],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = AppColors.accentCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Main body – low, long hood, fastback
    final body = Path()
      ..moveTo(50 * scaleX, 128 * scaleY)
      ..lineTo(50 * scaleX, 108 * scaleY)
      ..lineTo(85 * scaleX, 88 * scaleY)
      ..lineTo(135 * scaleX, 75 * scaleY)
      ..lineTo(170 * scaleX, 58 * scaleY)
      ..lineTo(200 * scaleX, 48 * scaleY)
      ..lineTo(270 * scaleX, 46 * scaleY)
      ..lineTo(320 * scaleX, 62 * scaleY)
      ..lineTo(355 * scaleX, 90 * scaleY)
      ..lineTo(355 * scaleX, 112 * scaleY)
      ..lineTo(335 * scaleX, 128 * scaleY)
      ..lineTo(265 * scaleX, 128 * scaleY)
      ..lineTo(135 * scaleX, 128 * scaleY)
      ..lineTo(50 * scaleX, 128 * scaleY)
      ..close();
    canvas.drawPath(body, bodyPaint);
    canvas.drawPath(body, strokePaint);

    // Windshield
    final windshield = Path()
      ..moveTo(135 * scaleX, 75 * scaleY)
      ..lineTo(170 * scaleX, 58 * scaleY)
      ..lineTo(198 * scaleX, 52 * scaleY)
      ..lineTo(192 * scaleX, 70 * scaleY)
      ..lineTo(158 * scaleX, 82 * scaleY)
      ..close();
    canvas.drawPath(
      windshield,
      Paint()..color = AppColors.accentCyan.withValues(alpha: 0.35),
    );
    canvas.drawPath(windshield, strokePaint);

    // Cabin / rear glass (fastback)
    final cabin = Path()
      ..moveTo(198 * scaleX, 52 * scaleY)
      ..lineTo(270 * scaleX, 46 * scaleY)
      ..lineTo(315 * scaleX, 60 * scaleY)
      ..lineTo(308 * scaleX, 78 * scaleY)
      ..lineTo(192 * scaleX, 70 * scaleY)
      ..close();
    canvas.drawPath(
      cabin,
      Paint()..color = AppColors.accentCyan.withValues(alpha: 0.3),
    );
    canvas.drawPath(cabin, strokePaint);

    // Front LED strip
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(52 * scaleX, 100 * scaleY, 32 * scaleX, 4 * scaleY),
        Radius.circular(2 * scaleX),
      ),
      Paint()..color = AppColors.accentOrange,
    );

    // Headlight (narrow LED)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(48 * scaleX, 104 * scaleY, 14 * scaleX, 6 * scaleY),
        Radius.circular(2 * scaleX),
      ),
      Paint()..color = AppColors.accentOrange.withValues(alpha: 0.9),
    );

    // Rear light
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(348 * scaleX, 96 * scaleY, 8 * scaleX, 14 * scaleY),
        Radius.circular(2 * scaleX),
      ),
      Paint()..color = AppColors.accentOrange.withValues(alpha: 0.8),
    );

    // Side mirror
    canvas.drawPath(
      Path()
        ..moveTo(165 * scaleX, 60 * scaleY)
        ..lineTo(180 * scaleX, 56 * scaleY)
        ..lineTo(180 * scaleX, 68 * scaleY)
        ..lineTo(165 * scaleX, 68 * scaleY)
        ..close(),
      Paint()..color = AppColors.backgroundDarkBlue,
    );
    canvas.drawPath(
      Path()
        ..moveTo(165 * scaleX, 60 * scaleY)
        ..lineTo(180 * scaleX, 56 * scaleY)
        ..lineTo(180 * scaleX, 68 * scaleY)
        ..lineTo(165 * scaleX, 68 * scaleY)
        ..close(),
      strokePaint,
    );

    // Belt line
    canvas.drawLine(
      Offset(100 * scaleX, 92 * scaleY),
      Offset(305 * scaleX, 92 * scaleY),
      Paint()
        ..color = AppColors.accentCyan.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Alloy wheels
    _drawWheel(canvas, Offset(115 * scaleX, 128 * scaleY), 22 * scaleX);
    _drawWheel(canvas, Offset(285 * scaleX, 128 * scaleY), 22 * scaleX);
  }

  void _drawWheel(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(center, radius, Paint()..color = AppColors.grayDark);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.accentCyan.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, radius * 0.7, Paint()..color = AppColors.grayMid);
    canvas.drawCircle(
      center,
      radius * 0.45,
      Paint()..color = AppColors.grayDarker,
    );
    // 5-spoke alloy
    for (int i = 0; i < 5; i++) {
      final angle = (i * 72) * 3.14159 / 180;
      final dx = radius * 0.45 * cos(angle);
      final dy = radius * 0.45 * sin(angle);
      canvas.drawLine(
        center,
        center + Offset(dx, dy),
        Paint()
          ..color = AppColors.accentCyan.withValues(alpha: 0.5)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawCircle(
      center,
      radius * 0.18,
      Paint()..color = AppColors.accentOrange,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
