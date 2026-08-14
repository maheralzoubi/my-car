import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/map_marker_helper.dart';
import '../../data/models/service_request.dart';
import '../../data/models/service_type.dart';
import '../bloc/roadside_bloc.dart';
import '../bloc/roadside_event.dart';
import '../bloc/roadside_state.dart';
import 'rating_screen.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  int _etaMinutes = 0;

  BitmapDescriptor? _customerPin;
  BitmapDescriptor? _driverPin;

  @override
  void initState() {
    super.initState();
    _preloadMarkers();
  }

  Future<void> _preloadMarkers() async {
    final customer = await MapMarkerHelper.buildPin(
      color: AppColors.accentOrange,
      icon: Icons.home_rounded,
    );
    final driver = await MapMarkerHelper.buildPin(
      color: AppColors.accentCyan,
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
        if (state.activeRequest != null) {
          await _updateMap(state.activeRequest!);
        }
      },
      builder: (context, state) {
        final req = state.activeRequest;
        final driver = req?.assignedDriver;
        final service = state.selectedService;
        final color = service?.color ?? AppColors.accentOrange;

        return Scaffold(
          backgroundColor: AppColors.backgroundDark,
          body: Stack(
            children: [
              // Map
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: req?.customerLocation ??
                      const LatLng(24.7136, 46.6753),
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
                style: _darkMapStyle,
              ),

              // Status banner
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(16.r),
                    child: _StatusBanner(
                      request: req,
                      color: color,
                      onCancel: req?.status == RequestStatus.driverEnRoute
                          ? () {
                              context
                                  .read<RoadsideBloc>()
                                  .add(const CancelRequest());
                              Navigator.of(context)
                                  .popUntil((r) => r.isFirst);
                            }
                          : null,
                    ),
                  ),
                ),
              ),

              // Bottom driver card
              if (driver != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _DriverCard(
                    driver: driver,
                    request: req!,
                    etaMinutes: _etaMinutes,
                    color: color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateMap(ServiceRequest req) async {
    final customer = req.customerLocation;
    final driverPos = req.driverLocation ?? customer;

    final dist = _haversine(
      driverPos.latitude, driverPos.longitude,
      customer.latitude, customer.longitude,
    );
    setState(() => _etaMinutes = max(1, (dist / 0.5).ceil()));

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('customer'),
        position: customer,
        icon: _customerPin ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Your Location'),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        icon: _driverPin ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: req.assignedDriver?.name ?? 'Driver'),
      ),
    };

    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: [driverPos, customer],
        color: AppColors.accentCyan,
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

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

class _StatusBanner extends StatelessWidget {
  final ServiceRequest? request;
  final Color color;
  final VoidCallback? onCancel;

  const _StatusBanner({
    required this.request,
    required this.color,
    this.onCancel,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(_statusIcon, color: color, size: 20.r),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(_statusText,
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600)),
          ),
          if (onCancel != null)
            GestureDetector(
              onTap: onCancel,
              child: Text(context.tr('cancel'),
                  style: TextStyle(color: AppColors.error, fontSize: 13.sp)),
            ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final dynamic driver;
  final ServiceRequest request;
  final int etaMinutes;
  final Color color;

  const _DriverCard({
    required this.driver,
    required this.request,
    required this.etaMinutes,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 36.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceDarkElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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
              // Avatar
              CircleAvatar(
                radius: 28.r,
                backgroundColor: color.withValues(alpha: 0.2),
                child: Text(driver.avatarInitials,
                    style: TextStyle(
                        color: color,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name,
                        style: TextStyle(
                            color: AppColors.white,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            color: const Color(0xFFFFD700), size: 14.r),
                        SizedBox(width: 3.w),
                        Text('${driver.rating}',
                            style: TextStyle(
                                color: AppColors.textLight, fontSize: 12.sp)),
                        SizedBox(width: 8.w),
                        Text('(${driver.totalJobs} jobs)',
                            style: TextStyle(
                                color: AppColors.textLight.withValues(alpha: 0.5),
                                fontSize: 12.sp)),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${driver.vehicleType}  ·  ${driver.vehiclePlate}',
                      style: TextStyle(
                          color: AppColors.textLight.withValues(alpha: 0.6),
                          fontSize: 11.sp),
                    ),
                  ],
                ),
              ),
              // Call button
              GestureDetector(
                onTap: () => launchUrl(Uri(scheme: 'tel', path: driver.phone as String)),
                child: Container(
                  width: 44.r,
                  height: 44.r,
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                        color: AppColors.accentCyan.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.phone_rounded,
                      color: AppColors.accentCyan, size: 20.r),
                ),
              ),
            ],
          ),

          SizedBox(height: 16.h),
          Divider(
              color: AppColors.outline.withValues(alpha: 0.3), height: 1.h),
          SizedBox(height: 16.h),

          // ETA + price row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _InfoChip(
                icon: Icons.access_time_rounded,
                value: request.status == RequestStatus.inProgress
                    ? 'Servicing'
                    : '$etaMinutes min away',
                color: AppColors.accentCyan,
              ),
              _InfoChip(
                icon: Icons.payments_rounded,
                value: '\$${(request.estimatedPrice + 5).toStringAsFixed(0)} cash',
                color: AppColors.accentOrange,
              ),
              _InfoChip(
                icon: Icons.local_shipping_rounded,
                value: request.serviceType.label,
                color: color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18.r),
        SizedBox(height: 4.h),
        Text(value,
            style: TextStyle(
                color: AppColors.white,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
      ],
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
