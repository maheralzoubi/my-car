import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _successGreen = Color(0xFF00E676);
  static const Color _ratingYellow = Color(0xFFFFD600);

  final Map<String, dynamic> userProfile = {
    'name': 'John Doe',
    'email': 'john.doe@email.com',
    'phone': '+1 (555) 123-4567',
    'location': 'San Francisco, CA',
    'memberSince': 'January 2024',
    'totalScans': 47,
    'tutorialsWatched': 23,
    'savedCodes': 12,
  };

  final List<Map<String, dynamic>> vehicles = [
    {
      'name': 'Toyota Camry 2020',
      'vin': '4T1B11HK...8901',
      'mileage': '45,230 miles',
      'health': 78,
      'isPrimary': true,
    },
    {
      'name': 'Honda Civic 2018',
      'vin': '2HGFC2F5...3456',
      'mileage': '62,450 miles',
      'health': 82,
      'isPrimary': false,
    },
  ];

  String get _initials {
    final name = userProfile['name'] as String? ?? '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    return parts.take(2).map((n) => n.isNotEmpty ? n[0].toUpperCase() : '').join();
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfileCard(),
                      const SizedBox(height: 25),
                      _buildStatsSection(),
                      const SizedBox(height: 25),
                      _buildPersonalInfoSection(),
                      const SizedBox(height: 25),
                      _buildVehiclesSection(),
                      const SizedBox(height: 25),
                      _buildAchievementsSection(),
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
            'My Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.share, color: AppColors.accentCyan),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
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
                child: Center(
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _successGreen,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.backgroundDark,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.verified,
                    color: AppColors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            userProfile['name'] as String? ?? '',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            userProfile['email'] as String? ?? '',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.editProfile);
              },
              icon: const Icon(Icons.edit),
              label: const Text(
                'Edit Profile',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentCyan,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
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
                'Activity Stats',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildStatItem(
                '🔍',
                'Total Scans',
                (userProfile['totalScans'] ?? 0).toString(),
              ),
              _buildStatItem(
                '📹',
                'Videos Watched',
                (userProfile['tutorialsWatched'] ?? 0).toString(),
              ),
              _buildStatItem(
                '🔖',
                'Saved Codes',
                (userProfile['savedCodes'] ?? 0).toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String icon, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.accentCyan,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textLight.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
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
              'Personal Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        _buildInfoCard('📧', 'Email', userProfile['email'] as String? ?? ''),
        _buildInfoCard('📱', 'Phone', userProfile['phone'] as String? ?? ''),
        _buildInfoCard(
          '📍',
          'Location',
          userProfile['location'] as String? ?? '',
        ),
        _buildInfoCard(
          '📅',
          'Member Since',
          userProfile['memberSince'] as String? ?? '',
        ),
      ],
    );
  }

  Widget _buildInfoCard(String icon, String label, String value) {
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
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehiclesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  'My Vehicles',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, color: AppColors.accentCyan),
              label: const Text(
                'Add',
                style: TextStyle(color: AppColors.accentCyan),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ...vehicles.map((vehicle) => _buildVehicleCard(vehicle)).toList(),
      ],
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final isPrimary = vehicle['isPrimary'] as bool? ?? false;
    final name = vehicle['name'] as String? ?? '';
    final vin = vehicle['vin'] as String? ?? '';
    final mileage = vehicle['mileage'] as String? ?? '';
    final health = vehicle['health'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: isPrimary
              ? AppColors.accentCyan
              : AppColors.white.withValues(alpha: 0.1),
          width: isPrimary ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accentCyan, AppColors.accentOrange],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: AppColors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textLight,
                            ),
                          ),
                        ),
                        if (isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentCyan.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Primary',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentCyan,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vin,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mileage',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      mileage,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Health Score',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$health%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _successGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementsSection() {
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
              'Achievements',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildAchievementBadge('🏆', 'First Scan', true),
              _buildAchievementBadge('🔧', 'DIY Master', true),
              _buildAchievementBadge('📹', 'Video Learner', true),
              _buildAchievementBadge('⭐', 'Pro User', false),
              _buildAchievementBadge('🚗', 'Fleet Owner', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAchievementBadge(String icon, String label, bool unlocked) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked
            ? _ratingYellow.withValues(alpha: 0.1)
            : AppColors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: unlocked
              ? _ratingYellow
              : AppColors.white.withValues(alpha: 0.1),
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: unlocked ? 1.0 : 0.3,
            child: Text(icon, style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: unlocked
                  ? _ratingYellow
                  : AppColors.textLight.withValues(alpha: 0.5),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
