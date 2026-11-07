import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../../core/network/api_exception.dart';
import '../../data/models/service_request.dart';
import '../../data/repositories/roadside_repository.dart';
import 'roadside_event.dart';
import 'roadside_state.dart';

class RoadsideBloc extends Bloc<RoadsideEvent, RoadsideState> {
  final RoadsideRepository _repo;
  StreamSubscription<ServiceRequest>? _requestSub;

  /// Server URL of each photo path already uploaded in this flow, so a retry
  /// after a failed create doesn't upload the same files again.
  final _uploadedPhotoUrls = <String, String>{};

  /// Exposed so screens can call one-off repository methods (e.g. reverse
  /// geocoding while dragging the map) that don't warrant their own event.
  RoadsideRepository get repository => _repo;

  RoadsideBloc(this._repo) : super(const RoadsideState()) {
    on<SelectService>(_onSelectService);
    on<ConfirmLocation>(_onConfirmLocation);
    on<UpdateNotes>(_onUpdateNotes);
    on<AddPhotoPath>(_onAddPhoto);
    on<SubmitRequest>(_onSubmitRequest);
    on<RequestUpdated>(_onRequestUpdated);
    on<RequestUpdateFailed>(_onRequestUpdateFailed);
    on<CancelRequest>(_onCancel);
    on<SubmitRating>(_onSubmitRating);
    on<ResetFlow>(_onReset);
  }

  void _onSelectService(SelectService e, Emitter<RoadsideState> emit) {
    emit(state.copyWith(
      selectedService: e.serviceType,
      phase: RoadsidePhase.locationPicker,
    ));
  }

  Future<void> _onConfirmLocation(
    ConfirmLocation e,
    Emitter<RoadsideState> emit,
  ) async {
    try {
      final price = await _repo.getEstimatedPrice(state.selectedService!, e.location);
      emit(state.copyWith(
        customerLocation: e.location,
        customerAddress: e.address,
        estimatedPrice: price,
        phase: RoadsidePhase.estimate,
      ));
    } catch (err) {
      emit(state.copyWith(error: _errorMessage(err)));
    }
  }

  void _onUpdateNotes(UpdateNotes e, Emitter<RoadsideState> emit) {
    emit(state.copyWith(notes: e.notes));
  }

  void _onAddPhoto(AddPhotoPath e, Emitter<RoadsideState> emit) {
    if (state.photoPaths.length >= RoadsideState.maxPhotos) return;
    emit(state.copyWith(photoPaths: [...state.photoPaths, e.path]));
  }

  /// Uploads the photos not uploaded yet and returns the URLs of all of
  /// [paths], in order.
  Future<List<String>> _uploadPhotos(List<String> paths) async {
    final pending = paths.where((p) => !_uploadedPhotoUrls.containsKey(p)).toList();
    if (pending.isNotEmpty) {
      final urls = await _repo.uploadPhotos(pending);
      for (var i = 0; i < pending.length; i++) {
        _uploadedPhotoUrls[pending[i]] = urls[i];
      }
    }
    return [for (final p in paths) _uploadedPhotoUrls[p]!];
  }

  Future<void> _onSubmitRequest(
    SubmitRequest _,
    Emitter<RoadsideState> emit,
  ) async {
    emit(state.copyWith(isSubmitting: true, phase: RoadsidePhase.searching));
    final List<String> photoUrls;
    try {
      photoUrls = await _uploadPhotos(state.photoPaths);
    } catch (_) {
      // Whatever the cause (offline, file gone, rejected image), the backend's
      // wording wouldn't help here; keep the photos so the user can retry.
      emit(state.copyWith(
        isSubmitting: false,
        phase: RoadsidePhase.estimate,
        error: 'roadside_error_photo_upload',
      ));
      return;
    }
    try {
      final request = await _repo.createRequestWithPhotos(
        type: state.selectedService!,
        location: state.customerLocation!,
        address: state.customerAddress,
        notes: state.notes.isEmpty ? null : state.notes,
        photoUrls: photoUrls,
      );
      emit(state.copyWith(activeRequest: request, isSubmitting: false));
      _requestSub?.cancel();
      _requestSub = _repo.watchRequest(request.id).listen(
        (updated) => add(RequestUpdated(updated)),
        onError: (Object err) => add(RequestUpdateFailed(err)),
      );
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        phase: RoadsidePhase.estimate,
        error: _errorMessage(e),
      ));
    }
  }

  void _onRequestUpdated(RequestUpdated e, Emitter<RoadsideState> emit) {
    final req = e.request;
    // Events run concurrently, so an update for a request the flow already
    // let go of (cancelled / reset / replaced) can land after the reset and
    // would resurrect it. activeRequest is set before we subscribe, so only
    // updates for the current request are applied.
    if (state.activeRequest?.id != req.id) return;
    RoadsidePhase phase;
    switch (req.status) {
      case RequestStatus.searching:
        phase = RoadsidePhase.searching;
        break;
      case RequestStatus.driverFound:
      case RequestStatus.driverEnRoute:
      case RequestStatus.arrived:
      case RequestStatus.inProgress:
        phase = RoadsidePhase.tracking;
        break;
      case RequestStatus.completed:
        phase = RoadsidePhase.rating;
        break;
      case RequestStatus.cancelled:
        phase = RoadsidePhase.idle;
        break;
    }
    emit(state.copyWith(activeRequest: req, phase: phase));
  }

  // Tracking stays subscribed after an error; the stream may recover.
  void _onRequestUpdateFailed(RequestUpdateFailed e, Emitter<RoadsideState> emit) {
    emit(state.copyWith(error: _errorMessage(e.error)));
  }

  Future<void> _onCancel(CancelRequest _, Emitter<RoadsideState> emit) async {
    if (state.activeRequest != null) {
      try {
        await _repo.cancelRequest(state.activeRequest!.id);
      } catch (e) {
        // The backend refused (e.g. the job already finished), so the request
        // is still live: keep tracking it and tell the user why.
        emit(state.copyWith(error: _errorMessage(e)));
        return;
      }
    }
    _requestSub?.cancel();
    _uploadedPhotoUrls.clear();
    emit(const RoadsideState());
  }

  Future<void> _onSubmitRating(
    SubmitRating e,
    Emitter<RoadsideState> emit,
  ) async {
    if (state.activeRequest == null) return;
    try {
      await _repo.rateDriver(state.activeRequest!.id, e.stars, e.review);
      emit(state.copyWith(phase: RoadsidePhase.done));
    } catch (err) {
      emit(state.copyWith(error: _errorMessage(err)));
    }
  }

  void _onReset(ResetFlow _, Emitter<RoadsideState> emit) {
    _requestSub?.cancel();
    _uploadedPhotoUrls.clear();
    emit(const RoadsideState());
  }

  /// [ApiException] messages are already user-facing (backend validation
  /// text or the friendly network messages). Anything else is unexpected, so
  /// show a generic message instead of a raw `toString()`. The result is
  /// rendered with `context.tr`, which translates the generic key and passes
  /// API messages through unchanged.
  static String _errorMessage(Object e) =>
      e is ApiException ? e.message : 'roadside_error_generic';

  @override
  Future<void> close() {
    _requestSub?.cancel();
    return super.close();
  }
}
