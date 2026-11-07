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

  /// Uploads local image files ([paths]) for a request that is about to be
  /// created and returns their server URLs, in the same order, to pass to
  /// [createRequestWithPhotos].
  Future<List<String>> uploadPhotos(List<String> paths);

  /// [createRequest] with photos already stored by [uploadPhotos].
  Future<ServiceRequest> createRequestWithPhotos({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
    required List<String> photoUrls,
  });
  Stream<ServiceRequest> watchRequest(String requestId);
  Future<void> cancelRequest(String requestId);
  Future<void> rateDriver(String requestId, int stars, String? review);
  Future<List<ServiceRequest>> getHistory();
}
