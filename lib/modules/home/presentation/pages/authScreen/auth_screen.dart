import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/auth/api_auth_repository.dart';
import '../../../../../core/bloc/locale/locale_bloc.dart';
import '../../../../../core/bloc/locale/locale_event.dart';
import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/network/api_exception.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  /// false: the sign-in form; true: the sign-up form.
  bool _isSignup = false;
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  final TextEditingController _signupNameController = TextEditingController();
  final TextEditingController _signupEmailController = TextEditingController();
  final TextEditingController _signupPhoneController = TextEditingController();
  final TextEditingController _signupPasswordController =
      TextEditingController();
  final TextEditingController _signupConfirmPasswordController =
      TextEditingController();

  bool _isLoginPasswordVisible = false;
  bool _isSignupPasswordVisible = false;
  bool _isSignupConfirmPasswordVisible = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPhoneController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await AppServices.instance.authRepository.login(
        _loginEmailController.text.trim(),
        _loginPasswordController.text,
      );
      AppServices.instance.socketClient.connect();
      unawaited(AppServices.instance.registerPushNotifications());
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.shell);
      }
    } on ApiException catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleSignup() async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await AppServices.instance.authRepository.register(
        email: _signupEmailController.text.trim(),
        password: _signupPasswordController.text,
        name: _signupNameController.text.trim(),
        phone: _signupPhoneController.text.trim(),
      );
      AppServices.instance.socketClient.connect();
      unawaited(AppServices.instance.registerPushNotifications());
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.shell);
      }
    } on ApiException catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  /// Server-provided messages are shown as sent; transport and generic
  /// failures carry a localization key instead of fixed English.
  String _errorText(ApiException e) =>
      e is AuthException ? context.tr(e.l10nKey) : e.message;

  /// The backend has no password-reset endpoint (only /auth/login and
  /// /auth/register), so this explains how to recover instead of faking a
  /// reset email.
  void _showForgotPassword() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('forgot_password_title')),
        content: Text(ctx.tr('forgot_password_unavailable')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('ok')),
          ),
        ],
      ),
    );
  }

  void _showError(ApiException error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_errorText(error))));
  }

  void _setSignup(bool value) {
    if (_isSubmitting || value == _isSignup) return;
    setState(() => _isSignup = value);
  }

  /// Switches between English and Arabic. The app's [LocaleBloc] is absent
  /// when the screen is shown on its own (tests); then this is a no-op.
  void _toggleLanguage() {
    final next = _isArabic ? const Locale('en') : const Locale('ar');
    try {
      context.read<LocaleBloc>().add(ChangeLocale(next));
    } on ProviderNotFoundException {
      // No app-level locale bloc above this screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.space20.w),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: AppSizes.space40.h),
                    _buildIntro(p),
                    SizedBox(height: AppSizes.space32.h),
                    if (_isSignup) _buildSignupForm() else _buildLoginForm(),
                    SizedBox(height: AppSizes.space24.h),
                    _buildSwitchMode(p),
                    const Spacer(),
                    SizedBox(height: AppSizes.space24.h),
                    _buildLanguageSwitch(p),
                    SizedBox(height: AppSizes.space8.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Logo tile, title and one-line subtitle.
  Widget _buildIntro(AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 56.r,
            height: 56.r,
            decoration: BoxDecoration(
              color: p.primaryButton,
              borderRadius: BorderRadius.circular(AppSizes.radiusLg.r),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.directions_car_filled_rounded,
              size: 28.r,
              color: p.onPrimary,
            ),
          ),
        ),
        SizedBox(height: AppSizes.space24.h),
        Semantics(
          header: true,
          child: Text(
            context.tr(_isSignup ? 'join_cardiag' : 'welcome_back'),
            style: AppTextStyles.display.copyWith(color: p.text),
          ),
        ),
        SizedBox(height: AppSizes.space4.h),
        Text(
          context.tr(
            _isSignup ? 'auth_signup_subtitle' : 'auth_welcome_subtitle',
          ),
          style: AppTextStyles.body.copyWith(color: p.text2),
        ),
      ],
    );
  }

  /// "New to CARDIAG?" / "Already have an account?" divider and the
  /// secondary button that switches between the two forms.
  Widget _buildSwitchMode(AppPalette p) {
    final divider = Expanded(child: Divider(color: p.border, height: 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            divider,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.space12.w),
              child: Text(
                context.tr(_isSignup ? 'already_have_account' : 'auth_new_to'),
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: p.muted,
                ),
              ),
            ),
            divider,
          ],
        ),
        SizedBox(height: AppSizes.space16.h),
        AppButton.secondary(
          label: context.tr(_isSignup ? 'auth_sign_in' : 'auth_create_account'),
          onPressed: _isSubmitting ? null : () => _setSignup(!_isSignup),
        ),
      ],
    );
  }

  /// Shows the other language's own name ("العربية" / "English").
  Widget _buildLanguageSwitch(AppPalette p) {
    return Center(
      child: TextButton.icon(
        onPressed: _toggleLanguage,
        style: TextButton.styleFrom(
          foregroundColor: p.text2,
          minimumSize: Size(44.r, 44.r),
        ),
        icon: Icon(Icons.language_rounded, size: 20.r),
        label: Text(
          _isArabic ? 'English' : 'العربية',
          style: AppTextStyles.label.copyWith(fontSize: 14.sp),
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return context.tr('enter_email');
    if (!value.contains('@')) return context.tr('invalid_email');
    return null;
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _loginEmailController,
            label: context.tr('email'),
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          SizedBox(height: AppSizes.space16.h),
          _buildTextField(
            controller: _loginPasswordController,
            label: context.tr('password'),
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            isPasswordVisible: _isLoginPasswordVisible,
            onTogglePassword: () {
              setState(
                () => _isLoginPasswordVisible = !_isLoginPasswordVisible,
              );
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('enter_password');
              }
              return null;
            },
          ),
          SizedBox(height: AppSizes.space4.h),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _showForgotPassword,
              style: TextButton.styleFrom(minimumSize: Size(44.r, 44.r)),
              child: Text(
                context.tr('forgot_password'),
                style: AppTextStyles.label.copyWith(fontSize: 14.sp),
              ),
            ),
          ),
          SizedBox(height: AppSizes.space12.h),
          AppButton(
            label: context.tr('auth_sign_in'),
            onPressed: _isSubmitting ? null : _handleLogin,
            isLoading: _isSubmitting,
          ),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            controller: _signupNameController,
            label: context.tr('full_name'),
            icon: Icons.person_outline_rounded,
            keyboardType: TextInputType.name,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('enter_full_name');
              }
              return null;
            },
          ),
          SizedBox(height: AppSizes.space16.h),
          _buildTextField(
            controller: _signupEmailController,
            label: context.tr('email'),
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          SizedBox(height: AppSizes.space16.h),
          _buildTextField(
            controller: _signupPhoneController,
            label: context.tr('phone'),
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('enter_phone');
              }
              return null;
            },
          ),
          SizedBox(height: AppSizes.space16.h),
          _buildTextField(
            controller: _signupPasswordController,
            label: context.tr('password'),
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            isPasswordVisible: _isSignupPasswordVisible,
            onTogglePassword: () {
              setState(
                () => _isSignupPasswordVisible = !_isSignupPasswordVisible,
              );
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('enter_password');
              }
              if (value.length < 6) return context.tr('password_too_short');
              return null;
            },
          ),
          SizedBox(height: AppSizes.space16.h),
          _buildTextField(
            controller: _signupConfirmPasswordController,
            label: context.tr('confirm_password'),
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            isPasswordVisible: _isSignupConfirmPasswordVisible,
            onTogglePassword: () {
              setState(
                () => _isSignupConfirmPasswordVisible =
                    !_isSignupConfirmPasswordVisible,
              );
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('confirm_your_password');
              }
              if (value != _signupPasswordController.text) {
                return context.tr('passwords_do_not_match');
              }
              return null;
            },
          ),
          SizedBox(height: AppSizes.space24.h),
          AppButton(
            label: context.tr('auth_create_account'),
            onPressed: _isSubmitting ? null : _handleSignup,
            isLoading: _isSubmitting,
          ),
        ],
      ),
    );
  }

  /// A label above a themed field (fill, borders and icon colors come from
  /// the theme's inputDecorationTheme).
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool isPasswordVisible = false,
    VoidCallback? onTogglePassword,
    String? Function(String?)? validator,
  }) {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(bottom: AppSizes.space8.h),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(color: p.text2),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: isPassword && !isPasswordVisible,
          keyboardType: keyboardType,
          validator: validator,
          style: AppTextStyles.body.copyWith(color: p.text),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20.r),
            suffixIcon: isPassword
                ? IconButton(
                    tooltip: context.tr(
                      isPasswordVisible
                          ? 'auth_hide_password'
                          : 'auth_show_password',
                    ),
                    icon: Icon(
                      isPasswordVisible
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20.r,
                    ),
                    onPressed: onTogglePassword,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
