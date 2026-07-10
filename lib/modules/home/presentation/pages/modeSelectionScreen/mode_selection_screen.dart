import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';

class ModeSelectionScreen extends StatefulWidget {
  const ModeSelectionScreen({super.key});

  @override
  State<ModeSelectionScreen> createState() => _ModeSelectionScreenState();
}

class _ModeSelectionScreenState extends State<ModeSelectionScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _orbitCtrl;

  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _card1Fade;
  late final Animation<Offset> _card1Slide;
  late final Animation<double> _card2Fade;
  late final Animation<Offset> _card2Slide;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _entranceCtrl, curve: const Interval(0.0, 0.5)),
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _entranceCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _card1Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _entranceCtrl, curve: const Interval(0.3, 0.7)),
    );
    _card1Slide = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _entranceCtrl, curve: const Interval(0.3, 0.7, curve: Curves.easeOut)),
    );
    _card2Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _entranceCtrl, curve: const Interval(0.5, 0.9)),
    );
    _card2Slide = Tween<Offset>(
      begin: const Offset(0.3, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _entranceCtrl, curve: const Interval(0.5, 0.9, curve: Curves.easeOut)),
    );

    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _pulseCtrl.dispose();
    _orbitCtrl.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final exitApp = context.tr('exit_app');
    final exitConfirm = context.tr('exit_app_confirm');
    final cancel = context.tr('cancel');
    final exit = context.tr('exit');
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1929),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(exitApp, style: const TextStyle(color: Colors.white)),
        content: Text(exitConfirm, style: const TextStyle(color: Color(0xFFE8EAED))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancel, style: const TextStyle(color: Color(0xFF00D9FF))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(exit, style: const TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
            // Animated background
            _AnimatedBackground(orbitCtrl: _orbitCtrl, pulseCtrl: _pulseCtrl),

            // Content
            SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    SizedBox(height: 24.h),

                    // Header
                    SlideTransition(
                      position: _headerSlide,
                      child: FadeTransition(
                        opacity: _headerFade,
                        child: _Header(),
                      ),
                    ),

                    SizedBox(height: 32.h),

                    // Diagnostic card
                    Expanded(
                      child: SlideTransition(
                        position: _card1Slide,
                        child: FadeTransition(
                          opacity: _card1Fade,
                          child: _ModeCard(
                            title: context.tr('car_diagnostics'),
                            subtitle: context.tr('car_diagnostics_sub'),
                            icon: Icons.bluetooth_searching_rounded,
                            accentColor: AppColors.accentCyan,
                            tag: 'OBD-II',
                            tagIcon: Icons.electrical_services_rounded,
                            features: [
                              context.tr('live_engine_data'),
                              context.tr('fault_code_scanner'),
                              context.tr('performance_metrics'),
                            ],
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.dashboard,
                            ),
                            buttonLabel: context.tr('connect_bluetooth'),
                            buttonIcon: Icons.bluetooth_rounded,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // Roadside card
                    Expanded(
                      child: SlideTransition(
                        position: _card2Slide,
                        child: FadeTransition(
                          opacity: _card2Fade,
                          child: _ModeCard(
                            title: context.tr('roadside_assistance'),
                            subtitle: context.tr('roadside_assistance_sub'),
                            icon: Icons.car_repair,
                            accentColor: AppColors.accentOrange,
                            tag: '24 / 7',
                            tagIcon: Icons.access_time_filled_rounded,
                            features: [
                              context.tr('towing_service'),
                              context.tr('battery_tire_repair'),
                              context.tr('fuel_delivery'),
                            ],
                            onTap: () => Navigator.pushNamed(
                              context,
                              AppRoutes.roadside,
                            ),
                            buttonLabel: context.tr('request_help'),
                            buttonIcon: Icons.local_shipping_rounded,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // Bottom note
                    FadeTransition(
                      opacity: _card2Fade,
                      child: Text(
                        context.tr('switch_services'),
                        style: TextStyle(
                          color: AppColors.textLight.withValues(alpha: 0.35),
                          fontSize: 12.sp,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    SizedBox(height: 16.h),
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
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.accentCyan, AppColors.textLight],
          ).createShader(bounds),
          child: Text(
            'CARDIAG',
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              color: AppColors.white,
            ),
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          context.tr('what_do_you_need'),
          style: TextStyle(
            color: AppColors.textLight.withValues(alpha: 0.55),
            fontSize: 14.sp,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ── Mode card ──────────────────────────────────────────────────────────────────

class _ModeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String tag;
  final IconData tagIcon;
  final List<String> features;
  final VoidCallback onTap;
  final String buttonLabel;
  final IconData buttonIcon;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.tag,
    required this.tagIcon,
    required this.features,
    required this.onTap,
    required this.buttonLabel,
    required this.buttonIcon,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressScale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor;

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        _pressCtrl.forward();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        _pressCtrl.reverse();
      },
      child: ScaleTransition(
        scale: _pressScale,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24.r),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.12),
                AppColors.surfaceDarkElevated.withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(
              color: _pressed
                  ? color.withValues(alpha: 0.8)
                  : color.withValues(alpha: 0.3),
              width: _pressed ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: _pressed ? 0.2 : 0.1),
                blurRadius: _pressed ? 24 : 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(20.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: icon + tag
                Row(
                  children: [
                    Container(
                      width: 52.r,
                      height: 52.r,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withValues(alpha: 0.3),
                            color.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.2),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: color, size: 26.r),
                    ),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 10.w, vertical: 5.h),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20.r),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.tagIcon, color: color, size: 12.r),
                          SizedBox(width: 5.w),
                          Text(
                            widget.tag,
                            style: TextStyle(
                              color: color,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 14.h),

                // Title
                Text(
                  widget.title,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),

                SizedBox(height: 6.h),

                // Subtitle
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: AppColors.textLight.withValues(alpha: 0.55),
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const Spacer(),

                // Feature bullets
                ...widget.features.map(
                  (f) => Padding(
                    padding: EdgeInsets.only(bottom: 5.h),
                    child: Row(
                      children: [
                        Container(
                          width: 5.r,
                          height: 5.r,
                          margin: EdgeInsets.only(right: 8.w),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          f,
                          style: TextStyle(
                            color: AppColors.textLight.withValues(alpha: 0.7),
                            fontSize: 11.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 14.h),

                // Action button
                Container(
                  width: double.infinity,
                  height: 46.h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.buttonIcon,
                          color: AppColors.white, size: 18.r),
                      SizedBox(width: 8.w),
                      Text(
                        widget.buttonLabel,
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Icon(Icons.arrow_forward_rounded,
                          color: AppColors.white.withValues(alpha: 0.8),
                          size: 16.r),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Animated background ────────────────────────────────────────────────────────

class _AnimatedBackground extends StatelessWidget {
  final AnimationController orbitCtrl;
  final AnimationController pulseCtrl;

  const _AnimatedBackground({
    required this.orbitCtrl,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([orbitCtrl, pulseCtrl]),
        builder: (context, _) {
          return CustomPaint(
            painter: _BgPainter(
              orbitProgress: orbitCtrl.value,
              pulseProgress: pulseCtrl.value,
            ),
          );
        },
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  final double orbitProgress;
  final double pulseProgress;

  const _BgPainter({
    required this.orbitProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.35;

    // Pulsing glow
    final glowRadius = 120.0 + pulseProgress * 60;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF00D9FF).withValues(alpha: 0.06 + pulseProgress * 0.03),
          Colors.transparent,
        ],
      ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: glowRadius));
    canvas.drawCircle(Offset(cx, cy), glowRadius, glowPaint);

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF00D9FF).withValues(alpha: 0.03)
      ..strokeWidth = 1;
    const spacing = 50.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Orbiting dots
    final dotPaint = Paint()..style = PaintingStyle.fill;
    const dotCount = 6;
    for (int i = 0; i < dotCount; i++) {
      final angle = (orbitProgress * 2 * pi) + (i * 2 * pi / dotCount);
      final radius = 180.0 + (i % 2) * 40;
      final x = cx + radius * cos(angle);
      final y = cy + radius * sin(angle);
      final isOrange = i % 2 == 0;
      dotPaint.color = (isOrange
              ? const Color(0xFFFF6B35)
              : const Color(0xFF00D9FF))
          .withValues(alpha: 0.15 + pulseProgress * 0.05);
      canvas.drawCircle(Offset(x, y), 3 + (i % 3).toDouble(), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) =>
      old.orbitProgress != orbitProgress || old.pulseProgress != pulseProgress;
}
