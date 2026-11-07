import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/data/repositories/api_roadside_repository.dart';

import 'helpers/roadside_fakes.dart';

/// Polls until [condition] holds (real-time, short) so async Dio + socket
/// plumbing can settle without fixed sleeps.
Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

Matcher isApiException({Object? message, Object? statusCode}) {
  var m = isA<ApiException>();
  if (message != null) m = m.having((e) => e.message, 'message', message);
  if (statusCode != null) m = m.having((e) => e.statusCode, 'statusCode', statusCode);
  return m;
}

void main() {
  late FakeHttpAdapter http;
  late FakeSocket socket;
  late ApiRoadsideRepository repo;

  const riyadh = LatLng(24.7136, 46.6753);

  setUp(() async {
    http = FakeHttpAdapter();
    socket = FakeSocket();
    final api = await buildApiClient(http, token: 'tok-123');
    repo = ApiRoadsideRepository(api, FakeSocketClient(socket));
  });

  test('never targets anything but the fake transport', () async {
    http.reply('GET', '/service-requests/price-estimate', 200, {'estimatedPrice': 1});
    await repo.getEstimatedPrice(ServiceType.tireRepair, riyadh);
    // Request went through the fake adapter (so not over the network).
    expect(http.requests, hasLength(1));
  });

  group('auth header', () {
    test('sends Bearer token from the session', () async {
      http.reply('GET', '/service-requests/history', 200, <Object>[]);
      await repo.getHistory();
      expect(http.requests.single.headers['Authorization'], 'Bearer tok-123');
    });

    test('omits Authorization when logged out', () async {
      final api = await buildApiClient(http);
      final anon = ApiRoadsideRepository(api, FakeSocketClient(socket));
      http.reply('GET', '/service-requests/history', 200, <Object>[]);
      await anon.getHistory();
      expect(http.requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('getEstimatedPrice', () {
    test('GETs /service-requests/price-estimate with serviceType + lat/lng query', () async {
      http.reply('GET', '/service-requests/price-estimate', 200, {'estimatedPrice': 82.35, 'estimatedMinutes': 25});

      final price = await repo.getEstimatedPrice(ServiceType.flatbedTowing, riyadh);

      expect(price, 82.35);
      final req = http.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/service-requests/price-estimate');
      expect(req.uri.queryParameters, {
        'serviceType': 'flatbedTowing',
        'lat': '24.7136',
        'lng': '46.6753',
      });
    });

    test('integer price from backend becomes a double', () async {
      http.reply('GET', '/service-requests/price-estimate', 200, {'estimatedPrice': 150});
      final price = await repo.getEstimatedPrice(ServiceType.flatbedTowing, riyadh);
      expect(price, 150.0);
      expect(price, isA<double>());
    });

    test('400 with class-validator message list -> ApiException joining messages', () async {
      http.reply('GET', '/service-requests/price-estimate', 400, {
        'statusCode': 400,
        'message': ['lat must be a number', 'serviceType must be one of ...'],
        'error': 'Bad Request',
      });
      await expectLater(
        repo.getEstimatedPrice(ServiceType.batteryJump, riyadh),
        throwsA(isApiException(
          message: 'lat must be a number, serviceType must be one of ...',
          statusCode: 400,
        )),
      );
    });

    test('401 with string message -> ApiException carrying status', () async {
      http.reply('GET', '/service-requests/price-estimate', 401, {'statusCode': 401, 'message': 'Unauthorized'});
      await expectLater(
        repo.getEstimatedPrice(ServiceType.batteryJump, riyadh),
        throwsA(isApiException(message: 'Unauthorized', statusCode: 401)),
      );
    });

    test('500 without a message body -> ApiException with status 500', () async {
      http.reply('GET', '/service-requests/price-estimate', 500);
      await expectLater(
        repo.getEstimatedPrice(ServiceType.batteryJump, riyadh),
        throwsA(isApiException(statusCode: 500)),
      );
    });

    test('connection timeout -> friendly timeout ApiException', () async {
      http.on('GET', '/service-requests/price-estimate',
          (o) => throw DioException.connectionTimeout(timeout: const Duration(seconds: 10), requestOptions: o));
      await expectLater(
        repo.getEstimatedPrice(ServiceType.batteryJump, riyadh),
        throwsA(isApiException(message: contains('timed out'), statusCode: isNull)),
      );
    });

    test('unreachable server -> friendly connection ApiException', () async {
      http.on('GET', '/service-requests/price-estimate',
          (o) => throw DioException.connectionError(requestOptions: o, reason: 'Failed host lookup'));
      await expectLater(
        repo.getEstimatedPrice(ServiceType.batteryJump, riyadh),
        throwsA(isApiException(message: contains('Could not reach the server'))),
      );
    });

    test('200 with a body missing estimatedPrice fails rather than returning a bogus price', () async {
      http.reply('GET', '/service-requests/price-estimate', 200, {'unexpected': true});
      await expectLater(
        repo.getEstimatedPrice(ServiceType.batteryJump, riyadh),
        throwsA(isApiException(message: contains('Unexpected response'), statusCode: isNull)),
      );
    });
  });

  group('reverseGeocode', () {
    test('GETs /geocode/reverse with lat/lng and returns the address', () async {
      http.reply('GET', '/geocode/reverse', 200, {'address': 'King Fahd Rd, Riyadh'});
      final address = await repo.reverseGeocode(riyadh);
      expect(address, 'King Fahd Rd, Riyadh');
      expect(http.requests.single.uri.queryParameters, {'lat': '24.7136', 'lng': '46.6753'});
    });

    test('errors are mapped to ApiException', () async {
      http.reply('GET', '/geocode/reverse', 502, {'message': 'Geocoder unavailable'});
      await expectLater(
        repo.reverseGeocode(riyadh),
        throwsA(isApiException(message: 'Geocoder unavailable', statusCode: 502)),
      );
    });
  });

  group('createRequest', () {
    test('POSTs CreateRequestDto shape and maps the created request', () async {
      http.reply('POST', '/service-requests', 201, requestJson());

      final created = await repo.createRequest(
        type: ServiceType.batteryJump,
        location: riyadh,
        address: 'Olaya St, Riyadh',
        notes: 'Gate 3',
      );

      final req = http.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/service-requests');
      expect(req.body, {
        'serviceType': 'batteryJump',
        'location': {'lat': 24.7136, 'lng': 46.6753},
        'address': 'Olaya St, Riyadh',
        'notes': 'Gate 3',
      });
      expect(created.id, 'req-1');
      expect(created.status, RequestStatus.searching);
      expect(created.estimatedPrice, 77.5);
      expect(created.customerLocation, riyadh);
    });

    test('maps photoUrls from the created request', () async {
      http.reply('POST', '/service-requests', 201, requestJson(overrides: {
        'photoUrls': ['/uploads/requests/x.jpg'],
      }));
      final created = await repo.createRequest(type: ServiceType.tireRepair, location: riyadh, address: 'X');
      expect(created.photoUrls, ['/uploads/requests/x.jpg']);
    });

    test('omits notes key when notes is null (backend @IsOptional @IsString)', () async {
      http.reply('POST', '/service-requests', 201, requestJson());
      await repo.createRequest(type: ServiceType.tireRepair, location: riyadh, address: 'X');
      expect((http.requests.single.body as Map).containsKey('notes'), isFalse);
    });

    test('validation error -> ApiException', () async {
      http.reply('POST', '/service-requests', 400, {
        'message': ['address must be a string'],
      });
      await expectLater(
        repo.createRequest(type: ServiceType.tireRepair, location: riyadh, address: 'X'),
        throwsA(isApiException(message: 'address must be a string', statusCode: 400)),
      );
    });
  });

  group('cancelRequest', () {
    test('POSTs /service-requests/:id/cancel', () async {
      http.reply('POST', '/service-requests/req-1/cancel', 201, requestJson(overrides: {'status': 'cancelled'}));
      await repo.cancelRequest('req-1');
      final req = http.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/service-requests/req-1/cancel');
    });

    test('backend refusal surfaces as ApiException', () async {
      http.reply('POST', '/service-requests/req-1/cancel', 400, {'message': 'Cannot cancel a completed request'});
      await expectLater(
        repo.cancelRequest('req-1'),
        throwsA(isApiException(message: 'Cannot cancel a completed request', statusCode: 400)),
      );
    });
  });

  group('rateDriver', () {
    test('POSTs stars + review to /service-requests/:id/rate', () async {
      http.reply('POST', '/service-requests/req-1/rate', 201, requestJson());
      await repo.rateDriver('req-1', 5, 'Great');
      final req = http.requests.single;
      expect(req.uri.path, '/service-requests/req-1/rate');
      expect(req.body, {'stars': 5, 'review': 'Great'});
    });

    test('omits review when null', () async {
      http.reply('POST', '/service-requests/req-1/rate', 201, requestJson());
      await repo.rateDriver('req-1', 3, null);
      expect(http.requests.single.body, {'stars': 3});
    });

    test('rating a non-completed request -> ApiException', () async {
      http.reply('POST', '/service-requests/req-1/rate', 400, {'message': 'Can only rate a completed request'});
      await expectLater(
        repo.rateDriver('req-1', 5, null),
        throwsA(isApiException(message: 'Can only rate a completed request', statusCode: 400)),
      );
    });
  });

  group('getHistory', () {
    test('GETs /service-requests/history and maps each entry in order', () async {
      http.reply('GET', '/service-requests/history', 200, [
        requestJson(overrides: {'id': 'a', 'status': 'completed', 'finalPrice': 90}),
        requestJson(overrides: {'id': 'b', 'status': 'cancelled', 'serviceType': 'fuelDelivery'}),
      ]);
      final history = await repo.getHistory();
      expect(history.map((r) => r.id), ['a', 'b']);
      expect(history[0].status, RequestStatus.completed);
      expect(history[0].displayPrice, 90.0);
      expect(history[1].status, RequestStatus.cancelled);
      expect(history[1].serviceType, ServiceType.fuelDelivery);
    });

    test('empty list', () async {
      http.reply('GET', '/service-requests/history', 200, <Object>[]);
      expect(await repo.getHistory(), isEmpty);
    });

    test('errors -> ApiException', () async {
      http.reply('GET', '/service-requests/history', 403, {'message': 'Forbidden resource'});
      await expectLater(repo.getHistory(), throwsA(isApiException(statusCode: 403)));
    });
  });

  group('malformed 200 bodies surface as ApiException, not TypeError/ArgumentError', () {
    final unexpected = isApiException(message: contains('Unexpected response'));

    test('reverseGeocode without an address', () async {
      http.reply('GET', '/geocode/reverse', 200, {'formatted': 'x'});
      await expectLater(repo.reverseGeocode(riyadh), throwsA(unexpected));
    });

    test('createRequest with an unknown serviceType', () async {
      http.reply('POST', '/service-requests', 201, requestJson(overrides: {'serviceType': 'helicopterLift'}));
      await expectLater(
        repo.createRequest(type: ServiceType.tireRepair, location: riyadh, address: 'X'),
        throwsA(unexpected),
      );
    });

    test('createRequest with a non-object body', () async {
      http.reply('POST', '/service-requests', 201, ['not', 'an', 'object']);
      await expectLater(
        repo.createRequest(type: ServiceType.tireRepair, location: riyadh, address: 'X'),
        throwsA(unexpected),
      );
    });

    test('getHistory with an unknown status in one entry', () async {
      http.reply('GET', '/service-requests/history', 200, [
        requestJson(),
        requestJson(overrides: {'id': 'b', 'status': 'paused'}),
      ]);
      await expectLater(repo.getHistory(), throwsA(unexpected));
    });

    test('getHistory with an object instead of a list', () async {
      http.reply('GET', '/service-requests/history', 200, {'items': <Object>[]});
      await expectLater(repo.getHistory(), throwsA(unexpected));
    });

    test('getHistory with a bad createdAt', () async {
      http.reply('GET', '/service-requests/history', 200, [
        requestJson(overrides: {'createdAt': 'yesterday'}),
      ]);
      await expectLater(repo.getHistory(), throwsA(unexpected));
    });
  });

  group('watchRequest', () {
    late List<ServiceRequest> events;
    late List<Object> errors;
    StreamSubscription<ServiceRequest>? sub;

    void listen([String id = 'req-1']) {
      sub = repo.watchRequest(id).listen(events.add, onError: errors.add);
    }

    int getCount(String path) =>
        http.requests.where((r) => r.method == 'GET' && r.uri.path == path).length;

    setUp(() {
      events = [];
      errors = [];
    });

    tearDown(() async {
      await sub?.cancel();
      sub = null;
    });

    test('hydrates via GET /service-requests/:id on listen, then subscribes to socket events',
        () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson());
      listen();
      await until(() => events.isNotEmpty);

      expect(getCount('/service-requests/req-1'), 1);
      expect(events.single.status, RequestStatus.searching);
      expect(socket.handlerCount('driver-assigned'), 1);
      expect(socket.handlerCount('driver-location-update'), 1);
      expect(socket.handlerCount('status-changed'), 1);
    });

    test('driver-assigned for this request re-hydrates and emits the driver', () async {
      var hydrations = 0;
      http.on('GET', '/service-requests/req-1', (_) {
        hydrations++;
        return FakeReply(
          200,
          hydrations == 1
              ? requestJson()
              : requestJson(overrides: {
                  'status': 'driverAssigned',
                  'assignedDriver': driverJson(),
                  'driverLocation': {'lat': 24.70, 'lng': 46.66},
                }),
        );
      });
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('driver-assigned', {
        'requestId': 'req-1',
        'driver': driverJson(),
        'driverLocation': {'lat': 24.70, 'lng': 46.66},
      });
      await until(() => events.length == 2);

      expect(events.last.status, RequestStatus.driverFound);
      expect(events.last.assignedDriver?.id, 'drv-1');
      expect(events.last.driverLocation, const LatLng(24.70, 46.66));
    });

    test('driver-location-update patches location only, keeping everything else', () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson(overrides: {
        'status': 'driverEnRoute',
        'assignedDriver': driverJson(),
        'driverLocation': {'lat': 24.70, 'lng': 46.66},
      }));
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('driver-location-update', {
        'requestId': 'req-1',
        'location': {'lat': 24.71, 'lng': 46.67},
      });
      await until(() => events.length == 2);

      expect(events.last.driverLocation, const LatLng(24.71, 46.67));
      expect(events.last.status, RequestStatus.driverEnRoute);
      expect(events.last.assignedDriver?.id, 'drv-1');
      // No extra HTTP round trip for a location tick.
      expect(getCount('/service-requests/req-1'), 1);
    });

    test('status-changed (non-terminal) patches status without an HTTP round trip', () async {
      http.reply('GET', '/service-requests/req-1', 200,
          requestJson(overrides: {'status': 'driverAssigned', 'assignedDriver': driverJson()}));
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'driverEnRoute'});
      socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'arrived'});
      await until(() => events.length == 3);

      expect(events.map((e) => e.status), [
        RequestStatus.driverFound,
        RequestStatus.driverEnRoute,
        RequestStatus.arrived,
      ]);
      expect(events.last.assignedDriver?.id, 'drv-1');
      expect(getCount('/service-requests/req-1'), 1);
    });

    test('status-changed: completed re-hydrates to pick up finalPrice + cashCollected', () async {
      var hydrations = 0;
      http.on('GET', '/service-requests/req-1', (_) {
        hydrations++;
        return FakeReply(
          200,
          hydrations == 1
              ? requestJson(overrides: {'status': 'inProgress', 'assignedDriver': driverJson()})
              : requestJson(overrides: {
                  'status': 'completed',
                  'assignedDriver': driverJson(),
                  'finalPrice': 95.0,
                  'cashCollected': true,
                }),
        );
      });
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'completed'});
      await until(() => events.length == 2);

      expect(hydrations, 2);
      expect(events.last.status, RequestStatus.completed);
      expect(events.last.finalPrice, 95.0);
      expect(events.last.displayPrice, 95.0);
      expect(events.last.cashCollected, isTrue);
    });

    test('status-changed: cancelled (by driver) is delivered', () async {
      http.reply('GET', '/service-requests/req-1', 200,
          requestJson(overrides: {'status': 'driverAssigned', 'assignedDriver': driverJson()}));
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'cancelled'});
      await until(() => events.length == 2);
      expect(events.last.status, RequestStatus.cancelled);
    });

    test('events for other requests are ignored', () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson(overrides: {'status': 'driverEnRoute'}));
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('driver-location-update', {
        'requestId': 'someone-else',
        'location': {'lat': 1, 'lng': 1},
      });
      socket.serverEmit('status-changed', {'requestId': 'someone-else', 'status': 'arrived'});
      socket.serverEmit('driver-assigned', {'requestId': 'someone-else'});
      await settle();

      expect(events, hasLength(1));
      expect(getCount('/service-requests/req-1'), 1);
    });

    test('hydration failure on listen is delivered as a stream error (ApiException)', () async {
      http.reply('GET', '/service-requests/req-1', 404, {'message': 'Request not found'});
      listen();
      await until(() => errors.isNotEmpty);
      expect(errors.single, isApiException(message: 'Request not found', statusCode: 404));
      expect(events, isEmpty);
    });

    test('cancelling the subscription removes all socket handlers', () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson());
      listen();
      await until(() => events.isNotEmpty);
      expect(socket.totalHandlers, 3);

      await sub!.cancel();
      sub = null;
      expect(socket.totalHandlers, 0);
    });

    test('re-listening after cancel re-registers exactly one set of handlers', () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson());
      listen();
      await until(() => events.isNotEmpty);
      await sub!.cancel();

      listen();
      await until(() => events.length == 2);
      expect(socket.totalHandlers, 3);
      expect(getCount('/service-requests/req-1'), 2);
    });

    test(
      'cancelling before hydration finishes must not leave socket handlers registered',
      () async {
        final gate = Completer<void>();
        http.on('GET', '/service-requests/req-1', (_) async {
          await gate.future;
          return FakeReply(200, requestJson());
        });
        listen();
        await settle();
        await sub!.cancel();
        sub = null;

        gate.complete();
        await settle();

        expect(socket.totalHandlers, 0);
      },
    );

    test(
      'a re-hydration failure after driver-assigned is surfaced as a stream error, not an '
      'uncaught async error',
      () async {
        var hydrations = 0;
        http.on('GET', '/service-requests/req-1', (_) {
          hydrations++;
          return hydrations == 1
              ? FakeReply(200, requestJson())
              : FakeReply(503, {'message': 'Service Unavailable'});
        });
        listen();
        await until(() => events.length == 1);

        socket.serverEmit('driver-assigned', {'requestId': 'req-1'});
        await until(() => errors.isNotEmpty);
        expect(errors.single, isApiException(statusCode: 503));
      },
    );

    test(
      'an unknown status in status-changed does not throw out of the socket handler',
      () async {
        http.reply('GET', '/service-requests/req-1', 200, requestJson(overrides: {'status': 'driverAssigned'}));
        listen();
        await until(() => events.length == 1);

        expect(
          () => socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'paused'}),
          returnsNormally,
        );
        socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'driverEnRoute'});
        await until(() => events.length == 2);
        expect(events.last.status, RequestStatus.driverEnRoute);
        // Ignored rather than reported: an unknown-to-this-app status is not
        // something the user can act on.
        expect(errors, isEmpty);
      },
    );

    test(
      'a status change that arrives while the initial hydration is in flight is not lost',
      () async {
        final gate = Completer<void>();
        http.on('GET', '/service-requests/req-1', (_) async {
          await gate.future;
          // Snapshot taken before the driver started moving.
          return FakeReply(200, requestJson(overrides: {'status': 'driverAssigned'}));
        });
        listen();
        await settle();

        socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'driverEnRoute'});
        gate.complete();
        await until(() => events.isNotEmpty);
        await settle();

        expect(events.last.status, RequestStatus.driverEnRoute);
      },
    );

    test('socket handlers are attached synchronously on listen, before the GET resolves', () async {
      final gate = Completer<void>();
      http.on('GET', '/service-requests/req-1', (_) async {
        await gate.future;
        return FakeReply(200, requestJson());
      });
      listen();
      expect(socket.totalHandlers, 3);
      gate.complete();
      await until(() => events.isNotEmpty);
      expect(socket.totalHandlers, 3);
    });

    test('a driver-assigned that arrives during the initial hydration re-hydrates afterwards', () async {
      final gate = Completer<void>();
      var hydrations = 0;
      http.on('GET', '/service-requests/req-1', (_) async {
        hydrations++;
        if (hydrations == 1) {
          await gate.future;
          return FakeReply(200, requestJson());
        }
        return FakeReply(200, requestJson(overrides: {
          'status': 'driverAssigned',
          'assignedDriver': driverJson(),
        }));
      });
      listen();
      await settle();

      socket.serverEmit('driver-assigned', {'requestId': 'req-1'});
      gate.complete();
      await until(() => events.length == 2);

      expect(hydrations, 2);
      expect(events.map((e) => e.status), [RequestStatus.searching, RequestStatus.driverFound]);
      expect(events.last.assignedDriver?.id, 'drv-1');
    });

    test('a hydration from a cancelled listen does not leak into the next listen', () async {
      final gate = Completer<void>();
      var hydrations = 0;
      http.on('GET', '/service-requests/req-1', (_) async {
        hydrations++;
        if (hydrations == 1) {
          await gate.future;
          return FakeReply(200, requestJson(overrides: {'status': 'searching'}));
        }
        return FakeReply(200, requestJson(overrides: {'status': 'driverAssigned'}));
      });
      listen();
      await settle();
      await sub!.cancel();

      listen();
      await until(() => events.isNotEmpty);
      gate.complete();
      await settle();

      expect(events.map((e) => e.status), [RequestStatus.driverFound]);
      expect(socket.totalHandlers, 3);
    });

    test('a re-hydration failure after status-changed: completed is surfaced as a stream error',
        () async {
      var hydrations = 0;
      http.on('GET', '/service-requests/req-1', (_) {
        hydrations++;
        return hydrations == 1
            ? FakeReply(200, requestJson(overrides: {'status': 'inProgress'}))
            : FakeReply(500, {'message': 'Internal server error'});
      });
      listen();
      await until(() => events.length == 1);

      socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': 'completed'});
      await until(() => errors.isNotEmpty);
      expect(errors.single, isApiException(message: 'Internal server error', statusCode: 500));
      expect(events, hasLength(1));
    });

    test('a malformed initial body is delivered as a stream ApiException', () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson(overrides: {'status': 'paused'}));
      listen();
      await until(() => errors.isNotEmpty);
      expect(errors.single, isApiException(message: contains('Unexpected response')));
      expect(events, isEmpty);
    });

    test('malformed socket payloads are ignored without throwing', () async {
      http.reply('GET', '/service-requests/req-1', 200, requestJson(overrides: {'status': 'driverEnRoute'}));
      listen();
      await until(() => events.length == 1);

      expect(() => socket.serverEmit('driver-location-update', 'garbage'), returnsNormally);
      expect(
        () => socket.serverEmit('driver-location-update', {'requestId': 'req-1', 'location': null}),
        returnsNormally,
      );
      expect(
        () => socket.serverEmit('status-changed', {'requestId': 'req-1', 'status': null}),
        returnsNormally,
      );
      expect(() => socket.serverEmit('driver-assigned', null), returnsNormally);
      await settle();
      expect(events, hasLength(1));
      expect(errors, isEmpty);
    });
  });

  group('photos', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('roadside-photos-'));
    tearDown(() => dir.deleteSync(recursive: true));

    String photo(String name, [List<int> bytes = const [0xff, 0xd8, 0xff, 0xe0]]) {
      final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
      return file.path;
    }

    test('uploadPhotos POSTs every file in the multipart `photos` field and returns the URLs',
        () async {
      http.reply('POST', '/service-requests/photos', 201, {
        'photoUrls': ['/uploads/request-photos/c/1.jpg', '/uploads/request-photos/c/2.png'],
      });

      final urls = await repo.uploadPhotos([photo('a.jpg'), photo('b.png')]);

      expect(urls, ['/uploads/request-photos/c/1.jpg', '/uploads/request-photos/c/2.png']);
      final req = http.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/service-requests/photos');
      expect(req.headers['Authorization'], 'Bearer tok-123');
      expect(req.form!.fields, isEmpty);
      expect(req.form!.files.map((f) => f.key), ['photos', 'photos']);
      expect(req.form!.files.map((f) => f.value.filename), ['a.jpg', 'b.png']);
      // The bytes actually went over the wire.
      expect(req.body, contains('filename="a.jpg"'));
      expect(req.body, contains('name="photos"'));
    });

    test('labels each part with an image content type the backend accepts', () async {
      http.on('POST', '/service-requests/photos', (o) {
        final count = (o.data as FormData).files.length;
        return FakeReply(201, {'photoUrls': List.generate(count, (i) => '/u/$i')});
      });
      await repo.uploadPhotos([
        photo('a.jpg'),
        photo('b.JPEG'),
        photo('c.png'),
        photo('d.webp'),
        photo('e.HEIC'),
        photo('f.heif'),
        photo('no_extension'),
      ]);
      expect(
        http.requests.single.form!.files.map((f) => f.value.contentType.toString()),
        [
          'image/jpeg',
          'image/jpeg',
          'image/png',
          'image/webp',
          'image/heic',
          'image/heif',
          'image/jpeg',
        ],
      );
    });

    test('no paths -> no request', () async {
      expect(await repo.uploadPhotos(const []), isEmpty);
      expect(http.requests, isEmpty);
    });

    test('backend rejection -> ApiException with its status', () async {
      http.reply('POST', '/service-requests/photos', 413, {'message': 'File too large'});
      await expectLater(
        repo.uploadPhotos([photo('a.jpg')]),
        throwsA(isApiException(message: 'File too large', statusCode: 413)),
      );
    });

    test('a response without one URL per photo -> ApiException', () async {
      http.reply('POST', '/service-requests/photos', 201, {'photoUrls': ['/u/1']});
      await expectLater(
        repo.uploadPhotos([photo('a.jpg'), photo('b.jpg')]),
        throwsA(isApiException()),
      );
      http.reply('POST', '/service-requests/photos', 201, {'urls': <String>[]});
      await expectLater(repo.uploadPhotos([photo('a.jpg')]), throwsA(isApiException()));
    });

    test('a photo file that no longer exists fails before anything is sent', () async {
      await expectLater(
        repo.uploadPhotos(['${dir.path}/gone.jpg']),
        throwsA(isA<FileSystemException>()),
      );
      expect(http.requests, isEmpty);
    });

    test('createRequestWithPhotos sends photoUrls with the request', () async {
      http.reply('POST', '/service-requests', 201, requestJson(overrides: {
        'photoUrls': ['/uploads/request-photos/c/1.jpg'],
      }));
      final created = await repo.createRequestWithPhotos(
        type: ServiceType.tireRepair,
        location: riyadh,
        address: 'X',
        photoUrls: ['/uploads/request-photos/c/1.jpg'],
      );
      expect(http.requests.single.body, {
        'serviceType': 'tireRepair',
        'location': {'lat': 24.7136, 'lng': 46.6753},
        'address': 'X',
        'photoUrls': ['/uploads/request-photos/c/1.jpg'],
      });
      expect(created.photoUrls, ['/uploads/request-photos/c/1.jpg']);
    });

    test('no photos -> no photoUrls key (same body as createRequest)', () async {
      http.reply('POST', '/service-requests', 201, requestJson());
      await repo.createRequestWithPhotos(
          type: ServiceType.tireRepair, location: riyadh, address: 'X', photoUrls: const []);
      await repo.createRequest(type: ServiceType.tireRepair, location: riyadh, address: 'X');
      for (final req in http.requests) {
        expect((req.body as Map).containsKey('photoUrls'), isFalse);
      }
    });
  });
}
