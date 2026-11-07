import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/modules/roadside/data/dto/lat_lng_dto.dart';
import 'package:mycar/modules/roadside/data/dto/service_request_dto.dart';
import 'package:mycar/modules/roadside/data/models/driver_model.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';

import 'helpers/roadside_fakes.dart';

void main() {
  group('LatLngDto', () {
    test('fromJson reads lat/lng doubles', () {
      final dto = LatLngDto.fromJson({'lat': 24.7136, 'lng': 46.6753});
      expect(dto.lat, 24.7136);
      expect(dto.lng, 46.6753);
    });

    test('fromJson accepts integer coordinates (JSON numbers without a fraction)', () {
      final dto = LatLngDto.fromJson({'lat': 24, 'lng': -46});
      expect(dto.lat, isA<double>());
      expect(dto.lat, 24.0);
      expect(dto.lng, -46.0);
    });

    test('toJson emits exactly {lat, lng} as the backend LatLngDto expects', () {
      expect(const LatLngDto(21.5, 39.2).toJson(), {'lat': 21.5, 'lng': 39.2});
    });

    test('JSON round trip preserves values', () {
      const original = LatLngDto(-33.8688, 151.2093);
      final copy = LatLngDto.fromJson(original.toJson());
      expect(copy.lat, original.lat);
      expect(copy.lng, original.lng);
    });

    test('LatLng -> DTO -> JSON -> DTO -> LatLng round trip is lossless', () {
      const latLng = LatLng(26.4207, 50.0888);
      final back = LatLngDto.fromJson(latLng.toDto().toJson()).toLatLng();
      expect(back, latLng);
    });

    test('toLatLng maps lat to latitude and lng to longitude (not swapped)', () {
      final ll = const LatLngDto(10.0, 20.0).toLatLng();
      expect(ll.latitude, 10.0);
      expect(ll.longitude, 20.0);
    });

    test('missing coordinate throws instead of silently defaulting to 0,0', () {
      expect(() => LatLngDto.fromJson({'lat': 24.7}), throwsA(isA<TypeError>()));
      expect(() => LatLngDto.fromJson({'lng': 46.6}), throwsA(isA<TypeError>()));
      expect(() => LatLngDto.fromJson({'lat': null, 'lng': 46.6}), throwsA(isA<TypeError>()));
    });

    test('string coordinates are rejected', () {
      expect(() => LatLngDto.fromJson({'lat': '24.7', 'lng': '46.6'}), throwsA(isA<TypeError>()));
    });
  });

  group('requestStatusFromCanonical', () {
    // Source of truth: my-car-backend src/common/enums/request-status.enum.ts
    const backendToApp = {
      'searching': RequestStatus.searching,
      'driverAssigned': RequestStatus.driverFound,
      'driverEnRoute': RequestStatus.driverEnRoute,
      'arrived': RequestStatus.arrived,
      'inProgress': RequestStatus.inProgress,
      'completed': RequestStatus.completed,
      'cancelled': RequestStatus.cancelled,
    };

    backendToApp.forEach((wire, expected) {
      test('maps "$wire" -> $expected', () {
        expect(requestStatusFromCanonical(wire), expected);
      });
    });

    test('every app RequestStatus is reachable from some backend status', () {
      expect(backendToApp.values.toSet(), RequestStatus.values.toSet());
    });

    test('app-side enum name "driverFound" is NOT a valid wire value', () {
      expect(() => requestStatusFromCanonical('driverFound'), throwsArgumentError);
    });

    test('unknown / per-driver-only statuses throw ArgumentError naming the value', () {
      expect(
        () => requestStatusFromCanonical('declined'),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('declined'))),
      );
      expect(() => requestStatusFromCanonical(''), throwsArgumentError);
      expect(() => requestStatusFromCanonical('SEARCHING'), throwsArgumentError);
    });
  });

  group('ServiceType wire names', () {
    // Source of truth: my-car-backend src/common/enums/service-type.enum.ts
    const backendValues = {
      'flatbedTowing',
      'batteryJump',
      'tireRepair',
      'carTowing',
      'batteryReplacement',
      'fuelDelivery',
    };

    test('app enum names match backend enum values one-to-one', () {
      expect(ServiceType.values.map((t) => t.name).toSet(), backendValues);
    });
  });

  group('DriverModel.fromJson', () {
    test('maps every field of the backend public driver shape', () {
      final d = DriverModel.fromJson(driverJson(overrides: {'distanceKm': 2.4}));
      expect(d.id, 'drv-1');
      expect(d.name, 'Ahmed Al-Rashidi');
      expect(d.phone, '+966501234567');
      expect(d.rating, 4.9);
      expect(d.totalJobs, 1243);
      expect(d.vehicleType, 'Flatbed Carrier');
      expect(d.vehiclePlate, 'ABC 1234');
      expect(d.avatarInitials, 'AA');
      expect(d.distanceKm, 2.4);
    });

    test('distanceKm is optional (backend omits it on request payloads) -> 0.0', () {
      final json = driverJson()..remove('distanceKm');
      expect(DriverModel.fromJson(json).distanceKm, 0.0);
      expect(DriverModel.fromJson(driverJson(overrides: {'distanceKm': null})).distanceKm, 0.0);
    });

    test('integer rating (backend default is 5) is accepted as a double', () {
      final d = DriverModel.fromJson(driverJson(overrides: {'rating': 5}));
      expect(d.rating, 5.0);
      expect(d.rating, isA<double>());
    });

    test('missing required field throws', () {
      final json = driverJson()..remove('phone');
      expect(() => DriverModel.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  group('serviceRequestFromJson', () {
    test('maps a freshly created (searching) request', () {
      final r = serviceRequestFromJson(requestJson());
      expect(r.id, 'req-1');
      expect(r.customerId, 'cust-9');
      expect(r.serviceType, ServiceType.batteryJump);
      expect(r.customerLocation, const LatLng(24.7136, 46.6753));
      expect(r.customerAddress, 'Olaya St, Riyadh');
      expect(r.estimatedPrice, 77.5);
      expect(r.finalPrice, isNull);
      expect(r.estimatedMinutes, 15);
      expect(r.status, RequestStatus.searching);
      expect(r.assignedDriver, isNull);
      expect(r.driverLocation, isNull);
      expect(r.createdAt, DateTime.utc(2026, 10, 1, 10));
      expect(r.createdAt.isUtc, isTrue);
      expect(r.notes, isNull);
      expect(r.rating, isNull);
      expect(r.review, isNull);
      expect(r.cashCollected, isFalse);
      expect(r.photoPaths, isEmpty);
      expect(r.photoUrls, isEmpty);
    });

    test('maps backend photoUrls as-is (server-relative paths), separate from local photoPaths', () {
      final r = serviceRequestFromJson(requestJson(overrides: {
        'photoUrls': ['/uploads/requests/a.jpg', '/uploads/requests/b.jpg'],
      }));
      expect(r.photoUrls, ['/uploads/requests/a.jpg', '/uploads/requests/b.jpg']);
      expect(r.photoPaths, isEmpty);
    });

    test('missing or null photoUrls maps to an empty list', () {
      expect(serviceRequestFromJson(requestJson()..remove('photoUrls')).photoUrls, isEmpty);
      expect(serviceRequestFromJson(requestJson(overrides: {'photoUrls': null})).photoUrls, isEmpty);
    });

    test('non-string photoUrls entries throw eagerly (inside the mapper, not later on access)', () {
      expect(
        () => serviceRequestFromJson(requestJson(overrides: {'photoUrls': [1, 2]})),
        throwsA(isA<TypeError>()),
      );
    });

    test('maps an assigned request with driver + live driver location', () {
      final r = serviceRequestFromJson(requestJson(overrides: {
        'status': 'driverEnRoute',
        'assignedDriver': driverJson(),
        'driverLocation': {'lat': 24.72, 'lng': 46.68},
        'notes': 'Blue Camry, hazard lights on',
      }));
      expect(r.status, RequestStatus.driverEnRoute);
      expect(r.assignedDriver, isNotNull);
      expect(r.assignedDriver!.id, 'drv-1');
      expect(r.assignedDriver!.distanceKm, 0.0);
      expect(r.driverLocation, const LatLng(24.72, 46.68));
      expect(r.notes, 'Blue Camry, hazard lights on');
    });

    test('maps a completed + rated request: finalPrice drives displayPrice', () {
      final r = serviceRequestFromJson(requestJson(overrides: {
        'status': 'completed',
        'finalPrice': 90,
        'cashCollected': true,
        'rating': 4,
        'review': 'Quick and friendly',
        'assignedDriver': driverJson(),
      }));
      expect(r.status, RequestStatus.completed);
      expect(r.finalPrice, 90.0);
      expect(r.displayPrice, 90.0);
      expect(r.cashCollected, isTrue);
      expect(r.rating, 4);
      expect(r.review, 'Quick and friendly');
    });

    test('displayPrice falls back to the estimate while finalPrice is null', () {
      expect(serviceRequestFromJson(requestJson()).displayPrice, 77.5);
    });

    test('integer estimatedPrice is accepted as double', () {
      final r = serviceRequestFromJson(requestJson(overrides: {'estimatedPrice': 75}));
      expect(r.estimatedPrice, 75.0);
      expect(r.estimatedPrice, isA<double>());
    });

    test('absent optional keys behave like explicit nulls', () {
      final json = requestJson()
        ..remove('customerId')
        ..remove('finalPrice')
        ..remove('assignedDriver')
        ..remove('driverLocation')
        ..remove('notes')
        ..remove('rating')
        ..remove('review')
        ..remove('cashCollected');
      final r = serviceRequestFromJson(json);
      expect(r.customerId, isNull);
      expect(r.finalPrice, isNull);
      expect(r.assignedDriver, isNull);
      expect(r.driverLocation, isNull);
      expect(r.notes, isNull);
      expect(r.rating, isNull);
      expect(r.review, isNull);
      expect(r.cashCollected, isFalse);
    });

    test('extra backend-only keys (customerName, paymentMethod, ...) are ignored', () {
      final r = serviceRequestFromJson(requestJson(overrides: {
        'dropoffLocation': {'lat': 1, 'lng': 2},
        'somethingNew': {'nested': true},
      }));
      expect(r.id, 'req-1');
    });

    test('unknown serviceType throws ArgumentError (no silent fallback)', () {
      expect(
        () => serviceRequestFromJson(requestJson(overrides: {'serviceType': 'helicopterLift'})),
        throwsArgumentError,
      );
    });

    test('unknown status throws ArgumentError', () {
      expect(
        () => serviceRequestFromJson(requestJson(overrides: {'status': 'declined'})),
        throwsArgumentError,
      );
    });

    test('missing required fields throw', () {
      for (final key in ['id', 'pickupLocation', 'pickupAddress', 'estimatedPrice', 'createdAt']) {
        final json = requestJson()..remove(key);
        expect(() => serviceRequestFromJson(json), throwsA(anything), reason: 'missing $key');
      }
    });

    test('malformed createdAt throws FormatException', () {
      expect(
        () => serviceRequestFromJson(requestJson(overrides: {'createdAt': 'yesterday'})),
        throwsFormatException,
      );
    });
  });

  group('ServiceRequest.copyWith', () {
    test('patching driverLocation keeps server-only fields (finalPrice, cashCollected, customerId)',
        () {
      final base = serviceRequestFromJson(requestJson(overrides: {
        'status': 'inProgress',
        'finalPrice': 99.0,
        'cashCollected': true,
      }));
      final moved = base.copyWith(driverLocation: const LatLng(1, 2));
      expect(moved.driverLocation, const LatLng(1, 2));
      expect(moved.finalPrice, 99.0);
      expect(moved.cashCollected, isTrue);
      expect(moved.customerId, 'cust-9');
      expect(moved.status, RequestStatus.inProgress);
      expect(moved.photoUrls, base.photoUrls);
      expect(moved.createdAt, base.createdAt);
    });
  });
}
