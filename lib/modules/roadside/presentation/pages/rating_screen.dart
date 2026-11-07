import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import '../widgets/roadside_visuals.dart';
import 'roadside_error_snackbar.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen>
    with SingleTickerProviderStateMixin {
  int _stars = 0;
  bool _submitting = false;
  final _reviewCtrl = TextEditingController();
  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _checkScale = CurvedAnimation(
      parent: _checkCtrl,
      curve: Curves.easeOutBack,
    );
    _checkCtrl.forward();
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    // The listener resets and leaves once the rating is saved (phase done),
    // so a failed rating keeps the user here with an error.
    setState(() => _submitting = true);
    context.read<RoadsideBloc>().add(
      SubmitRating(
        _stars == 0 ? 5 : _stars,
        _reviewCtrl.text.isEmpty ? null : _reviewCtrl.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoadsideBloc, RoadsideState>(
      listener: (context, state) {
        if (state.phase == RoadsidePhase.done) {
          context.read<RoadsideBloc>().add(const ResetFlow());
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else if (state.error != null) {
          setState(() => _submitting = false);
          showRoadsideError(context, state.error!);
        }
      },
      builder: (context, state) {
        final p = context.colors;
        final driver = state.activeRequest?.assignedDriver;
        final service = state.selectedService;
        final price = state.activeRequest?.displayPrice ?? 0;
        final cashCollected = state.activeRequest?.cashCollected ?? false;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.space20.w,
                      AppSizes.space32.h,
                      AppSizes.space20.w,
                      AppSizes.space24.h,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Success check
                        Center(
                          child: ScaleTransition(
                            scale: _checkScale,
                            child: Container(
                              width: 80.r,
                              height: 80.r,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: p.okSoft,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                color: p.ok,
                                size: 40.r,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: AppSizes.space16.h),
                        Text(
                          'Service Completed!',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.headline.copyWith(color: p.text),
                        ),
                        SizedBox(height: AppSizes.space8.h),
                        Text(
                          'Your ${service?.label ?? 'roadside'} service\nhas been successfully completed.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(color: p.text2),
                        ),
                        SizedBox(height: AppSizes.space24.h),

                        // Receipt
                        AppCard(
                          child: Column(
                            children: [
                              _ReceiptRow(
                                label: 'Service',
                                value: Text(service?.label ?? '—'),
                              ),
                              SizedBox(height: AppSizes.space12.h),
                              _ReceiptRow(
                                label: 'Amount',
                                value: Text('\$${price.toStringAsFixed(2)}'),
                              ),
                              SizedBox(height: AppSizes.space12.h),
                              const _ReceiptRow(
                                label: 'Payment',
                                value: Text('Cash'),
                              ),
                              SizedBox(height: AppSizes.space12.h),
                              _ReceiptRow(
                                label: 'Status',
                                value: cashCollected
                                    ? const StatusBadge(
                                        label: 'Paid',
                                        level: StatusLevel.ok,
                                        showIcon: true,
                                      )
                                    : const StatusBadge(
                                        label: 'Pending',
                                        level: StatusLevel.neutral,
                                      ),
                              ),
                            ],
                          ),
                        ),

                        // Driver rating
                        if (driver != null) ...[
                          SizedBox(height: AppSizes.space16.h),
                          AppCard(
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24.r,
                                      backgroundColor: p.primarySoft,
                                      child: Text(
                                        driver.avatarInitials,
                                        style: AppTextStyles.body.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: p.primary,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: AppSizes.space12.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            driver.name,
                                            style: AppTextStyles.body.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: p.text,
                                            ),
                                          ),
                                          Text(
                                            driver.vehicleType,
                                            style: AppTextStyles.label.copyWith(
                                              color: p.text2,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Divider(
                                  color: p.border,
                                  height: AppSizes.space32.h,
                                ),
                                Text(
                                  context.tr('how_was_experience'),
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.title.copyWith(
                                    color: p.text,
                                  ),
                                ),
                                SizedBox(height: AppSizes.space8.h),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(5, (i) {
                                    final filled = i < _stars;
                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          setState(() => _stars = i + 1),
                                      child: Padding(
                                        padding: EdgeInsets.all(
                                          AppSizes.space4.r,
                                        ),
                                        child: Icon(
                                          filled
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          color: filled
                                              ? RoadsideVisuals.ratingStar
                                              : p.muted,
                                          size: 40.r,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                                if (_stars > 0) ...[
                                  SizedBox(height: AppSizes.space4.h),
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
                                    style: AppTextStyles.label.copyWith(
                                      color: p.text2,
                                    ),
                                  ),
                                ],
                                SizedBox(height: AppSizes.space16.h),
                                // Fill, border and colors come from the app's
                                // input theme.
                                TextField(
                                  controller: _reviewCtrl,
                                  maxLines: 2,
                                  style: AppTextStyles.body,
                                  decoration: const InputDecoration(
                                    hintText: 'Leave a review (optional)...',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Pinned; snackbars float above it instead of covering it.
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.space20.w,
                AppSizes.space8.h,
                AppSizes.space20.w,
                AppSizes.space16.h,
              ),
              child: AppButton(
                label: _stars > 0 ? 'Submit Rating' : 'Skip & Done',
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
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

  /// A [Text] (styled here) or a [StatusBadge].
  final Widget value;

  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.body.copyWith(color: p.text2),
          ),
        ),
        DefaultTextStyle.merge(
          style: AppTextStyles.numeric(
            AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          child: value,
        ),
      ],
    );
  }
}
