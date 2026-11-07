import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'driver_model.dart';
import 'service_type.dart';

enum RequestStatus {
  searching,
  driverFound,
  driverEnRoute,
  arrived,
  inProgress,
  completed,
  cancelled,
}

class ServiceRequest {
  final String id;
  final String? customerId;
  final ServiceType serviceType;
  final LatLng customerLocation;
  final String customerAddress;
  final double estimatedPrice;
  final double? finalPrice;
  final int estimatedMinutes;
  final RequestStatus status;
  final DriverModel? assignedDriver;
  final LatLng? driverLocation;
  final DateTime createdAt;
  final String? notes;
  final List<String> photoPaths;

  /// Photos the backend has on file for this request (`photoUrls` in the API
  /// response), as returned — server-relative paths like `/uploads/...`.
  /// Distinct from [photoPaths], which are local files picked on this device.
  final List<String> photoUrls;
  final int? rating;
  final String? review;
  final bool cashCollected;

  const ServiceRequest({
    required this.id,
    this.customerId,
    required this.serviceType,
    required this.customerLocation,
    required this.customerAddress,
    required this.estimatedPrice,
    this.finalPrice,
    required this.estimatedMinutes,
    required this.status,
    this.assignedDriver,
    this.driverLocation,
    required this.createdAt,
    this.notes,
    this.photoPaths = const [],
    this.photoUrls = const [],
    this.rating,
    this.review,
    this.cashCollected = false,
  });

  /// The amount to show the customer — the driver-confirmed final price
  /// once the job is complete, falling back to the estimate until then.
  double get displayPrice => finalPrice ?? estimatedPrice;

  ServiceRequest copyWith({
    RequestStatus? status,
    DriverModel? assignedDriver,
    LatLng? driverLocation,
    String? notes,
    List<String>? photoPaths,
    int? rating,
    String? review,
  }) {
    return ServiceRequest(
      id: id,
      customerId: customerId,
      serviceType: serviceType,
      customerLocation: customerLocation,
      customerAddress: customerAddress,
      estimatedPrice: estimatedPrice,
      finalPrice: finalPrice,
      estimatedMinutes: estimatedMinutes,
      status: status ?? this.status,
      assignedDriver: assignedDriver ?? this.assignedDriver,
      driverLocation: driverLocation ?? this.driverLocation,
      createdAt: createdAt,
      notes: notes ?? this.notes,
      photoPaths: photoPaths ?? this.photoPaths,
      photoUrls: photoUrls,
      rating: rating ?? this.rating,
      review: review ?? this.review,
      cashCollected: cashCollected,
    );
  }
}
