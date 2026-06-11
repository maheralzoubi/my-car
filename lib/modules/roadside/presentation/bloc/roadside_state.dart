import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/models/service_request.dart';
import '../../data/models/service_type.dart';

enum RoadsidePhase {
  idle,
  locationPicker,
  estimate,
  searching,
  tracking,
  rating,
  done,
}

class RoadsideState {
  final RoadsidePhase phase;
  final ServiceType? selectedService;
  final LatLng? customerLocation;
  final String customerAddress;
  final double? estimatedPrice;
  final ServiceRequest? activeRequest;
  final String notes;
  final List<String> photoPaths;
  final bool isSubmitting;
  final String? error;

  const RoadsideState({
    this.phase = RoadsidePhase.idle,
    this.selectedService,
    this.customerLocation,
    this.customerAddress = '',
    this.estimatedPrice,
    this.activeRequest,
    this.notes = '',
    this.photoPaths = const [],
    this.isSubmitting = false,
    this.error,
  });

  RoadsideState copyWith({
    RoadsidePhase? phase,
    ServiceType? selectedService,
    LatLng? customerLocation,
    String? customerAddress,
    double? estimatedPrice,
    ServiceRequest? activeRequest,
    String? notes,
    List<String>? photoPaths,
    bool? isSubmitting,
    String? error,
  }) {
    return RoadsideState(
      phase: phase ?? this.phase,
      selectedService: selectedService ?? this.selectedService,
      customerLocation: customerLocation ?? this.customerLocation,
      customerAddress: customerAddress ?? this.customerAddress,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      activeRequest: activeRequest ?? this.activeRequest,
      notes: notes ?? this.notes,
      photoPaths: photoPaths ?? this.photoPaths,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
    );
  }
}
