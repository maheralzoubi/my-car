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
      return _parse(() => (response.data['estimatedPrice'] as num).toDouble());
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
      return _parse(() => response.data['address'] as String);
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
  }) =>
      createRequestWithPhotos(
        type: type,
        location: location,
        address: address,
        notes: notes,
        photoUrls: const [],
      );

  /// One multipart `POST /service-requests/photos` with every file in the
  /// `photos` field (the backend accepts up to 5 images of up to 10 MB each).
  @override
  Future<List<String>> uploadPhotos(List<String> paths) async {
    if (paths.isEmpty) return const [];
    final form = FormData();
    for (final path in paths) {
      form.files.add(MapEntry(
        'photos',
        await MultipartFile.fromFile(path, contentType: _photoContentType(path)),
      ));
    }
    try {
      final response = await _apiClient.dio.post('/service-requests/photos', data: form);
      final urls = _parse(() => List<String>.from(response.data['photoUrls'] as List));
      if (urls.length != paths.length) {
        throw ApiException('Unexpected response from the server. Please try again.');
      }
      return urls;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// The backend checks the declared type (and the file's bytes), so label
  /// each part explicitly rather than relying on Dio's filename lookup.
  /// image_picker produces JPEGs unless the file says otherwise.
  static DioMediaType _photoContentType(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'png':
        return DioMediaType('image', 'png');
      case 'webp':
        return DioMediaType('image', 'webp');
      case 'heic':
        return DioMediaType('image', 'heic');
      case 'heif':
        return DioMediaType('image', 'heif');
      default:
        return DioMediaType('image', 'jpeg');
    }
  }

  @override
  Future<ServiceRequest> createRequestWithPhotos({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
    required List<String> photoUrls,
  }) async {
    try {
      final response = await _apiClient.dio.post('/service-requests', data: {
        'serviceType': type.name,
        'location': location.toDto().toJson(),
        'address': address,
        if (notes != null) 'notes': notes,
        if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      });
      return _parse(() => serviceRequestFromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Stream<ServiceRequest> watchRequest(String requestId) {
    late StreamController<ServiceRequest> controller;
    ServiceRequest? last;

    // Bumped on every listen/cancel so async results from a previous listen
    // (an in-flight GET) are dropped instead of leaking into the next one.
    var session = 0;

    // Non-null while the initial GET is in flight: socket events that arrive
    // meanwhile are queued here and replayed on top of the snapshot.
    List<void Function()>? queued;

    void emit(ServiceRequest request) {
      last = request;
      if (!controller.isClosed) controller.add(request);
    }

    void rehydrate() {
      final s = session;
      _hydrate(requestId).then(
        (updated) {
          if (s == session) emit(updated);
        },
        onError: (Object e) {
          if (s == session && !controller.isClosed) controller.addError(e);
        },
      );
    }

    void handleDriverAssigned(dynamic data) {
      if (_payloadFor(data, requestId) == null) return;
      if (queued != null) {
        queued!.add(rehydrate);
        return;
      }
      rehydrate();
    }

    void handleLocationUpdate(dynamic data) {
      final map = _payloadFor(data, requestId);
      if (map == null) return;
      if (queued != null) {
        queued!.add(() => handleLocationUpdate(data));
        return;
      }
      if (last == null) return;
      final LatLng location;
      try {
        location = LatLngDto.fromJson(Map<String, dynamic>.from(map['location'] as Map)).toLatLng();
      } catch (_) {
        return; // Malformed tick; the next one will move the marker.
      }
      emit(last!.copyWith(driverLocation: location));
    }

    void handleStatusChanged(dynamic data) {
      final map = _payloadFor(data, requestId);
      if (map == null) return;
      if (queued != null) {
        queued!.add(() => handleStatusChanged(data));
        return;
      }
      if (last == null) return;
      final RequestStatus status;
      try {
        status = requestStatusFromCanonical(map['status'] as String);
      } catch (_) {
        // A status this app version doesn't know (e.g. added to the backend
        // later). Ignore it rather than throwing out of the socket handler;
        // the next known status or a re-hydrate will bring us back in sync.
        return;
      }
      if (status == RequestStatus.completed) {
        // Re-hydrate for the driver-confirmed finalPrice/cashCollected
        // rather than just patching status onto the stale estimate.
        rehydrate();
        return;
      }
      emit(last!.copyWith(status: status));
    }

    controller = StreamController<ServiceRequest>.broadcast(
      onListen: () async {
        final s = ++session;
        last = null;
        queued = [];
        // Attach before the GET so nothing emitted during hydration (seconds
        // on a cold backend) is lost, and so onCancel always has something
        // to detach even if it runs before the GET resolves.
        _socketClient.socket
          ..on('driver-assigned', handleDriverAssigned)
          ..on('driver-location-update', handleLocationUpdate)
          ..on('status-changed', handleStatusChanged);
        try {
          final initial = await _hydrate(requestId);
          if (s != session) return;
          emit(initial);
        } catch (e) {
          if (s != session) return;
          if (!controller.isClosed) controller.addError(e);
        }
        final replay = queued!;
        queued = null;
        for (final event in replay) {
          event();
        }
      },
      onCancel: () {
        session++;
        queued = null;
        _socketClient.socket
          ..off('driver-assigned', handleDriverAssigned)
          ..off('driver-location-update', handleLocationUpdate)
          ..off('status-changed', handleStatusChanged);
      },
    );
    return controller.stream;
  }

  /// The socket payload as a map if it is about [requestId], otherwise null
  /// (other requests' events and malformed payloads are ignored).
  static Map<String, dynamic>? _payloadFor(dynamic data, String requestId) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);
    return map['requestId'] == requestId ? map : null;
  }

  Future<ServiceRequest> _hydrate(String requestId) async {
    try {
      final response = await _apiClient.dio.get('/service-requests/$requestId');
      return _parse(() => serviceRequestFromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Runs [map] over a decoded response body. A body that doesn't match the
  /// expected shape (missing field, unknown enum, bad date) surfaces as an
  /// [ApiException] like any other API failure, instead of leaking a
  /// TypeError/ArgumentError up to the UI.
  static T _parse<T>(T Function() map) {
    try {
      return map();
    } catch (_) {
      throw ApiException('Unexpected response from the server. Please try again.');
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
      return _parse(() => (response.data as List)
          .map((json) => serviceRequestFromJson(json as Map<String, dynamic>))
          .toList());
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
