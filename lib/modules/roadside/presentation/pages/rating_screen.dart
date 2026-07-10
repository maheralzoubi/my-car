import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen>
    with SingleTickerProviderStateMixin {
  int _stars = 0;
  final _reviewCtrl = TextEditingController();
  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkScale = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);
    _checkCtrl.forward();
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    context
        .read<RoadsideBloc>()
        .add(SubmitRating(_stars == 0 ? 5 : _stars, _reviewCtrl.text.isEmpty ? null : _reviewCtrl.text));
    context.read<RoadsideBloc>().add(const ResetFlow());
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoadsideBloc, RoadsideState>(
      builder: (context, state) {
        final driver = state.activeRequest?.assignedDriver;
        final service = state.selectedService;
        final color = service?.color ?? AppColors.accentOrange;
        final price = state.activeRequest?.estimatedPrice ?? 0;

        return Scaffold(
          backgroundColor: AppColors.backgroundDark,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 32.h),
              child: Column(
                children: [
                  // Success check
                  ScaleTransition(
                    scale: _checkScale,
                    child: Container(
                      width: 96.r,
                      height: 96.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.success.withValues(alpha: 0.15),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.5),
                            width: 2),
                      ),
                      child: Icon(Icons.check_rounded,
                          color: AppColors.success, size: 48.r),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    'Service Completed!',
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 22.sp,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Your ${service?.label ?? 'roadside'} service\nhas been successfully completed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textLight.withValues(alpha: 0.6),
                        fontSize: 13.sp),
                  ),

                  SizedBox(height: 24.h),

                  // Receipt card
                  Container(
                    padding: EdgeInsets.all(16.r),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDarkElevated,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        _ReceiptRow(label: 'Service', value: service?.label ?? '—'),
                        SizedBox(height: 8.h),
                        _ReceiptRow(
                            label: 'Amount',
                            value: '\$${(price + 5).toStringAsFixed(0)}',
                            valueColor: color),
                        SizedBox(height: 8.h),
                        _ReceiptRow(label: 'Payment', value: 'Cash'),
                        SizedBox(height: 8.h),
                        _ReceiptRow(
                            label: 'Status',
                            value: '✓ Paid',
                            valueColor: AppColors.success),
                      ],
                    ),
                  ),

                  SizedBox(height: 24.h),

                  // Driver rating
                  if (driver != null) ...[
                    Container(
                      padding: EdgeInsets.all(16.r),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDarkElevated,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24.r,
                                backgroundColor: color.withValues(alpha: 0.2),
                                child: Text(driver.avatarInitials,
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 14.sp,
                                        fontWeight: FontWeight.bold)),
                              ),
                              SizedBox(width: 12.w),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(driver.name,
                                      style: TextStyle(
                                          color: AppColors.white,
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w600)),
                                  Text(driver.vehicleType,
                                      style: TextStyle(
                                          color: AppColors.textLight
                                              .withValues(alpha: 0.5),
                                          fontSize: 12.sp)),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 16.h),
                          Text(context.tr('how_was_experience'),
                              style: TextStyle(
                                  color: AppColors.textLight, fontSize: 13.sp)),
                          SizedBox(height: 12.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (i) {
                              final filled = i < _stars;
                              return GestureDetector(
                                onTap: () => setState(() => _stars = i + 1),
                                child: Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 4.w),
                                  child: Icon(
                                    filled
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    color: filled
                                        ? const Color(0xFFFFD700)
                                        : AppColors.outline,
                                    size: 40.r,
                                  ),
                                ),
                              );
                            }),
                          ),
                          if (_stars > 0) ...[
                            SizedBox(height: 8.h),
                            Text(
                              _stars == 5
                                  ? 'Excellent!'
                                  : _stars == 4
                                      ? 'Great!'
                                      : _stars == 3
                                          ? 'Good'
                                          : _stars == 2
                                              ? 'Fair'
                                              : 'Poor',
                              style: TextStyle(
                                  color: const Color(0xFFFFD700),
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                          SizedBox(height: 16.h),
                          TextField(
                            controller: _reviewCtrl,
                            maxLines: 2,
                            style: TextStyle(
                                color: AppColors.white, fontSize: 13.sp),
                            decoration: InputDecoration(
                              hintText: 'Leave a review (optional)...',
                              hintStyle: TextStyle(
                                  color: AppColors.textLight
                                      .withValues(alpha: 0.4),
                                  fontSize: 13.sp),
                              filled: true,
                              fillColor:
                                  AppColors.backgroundDark.withValues(alpha: 0.5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.r),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 24.h),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentOrange,
                        foregroundColor: AppColors.white,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r)),
                      ),
                      child: Text(
                        _stars > 0 ? 'Submit Rating' : 'Skip & Done',
                        style: TextStyle(
                            fontSize: 15.sp, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReceiptRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.textLight.withValues(alpha: 0.6),
                fontSize: 13.sp)),
        Text(value,
            style: TextStyle(
                color: valueColor ?? AppColors.white,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
