import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_routes.dart';
import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/services/dtc_repository.dart';
import '../../../../../core/services/obd_service.dart';

// ── DTC view model ─────────────────────────────────────────────────────────────

class _DtcItem {
  final String code;
  final String description;
  final String system;
  final String severity;
  final bool isPending; // true = mode 07 code, not yet confirmed by ECU

  const _DtcItem({
    required this.code,
    required this.description,
    required this.system,
    required this.severity,
    this.isPending = false,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class DiagnosticCodesScreen extends StatefulWidget {
  /// Inject a custom [DtcRepository] (useful in tests to avoid real I/O).
  final DtcRepository? repository;

  const DiagnosticCodesScreen({super.key, this.repository});

  @override
  State<DiagnosticCodesScreen> createState() => _DiagnosticCodesScreenState();
}

class _DiagnosticCodesScreenState extends State<DiagnosticCodesScreen> {
  late final DtcRepository _repo = widget.repository ?? DtcRepository();

  bool _loading = false;
  bool _clearing = false;
  String? _errorMessage;
  List<_DtcItem> _dtcItems = [];
  String _selectedFilter = 'All';

  static const _filters = ['All', 'Engine', 'Chassis', 'Body', 'Network'];

  static const Color _colCritical = Color(0xFFFF1744);
  static const Color _colWarning = Color(0xFFFF6B35);
  static const Color _colInfo = Color(0xFFFFD600);

  @override
  void initState() {
    super.initState();
    _fetchDtcs();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _fetchDtcs() async {
    if (!OBDService.instance.isInitialized) {
      setState(() {
        _errorMessage = 'not_connected';
        _dtcItems = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final codes = await OBDService.instance.getDtcs();
      if (!mounted) return;

      final isArabic = Localizations.localeOf(context).languageCode == 'ar';
      final lang = isArabic ? 'ar' : 'en';

      final items = await Future.wait(codes.map((raw) async {
        // Codes prefixed with '~' are mode-07 pending codes.
        final isPending = raw.startsWith('~');
        final code = isPending ? raw.substring(1) : raw;
        final desc = await _repo.getDtcDescription(code, languageCode: lang);
        return _DtcItem(
          code: code,
          description: desc ?? code,
          system: _systemFromCode(code),
          severity: _severityFromCode(code),
          isPending: isPending,
        );
      }));

      if (!mounted) return;
      setState(() => _dtcItems = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'fetch_error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearCodes() async {
    setState(() => _clearing = true);
    final ok = await OBDService.instance.clearDtcs();
    if (!mounted) return;
    if (ok) {
      // Re-scan immediately to confirm all codes were erased.
      await _fetchDtcs();
    } else {
      setState(() => _clearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear codes – check adapter connection.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ── DTC metadata helpers ──────────────────────────────────────────────────

  String _systemFromCode(String code) {
    if (code.isEmpty) return 'Unknown';
    switch (code[0].toUpperCase()) {
      case 'P':
        return 'Engine';
      case 'C':
        return 'Chassis';
      case 'B':
        return 'Body';
      case 'U':
        return 'Network';
      default:
        return 'Unknown';
    }
  }

  String _severityFromCode(String code) {
    if (code.length < 2) return 'warning';
    // P0xxx/C0xxx/B0xxx/U0xxx = SAE standard = treat as critical
    // P1xxx/C1xxx etc = manufacturer specific = info
    final digit = code.length > 1 ? code[1] : '0';
    if (digit == '0') return 'critical';
    if (digit == '1') return 'info';
    return 'warning';
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return _colCritical;
      case 'info':
        return _colInfo;
      default:
        return _colWarning;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error;
      case 'info':
        return Icons.info;
      default:
        return Icons.warning;
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────

  List<_DtcItem> get _filtered {
    if (_selectedFilter == 'All') return _dtcItems;
    return _dtcItems.where((d) => d.system == _selectedFilter).toList();
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
              if (!_loading && _errorMessage == null) _buildSummary(),
              _buildFilters(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.accentCyan),
            onPressed: () => Navigator.pop(context),
          ),
          Flexible(
            child: Text(
              context.tr('diagnostic_codes'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
          ),
          const Spacer(),
          if (_loading || _clearing)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: SizedBox(
                width: 20.r,
                height: 20.r,
                child: CircularProgressIndicator(
                  color: AppColors.accentCyan,
                  strokeWidth: 2,
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.accentCyan),
            onPressed: _loading ? null : _fetchDtcs,
          ),
          if (_dtcItems.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_all, color: AppColors.accentCyan),
              onPressed: _clearing ? null : _showClearDialog,
            ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final confirmed = _dtcItems.where((d) => !d.isPending).length;
    final pending   = _dtcItems.where((d) =>  d.isPending).length;
    final critical  = _dtcItems.where((d) => d.severity == 'critical').length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
      padding: EdgeInsets.all(20.r),
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
            color: AppColors.accentCyan.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Confirmed', confirmed, _colCritical),
          _summaryItem('Pending',   pending,   const Color(0xFFFFD600)),
          _summaryItem('Critical',  critical,  _colWarning),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 32.sp,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        SizedBox(height: 5.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            color: AppColors.textLight.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 50.h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 5.h),
        itemCount: _filters.length,
        itemBuilder: (_, i) {
          final f = _filters[i];
          final sel = f == _selectedFilter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = f),
            child: Container(
              margin: EdgeInsets.only(right: 10.w),
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        colors: [AppColors.accentCyan, AppColors.accentOrange])
                    : null,
                color: sel ? null : AppColors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: sel
                      ? AppColors.transparent
                      : AppColors.accentCyan.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(25.r),
              ),
              child: Center(
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: sel ? AppColors.white : AppColors.textLight,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_errorMessage == 'not_connected') return _buildNotConnected();
    if (_errorMessage != null) return _buildError();
    if (_filtered.isEmpty) return _buildEmpty();
    return _buildList();
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.accentCyan),
          SizedBox(height: 20.h),
          Text(
            'Reading diagnostic codes...',
            style: TextStyle(fontSize: 14.sp, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnected() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled,
              size: 80.r, color: Colors.redAccent.withValues(alpha: 0.5)),
          SizedBox(height: 20.h),
          Text(
            'No OBD device connected',
            style: TextStyle(fontSize: 18.sp, color: AppColors.textLight),
          ),
          SizedBox(height: 10.h),
          Text(
            'Connect your ELM327 adapter first',
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.connectionscreen),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
            ),
            child: const Text('Go to Connection'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 80.r, color: Colors.redAccent.withValues(alpha: 0.5)),
          SizedBox(height: 20.h),
          Text(
            'Failed to read codes',
            style: TextStyle(fontSize: 18.sp, color: AppColors.textLight),
          ),
          SizedBox(height: 24.h),
          ElevatedButton(
            onPressed: _fetchDtcs,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 80.r,
              color: const Color(0xFF00E676).withValues(alpha: 0.5)),
          SizedBox(height: 20.h),
          Text(
            context.tr('no_codes_found'),
            style: TextStyle(fontSize: 18.sp, color: AppColors.textLight),
          ),
          SizedBox(height: 8.h),
          Text(
            'Your vehicle has no stored fault codes.',
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textLight.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: EdgeInsets.all(20.r),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _buildCodeItem(_filtered[i], i),
    );
  }

  Widget _buildCodeItem(_DtcItem item, int index) {
    final color = _severityColor(item.severity);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + index * 80),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(40 * (1 - v), 0), child: child),
      ),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.codeDetail,
          arguments: {
            'code': item.code,
            'title': item.description,
            'title_ar': item.description,
            'severity': item.severity,
            'system': item.system,
            'system_ar': item.system,
            'description': item.description,
            'description_ar': item.description,
          },
        ),
        child: Container(
          margin: EdgeInsets.only(bottom: 15.h),
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.03),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _codeChip(item.code, color),
                  SizedBox(width: 10.w),
                  _systemChip(item.system),
                  if (item.isPending) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFFFFD600)),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Text(
                        'Pending',
                        style: TextStyle(
                          fontSize: 9.sp,
                          color: const Color(0xFFFFD600),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(_severityIcon(item.severity), color: color, size: 24.r),
                ],
              ),
              SizedBox(height: 12.h),
              Text(
                item.description,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textLight.withValues(alpha: 0.85),
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 5.w),
                  Icon(Icons.arrow_forward,
                      color: AppColors.accentCyan, size: 16.r),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeChip(String code, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _systemChip(String system) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.accentCyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        system,
        style: TextStyle(
          fontSize: 11.sp,
          color: AppColors.accentCyan,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Clear codes dialog ────────────────────────────────────────────────────

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: const Text('Clear Codes?',
            style: TextStyle(color: AppColors.textLight)),
        content: const Text(
          'This will erase all fault codes and reset the MIL lamp. '
          'Emissions readiness monitors will also reset.',
          style: TextStyle(color: AppColors.textLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('cancel'),
                style: const TextStyle(color: AppColors.accentCyan)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearCodes();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
