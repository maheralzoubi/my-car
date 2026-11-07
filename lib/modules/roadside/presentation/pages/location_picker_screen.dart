import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import '../widgets/roadside_visuals.dart';
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
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
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
      final address = await context
          .read<RoadsideBloc>()
          .repository
          .reverseGeocode(pos);
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
    context.read<RoadsideBloc>().add(ConfirmLocation(_center, _address));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return BlocListener<RoadsideBloc, RoadsideState>(
      listenWhen: (prev, curr) =>
          prev.phase != curr.phase || curr.error != null,
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
        body: Column(
          children: [
            // Header on a solid panel so it never sits on raw map tiles.
            _Panel(
              top: true,
              child: SafeArea(
                bottom: false,
                child: ScreenHeader(title: 'Set Your Location'),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _center,
                      zoom: 15,
                    ),
                    onMapCreated: _mapController.complete,
                    onCameraMove: _onCameraMove,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    style: RoadsideVisuals.mapStyleFor(context),
                  ),

                  // Fixed center pin; its tip marks the map center.
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 44.r),
                        child: Icon(
                          Icons.location_pin,
                          color: p.primaryButton,
                          size: 48.r,
                        ),
                      ),
                    ),
                  ),

                  // Current location
                  PositionedDirectional(
                    end: AppSizes.space16.w,
                    bottom: AppSizes.space16.h,
                    child: _MyLocationButton(
                      loading: _loadingLocation,
                      onPressed: _getCurrentLocation,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Address + confirm. As the bottom bar, snackbars float above it
        // instead of covering the button.
        bottomNavigationBar: _Panel(
          top: false,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSizes.space20.w,
                AppSizes.space16.h,
                AppSizes.space20.w,
                AppSizes.space16.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const IconBox(Icons.location_on_outlined),
                      SizedBox(width: AppSizes.space12.w),
                      Expanded(
                        child: _resolvingAddress
                            ? Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 14.r,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: p.primary,
                                    ),
                                  ),
                                  SizedBox(width: AppSizes.space8.w),
                                  Flexible(
                                    child: Text(
                                      context.tr('detecting_address'),
                                      style: AppTextStyles.body.copyWith(
                                        color: p.text2,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                _address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: p.text,
                                ),
                              ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSizes.space16.h),
                  AppButton(
                    label: 'Confirm Location',
                    isLoading: _confirming,
                    onPressed: _confirming ? null : _confirm,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid surface strip above or below the map with a hairline edge.
class _Panel extends StatelessWidget {
  const _Panel({required this.top, required this.child});

  /// True for the header strip (border below), false for the bottom sheet
  /// (border above).
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final edge = BorderSide(color: p.border);
    return Material(
      color: p.surface,
      shape: Border(
        top: top ? BorderSide.none : edge,
        bottom: top ? edge : BorderSide.none,
      ),
      child: child,
    );
  }
}

class _MyLocationButton extends StatelessWidget {
  const _MyLocationButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return SizedBox.square(
      dimension: 48.r,
      child: IconButton(
        onPressed: onPressed,
        tooltip: context.tr('use_my_location'),
        style: IconButton.styleFrom(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd.r),
            side: BorderSide(color: p.border),
          ),
        ),
        icon: loading
            ? SizedBox.square(
                dimension: 20.r,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.primary,
                ),
              )
            : Icon(Icons.my_location_rounded, size: 22.r, color: p.primary),
      ),
    );
  }
}
