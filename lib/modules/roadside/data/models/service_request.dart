import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'driver_model.dart';
import 'service_type.dart';

enum RequestStatus {
  searching,
  driverFound,
  driverEnRoute,
  inProgress,
  completed,
  cancelled,
}

class ServiceRequest {
  final String id;
  final ServiceType serviceType;
  final LatLng customerLocation;
  final String customerAddress;
  final double estimatedPrice;
  final int estimatedMinutes;
  final RequestStatus status;
  final DriverModel? assignedDriver;
  final LatLng? driverLocation;
  final DateTime createdAt;
  final String? notes;
  final List<String> photoPaths;
  final int? rating;
  final String? review;

  const ServiceRequest({
    required this.id,
    required this.serviceType,
    required this.customerLocation,
    required this.customerAddress,
    required this.estimatedPrice,
    required this.estimatedMinutes,
    required this.status,
    this.assignedDriver,
    this.driverLocation,
    required this.createdAt,
    this.notes,
    this.photoPaths = const [],
    this.rating,
    this.review,
  });

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
      serviceType: serviceType,
      customerLocation: customerLocation,
      customerAddress: customerAddress,
      estimatedPrice: estimatedPrice,
      estimatedMinutes: estimatedMinutes,
      status: status ?? this.status,
      assignedDriver: assignedDriver ?? this.assignedDriver,
      driverLocation: driverLocation ?? this.driverLocation,
      createdAt: createdAt,
      notes: notes ?? this.notes,
      photoPaths: photoPaths ?? this.photoPaths,
      rating: rating ?? this.rating,
      review: review ?? this.review,
    );
  }
}
