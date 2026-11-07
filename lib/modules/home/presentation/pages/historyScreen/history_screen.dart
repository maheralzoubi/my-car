import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_history_service.dart';

/// The History tab root: scan totals, a filter row and one card listing every
/// logged scan, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _filter = 'All';
  bool _loading = true;

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
      case 'With Codes':
        return all.where((e) => e.hasCodes).toList();
      case 'Clean':
        return all.where((e) => !e.hasCodes).toList();
      default:
        return all;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: context.tr('history_title'),
              actions: [
                if (DtcHistoryService.instance.entries.isNotEmpty)
                  HeaderAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: context.tr('clear_all'),
                    onPressed: _confirmClear,
                  ),
              ],
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              _buildStats(),
              SizedBox(height: AppSizes.space16.h),
              _buildFilterRow(),
              Expanded(child: _buildList()),
            ],
          ],
        ),
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Widget _buildStats() {
    final all = DtcHistoryService.instance.entries;
    final withCode = all.where((e) => e.hasCodes).length;
    final clean = all.length - withCode;

    Widget tile(String label, int n) => Expanded(
      child: StatTile(label: label, value: '$n'),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.space20.w),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSizes.space12.w,
          children: [
            tile(context.tr('total_scans'), all.length),
            tile(context.tr('with_codes'), withCode),
            tile(context.tr('clean_scan'), clean),
          ],
        ),
      ),
    );
  }

  // ── Filters ───────────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return SizedBox(
      height: 44.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: AppSizes.space20.w,
          vertical: 4.h,
        ),
        itemCount: _filters.length,
        separatorBuilder: (_, _) => SizedBox(width: AppSizes.space8.w),
        itemBuilder: (_, i) {
          final f = _filters[i];
          return AppFilterChip(
            label: _trFilter(f),
            selected: f == _filter,
            onTap: () => setState(() => _filter = f),
          );
        },
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        title: context.tr('no_scan_history_yet'),
        message: context.tr('run_scan_to_log'),
      );
    }

    final p = context.colors;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSizes.space20.w,
        AppSizes.space12.h,
        AppSizes.space20.w,
        AppSizes.space24.h,
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: p.border),
                _buildEntry(items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Single history entry ──────────────────────────────────────────────────

  Widget _buildEntry(DtcHistoryEntry entry) {
    final p = context.colors;
    final hasCode = entry.hasCodes;
    final confirmed = entry.confirmedCount;
    final pending = entry.pendingCount;

    // Overall tone of the scan: any confirmed code is critical, pending-only
    // is a warning, no codes is ok.
    final StatusLevel tone = !hasCode
        ? StatusLevel.ok
        : confirmed > 0
        ? StatusLevel.critical
        : StatusLevel.warning;

    // Strip '~' from pending codes for display
    final displayCodes = entry.codes
        .map((c) => c.startsWith('~') ? c.substring(1) : c)
        .toSet()
        .toList();

    return Padding(
      padding: EdgeInsets.all(AppSizes.space16.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(tone.icon, color: tone.colorOf(context)),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Date + summary badge ─────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatDate(entry.scannedAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.numeric(
                          AppTextStyles.body,
                        ).copyWith(fontWeight: FontWeight.w600, color: p.text),
                      ),
                    ),
                    SizedBox(width: AppSizes.space8.w),
                    StatusBadge(
                      label: hasCode
                          ? (entry.codes.length == 1
                                ? context.tr('history_code_one')
                                : context
                                      .tr('history_codes_n')
                                      .replaceAll(
                                        '{n}',
                                        '${entry.codes.length}',
                                      ))
                          : context.tr('clean_scan'),
                      level: hasCode ? StatusLevel.neutral : StatusLevel.ok,
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                Text(
                  '${entry.mileageKm.toStringAsFixed(0)} ${context.tr('unit_km')}',
                  style: AppTextStyles.numeric(
                    AppTextStyles.label,
                  ).copyWith(fontWeight: FontWeight.w400, color: p.text2),
                ),
                // ── Confirmed / pending breakdown ─────────────────────────
                if (hasCode) ...[
                  SizedBox(height: AppSizes.space8.h),
                  Wrap(
                    spacing: AppSizes.space8.w,
                    runSpacing: AppSizes.space4.h,
                    children: [
                      if (confirmed > 0)
                        StatusBadge(
                          label: context
                              .tr('history_confirmed_n')
                              .replaceAll('{n}', '$confirmed'),
                          level: StatusLevel.critical,
                        ),
                      if (pending > 0)
                        StatusBadge(
                          label: context
                              .tr('history_pending_n')
                              .replaceAll('{n}', '$pending'),
                          level: StatusLevel.warning,
                        ),
                    ],
                  ),
                ],
                // ── Code chips ───────────────────────────────────────────
                if (displayCodes.isNotEmpty) ...[
                  SizedBox(height: AppSizes.space8.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: [for (final c in displayCodes) _codeChip(c)],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeChip(String code) {
    final p = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSizes.space8.w,
        vertical: 3.h,
      ),
      decoration: BoxDecoration(
        color: p.surface2,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm.r),
      ),
      child: Text(
        code,
        textDirection: TextDirection.ltr,
        style: AppTextStyles.numeric(
          AppTextStyles.label,
        ).copyWith(fontSize: 12.sp, fontWeight: FontWeight.w600, color: p.text),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _trFilter(String f) {
    switch (f) {
      case 'All':
        return context.tr('all');
      case 'With Codes':
        return context.tr('with_codes');
      case 'Clean':
        return context.tr('clean_scan');
      default:
        return f;
    }
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 0) {
      return '${context.tr('history_today')} · $time';
    } else if (diff.inDays == 1) {
      return '${context.tr('history_yesterday')} · $time';
    }
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} · $time';
  }

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('clear_history')),
        content: Text(context.tr('clear_history_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await DtcHistoryService.instance.clearHistory();
              if (mounted) setState(() {});
            },
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.colors.crit,
            ),
            child: Text(context.tr('clear_all')),
          ),
        ],
      ),
    );
  }
}
