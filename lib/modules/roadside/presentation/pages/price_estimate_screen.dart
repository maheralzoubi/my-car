import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import 'roadside_error_snackbar.dart';
import 'searching_driver_screen.dart';

class PriceEstimateScreen extends StatefulWidget {
  const PriceEstimateScreen({super.key});

  @override
  State<PriceEstimateScreen> createState() => _PriceEstimateScreenState();
}

class _PriceEstimateScreenState extends State<PriceEstimateScreen> {
  final _notesCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final xFile =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (xFile != null && mounted) {
      context.read<RoadsideBloc>().add(AddPhotoPath(xFile.path));
    }
  }

  void _submit(RoadsideState state) {
    if (_notesCtrl.text.isNotEmpty) {
      context.read<RoadsideBloc>().add(UpdateNotes(_notesCtrl.text));
    }
    context.read<RoadsideBloc>().add(const SubmitRequest());
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchingDriverScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoadsideBloc, RoadsideState>(
      listener: (context, state) {
        if (state.phase == RoadsidePhase.idle) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else if (state.phase == RoadsidePhase.estimate && state.error != null) {
          showRoadsideError(context, state.error!);
        }
      },
      child: BlocBuilder<RoadsideBloc, RoadsideState>(
        builder: (context, state) {
          // ResetFlow / CancelRequest clear the service while this screen is
          // still mounted under searching/tracking; the idle listener above
          // pops it, so draw nothing for that last frame instead of crashing.
          final service = state.selectedService;
          if (service == null) return const SizedBox.shrink();
          final price = state.estimatedPrice ?? service.basePrice;
          final color = service.color;

          return Scaffold(
            backgroundColor: AppColors.backgroundDark,
            appBar: AppBar(
              backgroundColor: AppColors.backgroundDark,
              foregroundColor: AppColors.white,
              title: Text(context.tr('service_details'),
                  style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.bold)),
              elevation: 0,
            ),
            body: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceSummaryCard(
                      service: service, color: color, price: price),
                  SizedBox(height: 16.h),
                  _LocationCard(address: state.customerAddress),
                  SizedBox(height: 16.h),
                  _PriceBreakdownCard(
                      service: service, totalPrice: price, color: color),
                  SizedBox(height: 16.h),
                  _NotesField(controller: _notesCtrl),
                  SizedBox(height: 16.h),
                  _PhotosSection(
                    paths: state.photoPaths,
                    // The bloc ignores photos past the limit.
                    onAdd: state.photoPaths.length < RoadsideState.maxPhotos
                        ? _addPhoto
                        : null,
                  ),
                  SizedBox(height: 24.h),
                  _RequestButton(
                    color: color,
                    price: price,
                    isSubmitting: state.isSubmitting,
                    onTap: () => _submit(state),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ServiceSummaryCard extends StatelessWidget {
  final ServiceType service;
  final Color color;
  final double price;

  const _ServiceSummaryCard({
    required this.service,
    required this.color,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 56.r,
            height: 56.r,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
              ),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(service.icon, color: color, size: 28.r),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.label,
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4.h),
                Text(service.description,
                    style: TextStyle(
                        color: AppColors.textLight.withValues(alpha: 0.6),
                        fontSize: 12.sp)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      color: AppColors.accentCyan, size: 14.r),
                  SizedBox(width: 4.w),
                  Text('~${service.etaMinutes} min',
                      style: TextStyle(
                          color: AppColors.accentCyan, fontSize: 12.sp)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final String address;
  const _LocationCard({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded,
              color: AppColors.accentOrange, size: 22.r),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('your_location'),
                    style: TextStyle(
                        color: AppColors.textLight.withValues(alpha: 0.6),
                        fontSize: 11.sp)),
                SizedBox(height: 2.h),
                Text(address,
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBreakdownCard extends StatelessWidget {
  final ServiceType service;
  final double totalPrice;
  final Color color;

  const _PriceBreakdownCard({
    required this.service,
    required this.totalPrice,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final distanceFee = totalPrice - service.basePrice;

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('price_estimate_label'),
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 12.h),
          _PriceLine(
              label: 'Base service fee',
              value: '\$${service.basePrice.toStringAsFixed(0)}'),
          SizedBox(height: 8.h),
          _PriceLine(
              label: 'Distance fee',
              value: '\$${distanceFee.toStringAsFixed(0)}'),
          SizedBox(height: 8.h),
          _PriceLine(
              label: 'Platform fee',
              value: '\$5'),
          Divider(color: AppColors.outline.withValues(alpha: 0.4), height: 24.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.tr('total_estimate'),
                  style: TextStyle(
                      color: AppColors.white,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold)),
              Text('\$${(totalPrice + 5).toStringAsFixed(0)}',
                  style: TextStyle(
                      color: color,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.payments_rounded,
                    color: AppColors.success, size: 14.r),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(context.tr('cash_payment'),
                      style: TextStyle(
                          color: AppColors.success, fontSize: 11.sp)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final String value;
  const _PriceLine({required this.label, required this.value});

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
            style: TextStyle(color: AppColors.textLight, fontSize: 13.sp)),
      ],
    );
  }
}

class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: TextField(
        controller: controller,
        maxLines: 3,
        style: TextStyle(color: AppColors.white, fontSize: 13.sp),
        decoration: InputDecoration(
          hintText: 'Add notes (e.g. car model, issue description)...',
          hintStyle: TextStyle(
              color: AppColors.textLight.withValues(alpha: 0.4), fontSize: 13.sp),
          prefixIcon: Icon(Icons.notes_rounded,
              color: AppColors.accentCyan, size: 20.r),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }
}

class _PhotosSection extends StatelessWidget {
  final List<String> paths;
  final VoidCallback? onAdd;

  const _PhotosSection({required this.paths, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.tr('photos'),
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold)),
            if (onAdd != null)
              TextButton.icon(
                onPressed: onAdd,
                icon: Icon(Icons.add_a_photo_rounded,
                    color: AppColors.accentCyan, size: 16.r),
                label: Text(context.tr('add'),
                    style: TextStyle(
                        color: AppColors.accentCyan, fontSize: 13.sp)),
              ),
          ],
        ),
        if (paths.isNotEmpty)
          SizedBox(
            height: 80.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, __) => SizedBox(width: 8.w),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(10.r),
                // Camera captures are files on the device, not bundled assets.
                child: Image.file(
                  File(paths[i]),
                  width: 80.w,
                  height: 80.h,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80.w,
                    height: 80.h,
                    color: AppColors.surfaceDarkElevated,
                    child: Icon(Icons.image_rounded,
                        color: AppColors.accentCyan, size: 24.r),
                  ),
                ),
              ),
            ),
          ),
        if (paths.isEmpty)
          Container(
            height: 60.h,
            decoration: BoxDecoration(
              color: AppColors.surfaceDarkElevated,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                  color: AppColors.outline.withValues(alpha: 0.3),
                  style: BorderStyle.solid),
            ),
            child: Center(
              child: Text(context.tr('no_photos_added'),
                  style: TextStyle(
                      color: AppColors.textLight.withValues(alpha: 0.4),
                      fontSize: 12.sp)),
            ),
          ),
      ],
    );
  }
}

class _RequestButton extends StatelessWidget {
  final Color color;
  final double price;
  final bool isSubmitting;
  final VoidCallback onTap;

  const _RequestButton({
    required this.color,
    required this.price,
    required this.isSubmitting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 18.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.7)],
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSubmitting)
              SizedBox(
                width: 20.r,
                height: 20.r,
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else ...[
              Icon(Icons.local_shipping_rounded,
                  color: AppColors.white, size: 20.r),
              SizedBox(width: 8.w),
              Text('${context.tr('request_service_label')} — \$${(price + 5).toStringAsFixed(0)}',
                  style: TextStyle(
                      color: AppColors.white,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }
}
