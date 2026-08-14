import 'dart:async';

import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/socket_client.dart';
import '../dto/lat_lng_dto.dart';
import '../dto/service_request_dto.dart';
import '../models/service_request.dart';
import '../models/service_type.dart';
import 'roadside_repository.dart';

class ApiRoadsideRepository implements RoadsideRepository {
  ApiRoadsideRepository(this._apiClient, this._socketClient);

  final ApiClient _apiClient;
  final SocketClient _socketClient;

  @override
  Future<double> getEstimatedPrice(ServiceType type, LatLng location) async {
    try {
      final response = await _apiClient.dio.get('/service-requests/price-estimate', queryParameters: {
        'serviceType': type.name,
        'lat': location.latitude,
        'lng': location.longitude,
      });
      return (response.data['estimatedPrice'] as num).toDouble();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<String> reverseGeocode(LatLng location) async {
    try {
      final response = await _apiClient.dio.get('/geocode/reverse', queryParameters: {
        'lat': location.latitude,
        'lng': location.longitude,
      });
      return response.data['address'] as String;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ServiceRequest> createRequest({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
  }) async {
    try {
      final response = await _apiClient.dio.post('/service-requests', data: {
        'serviceType': type.name,
        'location': location.toDto().toJson(),
        'address': address,
        if (notes != null) 'notes': notes,
      });
      return serviceRequestFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Stream<ServiceRequest> watchRequest(String requestId) {
    late StreamController<ServiceRequest> controller;
    ServiceRequest? last;

    void handleDriverAssigned(dynamic data) {
      final map = Map<String, dynamic>.from(data as Map);
      if (map['requestId'] != requestId) return;
      _hydrate(requestId).then((updated) {
        last = updated;
        if (!controller.isClosed) controller.add(updated);
      });
    }

    void handleLocationUpdate(dynamic data) {
      final map = Map<String, dynamic>.from(data as Map);
      if (map['requestId'] != requestId || last == null) return;
      final location = LatLngDto.fromJson(Map<String, dynamic>.from(map['location'] as Map)).toLatLng();
      last = last!.copyWith(driverLocation: location);
      if (!controller.isClosed) controller.add(last!);
    }

    void handleStatusChanged(dynamic data) {
      final map = Map<String, dynamic>.from(data as Map);
      if (map['requestId'] != requestId || last == null) return;
      final status = requestStatusFromCanonical(map['status'] as String);
      if (status == RequestStatus.completed) {
        // Re-hydrate for the driver-confirmed finalPrice/cashCollected
        // rather than just patching status onto the stale estimate.
        _hydrate(requestId).then((updated) {
          last = updated;
          if (!controller.isClosed) controller.add(updated);
        });
        return;
      }
      last = last!.copyWith(status: status);
      if (!controller.isClosed) controller.add(last!);
    }

    controller = StreamController<ServiceRequest>.broadcast(
      onListen: () async {
        try {
          last = await _hydrate(requestId);
          controller.add(last!);
        } catch (e) {
          controller.addError(e);
        }
        _socketClient.socket
          ..on('driver-assigned', handleDriverAssigned)
          ..on('driver-location-update', handleLocationUpdate)
          ..on('status-changed', handleStatusChanged);
      },
      onCancel: () {
        _socketClient.socket
          ..off('driver-assigned', handleDriverAssigned)
          ..off('driver-location-update', handleLocationUpdate)
          ..off('status-changed', handleStatusChanged);
      },
    );
    return controller.stream;
  }

  Future<ServiceRequest> _hydrate(String requestId) async {
    try {
      final response = await _apiClient.dio.get('/service-requests/$requestId');
      return serviceRequestFromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    try {
      await _apiClient.dio.post('/service-requests/$requestId/cancel');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> rateDriver(String requestId, int stars, String? review) async {
    try {
      await _apiClient.dio.post('/service-requests/$requestId/rate', data: {
        'stars': stars,
        if (review != null) 'review': review,
      });
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<ServiceRequest>> getHistory() async {
    try {
      final response = await _apiClient.dio.get('/service-requests/history');
      return (response.data as List)
          .map((json) => serviceRequestFromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
