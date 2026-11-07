import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/core.dart';
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
    final xFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (xFile != null && mounted) {
      context.read<RoadsideBloc>().add(AddPhotoPath(xFile.path));
    }
  }

  void _submit(RoadsideState state) {
    if (_notesCtrl.text.isNotEmpty) {
      context.read<RoadsideBloc>().add(UpdateNotes(_notesCtrl.text));
    }
    context.read<RoadsideBloc>().add(const SubmitRequest());
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SearchingDriverScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoadsideBloc, RoadsideState>(
      listener: (context, state) {
        if (state.phase == RoadsidePhase.idle) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else if (state.phase == RoadsidePhase.estimate &&
            state.error != null) {
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

          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  ScreenHeader(title: context.tr('service_details')),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        AppSizes.space20.w,
                        AppSizes.space4.h,
                        AppSizes.space20.w,
                        AppSizes.space24.h,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: AppSizes.space16.h,
                        children: [
                          _ServiceSummaryCard(service: service),
                          _LocationCard(address: state.customerAddress),
                          _PriceBreakdownCard(
                            service: service,
                            totalPrice: price,
                          ),
                          _NotesField(controller: _notesCtrl),
                          _PhotosSection(
                            paths: state.photoPaths,
                            // The bloc ignores photos past the limit.
                            onAdd:
                                state.photoPaths.length <
                                    RoadsideState.maxPhotos
                                ? _addPhoto
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The one action, pinned under the scrolling details; snackbars
            // float above it instead of covering it.
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
                  label:
                      '${context.tr('request_service_label')}'
                      ' — \$${(price + 5).toStringAsFixed(0)}',
                  icon: Icons.local_shipping_rounded,
                  isLoading: state.isSubmitting,
                  onPressed: () => _submit(state),
                ),
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

  const _ServiceSummaryCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return AppCard(
      child: Row(
        children: [
          IconBox(service.icon, size: 48),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.label,
                  style: AppTextStyles.title.copyWith(color: p.text),
                ),
                SizedBox(height: 2.h),
                Text(
                  service.description,
                  style: AppTextStyles.label.copyWith(
                    color: p.text2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSizes.space8.w),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, color: p.text2, size: 16.r),
              SizedBox(width: AppSizes.space4.w),
              Text(
                '~${service.etaMinutes} min',
                style: AppTextStyles.numeric(
                  AppTextStyles.label.copyWith(color: p.text2),
                ),
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
    final p = context.colors;
    return AppCard(
      child: Row(
        children: [
          const IconBox(Icons.location_on_rounded),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('your_location'),
                  style: AppTextStyles.label.copyWith(color: p.text2),
                ),
                SizedBox(height: 2.h),
                Text(
                  address,
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
}

class _PriceBreakdownCard extends StatelessWidget {
  final ServiceType service;
  final double totalPrice;

  const _PriceBreakdownCard({required this.service, required this.totalPrice});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final distanceFee = totalPrice - service.basePrice;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('price_estimate_label'),
            style: AppTextStyles.title.copyWith(color: p.text),
          ),
          SizedBox(height: AppSizes.space12.h),
          _PriceLine(
            label: 'Base service fee',
            value: '\$${service.basePrice.toStringAsFixed(0)}',
          ),
          SizedBox(height: AppSizes.space8.h),
          _PriceLine(
            label: 'Distance fee',
            value: '\$${distanceFee.toStringAsFixed(0)}',
          ),
          SizedBox(height: AppSizes.space8.h),
          const _PriceLine(label: 'Platform fee', value: '\$5'),
          Divider(color: p.border, height: AppSizes.space24.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('total_estimate'),
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
              Text(
                '\$${(totalPrice + 5).toStringAsFixed(0)}',
                style: AppTextStyles.headline.copyWith(color: p.text),
              ),
            ],
          ),
          SizedBox(height: AppSizes.space12.h),
          Row(
            children: [
              Icon(Icons.payments_outlined, color: p.text2, size: 16.r),
              SizedBox(width: AppSizes.space8.w),
              Flexible(
                child: Text(
                  context.tr('cash_payment'),
                  style: AppTextStyles.label.copyWith(
                    color: p.text2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
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
    final p = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.body.copyWith(color: p.text2)),
        Text(
          value,
          style: AppTextStyles.numeric(
            AppTextStyles.body.copyWith(color: p.text),
          ),
        ),
      ],
    );
  }
}

class _NotesField extends StatelessWidget {
  final TextEditingController controller;
  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    // Fill, border, text and hint colors come from the app's input theme.
    return TextField(
      controller: controller,
      maxLines: 3,
      minLines: 2,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        hintText: 'Add notes (e.g. car model, issue description)...',
        prefixIcon: Icon(Icons.notes_rounded, size: 20.r),
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
    final p = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('photos'),
          trailing: onAdd == null
              ? null
              : AppButton.ghost(
                  label: context.tr('add'),
                  icon: Icons.add_a_photo_rounded,
                  onPressed: onAdd,
                ),
        ),
        if (paths.isNotEmpty)
          SizedBox(
            height: 80.r,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, __) => SizedBox(width: AppSizes.space8.w),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
                // Camera captures are files on the device, not bundled assets.
                child: Image.file(
                  File(paths[i]),
                  width: 80.r,
                  height: 80.r,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80.r,
                    height: 80.r,
                    color: p.surface2,
                    child: Icon(
                      Icons.image_outlined,
                      color: p.muted,
                      size: 24.r,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (paths.isEmpty)
          AppCard(
            padding: EdgeInsets.symmetric(
              horizontal: AppSizes.space16.w,
              vertical: AppSizes.space16.h,
            ),
            child: Text(
              context.tr('no_photos_added'),
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(
                color: p.muted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}
