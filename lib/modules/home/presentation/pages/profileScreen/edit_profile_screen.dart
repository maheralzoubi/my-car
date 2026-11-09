import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';
import 'profile_avatar.dart';

/// Screen for editing user profile: name, email, phone, location, avatar, password.
///
/// The backend only has /auth/login and /auth/register — no profile update,
/// password change or avatar upload — so edits and the photo are stored on
/// this device ([Session.updateProfile], [ProfilePhotoStore]) and the UI
/// says so; changing the password is not possible yet.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color _errorRed = Color(0xFFFF1744);

  /// Minimum time the save spinner shows, so the press registers visibly
  /// even though the local write is near-instant.
  static const Duration _minSaveFeedback = Duration(milliseconds: 600);

  final _formKey = GlobalKey<FormState>();
  final _session = AppServices.instance.session;
  late final TextEditingController _nameController =
      TextEditingController(text: _session.name ?? '');
  late final TextEditingController _emailController =
      TextEditingController(text: _session.email ?? '');
  late final TextEditingController _phoneController =
      TextEditingController(text: _session.phone ?? '');
  late final TextEditingController _locationController =
      TextEditingController(text: _session.location ?? '');
  final ImagePicker _picker = ImagePicker();

  bool isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
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
                  padding: EdgeInsets.all(20.r),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvatarSection(),
                        SizedBox(height: 30.h),
                        _buildNameField(),
                        SizedBox(height: 20.h),
                        _buildEmailField(),
                        SizedBox(height: 20.h),
                        _buildPhoneField(),
                        SizedBox(height: 20.h),
                        _buildLocationField(),
                        SizedBox(height: 30.h),
                        _buildPasswordSection(),
                        SizedBox(height: 30.h),
                        _buildSaveButton(),
                        SizedBox(height: 20.h),
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
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: AppColors.accentCyan, size: 24.r),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            context.tr('edit_profile'),
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 120.w,
            height: 120.h,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accentCyan, AppColors.accentOrange],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentCyan.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ProfileAvatarContent(fontSize: 42.sp),
          ),
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: GestureDetector(
              onTap: _showAvatarOptions,
              child: Container(
                width: 40.w,
                height: 40.h,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accentCyan, AppColors.accentOrange],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.backgroundDark,
                    width: 3,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: AppColors.white,
                  size: 20.r,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context.tr('full_name')),
        TextFormField(
          controller: _nameController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: _buildInputDecoration(
            hintText: context.tr('enter_full_name'),
            prefixIcon: Icons.person_outline,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.tr('please_enter_name');
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context.tr('email_address')),
        TextFormField(
          controller: _emailController,
          style: const TextStyle(color: AppColors.textLight),
          keyboardType: TextInputType.emailAddress,
          decoration: _buildInputDecoration(
            hintText: context.tr('enter_email'),
            prefixIcon: Icons.email_outlined,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.tr('please_enter_email');
            }
            if (!value.contains('@')) {
              return context.tr('invalid_email');
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context.tr('phone')),
        TextFormField(
          controller: _phoneController,
          style: const TextStyle(color: AppColors.textLight),
          keyboardType: TextInputType.phone,
          decoration: _buildInputDecoration(
            hintText: context.tr('enter_phone'),
            prefixIcon: Icons.phone_outlined,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return context.tr('please_enter_phone');
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(context.tr('location_label')),
        TextFormField(
          controller: _locationController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: _buildInputDecoration(
            hintText: context.tr('enter_location'),
            prefixIcon: Icons.location_on_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4.w,
              height: 20.h,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10.r)),
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              context.tr('security'),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        SizedBox(height: 15.h),
        GestureDetector(
          onTap: _showChangePasswordDialog,
          child: Container(
            padding: EdgeInsets.all(18.r),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.1),
              ),
              borderRadius: BorderRadius.circular(15.r),
            ),
            child: Row(
              children: [
                Container(
                  width: 45.w,
                  height: 45.h,
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: AppColors.accentOrange,
                  ),
                ),
                SizedBox(width: 15.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('change_password'),
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textLight,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        context.tr('update_your_password'),
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.accentCyan,
                  size: 16.r,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56.h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accentCyan, AppColors.accentOrange],
        ),
        borderRadius: BorderRadius.circular(15.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentCyan.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isSaving ? null : _handleSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15.r),
          ),
        ),
        child: isSaving
            ? SizedBox(
                width: 20.w,
                height: 20.h,
                child: const CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                context.tr('save_changes'),
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing:
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 0
                          : 2,
                  color: AppColors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.textLight,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: AppColors.textLight.withValues(alpha: 0.5),
      ),
      prefixIcon: Icon(prefixIcon, color: AppColors.accentCyan),
      filled: true,
      fillColor: AppColors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15.r),
        borderSide: BorderSide(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15.r),
        borderSide: BorderSide(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15.r),
        borderSide: const BorderSide(
          color: AppColors.accentCyan,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15.r),
        borderSide: const BorderSide(color: _errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15.r),
        borderSide: const BorderSide(color: _errorRed, width: 2),
      ),
    );
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25.r)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              context.tr('change_profile_picture'),
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
            SizedBox(height: 20.h),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.accentCyan),
              title: Text(
                context.tr('take_photo'),
                style: const TextStyle(color: AppColors.textLight),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accentCyan),
              title: Text(
                context.tr('choose_from_gallery'),
                style: const TextStyle(color: AppColors.textLight),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: _errorRed),
              title: Text(
                context.tr('remove_photo'),
                style: const TextStyle(color: _errorRed),
              ),
              onTap: () {
                Navigator.pop(context);
                AppServices.instance.profilePhoto.clear();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (file == null) return; // cancelled
      final bytes = await file.readAsBytes();
      await AppServices.instance.profilePhoto.save(bytes);
    } catch (_) {
      // Permission denied, no camera, plugin unavailable…
      if (!mounted) return;
      _showSnack(context.tr('photo_pick_failed'));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// The backend has no password-change endpoint, so a valid entry is not
  /// sent anywhere — the user is told it is not available yet instead of
  /// being shown a fake success.
  Future<void> _showChangePasswordDialog() async {
    final valid = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (valid == true && mounted) {
      _showSnack(context.tr('password_change_unavailable'));
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isSaving = true);

    final results = await Future.wait<Object?>([
      _session.updateProfile(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        location: _locationController.text.trim(),
      ),
      Future<void>.delayed(_minSaveFeedback),
    ]);
    final persisted = results.first == true;

    if (!mounted) return;
    setState(() => isSaving = false);

    // Secure storage could not be written: the edit would be lost on the
    // next restart, so it is not reported as saved.
    if (!persisted) {
      _showSnack(context.tr('profile_save_failed'));
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          context.tr('success'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('profile_updated'),
              style: const TextStyle(color: AppColors.textLight),
            ),
            SizedBox(height: 10.h),
            Text(
              context.tr('profile_saved_on_device'),
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textLight.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(this.context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: Text(context.tr('done')),
          ),
        ],
      ),
    );
  }
}

