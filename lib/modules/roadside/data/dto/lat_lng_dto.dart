import 'package:google_maps_flutter/google_maps_flutter.dart';

class LatLngDto {
  const LatLngDto(this.lat, this.lng);

  final double lat;
  final double lng;

  factory LatLngDto.fromJson(Map<String, dynamic> json) {
    return LatLngDto((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  LatLng toLatLng() => LatLng(lat, lng);
}

extension LatLngDtoX on LatLng {
  LatLngDto toDto() => LatLngDto(latitude, longitude);
}
