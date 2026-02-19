import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';

/// Screen for editing user profile: name, email, phone, location, avatar, password.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color _errorRed = Color(0xFFFF1744);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController =
      TextEditingController(text: 'John Doe');
  final TextEditingController _emailController =
      TextEditingController(text: 'john.doe@email.com');
  final TextEditingController _phoneController =
      TextEditingController(text: '+1 (555) 123-4567');
  final TextEditingController _locationController =
      TextEditingController(text: 'San Francisco, CA');

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
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvatarSection(),
                        const SizedBox(height: 30),
                        _buildNameField(),
                        const SizedBox(height: 20),
                        _buildEmailField(),
                        const SizedBox(height: 20),
                        _buildPhoneField(),
                        const SizedBox(height: 20),
                        _buildLocationField(),
                        const SizedBox(height: 30),
                        _buildPasswordSection(),
                        const SizedBox(height: 30),
                        _buildSaveButton(),
                        const SizedBox(height: 20),
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
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Edit Profile',
            style: TextStyle(
              fontSize: 24,
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
            width: 120,
            height: 120,
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
            child: const Center(
              child: Text(
                'JD',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _showAvatarOptions,
              child: Container(
                width: 40,
                height: 40,
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
                child: const Icon(
                  Icons.camera_alt,
                  color: AppColors.white,
                  size: 20,
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
        _buildLabel('Full Name'),
        TextFormField(
          controller: _nameController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: _buildInputDecoration(
            hintText: 'Enter your full name',
            prefixIcon: Icons.person_outline,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your name';
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
        _buildLabel('Email Address'),
        TextFormField(
          controller: _emailController,
          style: const TextStyle(color: AppColors.textLight),
          keyboardType: TextInputType.emailAddress,
          decoration: _buildInputDecoration(
            hintText: 'Enter your email',
            prefixIcon: Icons.email_outlined,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid email';
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
        _buildLabel('Phone Number'),
        TextFormField(
          controller: _phoneController,
          style: const TextStyle(color: AppColors.textLight),
          keyboardType: TextInputType.phone,
          decoration: _buildInputDecoration(
            hintText: 'Enter your phone number',
            prefixIcon: Icons.phone_outlined,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your phone number';
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
        _buildLabel('Location'),
        TextFormField(
          controller: _locationController,
          style: const TextStyle(color: AppColors.textLight),
          decoration: _buildInputDecoration(
            hintText: 'Enter your location',
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
              width: 4,
              height: 20,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Security',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        GestureDetector(
          onTap: _showChangePasswordDialog,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.1),
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: AppColors.accentOrange,
                  ),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textLight,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Update your password',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.accentCyan,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: AppColors.accentCyan,
                  size: 16,
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
        onPressed: isSaving ? null : _handleSave,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.transparent,
          shadowColor: AppColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'SAVE CHANGES',
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

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
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
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: AppColors.accentCyan.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: AppColors.accentCyan,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _errorRed, width: 2),
      ),
    );
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Change Profile Picture',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.accentCyan),
              title: const Text(
                'Take Photo',
                style: TextStyle(color: AppColors.textLight),
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.accentCyan),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(color: AppColors.textLight),
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: _errorRed),
              title: const Text(
                'Remove Photo',
                style: TextStyle(color: _errorRed),
              ),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              style: const TextStyle(color: AppColors.textLight),
              decoration: InputDecoration(
                labelText: 'Current Password',
                labelStyle: const TextStyle(color: AppColors.accentCyan),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentCyan),
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              obscureText: true,
              style: const TextStyle(color: AppColors.textLight),
              decoration: InputDecoration(
                labelText: 'New Password',
                labelStyle: const TextStyle(color: AppColors.accentCyan),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentCyan),
                ),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              obscureText: true,
              style: const TextStyle(color: AppColors.textLight),
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                labelStyle: const TextStyle(color: AppColors.accentCyan),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentCyan),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.accentCyan),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _handleSave() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isSaving = true;
      });

      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() {
          isSaving = false;
        });

        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surfaceDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Success!',
              style: TextStyle(color: AppColors.textLight),
            ),
            content: const Text(
              'Your profile has been updated successfully!',
              style: TextStyle(color: AppColors.textLight),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentCyan,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      });
    }
  }
}
