import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/maintenance_service.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _svc = MaintenanceService.instance;
  bool _loading = true;

  /// Icon per built-in item (the service stores an emoji, which the UI no
  /// longer shows).
  static const Map<String, IconData> _itemIcons = {
    'oil': Icons.oil_barrel_outlined,
    'tires': Icons.tire_repair_rounded,
    'air': Icons.air_rounded,
    'brakes': Icons.album_outlined,
    'coolant': Icons.thermostat_rounded,
    'spark': Icons.bolt_rounded,
    'belt': Icons.settings_outlined,
  };

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
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: context.tr('maintenance_tracker')),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              _buildMileageCard(),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppSizes.space20.w,
                    AppSizes.space16.h,
                    AppSizes.space20.w,
                    AppSizes.space24.h,
                  ),
                  itemCount: _svc.items.length,
                  separatorBuilder: (_, _) =>
                      SizedBox(height: AppSizes.space12.h),
                  itemBuilder: (_, i) => _buildItemCard(_svc.items[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Mileage card ──────────────────────────────────────────────────────────

  Widget _buildMileageCard() {
    final p = context.colors;
    return AppCard(
      margin: EdgeInsets.symmetric(horizontal: AppSizes.space20.w),
      child: Row(
        children: [
          const IconBox(Icons.speed_rounded),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('current_mileage'),
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: p.text2,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${_svc.currentMileageKm.toStringAsFixed(0)} ${context.tr('unit_km')}',
                    maxLines: 1,
                    style: AppTextStyles.headline.copyWith(color: p.text),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          AppButton.ghost(
            label: context.tr('set'),
            icon: Icons.edit_outlined,
            onPressed: _showSetMileageDialog,
          ),
        ],
      ),
    );
  }

  // ── Item card ─────────────────────────────────────────────────────────────

  Widget _buildItemCard(MaintenanceItem item) {
    final p = context.colors;
    final overdue = item.isOverdue(_svc.currentMileageKm);
    final due = item.isDue(_svc.currentMileageKm);
    final hasLog = item.lastServiceDate != null;

    // Status unknown until the user logs a service — neutral icon, no badge;
    // the "Never serviced" line + Log button prompt them instead.
    final StatusLevel? status;
    final String statusText;
    if (!item.hasHistory) {
      status = null;
      statusText = '';
    } else if (overdue) {
      status = StatusLevel.critical;
      statusText = context.tr('status_overdue');
    } else if (due) {
      status = StatusLevel.warning;
      statusText = context.tr('status_due_soon');
    } else {
      status = StatusLevel.ok;
      statusText = context.tr('status_ok');
    }
    // Only due / overdue items tint their icon; OK and unknown stay neutral.
    final attention =
        status == StatusLevel.critical || status == StatusLevel.warning;
    final icon = _itemIcons[item.id] ?? Icons.build_outlined;

    final caption = AppTextStyles.label.copyWith(
      fontWeight: FontWeight.w400,
      color: p.text2,
    );
    final next = _nextService(item);

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          attention
              ? IconBox(icon, color: status!.colorOf(context))
              : IconBox.neutral(icon, size: 40),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and status pill; the pill wraps under a long name.
                Wrap(
                  spacing: AppSizes.space8.w,
                  runSpacing: AppSizes.space4.h,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _itemName(item),
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    if (status != null)
                      StatusBadge(label: statusText, level: status),
                  ],
                ),
                SizedBox(height: AppSizes.space4.h),
                Text(
                  hasLog
                      ? context
                                .tr('maint_last_service')
                                .replaceAll(
                                  '{date}',
                                  _formatDate(item.lastServiceDate!),
                                ) +
                            (item.lastMileageKm != null
                                ? ' · ${item.lastMileageKm!.toStringAsFixed(0)} ${context.tr('unit_km')}'
                                : '')
                      : context.tr('never_serviced'),
                  style: caption,
                ),
                SizedBox(height: 2.h),
                // Logged: when the next service is due. Not yet logged: the
                // interval it will be measured against.
                if (next != null)
                  Text(next, style: caption.copyWith(color: p.text))
                else
                  Text(
                    context
                        .tr('maint_interval')
                        .replaceAll('{km}', item.intervalKm.toStringAsFixed(0))
                        .replaceAll('{days}', '${item.intervalDays}'),
                    style: caption.copyWith(color: p.muted),
                  ),
              ],
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          AppButton.secondary(
            label: context.tr('log_label'),
            onPressed: () => _logService(item),
            compact: true,
            expand: false,
          ),
        ],
      ),
    );
  }

  /// "Next: 10000 km · 2026-05-01" from the last logged service, or null when
  /// nothing has been logged.
  String? _nextService(MaintenanceItem item) {
    if (!item.hasHistory) return null;
    final parts = <String>[
      if (item.lastMileageKm != null)
        '${(item.lastMileageKm! + item.intervalKm).toStringAsFixed(0)} ${context.tr('unit_km')}',
      if (item.lastServiceDate != null)
        _formatDate(
          item.lastServiceDate!.add(Duration(days: item.intervalDays)),
        ),
    ];
    return context
        .tr('maint_next_service')
        .replaceAll('{value}', parts.join(' · '));
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _logService(MaintenanceItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr('maint_log_title').replaceAll('{name}', _itemName(item)),
        ),
        content: Text(
          context
              .tr('maint_log_msg')
              .replaceAll('{km}', _svc.currentMileageKm.toStringAsFixed(0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('confirm')),
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
      text: _svc.currentMileageKm.toStringAsFixed(0),
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('set_current_mileage')),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.tr('mileage_km')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final km = double.tryParse(ctrl.text);
              if (km != null) {
                await _svc.setMileage(km);
                if (mounted) setState(() {});
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(context.tr('save')),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Localized name for a built-in item; falls back to the stored name.
  String _itemName(MaintenanceItem item) {
    final key = 'maint_item_${item.id}';
    final label = context.tr(key);
    return label == key ? item.name : label;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
