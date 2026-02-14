import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';

class DiagnosticCodesScreen extends StatefulWidget {
  const DiagnosticCodesScreen({super.key});

  @override
  State<DiagnosticCodesScreen> createState() => _DiagnosticCodesScreenState();
}

class _DiagnosticCodesScreenState extends State<DiagnosticCodesScreen> {
  String selectedFilter = 'All';

  final List<Map<String, dynamic>> diagnosticCodes = [
    {
      'code': 'P0420',
      'title': 'Catalyst System Efficiency Below Threshold',
      'severity': 'critical',
      'system': 'Engine',
      'description':
          'Bank 1 catalytic converter is not working efficiently',
    },
    {
      'code': 'P0171',
      'title': 'System Too Lean (Bank 1)',
      'severity': 'warning',
      'system': 'Engine',
      'description':
          'Engine is running with too much air or not enough fuel',
    },
    {
      'code': 'C1201',
      'title': 'ABS Control Module Malfunction',
      'severity': 'critical',
      'system': 'ABS',
      'description':
          'Anti-lock brake system control module has detected a fault',
    },
    {
      'code': 'U0100',
      'title': 'Lost Communication with ECM/PCM',
      'severity': 'warning',
      'system': 'Transmission',
      'description': 'Communication lost with engine control module',
    },
    {
      'code': 'P0301',
      'title': 'Cylinder 1 Misfire Detected',
      'severity': 'info',
      'system': 'Engine',
      'description': 'Engine cylinder 1 is not firing properly',
    },
  ];

  final List<String> filters = ['All', 'Engine', 'ABS', 'Transmission'];

  List<Map<String, dynamic>> get filteredCodes {
    if (selectedFilter == 'All') {
      return diagnosticCodes;
    }
    return diagnosticCodes
        .where((code) => code['system'] == selectedFilter)
        .toList();
  }

  static const Color _severityCritical = Color(0xFFFF1744);
  static const Color _severityWarning = Color(0xFFFF6B35);
  static const Color _severityInfo = Color(0xFFFFD600);

  Color getSeverityColor(String severity) {
    switch (severity) {
      case 'critical':
        return _severityCritical;
      case 'warning':
        return _severityWarning;
      case 'info':
        return _severityInfo;
      default:
        return AppColors.accentCyan;
    }
  }

  IconData getSeverityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error;
      case 'warning':
        return Icons.warning;
      case 'info':
        return Icons.info;
      default:
        return Icons.check_circle;
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
              _buildSummary(),
              _buildFilters(),
              Expanded(
                child: _buildCodesList(),
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
            'Diagnostic Codes',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.clear_all, color: AppColors.accentCyan),
            onPressed: _showClearCodesDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final critical =
        diagnosticCodes.where((c) => c['severity'] == 'critical').length;
    final warning =
        diagnosticCodes.where((c) => c['severity'] == 'warning').length;
    final info = diagnosticCodes.where((c) => c['severity'] == 'info').length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.white.withValues(alpha: 0.05),
            AppColors.white.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(
          color: AppColors.accentCyan.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Critical', critical, _severityCritical),
          _buildSummaryItem('Warning', warning, _severityWarning),
          _buildSummaryItem('Info', info, _severityInfo),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textLight.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedFilter = filter;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [
                          AppColors.accentCyan,
                          AppColors.accentOrange,
                        ],
                      )
                    : null,
                color: isSelected ? null : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: isSelected
                      ? AppColors.transparent
                      : AppColors.accentCyan.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.white
                        : AppColors.textLight,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCodesList() {
    final codes = filteredCodes;

    if (codes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: const Color(0xFF00E676).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            const Text(
              'No codes found',
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textLight,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: codes.length,
      itemBuilder: (context, index) {
        final code = codes[index];
        return _buildCodeItem(code, index);
      },
    );
  }

  Widget _buildCodeItem(Map<String, dynamic> code, int index) {
    final severityColor = getSeverityColor(code['severity'] as String);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(50 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.codeDetail,
            arguments: code,
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: severityColor.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.2),
                      border: Border.all(color: severityColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      code['code'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: severityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentCyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      code['system'] as String,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.accentCyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    getSeverityIcon(code['severity'] as String),
                    color: severityColor,
                    size: 24,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                code['title'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                code['description'] as String,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textLight.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  const Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.arrow_forward,
                    color: AppColors.accentCyan,
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearCodesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Clear Codes?',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: const Text(
          'Are you sure you want to clear all diagnostic codes? This action cannot be undone.',
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
              // Clear codes logic
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
