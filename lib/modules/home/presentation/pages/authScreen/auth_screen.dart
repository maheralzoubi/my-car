import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  final TextEditingController _signupNameController = TextEditingController();
  final TextEditingController _signupEmailController = TextEditingController();
  final TextEditingController _signupPasswordController =
      TextEditingController();
  final TextEditingController _signupConfirmPasswordController =
      TextEditingController();

  bool _isLoginPasswordVisible = false;
  bool _isSignupPasswordVisible = false;
  bool _isSignupConfirmPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    super.dispose();
  }

  static const String _validEmail = 'maher@gmail.com';
  static const String _validPassword = 'maher1997';

  void _handleLogin() {
    if (!_loginFormKey.currentState!.validate()) return;
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;
    if (email == _validEmail && password == _validPassword) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.connectionscreen);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('invalid_credentials')),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  void _handleSignup() {
    if (_signupFormKey.currentState!.validate()) {
      // Handle signup logic
      Navigator.pushReplacementNamed(context, AppRoutes.connectionscreen);
    }
  }

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
                  child: Padding(
                    padding: EdgeInsets.all(20.r),
                    child: Column(
                      children: [
                        _buildLogo(),
                        SizedBox(height: 40.h),
                        _buildTabBar(),
                        SizedBox(height: 30.h),
                        _buildTabContent(),
                      ],
                    ),
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
    return const SizedBox.shrink();
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80.w,
          height: 80.h,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D9FF).withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Icon(
            Icons.directions_car,
            size: 40.r,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 20.h),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF00D9FF), Color(0xFFE8EAED)],
          ).createShader(bounds),
          child: Text(
            'CARDIAG',
            style: TextStyle(
              fontSize: 32.sp,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Professional Vehicle Diagnostics',
          style: TextStyle(
            fontSize: 14.sp,
            color: const Color(0xFF00D9FF),
            fontWeight: FontWeight.w300,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 50.h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15.r),
        border: Border.all(color: const Color(0xFF00D9FF).withValues(alpha: 0.2)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
          ),
          borderRadius: BorderRadius.circular(15.r),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFFE8EAED).withValues(alpha: 0.6),
        labelStyle: TextStyle(
          fontSize: 16.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
        tabs: [
          Tab(text: context.tr('login_tab')),
          Tab(text: context.tr('signup_tab')),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return SizedBox(
      height: 500.h,
      child: TabBarView(
        controller: _tabController,
        children: [_buildLoginForm(), _buildSignupForm()],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          _buildTextField(
            controller: _loginEmailController,
            label: context.tr('email'),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) return context.tr('enter_email');
              if (!value.contains('@')) return context.tr('enter_email');
              return null;
            },
          ),
          SizedBox(height: 20.h),
          _buildTextField(
            controller: _loginPasswordController,
            label: context.tr('password'),
            icon: Icons.lock_outline,
            isPassword: true,
            isPasswordVisible: _isLoginPasswordVisible,
            onTogglePassword: () {
              setState(() => _isLoginPasswordVisible = !_isLoginPasswordVisible);
            },
            validator: (value) {
              if (value == null || value.isEmpty) return context.tr('enter_password');
              return null;
            },
          ),
          SizedBox(height: 15.h),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: Text(
                context.tr('forgot_password'),
                style: TextStyle(color: const Color(0xFF00D9FF), fontSize: 14.sp),
              ),
            ),
          ),
          SizedBox(height: 30.h),
          _buildGradientButton(text: context.tr('login_tab'), onPressed: _handleLogin),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    return Form(
      key: _signupFormKey,
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildTextField(
              controller: _signupNameController,
              label: context.tr('full_name'),
              icon: Icons.person_outline,
              validator: (value) {
                if (value == null || value.isEmpty) return context.tr('enter_full_name');
                return null;
              },
            ),
            SizedBox(height: 20.h),
            _buildTextField(
              controller: _signupEmailController,
              label: context.tr('email'),
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) return context.tr('enter_email');
                if (!value.contains('@')) return context.tr('enter_email');
                return null;
              },
            ),
            SizedBox(height: 20.h),
            _buildTextField(
              controller: _signupPasswordController,
              label: context.tr('password'),
              icon: Icons.lock_outline,
              isPassword: true,
              isPasswordVisible: _isSignupPasswordVisible,
              onTogglePassword: () {
                setState(() => _isSignupPasswordVisible = !_isSignupPasswordVisible);
              },
              validator: (value) {
                if (value == null || value.isEmpty) return context.tr('enter_password');
                if (value.length < 6) return context.tr('enter_password');
                return null;
              },
            ),
            SizedBox(height: 20.h),
            _buildTextField(
              controller: _signupConfirmPasswordController,
              label: context.tr('confirm_password'),
              icon: Icons.lock_outline,
              isPassword: true,
              isPasswordVisible: _isSignupConfirmPasswordVisible,
              onTogglePassword: () {
                setState(() => _isSignupConfirmPasswordVisible = !_isSignupConfirmPasswordVisible);
              },
              validator: (value) {
                if (value == null || value.isEmpty) return context.tr('confirm_your_password');
                if (value != _signupPasswordController.text) return context.tr('confirm_your_password');
                return null;
              },
            ),
            SizedBox(height: 30.h),
            _buildGradientButton(text: context.tr('signup_tab'), onPressed: _handleSignup),
          ],
        ),
      ),
    );
  }

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
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !isPasswordVisible,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Color(0xFFE8EAED)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: const Color(0xFF00D9FF).withValues(alpha: 0.7)),
        prefixIcon: Icon(icon, color: const Color(0xFF00D9FF)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: const Color(0xFF00D9FF).withValues(alpha: 0.7),
                ),
                onPressed: onTogglePassword,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.r),
          borderSide: BorderSide(
            color: const Color(0xFF00D9FF).withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.r),
          borderSide: BorderSide(
            color: const Color(0xFF00D9FF).withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.r),
          borderSide: const BorderSide(color: Color(0xFF00D9FF), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.r),
          borderSide: const BorderSide(color: Color(0xFFFF1744)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15.r),
          borderSide: const BorderSide(color: Color(0xFFFF1744), width: 2),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 56.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00D9FF), Color(0xFFFF6B35)],
        ),
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D9FF).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
