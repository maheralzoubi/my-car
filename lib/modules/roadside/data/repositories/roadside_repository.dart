import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/service_request.dart';
import '../models/service_type.dart';

abstract class RoadsideRepository {
  Future<double> getEstimatedPrice(ServiceType type, LatLng location);
  Future<String> reverseGeocode(LatLng location);
  Future<ServiceRequest> createRequest({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
  });
  Stream<ServiceRequest> watchRequest(String requestId);
  Future<void> cancelRequest(String requestId);
  Future<void> rateDriver(String requestId, int stars, String? review);
  Future<List<ServiceRequest>> getHistory();
}
