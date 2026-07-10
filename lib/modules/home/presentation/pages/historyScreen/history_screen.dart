import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_history_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const Color _colCritical = Color(0xFFFF1744);
  static const Color _colWarning  = Color(0xFFFF6B35);
  static const Color _colClean    = Color(0xFF00E676);

  String _filter = 'All';
  bool   _loading = true;

  static const _filters = ['All', 'With Codes', 'Clean'];

  @override
  void initState() {
    super.initState();
    DtcHistoryService.instance.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  List<DtcHistoryEntry> get _filtered {
    final all = DtcHistoryService.instance.entries;
    switch (_filter) {
      case 'With Codes': return all.where((e) => e.hasCodes).toList();
      case 'Clean':      return all.where((e) => !e.hasCodes).toList();
      default:           return all;
    }
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
                const Expanded(child: Center(
                  child: CircularProgressIndicator(color: AppColors.accentCyan)))
              else ...[
                _buildStats(),
                _buildFilterRow(),
                Expanded(child: _buildList()),
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
            context.tr('history_title'),
            style: TextStyle(
              fontSize: 24.sp, fontWeight: FontWeight.w700,
              color: AppColors.textLight,
            ),
          ),
          const Spacer(),
          if (DtcHistoryService.instance.entries.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.accentOrange),
              onPressed: _confirmClear,
            ),
        ],
      ),
    );
  }

  // ── Stats card ────────────────────────────────────────────────────────────

  Widget _buildStats() {
    final all      = DtcHistoryService.instance.entries;
    final withCode = all.where((e) => e.hasCodes).length;
    final clean    = all.where((e) => !e.hasCodes).length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.04),
        border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(context.tr('total_scans'), all.length, AppColors.accentCyan),
          _stat(context.tr('with_codes'),  withCode,   _colWarning),
          _stat(context.tr('clean_scan'),  clean,      _colClean),
        ],
      ),
    );
  }

  Widget _stat(String label, int n, Color color) => Column(
    children: [
      Text('$n', style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w900, color: color)),
      SizedBox(height: 4.h),
      Text(label, style: TextStyle(fontSize: 11.sp, color: AppColors.textLight.withValues(alpha: 0.7))),
    ],
  );

  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return SizedBox(
      height: 46.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        children: _filters.map((f) {
          final sel = f == _filter;
          return GestureDetector(
            onTap: () => setState(() => _filter = f),
            child: Container(
              margin: EdgeInsets.only(right: 10.w),
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: sel ? const LinearGradient(
                  colors: [AppColors.accentCyan, AppColors.accentOrange]) : null,
                color: sel ? null : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: sel ? AppColors.transparent
                              : AppColors.accentCyan.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(25.r),
              ),
              child: Center(
                child: Text(_trFilter(f), style: TextStyle(
                  fontSize: 13.sp, fontWeight: FontWeight.w600,
                  color: sel ? AppColors.white : AppColors.textLight,
                )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 70.r,
                color: AppColors.accentCyan.withValues(alpha: 0.3)),
            SizedBox(height: 16.h),
            Text(context.tr('no_scan_history_yet'),
                style: TextStyle(fontSize: 16.sp, color: AppColors.textLight)),
            SizedBox(height: 8.h),
            Text(context.tr('run_scan_to_log'),
                style: TextStyle(fontSize: 13.sp,
                    color: AppColors.textLight.withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 20.h),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildEntry(items[i], i),
    );
  }

  // ── Single history entry ──────────────────────────────────────────────────

  Widget _buildEntry(DtcHistoryEntry entry, int index) {
    final hasCode  = entry.hasCodes;
    final color    = hasCode ? _colWarning : _colClean;
    final confirmed = entry.confirmedCount;
    final pending   = entry.pendingCount;

    // Strip '~' from pending codes for display
    final displayCodes = entry.codes
        .map((c) => c.startsWith('~') ? c.substring(1) : c)
        .toSet()
        .toList();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 250 + index * 60),
      builder: (_, v, child) => Opacity(
          opacity: v, child: Transform.translate(offset: Offset(30*(1-v), 0), child: child)),
      child: Container(
        margin: EdgeInsets.only(bottom: 14.h),
        padding: EdgeInsets.all(18.r),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.03),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(18.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: date + mileage + badge ─────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDate(entry.scannedAt),
                        style: TextStyle(
                            fontSize: 13.sp, color: AppColors.accentCyan,
                            fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        '${entry.mileageKm.toStringAsFixed(0)} km',
                        style: TextStyle(
                            fontSize: 11.sp,
                            color: AppColors.textLight.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    hasCode
                        ? '${entry.codes.length} code${entry.codes.length > 1 ? 's' : ''}'
                        : context.tr('clean_scan'),
                    style: TextStyle(
                        fontSize: 11.sp, fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ],
            ),
            // ── Row 2: confirmed/pending breakdown ────────────────────────
            if (hasCode) ...[
              SizedBox(height: 10.h),
              Row(
                children: [
                  if (confirmed > 0) _pill('$confirmed confirmed', _colCritical),
                  if (confirmed > 0 && pending > 0) SizedBox(width: 6.w),
                  if (pending > 0)   _pill('$pending pending',   const Color(0xFFFFD600)),
                ],
              ),
            ],
            // ── Row 3: code chips ─────────────────────────────────────────
            if (displayCodes.isNotEmpty) ...[
              SizedBox(height: 10.h),
              Wrap(
                spacing: 6.w, runSpacing: 6.h,
                children: displayCodes.map((c) => Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.05),
                    border: Border.all(
                        color: AppColors.accentCyan.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(c,
                      style: TextStyle(
                          fontSize: 11.sp, fontWeight: FontWeight.w700,
                          color: AppColors.accentCyan)),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6.r),
    ),
    child: Text(text,
        style: TextStyle(fontSize: 10.sp, color: color, fontWeight: FontWeight.w600)),
  );

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _trFilter(String f) {
    switch (f) {
      case 'All':        return context.tr('all');
      case 'With Codes': return context.tr('with_codes');
      case 'Clean':      return context.tr('clean_scan');
      default:           return f;
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) {
      return 'Today  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}  '
        '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.r)),
        title: Text(context.tr('clear_history'),
            style: const TextStyle(color: AppColors.textLight)),
        content: Text(
          context.tr('clear_history_content'),
          style: const TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel'),
                style: const TextStyle(color: AppColors.accentCyan)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await DtcHistoryService.instance.clearHistory();
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text(context.tr('clear_all')),
          ),
        ],
      ),
    );
  }
}
