import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/core.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/map_marker_helper.dart';
import '../../data/models/driver_model.dart';
import '../../data/models/service_request.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import '../widgets/roadside_visuals.dart';
import 'rating_screen.dart';
import 'roadside_error_snackbar.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _cancelling = false;

  BitmapDescriptor? _customerPin;
  BitmapDescriptor? _driverPin;
  Brightness? _pinBrightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pins follow the theme; rebuild them when the brightness changes.
    final brightness = Theme.of(context).brightness;
    if (brightness != _pinBrightness) {
      _pinBrightness = brightness;
      _preloadMarkers(context.colors, brightness);
    }
  }

  Future<void> _preloadMarkers(AppPalette p, Brightness brightness) async {
    final customer = await MapMarkerHelper.buildPin(
      color: p.primaryButton,
      icon: Icons.home_rounded,
    );
    // Navy in light, slate in dark; the pin's white ring keeps it visible on
    // either map style.
    final driver = await MapMarkerHelper.buildPin(
      color: brightness == Brightness.dark ? p.surface2 : p.text,
      icon: Icons.directions_car_rounded,
    );
    if (mounted) {
      setState(() {
        _customerPin = customer;
        _driverPin = driver;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoadsideBloc, RoadsideState>(
      listener: (context, state) async {
        if (state.phase == RoadsidePhase.rating) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RatingScreen()),
          );
          return;
        }
        if (state.phase == RoadsidePhase.idle) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          return;
        }
        if (state.error != null) {
          if (_cancelling) setState(() => _cancelling = false);
          showRoadsideError(context, state.error!);
        }
        if (state.activeRequest != null) {
          await _updateMap(state.activeRequest!);
        }
      },
      builder: (context, state) {
        final req = state.activeRequest;
        final driver = req?.assignedDriver;

        return Scaffold(
          body: Stack(
            children: [
              // Map
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target:
                      req?.customerLocation ?? const LatLng(24.7136, 46.6753),
                  zoom: 14,
                ),
                onMapCreated: (ctrl) {
                  _mapCtrl.complete(ctrl);
                  if (req != null) _updateMap(req);
                },
                markers: _markers,
                polylines: _polylines,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                style: RoadsideVisuals.mapStyleFor(context),
              ),

              // Status panel
              PositionedDirectional(
                top: 0,
                start: 0,
                end: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSizes.space16.w,
                      AppSizes.space12.h,
                      AppSizes.space16.w,
                      0,
                    ),
                    child: _StatusBanner(
                      request: req,
                      cancelling: _cancelling,
                      onCancel:
                          req?.status == RequestStatus.driverEnRoute &&
                              !_cancelling
                          ? () {
                              // The idle listener pops once the backend
                              // confirms; a refusal shows an error instead.
                              setState(() => _cancelling = true);
                              context.read<RoadsideBloc>().add(
                                const CancelRequest(),
                              );
                            }
                          : null,
                    ),
                  ),
                ),
              ),

              // Driver panel
              if (driver != null)
                PositionedDirectional(
                  bottom: 0,
                  start: 0,
                  end: 0,
                  child: _DriverCard(
                    driver: driver,
                    request: req!,
                    etaMinutes: _etaMinutesFor(req),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateMap(ServiceRequest req) async {
    if (!mounted) return;
    final customer = req.customerLocation;
    final driverPos = req.driverLocation ?? customer;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('customer'),
        position: customer,
        icon:
            _customerPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        icon: _driverPin ?? BitmapDescriptor.defaultMarker,
        infoWindow: InfoWindow(title: req.assignedDriver?.name ?? 'Driver'),
      ),
    };

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: [driverPos, customer],
        color: context.colors.primary,
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ),
    };

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });

    if (_mapCtrl.isCompleted) {
      final ctrl = await _mapCtrl.future;
      final bounds = LatLngBounds(
        southwest: LatLng(
          min(driverPos.latitude, customer.latitude) - 0.005,
          min(driverPos.longitude, customer.longitude) - 0.005,
        ),
        northeast: LatLng(
          max(driverPos.latitude, customer.latitude) + 0.005,
          max(driverPos.longitude, customer.longitude) + 0.005,
        ),
      );
      ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
    }
  }

  // Derived from the request on every build, so the card is right from the
  // first frame instead of "0 min" until the next update arrives.
  int _etaMinutesFor(ServiceRequest req) {
    final customer = req.customerLocation;
    final driverPos = req.driverLocation ?? customer;
    final dist = _haversine(
      driverPos.latitude,
      driverPos.longitude,
      customer.latitude,
      customer.longitude,
    );
    return max(1, (dist / 0.5).ceil());
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

class _StatusBanner extends StatelessWidget {
  final ServiceRequest? request;
  final VoidCallback? onCancel;
  final bool cancelling;

  const _StatusBanner({
    required this.request,
    this.onCancel,
    this.cancelling = false,
  });

  String get _statusText {
    switch (request?.status) {
      case RequestStatus.driverFound:
        return 'Driver found — preparing to depart';
      case RequestStatus.driverEnRoute:
        return 'Driver is on the way';
      case RequestStatus.arrived:
        return 'Driver has arrived';
      case RequestStatus.inProgress:
        return 'Service in progress';
      case RequestStatus.completed:
        return 'Service completed!';
      default:
        return 'Connecting...';
    }
  }

  IconData get _statusIcon {
    switch (request?.status) {
      case RequestStatus.driverFound:
        return Icons.check_circle_rounded;
      case RequestStatus.driverEnRoute:
        return Icons.navigation_rounded;
      case RequestStatus.arrived:
        return Icons.pin_drop_rounded;
      case RequestStatus.inProgress:
        return Icons.build_circle_rounded;
      case RequestStatus.completed:
        return Icons.task_alt_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  /// Arrived / completed are the "good news" states; the rest are progress.
  StatusLevel get _level {
    switch (request?.status) {
      case RequestStatus.arrived:
      case RequestStatus.completed:
        return StatusLevel.ok;
      case RequestStatus.driverFound:
      case RequestStatus.driverEnRoute:
      case RequestStatus.inProgress:
        return StatusLevel.info;
      default:
        return StatusLevel.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    // Solid surface (not glass) so it stays legible over map tiles.
    return AppCard(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSizes.space12.w,
        AppSizes.space12.h,
        AppSizes.space8.w,
        AppSizes.space12.h,
      ),
      child: Row(
        children: [
          IconBox(_statusIcon, color: _level.colorOf(context), size: 40),
          SizedBox(width: AppSizes.space12.w),
          Expanded(
            child: Text(
              _statusText,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ),
          if (cancelling)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSizes.space16.w),
              child: SizedBox.square(
                dimension: 16.r,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: p.crit,
                ),
              ),
            )
          else if (onCancel != null)
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: p.crit,
                minimumSize: Size(44.r, 44.r),
              ),
              child: Text(
                context.tr('cancel'),
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: p.crit,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final DriverModel driver;
  final ServiceRequest request;
  final int etaMinutes;

  const _DriverCard({
    required this.driver,
    required this.request,
    required this.etaMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusXl.r),
        ),
        side: BorderSide(color: p.border),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSizes.space20.w,
            AppSizes.space20.h,
            AppSizes.space20.w,
            AppSizes.space16.h,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26.r,
                    backgroundColor: p.primarySoft,
                    child: Text(
                      driver.avatarInitials,
                      style: AppTextStyles.title.copyWith(color: p.primary),
                    ),
                  ),
                  SizedBox(width: AppSizes.space12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.title.copyWith(color: p.text),
                        ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: RoadsideVisuals.ratingStar,
                              size: 16.r,
                            ),
                            SizedBox(width: 2.w),
                            Text(
                              '${driver.rating}',
                              style: AppTextStyles.label.copyWith(
                                color: p.text,
                              ),
                            ),
                            SizedBox(width: AppSizes.space8.w),
                            Flexible(
                              child: Text(
                                '(${driver.totalJobs} jobs)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.label.copyWith(
                                  color: p.text2,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          '${driver.vehicleType}  ·  ${driver.vehiclePlate}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.label.copyWith(
                            color: p.text2,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSizes.space8.w),
                  HeaderAction(
                    icon: Icons.phone_rounded,
                    tooltip: context.tr('call_driver'),
                    color: p.primary,
                    onPressed: () =>
                        launchUrl(Uri(scheme: 'tel', path: driver.phone)),
                  ),
                ],
              ),
              Divider(color: p.border, height: AppSizes.space32.h),
              Row(
                children: [
                  Expanded(
                    child: _InfoItem(
                      icon: Icons.schedule_rounded,
                      value: request.status == RequestStatus.inProgress
                          ? 'Servicing'
                          : '$etaMinutes min away',
                    ),
                  ),
                  Expanded(
                    child: _InfoItem(
                      icon: Icons.payments_outlined,
                      value:
                          '\$${(request.estimatedPrice + 5).toStringAsFixed(0)} cash',
                    ),
                  ),
                  Expanded(
                    child: _InfoItem(
                      icon: request.serviceType.icon,
                      value: request.serviceType.label,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoItem({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Column(
      children: [
        Icon(icon, color: p.text2, size: 20.r),
        SizedBox(height: AppSizes.space4.h),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.numeric(
            AppTextStyles.label.copyWith(
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
        ),
      ],
    );
  }
}