/// Change-password form. Pops `true` once the three fields are valid (the
/// caller then explains that the change can't be applied yet).
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  static const Color _errorRed = Color(0xFFFF1744);

  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final String? problem;
    if (_current.text.isEmpty || _next.text.isEmpty || _confirm.text.isEmpty) {
      problem = context.tr('fill_all_password_fields');
    } else if (_next.text.length < 6) {
      problem = context.tr('password_too_short');
    } else if (_next.text != _confirm.text) {
      problem = context.tr('passwords_do_not_match');
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, true);
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.accentCyan),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.r),
        borderSide: BorderSide(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.r),
        borderSide: const BorderSide(color: AppColors.accentCyan),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(color: AppColors.textLight),
      decoration: _decoration(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      title: Text(
        context.tr('change_password'),
        style: const TextStyle(color: AppColors.textLight),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('password_change_unavailable'),
              style: TextStyle(fontSize: 13.sp, color: AppColors.accentOrange),
            ),
            SizedBox(height: 15.h),
            _field(_current, context.tr('current_password')),
            SizedBox(height: 15.h),
            _field(_next, context.tr('new_password')),
            SizedBox(height: 15.h),
            _field(_confirm, context.tr('confirm_new_password')),
            if (_error != null) ...[
              SizedBox(height: 12.h),
              Text(
                _error!,
                style: TextStyle(fontSize: 13.sp, color: _errorRed),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.tr('cancel'),
            style: const TextStyle(color: AppColors.accentCyan),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentCyan,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r),
            ),
          ),
          child: Text(context.tr('update')),
        ),
      ],
    );
  }
}
