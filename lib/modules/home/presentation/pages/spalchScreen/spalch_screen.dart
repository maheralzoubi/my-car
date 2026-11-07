import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';

/// Brand splash: the blue car logo, the CARDIAG wordmark and a slim progress
/// bar on the theme background. Routes to the shell (signed in) or sign-in
/// after 5 s.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _titleController;

  // Leaving the splash waits for the 5 s intro AND the saved session
  // (main() no longer waits for it before drawing). If the session is still
  // loading after the intro, wait at most 3 s more: a stuck storage read must
  // never trap the user here. Both timers are cancelled in dispose().
  Timer? _introTimer;
  Timer? _capTimer;
  bool _introDone = false;
  bool _servicesReady = false;
  bool _left = false;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;

  @override
  void initState() {
    super.initState();

    // Logo: a gentle fade + settle.
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _logoOpacity = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    );
    _logoScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    // Wordmark, tagline and progress.
    _titleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _titleOpacity = CurvedAnimation(
      parent: _titleController,
      curve: Curves.easeOut,
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _titleController, curve: Curves.easeOutCubic),
        );

    _startAnimations();

    // Only observe: main() starts the loading (AppServices.start).
    AppServices.instance.session.loaded.then((_) {
      _servicesReady = true;
      if (_introDone) _leave();
    });
    _introTimer = Timer(const Duration(seconds: 5), () {
      _introDone = true;
      if (_servicesReady || AppServices.instance.session.isLoaded) {
        _leave();
      } else {
        _capTimer = Timer(const Duration(seconds: 3), _leave);
      }
    });
  }

  /// Goes to the app when already signed in, otherwise to sign-in.
  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    _capTimer?.cancel();
    final isLoggedIn = AppServices.instance.session.isLoggedIn;
    Navigator.pushReplacementNamed(
      context,
      isLoggedIn ? AppRoutes.shell : AppRoutes.auth,
    );
  }

  void _startAnimations() async {
    // The screen can be disposed during either delay (e.g. app backgrounded
    // and route replaced); a disposed controller throws on forward().
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _logoController.forward();

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    _titleController.forward();
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _capTimer?.cancel();
    _logoController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          // Scaled down to fit when the screen is shorter than the portrait
          // design (e.g. a phone in landscape).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.all(AppSizes.space24.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLogo(context),
                  SizedBox(height: AppSizes.space24.h),
                  _buildTitle(context),
                  SizedBox(height: AppSizes.space48.h),
                  _buildProgress(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final p = context.colors;
    return FadeTransition(
      opacity: _logoOpacity,
      child: ScaleTransition(
        scale: _logoScale,
        child: ExcludeSemantics(
          child: Container(
            width: 80.r,
            height: 80.r,
            decoration: BoxDecoration(
              color: p.primaryButton,
              borderRadius: BorderRadius.circular(AppSizes.radiusXl.r),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.directions_car_rounded,
              size: 42.r,
              color: p.onPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final p = context.colors;
    return SlideTransition(
      position: _titleSlide,
      child: FadeTransition(
        opacity: _titleOpacity,
        child: Column(
          children: [
            Text(
              // Latin brand wordmark in every locale.
              'CARDIAG',
              textDirection: TextDirection.ltr,
              style: AppTextStyles.display.copyWith(
                fontSize: 34.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: p.text,
              ),
            ),
            SizedBox(height: AppSizes.space4.h),
            Text(
              context.tr('splash_tagline'),
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: p.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final p = context.colors;
    return FadeTransition(
      opacity: _titleOpacity,
      child: Column(
        children: [
          SizedBox(
            width: 160.w,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              child: LinearProgressIndicator(
                minHeight: 4.h,
                color: p.primary,
                backgroundColor: p.track,
              ),
            ),
          ),
          SizedBox(height: AppSizes.space12.h),
          Text(
            context.tr('splash_initializing'),
            textAlign: TextAlign.center,
            style: AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w400,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }
}
