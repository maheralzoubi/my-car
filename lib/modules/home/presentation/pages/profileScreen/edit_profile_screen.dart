import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/app_services.dart';
import '../../../../../core/core.dart';
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
  /// Minimum time the save spinner shows, so the press registers visibly
  /// even though the local write is near-instant.
  static const Duration _minSaveFeedback = Duration(milliseconds: 600);

  final _formKey = GlobalKey<FormState>();
  final _session = AppServices.instance.session;
  late final TextEditingController _nameController = TextEditingController(
    text: _session.name ?? '',
  );
  late final TextEditingController _emailController = TextEditingController(
    text: _session.email ?? '',
  );
  late final TextEditingController _phoneController = TextEditingController(
    text: _session.phone ?? '',
  );
  late final TextEditingController _locationController = TextEditingController(
    text: _session.location ?? '',
  );
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
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  AppSizes.space8.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAvatarSection(),
                      SizedBox(height: AppSizes.space24.h),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSizes.space16.h,
                        children: [
                          _buildNameField(),
                          _buildEmailField(),
                          _buildPhoneField(),
                          _buildLocationField(),
                        ],
                      ),
                      SizedBox(height: AppSizes.space24.h),
                      _buildPasswordSection(),
                      SizedBox(height: AppSizes.space32.h),
                      _buildSaveButton(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() =>
      ScreenHeader(title: context.tr('edit_profile'), close: true);

  /// Avatar with a camera badge; the avatar, the badge and the "Change
  /// photo" link all open the picture options.
  Widget _buildAvatarSection() {
    final p = context.colors;
    final size = 96.r;
    final badge = 36.r;
    return Column(
      children: [
        SizedBox(
          width: size + AppSizes.space4.r,
          height: size + AppSizes.space4.r,
          child: Stack(
            children: [
              Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _showAvatarOptions,
                  child: ProfileAvatar(size: size),
                ),
              ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: Tooltip(
                  message: context.tr('change_profile_picture'),
                  child: Material(
                    color: p.primaryButton,
                    shape: CircleBorder(
                      side: BorderSide(color: p.bg, width: 3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _showAvatarOptions,
                      child: SizedBox.square(
                        dimension: badge,
                        child: Icon(
                          Icons.photo_camera_rounded,
                          color: p.onPrimary,
                          size: 18.r,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSizes.space8.h),
        AppButton.ghost(
          label: context.tr('change_photo'),
          onPressed: _showAvatarOptions,
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return _labelled(
      context.tr('full_name'),
      TextFormField(
        controller: _nameController,
        style: AppTextStyles.body,
        textInputAction: TextInputAction.next,
        decoration: _buildInputDecoration(
          hintText: context.tr('enter_full_name'),
          prefixIcon: Icons.person_outline_rounded,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return context.tr('please_enter_name');
          }
          return null;
        },
      ),
    );
  }

  Widget _buildEmailField() {
    return _labelled(
      context.tr('email_address'),
      TextFormField(
        controller: _emailController,
        style: AppTextStyles.body,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        decoration: _buildInputDecoration(
          hintText: context.tr('enter_email'),
          prefixIcon: Icons.mail_outline_rounded,
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
    );
  }

  Widget _buildPhoneField() {
    return _labelled(
      context.tr('phone'),
      TextFormField(
        controller: _phoneController,
        style: AppTextStyles.body,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
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
    );
  }

  Widget _buildLocationField() {
    return _labelled(
      context.tr('location_label'),
      TextFormField(
        controller: _locationController,
        style: AppTextStyles.body,
        textInputAction: TextInputAction.done,
        decoration: _buildInputDecoration(
          hintText: context.tr('enter_location'),
          prefixIcon: Icons.location_on_outlined,
        ),
      ),
    );
  }

  Widget _buildPasswordSection() {
    return SettingsGroup(
      title: context.tr('security'),
      children: [
        SettingsTile(
          leading: const IconBox.neutral(Icons.lock_outline_rounded),
          title: context.tr('change_password'),
          subtitle: context.tr('update_your_password'),
          onTap: _showChangePasswordDialog,
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return AppButton(
      label: context.tr('save_changes'),
      onPressed: _handleSave,
      isLoading: isSaving,
    );
  }

  /// A field with its [label] above it (mockup sign-in form style).
  Widget _labelled(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(bottom: AppSizes.space8.h),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(color: context.colors.text),
          ),
        ),
        field,
      ],
    );
  }

  /// Fill, borders, icon and error colors come from the app's input theme.
  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(hintText: hintText, prefixIcon: Icon(prefixIcon));
  }

  void _showAvatarOptions() {
    // Background, corners and the drag handle come from the bottom-sheet
    // theme (which draws its own handle).
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final p = context.colors;
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSizes.space20.w,
            0,
            AppSizes.space20.w,
            AppSizes.space20.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('change_profile_picture'),
                style: AppTextStyles.title.copyWith(color: p.text),
              ),
              SizedBox(height: AppSizes.space16.h),
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: p.primary),
                title: Text(context.tr('take_photo')),
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: p.primary),
                title: Text(context.tr('choose_from_gallery')),
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: p.crit),
                title: Text(
                  context.tr('remove_photo'),
                  style: TextStyle(color: p.crit),
                ),
                onTap: () {
                  Navigator.pop(context);
                  AppServices.instance.profilePhoto.clear();
                },
              ),
            ],
          ),
        );
      },
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        title: Text(context.tr('success')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('profile_updated')),
            SizedBox(height: AppSizes.space8.h),
            Text(
              context.tr('profile_saved_on_device'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w400,
                color: context.colors.text2,
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

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: AppTextStyles.body,
      // Borders and label colors come from the app's input theme.
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('change_password')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('password_change_unavailable'),
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w400,
                color: context.colors.warn,
              ),
            ),
            SizedBox(height: AppSizes.space16.h),
            _field(_current, context.tr('current_password')),
            SizedBox(height: AppSizes.space16.h),
            _field(_next, context.tr('new_password')),
            SizedBox(height: AppSizes.space16.h),
            _field(_confirm, context.tr('confirm_new_password')),
            if (_error != null) ...[
              SizedBox(height: AppSizes.space12.h),
              Text(
                _error!,
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: context.colors.crit,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(onPressed: _submit, child: Text(context.tr('update'))),
      ],
    );
  }
}
