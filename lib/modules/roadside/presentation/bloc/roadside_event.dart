import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/models/service_request.dart';
import '../../data/models/service_type.dart';

abstract class RoadsideEvent {
  const RoadsideEvent();
}

class SelectService extends RoadsideEvent {
  final ServiceType serviceType;
  const SelectService(this.serviceType);
}

class ConfirmLocation extends RoadsideEvent {
  final LatLng location;
  final String address;
  const ConfirmLocation(this.location, this.address);
}

class UpdateNotes extends RoadsideEvent {
  final String notes;
  const UpdateNotes(this.notes);
}

class AddPhotoPath extends RoadsideEvent {
  final String path;
  const AddPhotoPath(this.path);
}

class SubmitRequest extends RoadsideEvent {
  const SubmitRequest();
}

class RequestUpdated extends RoadsideEvent {
  final ServiceRequest request;
  const RequestUpdated(this.request);
}

class CancelRequest extends RoadsideEvent {
  const CancelRequest();
}

class SubmitRating extends RoadsideEvent {
  final int stars;
  final String? review;
  const SubmitRating(this.stars, this.review);
}

class ResetFlow extends RoadsideEvent {
  const ResetFlow();
}
