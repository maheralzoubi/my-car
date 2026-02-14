import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String selectedFilter = 'All';

  static const Color _criticalRed = Color(0xFFFF1744);
  static const Color _successGreen = Color(0xFF00E676);

  late List<Map<String, dynamic>> _scanHistory;

  @override
  void initState() {
    super.initState();
    _scanHistory = [
      {
        'date': 'Today, 2:30 PM',
        'result': '2 codes detected',
        'status': 'warning',
        'codes': ['P0420', 'C1201'],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Yesterday, 10:15 AM',
        'result': 'No issues found',
        'status': 'success',
        'codes': [],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Jan 28, 4:20 PM',
        'result': '1 code detected',
        'status': 'warning',
        'codes': ['P0171'],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Jan 25, 9:00 AM',
        'result': 'No issues found',
        'status': 'success',
        'codes': [],
        'vehicle': 'Toyota Camry 2020',
      },
      {
        'date': 'Jan 20, 3:45 PM',
        'result': '3 codes detected',
        'status': 'critical',
        'codes': ['P0420', 'P0171', 'U0100'],
        'vehicle': 'Toyota Camry 2020',
      },
    ];
  }

  final List<String> filters = ['All', 'Critical', 'Warning', 'Success'];

  List<Map<String, dynamic>> get filteredHistory {
    if (selectedFilter == 'All') {
      return _scanHistory;
    }
    return _scanHistory
        .where((scan) =>
            scan['status'].toString().toLowerCase() ==
            selectedFilter.toLowerCase())
        .toList();
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'critical':
        return _criticalRed;
      case 'warning':
        return AppColors.accentOrange;
      case 'success':
        return _successGreen;
      default:
        return AppColors.accentCyan;
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
              _buildStats(),
              _buildFilters(),
              Expanded(
                child: _buildHistoryList(),
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
            'Scan History',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.accentOrange),
            onPressed: _showClearHistoryDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final total = _scanHistory.length;
    final critical =
        _scanHistory.where((s) => s['status'] == 'critical').length;
    final warning = _scanHistory.where((s) => s['status'] == 'warning').length;
    final success = _scanHistory.where((s) => s['status'] == 'success').length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Total', total, AppColors.accentCyan),
              _buildStatItem('Critical', critical, _criticalRed),
              _buildStatItem('Warning', warning, AppColors.accentOrange),
              _buildStatItem('Clean', success, _successGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
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
              setState(() => selectedFilter = filter);
            },
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [AppColors.accentCyan, AppColors.accentOrange],
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

  Widget _buildHistoryList() {
    final history = filteredHistory;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 80,
              color: AppColors.accentCyan.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 20),
            const Text(
              'No scans found',
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
      itemCount: history.length,
      itemBuilder: (context, index) {
        return _buildHistoryItem(history[index], index);
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> scan, int index) {
    final statusColor = getStatusColor(scan['status'] as String);
    final codes = scan['codes'] as List<dynamic>? ?? [];

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
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.03),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scan['date'] as String? ?? '—',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.accentCyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        scan['vehicle'] as String? ?? '—',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textLight.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    border: Border.all(color: statusColor),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    scan['status'] == 'success'
                        ? 'Clean'
                        : '${codes.length} Code${codes.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              scan['result'] as String? ?? '—',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textLight,
              ),
            ),
            if (codes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: codes.map<Widget>((code) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: AppColors.accentCyan.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      code.toString(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentCyan,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // View details
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Details',
                        style: TextStyle(
                          color: AppColors.accentCyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(width: 5),
                      Icon(
                        Icons.arrow_forward,
                        color: AppColors.accentCyan,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Clear History?',
          style: TextStyle(color: AppColors.textLight),
        ),
        content: const Text(
          'Are you sure you want to clear all scan history? This action cannot be undone.',
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
              setState(() => _scanHistory.clear());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
