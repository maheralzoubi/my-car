/// What the structure of an OBD-II trouble code itself says about it
/// (SAE J2012 / ISO 15031-6): the system letter, whether the code is
/// SAE-defined or manufacturer-controlled, and — for the generic powertrain
/// and network blocks — the subsystem encoded by the third character.
///
/// Every getter returns a localization key (or null when the code's shape
/// tells us nothing), so callers render it with `context.tr`.
class DtcCodeInfo {
  DtcCodeInfo(String raw) : code = _normalize(raw);

  final String code;

  static final RegExp _shape = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');

  // Manufacturer-controlled blocks: P1xxx, P3000–P33FF, B1/B2, C1/C2, U1/U2.
  static final RegExp _manufacturer =
      RegExp(r'^(?:P1|P3[0-3]|[BCU][12])');

  static String _normalize(String raw) {
    final s = raw.trim().toUpperCase();
    return s.startsWith('~') ? s.substring(1) : s;
  }

  bool get isValid => _shape.hasMatch(code);

  bool get isManufacturerSpecific => isValid && _manufacturer.hasMatch(code);

  /// 'P' / 'C' / 'B' / 'U', or null for a malformed code.
  String? get letter => isValid ? code[0] : null;

  String? get categoryKey =>
      isValid ? 'dtc_cat_${code[0].toLowerCase()}' : null;

  String? get typeKey => !isValid
      ? null
      : isManufacturerSpecific
          ? 'dtc_type_manufacturer'
          : 'dtc_type_generic';

  String? get subsystemKey {
    if (!isValid || isManufacturerSpecific) return null;
    final block = code.substring(0, 2);
    final digit = code[2];
    switch (block) {
      case 'P0':
        return switch (digit) {
          '0' => 'dtc_sub_fuel_air_aux',
          '1' || '2' => 'dtc_sub_fuel_air',
          '3' => 'dtc_sub_ignition',
          '4' => 'dtc_sub_aux_emission',
          '5' => 'dtc_sub_speed_idle',
          '6' => 'dtc_sub_computer',
          '7' || '8' || '9' => 'dtc_sub_transmission',
          'A' || 'B' || 'C' || 'D' => 'dtc_sub_hybrid',
          _ => null,
        };
      case 'P2':
        return switch (digit) {
          '0' || '1' || '2' || '9' || 'A' => 'dtc_sub_fuel_air_aux',
          '3' => 'dtc_sub_ignition',
          '4' => 'dtc_sub_aux_emission',
          '5' => 'dtc_sub_aux_inputs',
          '6' => 'dtc_sub_computer',
          '7' => 'dtc_sub_transmission',
          _ => null,
        };
      case 'U0':
        return switch (digit) {
          '0' => 'dtc_sub_net_electrical',
          '1' || '2' => 'dtc_sub_net_comm',
          '3' => 'dtc_sub_net_software',
          '4' => 'dtc_sub_net_data',
          _ => null,
        };
      default:
        return null;
    }
  }

  /// General next steps that hold for this kind of code — nothing here is
  /// specific to a single code's root cause.
  List<String> nextStepKeys({bool isPending = false}) => [
        'dtc_step_record',
        if (isPending) 'dtc_step_pending',
        if (typeKey != null)
          isManufacturerSpecific ? 'dtc_step_manufacturer' : 'dtc_step_generic',
        if (letter != null) 'dtc_step_${letter!.toLowerCase()}',
        'dtc_step_bulletins',
        'dtc_step_clear',
        'dtc_step_stop',
      ];
}
