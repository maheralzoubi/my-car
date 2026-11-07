import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/modules/roadside/data/models/driver_model.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/data/repositories/mock_roadside_repository.dart';

// The mock is driven by Future.delayed / Timer.periodic, so these tests run
// under testWidgets' fake clock and advance time with tester.pump().

const _customer = LatLng(24.7136, 46.6753);

double _deg(LatLng a, LatLng b) =>
    sqrt(pow(a.latitude - b.latitude, 2) + pow(a.longitude - b.longitude, 2));

Future<T> _settle<T>(WidgetTester tester, Future<T> future, Duration d) async {
  await tester.pump(d);
  return future;
}

Future<void> _advance(WidgetTester tester, Duration total) async {
  final steps = total.inMilliseconds ~/ 500;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<ServiceRequest> _create(
  WidgetTester tester,
  MockRoadsideRepository repo, {
  ServiceType type = ServiceType.batteryJump,
  String? notes,
}) {
  return _settle(
    tester,
    repo.createRequest(type: type, location: _customer, address: 'Olaya St', notes: notes),
    const Duration(milliseconds: 400),
  );
}

List<RequestStatus> _distinctStatuses(Iterable<ServiceRequest> events) {
  final out = <RequestStatus>[];
  for (final e in events) {
    if (out.isEmpty || out.last != e.status) out.add(e.status);
  }
  return out;
}

void main() {
  testWidgets('getEstimatedPrice = basePrice + (2..5 km * 5/km) for every service', (tester) async {
    final repo = MockRoadsideRepository();
    for (final type in ServiceType.values) {
      final price = await _settle(
        tester,
        repo.getEstimatedPrice(type, _customer),
        const Duration(milliseconds: 300),
      );
      expect(price, inInclusiveRange(type.basePrice + 10, type.basePrice + 25), reason: type.name);
    }
  });

  testWidgets('reverseGeocode returns a non-empty address', (tester) async {
    final repo = MockRoadsideRepository();
    final address = await _settle(tester, repo.reverseGeocode(_customer), const Duration(milliseconds: 200));
    expect(address, isNotEmpty);
  });

  testWidgets('createRequest returns a searching request built from the inputs', (tester) async {
    final repo = MockRoadsideRepository();
    final r = await _create(tester, repo, type: ServiceType.flatbedTowing, notes: 'Gate 3');

    expect(r.id, isNotEmpty);
    expect(r.status, RequestStatus.searching);
    expect(r.serviceType, ServiceType.flatbedTowing);
    expect(r.customerLocation, _customer);
    expect(r.customerAddress, 'Olaya St');
    expect(r.notes, 'Gate 3');
    expect(r.estimatedPrice, ServiceType.flatbedTowing.basePrice + 12.5);
    expect(r.estimatedMinutes, ServiceType.flatbedTowing.etaMinutes);
    expect(r.assignedDriver, isNull);

    final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
    expect(history.first.id, r.id);

    // Drain the simulation so no timers are left pending.
    await _advance(tester, const Duration(seconds: 90));
  });

  testWidgets('photos: uploadPhotos echoes the local paths and the request keeps them', (tester) async {
    final repo = MockRoadsideRepository();
    final urls = await _settle(
      tester,
      repo.uploadPhotos(['/tmp/a.jpg', '/tmp/b.jpg']),
      const Duration(milliseconds: 300),
    );
    expect(urls, ['/tmp/a.jpg', '/tmp/b.jpg']);

    final r = await _settle(
      tester,
      repo.createRequestWithPhotos(
        type: ServiceType.batteryJump,
        location: _customer,
        address: 'Olaya St',
        photoUrls: urls,
      ),
      const Duration(milliseconds: 400),
    );
    expect(r.photoUrls, urls);
    expect((await _create(tester, repo)).photoUrls, isEmpty);

    await _advance(tester, const Duration(seconds: 90));
  });

  testWidgets('watchRequest on an unknown id is an empty, completed stream', (tester) async {
    final repo = MockRoadsideRepository();
    var done = false;
    final events = <ServiceRequest>[];
    repo.watchRequest('nope').listen(events.add, onDone: () => done = true);
    await tester.pump();
    expect(events, isEmpty);
    expect(done, isTrue);
  });

  testWidgets('simulated lifecycle: driver found -> en route -> approaches -> arrived -> in progress -> completed',
      (tester) async {
    final repo = MockRoadsideRepository();
    final r = await _create(tester, repo);
    final events = <ServiceRequest>[];
    final sub = repo.watchRequest(r.id).listen(events.add);

    await _advance(tester, const Duration(seconds: 3));
    expect(events.where((e) => e.status != RequestStatus.searching), isEmpty,
        reason: 'no driver before 4s');

    await _advance(tester, const Duration(seconds: 90));

    final statuses = _distinctStatuses(events.where((e) => e.status != RequestStatus.searching));
    expect(statuses, [
      RequestStatus.driverFound,
      RequestStatus.driverEnRoute,
      RequestStatus.arrived,
      RequestStatus.inProgress,
      RequestStatus.completed,
    ]);

    final found = events.firstWhere((e) => e.status == RequestStatus.driverFound);
    expect(DriverModel.mockDrivers.map((d) => d.id), contains(found.assignedDriver!.id));
    // Spawned 0.015–0.025° away from the customer.
    expect(_deg(found.driverLocation!, _customer), inInclusiveRange(0.0149, 0.0251));

    // Location ticks while en route move strictly closer to the customer.
    final enRoute = events.where((e) => e.status == RequestStatus.driverEnRoute).toList();
    expect(enRoute.length, greaterThan(3));
    for (var i = 1; i < enRoute.length; i++) {
      expect(
        _deg(enRoute[i].driverLocation!, _customer),
        lessThanOrEqualTo(_deg(enRoute[i - 1].driverLocation!, _customer)),
      );
    }

    final inProgress = events.firstWhere((e) => e.status == RequestStatus.inProgress);
    expect(inProgress.driverLocation, _customer);
    expect(events.last.status, RequestStatus.completed);
    expect(events.last.assignedDriver!.id, found.assignedDriver!.id);
    // The request identity never changes across updates.
    expect(events.map((e) => e.id).toSet(), {r.id});

    final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
    expect(history.single.status, RequestStatus.completed);

    // Not awaited: the cancel future completes in the root zone and would
    // deadlock the fake-async test zone.
    unawaited(sub.cancel());
  });

  group('regression:', () {
    testWidgets(
      'simulated lifecycle follows backend legal transitions (en route -> arrived -> in progress)',
      (tester) async {
        final repo = MockRoadsideRepository();
        final r = await _create(tester, repo);
        final events = <ServiceRequest>[];
        final sub = repo.watchRequest(r.id).listen(events.add);
        await _advance(tester, const Duration(seconds: 90));

        final statuses = _distinctStatuses(events);
        expect(statuses, containsAllInOrder([
          RequestStatus.driverEnRoute,
          RequestStatus.arrived,
          RequestStatus.inProgress,
        ]));
        unawaited(sub.cancel());
      },
    );
  });

  testWidgets('cancelRequest mid-trip emits cancelled, closes the stream and stops simulation',
      (tester) async {
    final repo = MockRoadsideRepository();
    final r = await _create(tester, repo);
    final events = <ServiceRequest>[];
    var closed = false;
    repo.watchRequest(r.id).listen(events.add, onDone: () => closed = true);

    await _advance(tester, const Duration(seconds: 12)); // driver en route + moving
    expect(events.last.status, RequestStatus.driverEnRoute);

    await repo.cancelRequest(r.id);
    await tester.pump();

    expect(events.last.status, RequestStatus.cancelled);
    expect(closed, isTrue);

    final countAtCancel = events.length;
    await _advance(tester, const Duration(seconds: 90));
    expect(events.length, countAtCancel, reason: 'no updates after cancel');

    final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
    expect(history.single.status, RequestStatus.cancelled);
    expect(repo.watchRequest(r.id), emitsDone);
  });

  group('regression:', () {
    testWidgets(
      'cancelling while still searching marks the request cancelled and it stays cancelled',
      (tester) async {
        final repo = MockRoadsideRepository();
        final r = await _create(tester, repo);
        await repo.cancelRequest(r.id);
        await _advance(tester, const Duration(seconds: 90));

        final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
        expect(history.single.status, RequestStatus.cancelled);
        expect(history.single.assignedDriver, isNull);
      },
    );
  });

  group('regression:', () {
    testWidgets(
      'rateDriver stores rating + review on the request shown in history',
      (tester) async {
        final repo = MockRoadsideRepository();
        final r = await _create(tester, repo);
        await _advance(tester, const Duration(seconds: 90));

        await repo.rateDriver(r.id, 4, 'Good');
        final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
        expect(history.single.status, RequestStatus.completed);
        expect(history.single.rating, 4);
        expect(history.single.review, 'Good');
        // Built with copyWith, so nothing else on the request is dropped.
        expect(history.single.assignedDriver, isNotNull);
        expect(history.single.driverLocation, _customer);
        expect(history.single.estimatedPrice, r.estimatedPrice);
      },
    );
  });

  testWidgets('rateDriver closes the request stream', (tester) async {
    final repo = MockRoadsideRepository();
    final r = await _create(tester, repo);
    var closed = false;
    repo.watchRequest(r.id).listen((_) {}, onDone: () => closed = true);
    await _advance(tester, const Duration(seconds: 90));

    await repo.rateDriver(r.id, 5, null);
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('getHistory is newest-first and unmodifiable', (tester) async {
    final repo = MockRoadsideRepository();
    final first = await _create(tester, repo, type: ServiceType.tireRepair);
    await _create(tester, repo, type: ServiceType.fuelDelivery);

    final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
    expect(history.map((r) => r.serviceType), [ServiceType.fuelDelivery, ServiceType.tireRepair]);
    expect(() => history.add(first), throwsUnsupportedError);

    await _advance(tester, const Duration(seconds: 90));
  });

  group('regression:', () {
    testWidgets('requests created back-to-back get distinct ids', (tester) async {
      final repo = MockRoadsideRepository();
      final first = await _create(tester, repo, type: ServiceType.tireRepair);
      final second = await _create(tester, repo, type: ServiceType.fuelDelivery);
      expect(second.id, isNot(first.id));
      await _advance(tester, const Duration(seconds: 90));
    });

    testWidgets('two requests in flight simulate independently', (tester) async {
      final repo = MockRoadsideRepository();
      final first = await _create(tester, repo, type: ServiceType.tireRepair);
      final second = await _create(tester, repo, type: ServiceType.fuelDelivery);
      final firstEvents = <ServiceRequest>[];
      final secondEvents = <ServiceRequest>[];
      final sub1 = repo.watchRequest(first.id).listen(firstEvents.add);
      final sub2 = repo.watchRequest(second.id).listen(secondEvents.add);

      await _advance(tester, const Duration(seconds: 90));

      expect(firstEvents.last.status, RequestStatus.completed);
      expect(secondEvents.last.status, RequestStatus.completed);
      expect(firstEvents.every((e) => e.id == first.id), isTrue);
      expect(secondEvents.every((e) => e.id == second.id), isTrue);
      unawaited(sub1.cancel());
      unawaited(sub2.cancel());
    });

    testWidgets('cancelling one request does not stop another one\'s simulation', (tester) async {
      final repo = MockRoadsideRepository();
      final first = await _create(tester, repo, type: ServiceType.tireRepair);
      final second = await _create(tester, repo, type: ServiceType.fuelDelivery);
      final secondEvents = <ServiceRequest>[];
      final sub = repo.watchRequest(second.id).listen(secondEvents.add);

      await _advance(tester, const Duration(seconds: 12)); // both en route
      await repo.cancelRequest(first.id);
      await _advance(tester, const Duration(seconds: 90));

      expect(secondEvents.last.status, RequestStatus.completed);
      final history = await _settle(tester, repo.getHistory(), const Duration(milliseconds: 200));
      expect(history.firstWhere((h) => h.id == first.id).status, RequestStatus.cancelled);
      expect(history.firstWhere((h) => h.id == second.id).status, RequestStatus.completed);
      unawaited(sub.cancel());
    });
  });
}
