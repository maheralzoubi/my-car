import '../models/driver_model.dart';
import '../models/service_request.dart';
import '../models/service_type.dart';
import 'lat_lng_dto.dart';

/// Maps the backend's canonical status strings to this app's [RequestStatus].
/// See my-car-backend's `common/enums/request-status.enum.ts` for the source
/// of truth — the backend never emits a request-level "declined" status,
/// that only exists as a per-driver relationship.
RequestStatus requestStatusFromCanonical(String status) {
  switch (status) {
    case 'searching':
      return RequestStatus.searching;
    case 'driverAssigned':
      return RequestStatus.driverFound;
    case 'driverEnRoute':
      return RequestStatus.driverEnRoute;
    case 'arrived':
      return RequestStatus.arrived;
    case 'inProgress':
      return RequestStatus.inProgress;
    case 'completed':
      return RequestStatus.completed;
    case 'cancelled':
      return RequestStatus.cancelled;
    default:
      throw ArgumentError('Unknown request status: $status');
  }
}

ServiceRequest serviceRequestFromJson(Map<String, dynamic> json) {
  final driverJson = json['assignedDriver'] as Map<String, dynamic>?;
  final driverLocationJson = json['driverLocation'] as Map<String, dynamic>?;
  final pickup = LatLngDto.fromJson(json['pickupLocation'] as Map<String, dynamic>);

  return ServiceRequest(
    id: json['id'] as String,
    customerId: json['customerId'] as String?,
    serviceType: ServiceType.values.byName(json['serviceType'] as String),
    customerLocation: pickup.toLatLng(),
    customerAddress: json['pickupAddress'] as String,
    estimatedPrice: (json['estimatedPrice'] as num).toDouble(),
    finalPrice: (json['finalPrice'] as num?)?.toDouble(),
    estimatedMinutes: json['estimatedMinutes'] as int,
    status: requestStatusFromCanonical(json['status'] as String),
    assignedDriver: driverJson != null ? DriverModel.fromJson(driverJson) : null,
    driverLocation: driverLocationJson != null ? LatLngDto.fromJson(driverLocationJson).toLatLng() : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
    notes: json['notes'] as String?,
    photoPaths: const [],
    photoUrls: List<String>.from(json['photoUrls'] as List? ?? const []),
    rating: (json['rating'] as num?)?.toInt(),
    review: json['review'] as String?,
    cashCollected: json['cashCollected'] as bool? ?? false,
  );
}
