import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../data/models/service_request.dart';
import '../../data/repositories/roadside_repository.dart';
import 'roadside_event.dart';
import 'roadside_state.dart';

class RoadsideBloc extends Bloc<RoadsideEvent, RoadsideState> {
  final RoadsideRepository _repo;
  StreamSubscription<ServiceRequest>? _requestSub;

  RoadsideBloc(this._repo) : super(const RoadsideState()) {
    on<SelectService>(_onSelectService);
    on<ConfirmLocation>(_onConfirmLocation);
    on<UpdateNotes>(_onUpdateNotes);
    on<AddPhotoPath>(_onAddPhoto);
    on<SubmitRequest>(_onSubmitRequest);
    on<RequestUpdated>(_onRequestUpdated);
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
    final price = await _repo.getEstimatedPrice(state.selectedService!, e.location);
    emit(state.copyWith(
      customerLocation: e.location,
      customerAddress: e.address,
      estimatedPrice: price,
      phase: RoadsidePhase.estimate,
    ));
  }

  void _onUpdateNotes(UpdateNotes e, Emitter<RoadsideState> emit) {
    emit(state.copyWith(notes: e.notes));
  }

  void _onAddPhoto(AddPhotoPath e, Emitter<RoadsideState> emit) {
    emit(state.copyWith(photoPaths: [...state.photoPaths, e.path]));
  }

  Future<void> _onSubmitRequest(
    SubmitRequest _,
    Emitter<RoadsideState> emit,
  ) async {
    emit(state.copyWith(isSubmitting: true, phase: RoadsidePhase.searching));
    try {
      final request = await _repo.createRequest(
        type: state.selectedService!,
        location: state.customerLocation!,
        address: state.customerAddress,
        notes: state.notes.isEmpty ? null : state.notes,
      );
      emit(state.copyWith(activeRequest: request, isSubmitting: false));
      _requestSub?.cancel();
      _requestSub = _repo.watchRequest(request.id).listen((updated) {
        add(RequestUpdated(updated));
      });
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        phase: RoadsidePhase.estimate,
        error: e.toString(),
      ));
    }
  }

  void _onRequestUpdated(RequestUpdated e, Emitter<RoadsideState> emit) {
    final req = e.request;
    RoadsidePhase phase;
    switch (req.status) {
      case RequestStatus.searching:
        phase = RoadsidePhase.searching;
        break;
      case RequestStatus.driverFound:
      case RequestStatus.driverEnRoute:
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

  Future<void> _onCancel(CancelRequest _, Emitter<RoadsideState> emit) async {
    _requestSub?.cancel();
    if (state.activeRequest != null) {
      await _repo.cancelRequest(state.activeRequest!.id);
    }
    emit(const RoadsideState());
  }

  Future<void> _onSubmitRating(
    SubmitRating e,
    Emitter<RoadsideState> emit,
  ) async {
    if (state.activeRequest == null) return;
    await _repo.rateDriver(state.activeRequest!.id, e.stars, e.review);
    emit(state.copyWith(phase: RoadsidePhase.done));
  }

  void _onReset(ResetFlow _, Emitter<RoadsideState> emit) {
    _requestSub?.cancel();
    emit(const RoadsideState());
  }

  @override
  Future<void> close() {
    _requestSub?.cancel();
    return super.close();
  }
}
