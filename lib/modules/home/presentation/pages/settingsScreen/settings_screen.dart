import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notifications = true;
  bool autoScan = false;
  bool darkMode = true;
  bool soundEffects = true;
  String language = 'English';
  String units = 'Metric';

  static const Color _dangerRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _successGreenDark = Color(0xFF00C853);

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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfileSection(),
                      const SizedBox(height: 30),
                      _buildGeneralSettings(),
                      const SizedBox(height: 30),
                      _buildPreferencesSettings(),
                      const SizedBox(height: 30),
                      _buildAboutSection(),
                      const SizedBox(height: 30),
                      _buildDangerZone(),
                      const SizedBox(height: 20),
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
            'Settings',
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

  Widget _buildProfileSection() {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, AppRoutes.profile);
      },
      child: Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accentCyan.withValues(alpha: 0.1),
              AppColors.accentOrange.withValues(alpha: 0.05),
            ],
          ),
          border: Border.all(
            color: AppColors.accentCyan.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'JD',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'John Doe',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'john.doe@email.com',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textLight.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.accentCyan),
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.profile);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('General'),
        _buildSettingToggle(
          '🔔',
          'Notifications',
          'Receive alerts for diagnostic issues',
          notifications,
          (value) => setState(() => notifications = value),
        ),
        _buildSettingToggle(
          '🔄',
          'Auto-Scan',
          'Automatically scan on connection',
          autoScan,
          (value) => setState(() => autoScan = value),
        ),
        _buildSettingToggle(
          '🌙',
          'Dark Mode',
          'Use dark theme',
          darkMode,
          (value) => setState(() => darkMode = value),
        ),
        _buildSettingToggle(
          '🔊',
          'Sound Effects',
          'Play sounds for actions',
          soundEffects,
          (value) => setState(() => soundEffects = value),
        ),
      ],
    );
  }

  Widget _buildPreferencesSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Preferences'),
        _buildSettingSelector(
          '🌐',
          'Language',
          language,
          ['English', 'العربية', 'Español', 'Français'],
          (value) => setState(() => language = value),
        ),
        _buildSettingSelector(
          '📏',
          'Units',
          units,
          ['Metric', 'Imperial'],
          (value) => setState(() => units = value),
        ),
        _buildSettingItem(
          '🚗',
          'Vehicle Profile',
          'Manage your vehicles',
          () {},
        ),
        _buildSettingItem(
          '📊',
          'Data & Privacy',
          'Manage your data preferences',
          () {},
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('About'),
        _buildSettingItem(
          'ℹ️',
          'App Version',
          'v1.0.0',
          () {},
        ),
        _buildSettingItem(
          '📄',
          'Terms of Service',
          'View terms and conditions',
          () {},
        ),
        _buildSettingItem(
          '🔒',
          'Privacy Policy',
          'How we protect your data',
          () {},
        ),
        _buildSettingItem(
          '💬',
          'Support',
          'Get help and contact us',
          () {},
        ),
      ],
    );
  }

  Widget _buildDangerZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Danger Zone'),
        GestureDetector(
          onTap: _showLogoutDialog,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _dangerRed.withValues(alpha: 0.1),
              border: Border.all(
                color: _dangerRed.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(Icons.logout, color: _dangerRed, size: 24),
                const SizedBox(width: 15),
                const Expanded(
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _dangerRed,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: _dangerRed, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle(
    String icon,
    String title,
    String subtitle,
    bool value,
    void Function(bool) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          _buildToggleSwitch(value, onChanged),
        ],
      ),
    );
  }

  Widget _buildSettingSelector(
    String icon,
    String title,
    String currentValue,
    List<String> options,
    void Function(String) onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textLight,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              _showSelectorDialog(title, currentValue, options, onChanged);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.accentCyan.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentValue,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentCyan,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.accentCyan,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    String icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textLight.withValues(alpha: 0.6),
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
    );
  }

  Widget _buildToggleSwitch(bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 60,
        height: 32,
        decoration: BoxDecoration(
          gradient: value
              ? const LinearGradient(
                  colors: [_successGreen, _successGreenDark],
                )
              : null,
          color: value ? null : AppColors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSelectorDialog(
    String title,
    String currentValue,
    List<String> options,
    void Function(String) onChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Select $title',
          style: const TextStyle(color: AppColors.textLight),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((option) {
            return ListTile(
              title: Text(
                option,
                style: const TextStyle(color: AppColors.textLight),
              ),
              trailing: option == currentValue
                  ? const Icon(Icons.check, color: AppColors.accentCyan)
                  : null,
              onTap: () {
                onChanged(option);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Logout?',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: AppColors.textLight),
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
            onPressed: () {
              Navigator.pop(context);
              // Logout logic
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _dangerRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
