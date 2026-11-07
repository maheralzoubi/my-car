import 'package:flutter/material.dart';

/// Roadside-only visual constants that have no app-wide token.
abstract final class RoadsideVisuals {
  RoadsideVisuals._();

  /// Gold for rating stars (driver rating, "4.8 Rating" fact, star picker).
  /// Not a status color, so deliberately not the palette's `warn`. Reads on
  /// both the light and the dark surfaces.
  static const Color ratingStar = Color(0xFFF5B400);

  /// Google Maps style for the current theme brightness.
  static String mapStyleFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkMapStyle
      : lightMapStyle;

  /// Light map: Google's default palette, quieted (no business POIs, soft
  /// water) so the blue pins and route stand out. Map tiles take hex strings,
  /// not Flutter colors.
  static const String lightMapStyle = '''
[
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"saturation":-100},{"lightness":20}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cfdcf0"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#f5f7fa"}]}
]
''';

  /// Dark map: matches the dark palette (bg #0B0F17, surface #131A26,
  /// surface2 #1A2332, border #253044, text2 #A9B4C7, muted #7C889D).
  static const String darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#131a26"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#7c889d"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b0f17"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"saturation":-100},{"lightness":-40}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a2332"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#0b0f17"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a9b4c7"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#253044"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b0f17"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#7c889d"}]}
]
''';
}
