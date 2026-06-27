import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/services/maintenance_service.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _svc = MaintenanceService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.backgroundDark, AppColors.backgroundDarkBlue],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (_loading)
                const Expanded(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentCyan)))
              else ...[
                _buildMileageCard(),
                Expanded(
                    child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                  itemCount: _svc.items.length,
                  itemBuilder: (_, i) => _buildItemCard(_svc.items[i]),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'Maintenance Tracker',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mileage card ──────────────────────────────────────────────────────────

  Widget _buildMileageCard() {
    return Container(
      margin: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_outlined, color: AppColors.accentCyan, size: 22.r),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Mileage',
                  style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textLight.withValues(alpha: 0.6)),
                ),
                Text(
                  '${_svc.currentMileageKm.toStringAsFixed(0)} km',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentCyan,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _showSetMileageDialog,
            icon: Icon(Icons.edit, size: 15.r, color: AppColors.accentCyan),
            label: Text('Set',
                style: TextStyle(
                    fontSize: 13.sp, color: AppColors.accentCyan)),
          ),
        ],
      ),
    );
  }

  // ── Item card ─────────────────────────────────────────────────────────────

  Widget _buildItemCard(MaintenanceItem item) {
    final overdue  = item.isOverdue(_svc.currentMileageKm);
    final due      = item.isDue(_svc.currentMileageKm);
    final hasLog   = item.lastServiceDate != null;

    final Color statusColor;
    final String statusText;
    if (overdue) {
      statusColor = const Color(0xFFFF1744);
      statusText  = 'OVERDUE';
    } else if (due) {
      statusColor = const Color(0xFFFFD600);
      statusText  = 'DUE SOON';
    } else {
      statusColor = const Color(0xFF00E676);
      statusText  = 'OK';
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.03),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          // Icon + status badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Text(item.icon, style: TextStyle(fontSize: 32.sp)),
              if (overdue || due)
                Positioned(
                  top: -4, right: -6,
                  child: Container(
                    width: 10.r, height: 10.r,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textLight,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  hasLog
                      ? 'Last: ${_formatDate(item.lastServiceDate!)}  •  ${item.lastMileageKm!.toStringAsFixed(0)} km'
                      : 'Never serviced',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.textLight.withValues(alpha: 0.55),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Every ${item.intervalKm.toStringAsFixed(0)} km / ${item.intervalDays} days',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.accentCyan.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          // Log button
          GestureDetector(
            onTap: () => _logService(item),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.accentCyan.withValues(alpha: 0.1),
                border:
                    Border.all(color: AppColors.accentCyan.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                'Log',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.accentCyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _logService(MaintenanceItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Log ${item.name}?',
            style: const TextStyle(color: AppColors.textLight)),
        content: Text(
          'This will record today\'s date and '
          '${_svc.currentMileageKm.toStringAsFixed(0)} km as the last service.',
          style:
              TextStyle(color: AppColors.textLight.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.accentCyan)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _svc.logService(item.id);
      if (mounted) setState(() {});
    }
  }

  void _showSetMileageDialog() {
    final ctrl = TextEditingController(
        text: _svc.currentMileageKm.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: const Text('Set Current Mileage',
            style: TextStyle(color: AppColors.textLight)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textLight),
          decoration: const InputDecoration(
            labelText: 'Mileage (km)',
            labelStyle: TextStyle(color: AppColors.accentCyan),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.accentCyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.accentCyan)),
          ),
          ElevatedButton(
            onPressed: () async {
              final km = double.tryParse(ctrl.text);
              if (km != null) {
                await _svc.setMileage(km);
                if (mounted) setState(() {});
              }
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
