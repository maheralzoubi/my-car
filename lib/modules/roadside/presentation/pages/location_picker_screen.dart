import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import 'price_estimate_screen.dart';
import 'roadside_error_snackbar.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  LatLng _center = const LatLng(24.7136, 46.6753); // Riyadh default
  String _address = 'Move map to set location';
  bool _loadingLocation = false;
  bool _resolvingAddress = false;
  bool _confirming = false;
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        final latLng = LatLng(pos.latitude, pos.longitude);
        if (!mounted) return;
        setState(() => _center = latLng);
        final ctrl = await _mapController.future;
        ctrl.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
        _resolveAddress(latLng);
      }
    } catch (_) {}
    // The user may have left while the GPS fix / permission prompt was open.
    if (mounted) setState(() => _loadingLocation = false);
  }

  void _onCameraMove(CameraPosition position) {
    _center = position.target;
    _addressDebounce?.cancel();
    _addressDebounce = Timer(const Duration(milliseconds: 600), () {
      _resolveAddress(_center);
    });
  }

  Future<void> _resolveAddress(LatLng pos) async {
    if (!mounted) return;
    setState(() => _resolvingAddress = true);
    try {
      final address = await context.read<RoadsideBloc>().repository.reverseGeocode(pos);
      if (mounted) {
        setState(() {
          _address = address;
          _resolvingAddress = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _address =
              '${pos.latitude.toStringAsFixed(4)}°N, ${pos.longitude.toStringAsFixed(4)}°E';
          _resolvingAddress = false;
        });
      }
    }
  }

  // Navigation happens in the listener once the price estimate arrives, so
  // a failed estimate keeps the user here with an error.
  void _confirm() {
    setState(() => _confirming = true);
    context
        .read<RoadsideBloc>()
        .add(ConfirmLocation(_center, _address));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoadsideBloc, RoadsideState>(
      listenWhen: (prev, curr) => prev.phase != curr.phase || curr.error != null,
      listener: (context, state) {
        if (state.phase == RoadsidePhase.idle) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        } else if (state.phase == RoadsidePhase.estimate) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const PriceEstimateScreen()),
          );
        } else if (state.error != null) {
          setState(() => _confirming = false);
          showRoadsideError(context, state.error!);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Stack(
          children: [
            // Map
            GoogleMap(
              initialCameraPosition:
                  CameraPosition(target: _center, zoom: 15),
              onMapCreated: _mapController.complete,
              onCameraMove: _onCameraMove,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              style: _darkMapStyle,
            ),

            // Fixed center pin
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_pin,
                      color: AppColors.accentOrange, size: 48.r),
                  SizedBox(height: 24.h),
                ],
              ),
            ),

            // Top bar
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 40.r,
                        height: 40.r,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDarkElevated,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.white, size: 18),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDarkElevated,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          'Set Your Location',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Current location FAB
            Positioned(
              right: 16.w,
              bottom: 160.h,
              child: GestureDetector(
                onTap: _getCurrentLocation,
                child: Container(
                  width: 48.r,
                  height: 48.r,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDarkElevated,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                        color: AppColors.accentCyan.withValues(alpha: 0.4)),
                  ),
                  child: _loadingLocation
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentCyan),
                        )
                      : const Icon(Icons.my_location_rounded,
                          color: AppColors.accentCyan),
                ),
              ),
            ),

            // Bottom address + confirm bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDarkElevated,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24.r)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40.w,
                      height: 4.h,
                      margin: EdgeInsets.only(bottom: 16.h),
                      decoration: BoxDecoration(
                        color: AppColors.outline,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8.r),
                          decoration: BoxDecoration(
                            color:
                                AppColors.accentOrange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Icon(Icons.location_on_rounded,
                              color: AppColors.accentOrange, size: 20.r),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: _resolvingAddress
                              ? Row(
                                  children: [
                                    SizedBox(
                                      width: 14.r,
                                      height: 14.r,
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accentCyan,
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(context.tr('detecting_address'),
                                        style: TextStyle(
                                            color: AppColors.textLight
                                                .withValues(alpha: 0.6),
                                            fontSize: 13.sp)),
                                  ],
                                )
                              : Text(
                                  _address,
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirming ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentOrange,
                          foregroundColor: AppColors.white,
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                        ),
                        child: _confirming
                            ? SizedBox(
                                width: 18.r,
                                height: 18.r,
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.white),
                              )
                            : Text(
                                'Confirm Location',
                                style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0d0d0d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212121"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2d2d2d"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0a1929"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]}
]
''';
