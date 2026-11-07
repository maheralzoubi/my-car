import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../../core/core.dart';
import '../../../../../core/localization/app_localizations.dart';
import 'dtc_code_info.dart';

class CodeDetailScreen extends StatefulWidget {
  const CodeDetailScreen({super.key, required this.code});

  /// Route arguments: `code`, `title`, `description`, `system`, `severity`
  /// (+ optional `title_ar`, `description_ar`, `system_ar`), `pending`
  /// (true for a mode-07 code the ECU has not confirmed yet) and optional
  /// `freeze_frame` (already-localized label → value snapshot).
  final Map<String, dynamic> code;

  @override
  State<CodeDetailScreen> createState() => _CodeDetailScreenState();
}

class _CodeDetailScreenState extends State<CodeDetailScreen> {
  /// The shared [StatusLevel] for this code's severity, or null when the
  /// caller passed none / an unknown one.
  StatusLevel? get _severityLevel => switch (widget.code['severity']) {
    'critical' => StatusLevel.critical,
    'warning' => StatusLevel.warning,
    'info' => StatusLevel.info,
    _ => null,
  };

  /// Severity tone; the accent when the severity is unknown.
  Color getSeverityColor() =>
      _severityLevel?.colorOf(context) ?? context.colors.primary;

  // ── Argument accessors ────────────────────────────────────────────────────

  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  /// The localized field [key], falling back to the English one.
  String? _field(String key) {
    final v = _isArabic
        ? (widget.code['${key}_ar'] ?? widget.code[key])
        : widget.code[key];
    final s = (v as String?)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? get _codeStr {
    final raw = (widget.code['code'] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('~') ? raw.substring(1) : raw;
  }

  /// null when the caller did not say (e.g. opened from a lookup).
  bool? get _isPending => widget.code['pending'] as bool?;

  String get _title => _field('title') ?? '—';

  /// The description, unless it only repeats the title.
  String? get _description {
    final d = _field('description');
    if (d == null) return _field('title') == null ? '—' : null;
    return d == _field('title') ? null : d;
  }

  DtcCodeInfo get _info => DtcCodeInfo(_codeStr ?? '');

  Map<String, String> get _freezeFrame {
    final raw = widget.code['freeze_frame'];
    if (raw is! Map) return const {};
    return {for (final e in raw.entries) '${e.key}': '${e.value}'};
  }

  // ── Share ─────────────────────────────────────────────────────────────────

  Future<void> _share(BuildContext buttonContext) async {
    final code = _codeStr ?? context.tr('diagnostic_code_fallback');
    final info = _info;
    final buf = StringBuffer('$code — $_title');
    final desc = _description;
    if (desc != null && desc != '—') buf.write('\n$desc');
    if (info.categoryKey != null) {
      buf.write(
        '\n${context.tr('dtc_category_label')}: '
        '${context.tr(info.categoryKey!)}',
      );
    }
    if (info.typeKey != null) {
      buf.write(
        '\n${context.tr('dtc_type_label')}: '
        '${context.tr(info.typeKey!)}',
      );
    }
    if (info.subsystemKey != null) {
      buf.write(
        '\n${context.tr('dtc_subsystem_label')}: '
        '${context.tr(info.subsystemKey!)}',
      );
    }
    if (_isPending != null) {
      buf.write(
        '\n${context.tr('dtc_status_label')}: ${context.tr(_isPending! ? 'dtc_status_pending' : 'dtc_status_confirmed')}',
      );
    }
    buf.write('\n\n${context.tr('report_generated_by')}');

    final box = buttonContext.findRenderObject() as RenderBox?;
    await Share.share(
      buf.toString(),
      subject: '$code — $_title',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: context.tr('code_details'),
              actions: [
                Builder(
                  builder: (buttonContext) => HeaderAction(
                    icon: Icons.share_outlined,
                    tooltip: context.tr('dtc_share_code'),
                    onPressed: () => _share(buttonContext),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppSizes.space20.w,
                  AppSizes.space8.h,
                  AppSizes.space20.w,
                  AppSizes.space24.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSizes.space24.h,
                  children: [
                    _buildCodeCard(),
                    _buildDetailsSection(),
                    if (_freezeFrame.isNotEmpty) _buildFreezeFrame(),
                    _buildNextSteps(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSizes.space20.w,
                AppSizes.space8.h,
                AppSizes.space20.w,
                AppSizes.space12.h,
              ),
              child: AppButton(
                label: context.tr('view_solution'),
                icon: Icons.build_outlined,
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppRoutes.solution,
                  arguments: widget.code,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Code, severity / pending badges, title and description.
  Widget _buildCodeCard() {
    final p = context.colors;
    final level = _severityLevel;
    final description = _description;
    return AppCard(
      padding: EdgeInsets.all(AppSizes.space20.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBox(
                level?.icon ?? Icons.info_outline_rounded,
                key: const ValueKey('dtc_severity_icon'),
                color: getSeverityColor(),
                size: 48,
              ),
              SizedBox(width: AppSizes.space12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _codeStr ?? '—',
                      style: AppTextStyles.headline.copyWith(color: p.text),
                    ),
                    if (level != null || _isPending == true) ...[
                      SizedBox(height: AppSizes.space4.h),
                      Wrap(
                        spacing: AppSizes.space8.w,
                        runSpacing: AppSizes.space4.h,
                        children: [
                          if (level != null)
                            StatusBadge(
                              label: context.tr(
                                'severity_${widget.code['severity']}',
                              ),
                              level: level,
                            ),
                          if (_isPending == true)
                            StatusBadge(
                              label: context.tr('dtc_pending'),
                              level: StatusLevel.info,
                              icon: Icons.hourglass_empty_rounded,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space16.h),
          Text(_title, style: AppTextStyles.title.copyWith(color: p.text)),
          if (description != null) ...[
            SizedBox(height: AppSizes.space8.h),
            Text(
              description,
              style: AppTextStyles.body.copyWith(color: p.text2),
            ),
          ],
        ],
      ),
    );
  }

  /// Facts derived from the code itself (SAE J2012 structure) plus the
  /// status reported by the ECU — nothing guessed about the root cause.
  Widget _buildDetailsSection() {
    final info = _info;
    final pending = _isPending;
    final rows = <Widget>[
      _detailRow(
        Icons.directions_car_outlined,
        context.tr('dtc_system_label'),
        _field('system') ?? '—',
      ),
      if (pending != null)
        _detailRow(
          pending ? Icons.hourglass_empty_rounded : Icons.push_pin_outlined,
          context.tr('dtc_status_label'),
          context.tr(pending ? 'dtc_status_pending' : 'dtc_status_confirmed'),
        ),
      if (info.categoryKey != null)
        _detailRow(
          Icons.category_outlined,
          context.tr('dtc_category_label'),
          context.tr(info.categoryKey!),
        ),
      if (info.typeKey != null)
        _detailRow(
          info.isManufacturerSpecific
              ? Icons.factory_outlined
              : Icons.menu_book_outlined,
          context.tr('dtc_type_label'),
          context.tr(info.typeKey!),
        ),
      if (info.subsystemKey != null)
        _detailRow(
          Icons.manage_search_rounded,
          context.tr('dtc_subsystem_label'),
          context.tr(info.subsystemKey!),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionTitle(context.tr('what_this_means')), _rowsCard(rows)],
    );
  }

  /// [rows] in one card, separated by hairlines.
  Widget _rowsCard(List<Widget> rows) {
    final divider = Divider(
      height: 1,
      thickness: 1,
      color: context.colors.border,
    );
    return AppCard(
      padding: EdgeInsets.symmetric(horizontal: AppSizes.space16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) divider,
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final p = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSizes.space12.h),
      child: Row(
        children: [
          IconBox.neutral(icon, size: 36),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.label.copyWith(color: p.text2),
                ),
                SizedBox(height: 2.h),
                Text(
                  value,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w500,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sensor snapshot the ECU stored when the fault was set.
  Widget _buildFreezeFrame() {
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('freeze_frame_title')),
        _rowsCard([
          for (final e in _freezeFrame.entries)
            Padding(
              padding: EdgeInsets.symmetric(vertical: AppSizes.space12.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: AppTextStyles.body.copyWith(color: p.text2),
                    ),
                  ),
                  SizedBox(width: AppSizes.space12.w),
                  Text(
                    e.value,
                    style: AppTextStyles.numeric(
                      AppTextStyles.body,
                    ).copyWith(fontWeight: FontWeight.w600, color: p.text),
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }

  Widget _buildNextSteps() {
    final p = context.colors;
    final steps = _info.nextStepKeys(isPending: _isPending ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('dtc_next_steps')),
        AppCard(
          child: Column(
            spacing: AppSizes.space12.h,
            children: [
              for (final step in steps)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2.h),
                      child: Icon(
                        step == 'dtc_step_stop'
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18.r,
                        color: step == 'dtc_step_stop'
                            ? StatusLevel.warning.colorOf(context)
                            : p.primary,
                      ),
                    ),
                    SizedBox(width: AppSizes.space12.w),
                    Expanded(
                      child: Text(
                        context.tr(step),
                        style: AppTextStyles.body.copyWith(color: p.text),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
