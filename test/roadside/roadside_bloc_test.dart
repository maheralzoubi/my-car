import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mycar/core/localization/app_localizations.dart';
import 'package:mycar/core/network/api_exception.dart';
import 'package:mycar/modules/roadside/data/models/service_request.dart';
import 'package:mycar/modules/roadside/data/models/service_type.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_bloc.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_event.dart';
import 'package:mycar/modules/roadside/presentation/bloc/roadside_state.dart';

import 'helpers/roadside_fakes.dart';

// bloc_test is not a dev_dependency, so states are collected from bloc.stream.

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

const _loc = LatLng(24.7136, 46.6753);

void main() {
  late FakeRoadsideRepository repo;
  late RoadsideBloc bloc;
  late List<RoadsideState> states;
  late StreamSubscription<RoadsideState> statesSub;

  setUp(() {
    repo = FakeRoadsideRepository();
    bloc = RoadsideBloc(repo);
    states = [];
    statesSub = bloc.stream.listen(states.add);
  });

  tearDown(() async {
    await statesSub.cancel();
    await bloc.close();
  });

  /// Drives the bloc to the estimate screen for [type].
  Future<void> toEstimate({ServiceType type = ServiceType.batteryJump}) async {
    bloc.add(SelectService(type));
    bloc.add(const ConfirmLocation(_loc, 'Olaya St, Riyadh'));
    await settle();
    states.clear();
  }

  /// Drives the bloc through a successful submit; returns the active request.
  Future<ServiceRequest> toSearching() async {
    await toEstimate();
    bloc.add(const SubmitRequest());
    await settle();
    states.clear();
    return bloc.state.activeRequest!;
  }

  test('initial state is an empty idle flow', () {
    final s = bloc.state;
    expect(s.phase, RoadsidePhase.idle);
    expect(s.selectedService, isNull);
    expect(s.customerLocation, isNull);
    expect(s.customerAddress, '');
    expect(s.estimatedPrice, isNull);
    expect(s.activeRequest, isNull);
    expect(s.notes, '');
    expect(s.photoPaths, isEmpty);
    expect(s.isSubmitting, isFalse);
    expect(s.error, isNull);
  });

  test('exposes the injected repository', () {
    expect(bloc.repository, same(repo));
  });

  group('service selection & price estimate', () {
    test('SelectService moves to the location picker with the chosen service', () async {
      bloc.add(const SelectService(ServiceType.tireRepair));
      await settle();
      expect(states, hasLength(1));
      expect(states.single.phase, RoadsidePhase.locationPicker);
      expect(states.single.selectedService, ServiceType.tireRepair);
    });

    test('ConfirmLocation asks the repo for a price for the selected service + location', () async {
      repo.price = 91.25;
      bloc.add(const SelectService(ServiceType.flatbedTowing));
      bloc.add(const ConfirmLocation(_loc, 'Olaya St, Riyadh'));
      await settle();

      expect(repo.priceCalls, [(ServiceType.flatbedTowing, _loc)]);
      final s = states.last;
      expect(s.phase, RoadsidePhase.estimate);
      expect(s.estimatedPrice, 91.25);
      expect(s.customerLocation, _loc);
      expect(s.customerAddress, 'Olaya St, Riyadh');
      expect(s.selectedService, ServiceType.flatbedTowing);
      expect(s.error, isNull);
    });

    test(
      'ConfirmLocation price failure surfaces an error and stays on the location picker',
      () async {
        repo.priceError = ApiException('Could not reach the server.');
        bloc.add(const SelectService(ServiceType.batteryJump));
        bloc.add(const ConfirmLocation(_loc, 'Olaya St'));
        await settle();

        expect(bloc.state.error, 'Could not reach the server.');
        expect(bloc.state.phase, RoadsidePhase.locationPicker);
        expect(bloc.state.estimatedPrice, isNull);
      },
    );

    test('ConfirmLocation retry after a price failure clears the error and proceeds', () async {
      repo.priceError = ApiException('Could not reach the server.');
      bloc.add(const SelectService(ServiceType.batteryJump));
      bloc.add(const ConfirmLocation(_loc, 'Olaya St'));
      await settle();
      expect(bloc.state.error, isNotNull);

      repo.priceError = null;
      bloc.add(const ConfirmLocation(_loc, 'Olaya St'));
      await settle();
      expect(bloc.state.error, isNull);
      expect(bloc.state.phase, RoadsidePhase.estimate);
      expect(bloc.state.estimatedPrice, 80.0);
    });

    test('UpdateNotes and AddPhotoPath accumulate draft details', () async {
      await toEstimate();
      bloc.add(const UpdateNotes('Blue Camry'));
      bloc.add(const AddPhotoPath('/tmp/a.jpg'));
      bloc.add(const AddPhotoPath('/tmp/b.jpg'));
      await settle();
      expect(bloc.state.notes, 'Blue Camry');
      expect(bloc.state.photoPaths, ['/tmp/a.jpg', '/tmp/b.jpg']);
      expect(bloc.state.phase, RoadsidePhase.estimate);
      expect(bloc.state.estimatedPrice, 80.0);
    });
  });

  group('photos', () {
    Future<void> withPhotos(List<String> paths) async {
      await toEstimate();
      for (final p in paths) {
        bloc.add(AddPhotoPath(p));
      }
      await settle();
      states.clear();
    }

    test('submit uploads the photos, then creates the request with their URLs', () async {
      await withPhotos(['/tmp/a.jpg', '/tmp/b.jpg']);
      bloc.add(const SubmitRequest());
      await settle();

      expect(repo.uploadCalls, [
        ['/tmp/a.jpg', '/tmp/b.jpg'],
      ]);
      expect(repo.createPhotoUrls, [
        ['/uploads/request-photos/a.jpg', '/uploads/request-photos/b.jpg'],
      ]);
      expect(bloc.state.activeRequest, isNotNull);
      expect(bloc.state.error, isNull);
    });

    test('without photos nothing is uploaded and the request has no photo URLs', () async {
      await toEstimate();
      bloc.add(const SubmitRequest());
      await settle();
      expect(repo.uploadCalls, isEmpty);
      expect(repo.createPhotoUrls, [<String>[]]);
    });

    test('an upload failure returns to the estimate with a photo-specific localized error',
        () async {
      await withPhotos(['/tmp/a.jpg']);
      repo.uploadError = ApiException('File too large', statusCode: 413);
      bloc.add(const SubmitRequest());
      await settle();

      expect(states.first.phase, RoadsidePhase.searching);
      expect(bloc.state.phase, RoadsidePhase.estimate);
      expect(bloc.state.isSubmitting, isFalse);
      expect(bloc.state.error, 'roadside_error_photo_upload');
      expect(repo.createCalls, isEmpty, reason: 'no request without its photos');
      // Draft (including the photos) is kept for a retry.
      expect(bloc.state.photoPaths, ['/tmp/a.jpg']);
      expect(bloc.state.estimatedPrice, 80.0);
    });

    test('unexpected upload errors (e.g. a missing file) get the same message', () async {
      await withPhotos(['/tmp/a.jpg']);
      repo.uploadError = const FileSystemException('Cannot open file', '/tmp/a.jpg');
      bloc.add(const SubmitRequest());
      await settle();
      expect(bloc.state.error, 'roadside_error_photo_upload');
    });

    test('a short upload response is treated as an upload failure', () async {
      await withPhotos(['/tmp/a.jpg', '/tmp/b.jpg']);
      repo.uploadResult = (_) => ['/u/only-one.jpg'];
      bloc.add(const SubmitRequest());
      await settle();
      expect(bloc.state.error, 'roadside_error_photo_upload');
      expect(repo.createCalls, isEmpty);
    });

    test('retrying after an upload failure uploads again and submits', () async {
      await withPhotos(['/tmp/a.jpg']);
      repo.uploadError = Exception('offline');
      bloc.add(const SubmitRequest());
      await settle();

      repo.uploadError = null;
      bloc.add(const SubmitRequest());
      await settle();
      expect(repo.uploadCalls, hasLength(2));
      expect(repo.createPhotoUrls.single, ['/uploads/request-photos/a.jpg']);
      expect(bloc.state.error, isNull);
      expect(bloc.state.activeRequest, isNotNull);
    });

    test('retrying after a failed create reuses photos that were already uploaded', () async {
      await withPhotos(['/tmp/a.jpg']);
      repo.createError = ApiException('Request timed out');
      bloc.add(const SubmitRequest());
      await settle();
      expect(bloc.state.error, 'Request timed out');

      repo.createError = null;
      bloc.add(const AddPhotoPath('/tmp/b.jpg'));
      bloc.add(const SubmitRequest());
      await settle();

      expect(repo.uploadCalls, [
        ['/tmp/a.jpg'],
        ['/tmp/b.jpg'],
      ]);
      expect(repo.createPhotoUrls.last,
          ['/uploads/request-photos/a.jpg', '/uploads/request-photos/b.jpg']);
    });

    test('ResetFlow forgets uploaded photos', () async {
      await withPhotos(['/tmp/a.jpg']);
      bloc.add(const SubmitRequest());
      await settle();
      bloc.add(const ResetFlow());
      await withPhotos(['/tmp/a.jpg']);
      bloc.add(const SubmitRequest());
      await settle();
      expect(repo.uploadCalls, hasLength(2));
    });

    test('AddPhotoPath stops at the backend limit of ${RoadsideState.maxPhotos}', () async {
      await withPhotos([for (var i = 0; i < 7; i++) '/tmp/$i.jpg']);
      expect(bloc.state.photoPaths, [for (var i = 0; i < 5; i++) '/tmp/$i.jpg']);
      expect(RoadsideState.maxPhotos, 5);
    });

    test('the photo upload error key has English and Arabic translations', () {
      const key = 'roadside_error_photo_upload';
      final en = AppLocalizations(const Locale('en')).tr(key);
      final ar = AppLocalizations(const Locale('ar')).tr(key);
      expect(en, isNot(key));
      expect(ar, isNot(key));
      expect(ar, isNot(en));
    });
  });

  group('SubmitRequest', () {
    test('emits searching+submitting, then stores the created request and starts watching it',
        () async {
      await toEstimate();
      repo.createResult = sampleRequest(id: 'req-42');
      bloc.add(const SubmitRequest());
      await settle();

      expect(states, hasLength(2));
      expect(states[0].phase, RoadsidePhase.searching);
      expect(states[0].isSubmitting, isTrue);
      expect(states[0].activeRequest, isNull);

      expect(states[1].phase, RoadsidePhase.searching);
      expect(states[1].isSubmitting, isFalse);
      expect(states[1].activeRequest?.id, 'req-42');
      expect(states[1].error, isNull);

      expect(repo.watchCalls, ['req-42']);
      expect(repo.watcher('req-42').hasListener, isTrue);
    });

    test('sends type, location, address; empty notes are sent as null', () async {
      await toEstimate(type: ServiceType.fuelDelivery);
      bloc.add(const SubmitRequest());
      await settle();
      expect(repo.createCalls.single, {
        'type': ServiceType.fuelDelivery,
        'location': _loc,
        'address': 'Olaya St, Riyadh',
        'notes': null,
      });
    });

    test('non-empty notes are forwarded', () async {
      await toEstimate();
      bloc.add(const UpdateNotes('Gate 3'));
      bloc.add(const SubmitRequest());
      await settle();
      expect(repo.createCalls.single['notes'], 'Gate 3');
    });

    test('failure returns to the estimate screen with the error message', () async {
      await toEstimate();
      repo.createError = ApiException('address must be a string', statusCode: 400);
      bloc.add(const SubmitRequest());
      await settle();

      expect(states, hasLength(2));
      expect(states[0].phase, RoadsidePhase.searching);
      expect(states[1].phase, RoadsidePhase.estimate);
      expect(states[1].isSubmitting, isFalse);
      expect(states[1].error, 'address must be a string');
      expect(states[1].activeRequest, isNull);
      // Draft is preserved so the user can retry.
      expect(states[1].estimatedPrice, 80.0);
      expect(states[1].customerAddress, 'Olaya St, Riyadh');
      expect(repo.watchCalls, isEmpty);
    });

    test('retrying after a failure clears the previous error', () async {
      await toEstimate();
      repo.createError = ApiException('boom');
      bloc.add(const SubmitRequest());
      await settle();
      expect(bloc.state.error, 'boom');

      repo.createError = null;
      states.clear();
      bloc.add(const SubmitRequest());
      await settle();
      expect(states.first.error, isNull);
      expect(bloc.state.error, isNull);
      expect(bloc.state.activeRequest, isNotNull);
    });
  });

  group('tracking updates', () {
    test('maps every request status to the right phase', () async {
      final req = await toSearching();
      final w = repo.watcher(req.id);

      final expectations = <RequestStatus, RoadsidePhase>{
        RequestStatus.searching: RoadsidePhase.searching,
        RequestStatus.driverFound: RoadsidePhase.tracking,
        RequestStatus.driverEnRoute: RoadsidePhase.tracking,
        RequestStatus.arrived: RoadsidePhase.tracking,
        RequestStatus.inProgress: RoadsidePhase.tracking,
        RequestStatus.completed: RoadsidePhase.rating,
      };
      for (final entry in expectations.entries) {
        w.add(req.copyWith(status: entry.key));
        await settle();
        expect(bloc.state.phase, entry.value, reason: '${entry.key}');
        expect(bloc.state.activeRequest!.status, entry.key);
      }
    });

    test('driver location ticks replace the active request (map follows the driver)', () async {
      final req = await toSearching();
      final w = repo.watcher(req.id);
      w.add(req.copyWith(status: RequestStatus.driverEnRoute, driverLocation: const LatLng(24.70, 46.66)));
      w.add(req.copyWith(status: RequestStatus.driverEnRoute, driverLocation: const LatLng(24.71, 46.67)));
      await settle();
      expect(states.map((s) => s.activeRequest!.driverLocation), [
        const LatLng(24.70, 46.66),
        const LatLng(24.71, 46.67),
      ]);
      expect(states.every((s) => s.phase == RoadsidePhase.tracking), isTrue);
    });

    test('a driver/backend cancellation returns the flow to idle', () async {
      final req = await toSearching();
      repo.watcher(req.id).add(req.copyWith(status: RequestStatus.cancelled));
      await settle();
      expect(bloc.state.phase, RoadsidePhase.idle);
    });

    test(
      'an error on the tracking stream is surfaced in state instead of crashing',
      () async {
        final req = await toSearching();
        repo.watcher(req.id).addError(ApiException('Request not found', statusCode: 404));
        await settle();
        expect(bloc.state.error, 'Request not found');
      },
    );

    test('tracking keeps listening after a stream error', () async {
      final req = await toSearching();
      final w = repo.watcher(req.id);
      w.addError(ApiException('Service Unavailable', statusCode: 503));
      await settle();
      expect(w.hasListener, isTrue);

      w.add(req.copyWith(status: RequestStatus.driverFound));
      await settle();
      expect(bloc.state.phase, RoadsidePhase.tracking);
      expect(bloc.state.error, isNull, reason: 'the next update clears the error');
    });

    test('a second submit replaces the previous watch subscription', () async {
      final first = await toSearching();
      repo.createResult = sampleRequest(id: 'req-2');
      bloc.add(const SubmitRequest());
      await settle();
      expect(repo.watcher(first.id).hasListener, isFalse);
      expect(repo.watcher('req-2').hasListener, isTrue);
    });
  });

  group('CancelRequest', () {
    test('cancels the active request on the backend and resets the flow', () async {
      final req = await toSearching();
      bloc.add(const CancelRequest());
      await settle();

      expect(repo.cancelCalls, [req.id]);
      expect(bloc.state.phase, RoadsidePhase.idle);
      expect(bloc.state.activeRequest, isNull);
      expect(bloc.state.selectedService, isNull);
      expect(bloc.state.estimatedPrice, isNull);
      expect(repo.watcher(req.id).hasListener, isFalse);
    });

    test('updates arriving after cancel are ignored', () async {
      final req = await toSearching();
      final w = repo.watcher(req.id);
      bloc.add(const CancelRequest());
      await settle();
      states.clear();

      w.add(req.copyWith(status: RequestStatus.driverFound));
      await settle();
      expect(states, isEmpty);
      expect(bloc.state.phase, RoadsidePhase.idle);
    });

    test('with no active request it just resets without calling the backend', () async {
      await toEstimate();
      bloc.add(const CancelRequest());
      await settle();
      expect(repo.cancelCalls, isEmpty);
      expect(bloc.state.phase, RoadsidePhase.idle);
      expect(bloc.state.selectedService, isNull);
    });

    test(
      'backend refusal keeps the request active/tracked and surfaces the error',
      () async {
        final req = await toSearching();
        repo.cancelError = ApiException('Cannot cancel a completed request', statusCode: 400);
        bloc.add(const CancelRequest());
        await settle();

        expect(bloc.state.error, 'Cannot cancel a completed request');
        expect(bloc.state.activeRequest?.id, req.id);
        expect(repo.watcher(req.id).hasListener, isTrue);
      },
    );

    test('after a refused cancel, live updates for the request still reach the UI', () async {
      final req = await toSearching();
      repo.cancelError = ApiException('Cannot cancel a completed request', statusCode: 400);
      bloc.add(const CancelRequest());
      await settle();

      repo.watcher(req.id).add(req.copyWith(status: RequestStatus.completed));
      await settle();
      expect(bloc.state.phase, RoadsidePhase.rating);
      expect(bloc.state.activeRequest?.status, RequestStatus.completed);
    });
  });

  group('SubmitRating', () {
    test('rates the active request and moves to done', () async {
      final req = await toSearching();
      repo.watcher(req.id).add(req.copyWith(status: RequestStatus.completed));
      await settle();
      expect(bloc.state.phase, RoadsidePhase.rating);

      bloc.add(const SubmitRating(5, 'Excellent'));
      await settle();
      expect(repo.rateCalls, [(req.id, 5, 'Excellent')]);
      expect(bloc.state.phase, RoadsidePhase.done);
    });

    test('null review is passed through as null', () async {
      final req = await toSearching();
      bloc.add(const SubmitRating(3, null));
      await settle();
      expect(repo.rateCalls, [(req.id, 3, null)]);
    });

    test('without an active request it does nothing', () async {
      bloc.add(const SubmitRating(5, null));
      await settle();
      expect(repo.rateCalls, isEmpty);
      expect(states, isEmpty);
    });

    test(
      'rating failure stays on the rating screen and surfaces the error',
      () async {
        final req = await toSearching();
        repo.watcher(req.id).add(req.copyWith(status: RequestStatus.completed));
        await settle();
        repo.rateError = ApiException('Can only rate a completed request', statusCode: 400);

        bloc.add(const SubmitRating(4, null));
        await settle();
        expect(bloc.state.phase, RoadsidePhase.rating);
        expect(bloc.state.error, 'Can only rate a completed request');
      },
    );

    test('retrying a failed rating succeeds and moves to done', () async {
      final req = await toSearching();
      repo.watcher(req.id).add(req.copyWith(status: RequestStatus.completed));
      await settle();
      repo.rateError = ApiException('Could not reach the server.');
      bloc.add(const SubmitRating(4, null));
      await settle();
      expect(bloc.state.phase, RoadsidePhase.rating);

      repo.rateError = null;
      bloc.add(const SubmitRating(4, null));
      await settle();
      expect(bloc.state.phase, RoadsidePhase.done);
      expect(bloc.state.error, isNull);
    });
  });

  group('user-facing error text', () {
    // Non-ApiException failures are bugs/unexpected states; their toString()
    // ("Bad state: ...", "Null check operator ...") must never reach users.
    const generic = 'roadside_error_generic';

    test('price estimate: unexpected error -> generic localized key', () async {
      repo.priceError = StateError('internal detail');
      bloc.add(const SelectService(ServiceType.batteryJump));
      bloc.add(const ConfirmLocation(_loc, 'Olaya St'));
      await settle();
      expect(bloc.state.error, generic);
    });

    test('submit: unexpected error -> generic localized key', () async {
      await toEstimate();
      repo.createError = TypeError();
      bloc.add(const SubmitRequest());
      await settle();
      expect(bloc.state.error, generic);
      expect(bloc.state.phase, RoadsidePhase.estimate);
    });

    test('tracking / cancel / rating: unexpected error -> generic localized key', () async {
      final req = await toSearching();
      repo.watcher(req.id).addError(ArgumentError('Unknown request status: paused'));
      await settle();
      expect(bloc.state.error, generic);

      repo.cancelError = FormatException('bad');
      bloc.add(const CancelRequest());
      await settle();
      expect(bloc.state.error, generic);

      repo.rateError = Exception('boom');
      bloc.add(const SubmitRating(5, null));
      await settle();
      expect(bloc.state.error, generic);
    });

    test('the generic key has English and Arabic translations', () {
      final en = AppLocalizations(const Locale('en')).tr(generic);
      final ar = AppLocalizations(const Locale('ar')).tr(generic);
      expect(en, isNot(generic));
      expect(ar, isNot(generic));
      expect(ar, isNot(en));
    });

    test('API messages pass through tr() unchanged', () {
      expect(AppLocalizations(const Locale('ar')).tr('Request not found'), 'Request not found');
    });
  });

  group('ResetFlow / close', () {
    test('ResetFlow returns to the initial state and stops listening', () async {
      final req = await toSearching();
      bloc.add(const ResetFlow());
      await settle();
      expect(bloc.state.phase, RoadsidePhase.idle);
      expect(bloc.state.activeRequest, isNull);
      expect(repo.watcher(req.id).hasListener, isFalse);
      expect(repo.cancelCalls, isEmpty, reason: 'reset is local only');
    });

    test('close() cancels the tracking subscription', () async {
      final req = await toSearching();
      await bloc.close();
      expect(repo.watcher(req.id).hasListener, isFalse);
    });
  });
}
