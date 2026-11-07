import 'dart:async';
import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/driver_model.dart';
import '../models/service_request.dart';
import '../models/service_type.dart';
import 'roadside_repository.dart';

class MockRoadsideRepository implements RoadsideRepository {
  final _history = <ServiceRequest>[];
  final _controllers = <String, StreamController<ServiceRequest>>{};

  // The pending simulation step for each request, so requests simulate
  // independently and cancelling one stops exactly its own simulation.
  final _timers = <String, Timer>{};
  int _lastId = 0;

  static const _pricePerKm = 5.0;

  @override
  Future<double> getEstimatedPrice(ServiceType type, LatLng location) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final distanceKm = 2.0 + Random().nextDouble() * 3;
    return type.basePrice + (distanceKm * _pricePerKm);
  }

  @override
  Future<String> reverseGeocode(LatLng location) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return 'King Fahd Road, Riyadh 12271, Saudi Arabia';
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

  /// There is no server to store photos on, so the local paths stand in for
  /// their URLs.
  @override
  Future<List<String>> uploadPhotos(List<String> paths) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.of(paths);
  }

  @override
  Future<ServiceRequest> createRequestWithPhotos({
    required ServiceType type,
    required LatLng location,
    required String address,
    String? notes,
    required List<String> photoUrls,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));

    final price = type.basePrice + (2.5 * _pricePerKm);
    final request = ServiceRequest(
      id: 'req_${++_lastId}',
      serviceType: type,
      customerLocation: location,
      customerAddress: address,
      estimatedPrice: price,
      estimatedMinutes: type.etaMinutes,
      status: RequestStatus.searching,
      createdAt: DateTime.now(),
      notes: notes,
      photoUrls: List.unmodifiable(photoUrls),
    );

    _history.insert(0, request);
    _controllers[request.id] = StreamController<ServiceRequest>.broadcast();
    _emit(request.id, request);

    _simulateDriverAssignment(request);
    return request;
  }

  /// Schedules the next simulation step for [requestId], replacing any
  /// pending one.
  void _schedule(String requestId, Duration delay, void Function() step) {
    _timers[requestId]?.cancel();
    _timers[requestId] = Timer(delay, step);
  }

  void _simulateDriverAssignment(ServiceRequest initial) {
    // After 4 seconds: driver found
    _schedule(initial.id, const Duration(seconds: 4), () {
      final driver = DriverModel
          .mockDrivers[Random().nextInt(DriverModel.mockDrivers.length)];
      final offset = 0.015 + Random().nextDouble() * 0.01;
      final angle = Random().nextDouble() * 2 * pi;
      final driverLat = initial.customerLocation.latitude + offset * sin(angle);
      final driverLng = initial.customerLocation.longitude + offset * cos(angle);

      final found = initial.copyWith(
        status: RequestStatus.driverFound,
        assignedDriver: driver,
        driverLocation: LatLng(driverLat, driverLng),
      );
      _emit(initial.id, found);

      // After 2 more seconds: driver en route
      _schedule(initial.id, const Duration(seconds: 2), () {
        _emit(initial.id, found.copyWith(status: RequestStatus.driverEnRoute));
        _simulateMovement(initial.id, found);
      });
    });
  }

  void _simulateMovement(String requestId, ServiceRequest request) {
    var currentLat = request.driverLocation!.latitude;
    var currentLng = request.driverLocation!.longitude;
    final targetLat = request.customerLocation.latitude;
    final targetLng = request.customerLocation.longitude;

    int tick = 0;
    _timers[requestId]?.cancel();
    _timers[requestId] = Timer.periodic(const Duration(seconds: 2), (timer) {
      tick++;
      currentLat += (targetLat - currentLat) * 0.12;
      currentLng += (targetLng - currentLng) * 0.12;

      final dist = _haversine(currentLat, currentLng, targetLat, targetLng);

      final ctrl = _controllers[requestId];
      if (ctrl == null || ctrl.isClosed) {
        timer.cancel();
        return;
      }

      if (dist < 0.05 || tick > 30) {
        timer.cancel();
        // Same order as the backend's LEGAL_STATUS_TRANSITIONS:
        // driverEnRoute -> arrived -> inProgress -> completed.
        final arrived = (_lastEmitted(requestId) ?? request).copyWith(
          status: RequestStatus.arrived,
          driverLocation: LatLng(targetLat, targetLng),
        );
        _emit(requestId, arrived);

        // Start work after 3 seconds, complete 5 seconds after that
        _schedule(requestId, const Duration(seconds: 3), () {
          final inProgress = arrived.copyWith(status: RequestStatus.inProgress);
          _emit(requestId, inProgress);
          _schedule(requestId, const Duration(seconds: 5), () {
            _timers.remove(requestId);
            _emit(requestId, inProgress.copyWith(status: RequestStatus.completed));
          });
        });
      } else {
        final current = _lastEmitted(requestId);
        if (current != null) {
          _emit(
            requestId,
            current.copyWith(driverLocation: LatLng(currentLat, currentLng)),
          );
        }
      }
    });
  }

  final _latestEmitted = <String, ServiceRequest>{};

  void _emit(String id, ServiceRequest req) {
    _store(id, req);
    _controllers[id]?.add(req);
  }

  /// Records [req] as the latest state of [id], including in history.
  void _store(String id, ServiceRequest req) {
    _latestEmitted[id] = req;
    final idx = _history.indexWhere((r) => r.id == id);
    if (idx != -1) _history[idx] = req;
  }

  ServiceRequest? _lastEmitted(String id) => _latestEmitted[id];

  @override
  Stream<ServiceRequest> watchRequest(String requestId) {
    return _controllers[requestId]?.stream ?? const Stream.empty();
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    _timers.remove(requestId)?.cancel();
    final current = _lastEmitted(requestId);
    if (current != null) {
      _emit(requestId, current.copyWith(status: RequestStatus.cancelled));
    }
    _controllers[requestId]?.close();
    _controllers.remove(requestId);
  }

  @override
  Future<void> rateDriver(String requestId, int stars, String? review) async {
    final current = _lastEmitted(requestId);
    if (current != null) {
      _store(requestId, current.copyWith(rating: stars, review: review));
    }
    _controllers[requestId]?.close();
    _controllers.remove(requestId);
  }

  @override
  Future<List<ServiceRequest>> getHistory() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return List.unmodifiable(_history);
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}
