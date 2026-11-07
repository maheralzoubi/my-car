// Compatibility matrix, Chinese cars group D: SAIC MG, GAC, BAIC, JAC,
// Hongqi (FAW), Dongfeng and BYD — incl. a plug-in hybrid and two EVs — driven
// through the ELM327 simulator (test/helpers/elm327_sim.dart).
//
// House style follows test/vehicles/korean_chinese_cars_test.dart (which
// already covers the MG ZS 2021 1.5 MPI, so that car is not repeated here):
// support bitmaps are generated from the PIDs that really answer, so
// 0100/0120/0140 are always consistent; NO DATA latency is modelled; mode 04
// really clears the stored codes.
//
// Grounding:
//  * Combustion cars: China 6 (GB 18352.6-2016) OBD → ISO 15765-4 CAN 11-bit
//    500k (ELM protocol 6), SAE J1979 mode 01/02/03/04/07/09 formats.
//  * WMIs: Wikibooks "World Manufacturer Identifier (WMI)" list — LSJ SAIC MG,
//    LMG GAC Motor/Trumpchi, LNB BAIC Motor, LJ1 JAC, LFP FAW Car/Hongqi,
//    LDP Dongfeng Fengshen (Aeolus), LC0 / LGX BYD Auto. GB 16735: position
//    9 = check digit, position 10 = model year.
//  * EVs: community tooling for the BYD Atto 3 / Dolphin (loryanstrant/
//    BYD-PID-list) reads everything with UDS mode 22 on physical headers
//    (ATSH7E7, protocol 6) and documents no mode 01 PIDs; MG ZS EV tools
//    likewise use mode 22 at header 781. Whether a BEV answers the functional
//    (7DF) mode 01 request at all is NOT documented — both outcomes are
//    modelled (MG ZS EV: minimal VCU answer; Atto 3: no answer) and marked
//    UNVERIFIED.
// Per-model PID sets, latencies and DTC meanings are not published by the
// OEMs; plausible assumptions are marked "UNVERIFIED".
//
// Tests that once asserted correct behaviour the app got wrong (`skip: 'BUG:
// …'`) now run un-skipped against the fixes (Chinese WMIs in VinDecoder,
// hybrid P0A00–P0C87 + manufacturer-range label in DtcRepository,
// OBDFailureReason.noStandardObdData); any new app bug found is left as a
// test marked `skip: 'REGRESSION: …'`.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/vin_decoder.dart';

import '../helpers/elm327_sim.dart';

// Fixed clock for VinDecoder's non-North-American model-year heuristic.
final _now = DateTime(2026, 11, 7);

// ── Measurement log (printed once at the end) ─────────────────────────────────

final _matrix = <String>[];
void _log(String line) => _matrix.add(line);

String _secs(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

// ── Helpers: hex, VIN, ELM reply builders ─────────────────────────────────────

String _h(int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase();
String _hx(Iterable<int> bytes) => bytes.map(_h).join(' ');

const _translit = {
  'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8, //
  'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9,
  'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9,
};
const _weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];

/// ISO 3779 check digit (position 9) — mandated in China by GB 16735.
String _checkDigit(String vin) {
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += (int.tryParse(vin[i]) ?? _translit[vin[i]]!) * _weights[i];
  }
  final r = sum % 11;
  return r == 10 ? 'X' : '$r';
}

/// Fills position 9 of [template] ('?') with the correct check digit.
String _vin(String template) {
  assert(template.length == 17 && template[8] == '?');
  final v = template.replaceRange(8, 9, '0');
  return v.replaceRange(8, 9, _checkDigit(v));
}

/// 09 02 on ISO 15765-4 with headers off: ISO-TP byte count 0x014
/// (49 02 01 + 17 chars) and three numbered frames.
String _canVinReply(String vin) => _canVinBytes(vin.codeUnits);

String _canVinBytes(List<int> vin) {
  assert(vin.length == 17);
  final b = [0x49, 0x02, 0x01, ...vin];
  return '014\n'
      '0: ${_hx(b.sublist(0, 6))}\n'
      '1: ${_hx(b.sublist(6, 13))}\n'
      '2: ${_hx(b.sublist(13, 20))}';
}

// ── ECU / vehicle profile model ───────────────────────────────────────────────

/// One ECU on the diagnostic bus.
class _Ecu {
  const _Ecu({required this.mode01, this.other = const {}});

  /// Mode 01 PID → data bytes. Support bitmaps (00/20/40/…) are generated
  /// from these keys — never list them here.
  final Map<int, String> mode01;

  /// Replies to everything else (03, 07, 02xx00, 0902 …).
  final Map<String, String> other;

  Map<String, String> replies() {
    final out = <String, String>{};
    final pids = mode01.keys.toSet();
    for (var base = 0; base <= 0xE0; base += 0x20) {
      if (base != 0 && !pids.any((p) => p > base)) break;
      final bits = [0, 0, 0, 0];
      for (final p in pids) {
        if (p > base && p < base + 0x20) {
          final i = p - base - 1;
          bits[i ~/ 8] |= 0x80 >> (i % 8);
        }
      }
      if (pids.any((p) => p > base + 0x20)) bits[3] |= 0x01;
      out['01${_h(base)}'] = '41 ${_h(base)} ${_hx(bits)}';
    }
    for (final e in mode01.entries) {
      out['01${_h(e.key)}'] = '41 ${_h(e.key)} ${e.value}';
    }
    out.addAll(other);
    return out;
  }
}

/// A [SimCar] whose replies come from several ECUs (joined line by line, as
/// the ELM327 prints them with headers off), with realistic NO DATA timing,
/// a mode 04 that really clears the stored codes and an optional per-request
/// [intercept] for stateful behaviour (e.g. a hybrid's engine starting).
class _ProfileCar extends SimCar {
  _ProfileCar({
    required super.protocol,
    required super.responses,
    required super.ecuLatency,
    required super.autoSearchTime,
    required super.wrongProtocolReply,
    required this.noDataLatency,
    required this.emptyDtcReply,
    required this.clearReply,
    super.silent,
    super.hangsOnce,
    super.adapterVoltage,
    this.intercept,
  });

  final Duration noDataLatency;
  final String emptyDtcReply;
  final String clearReply;

  /// Returns a reply for [cmd], or null to fall through to the profile.
  final String? Function(String cmd)? intercept;

  bool cleared = false;

  @override
  String answer(String cmd) {
    final i = intercept?.call(cmd);
    if (i != null) return i;
    if (cmd == '04') {
      final lines = clearReply.split('\n').map((l) => l.trim()).toList();
      final refused = lines.any(
        (l) => l.startsWith('7F 04') && l != '7F 04 78',
      );
      if (!refused && lines.contains('44')) cleared = true;
      return clearReply;
    }
    if (cleared) {
      if (cmd == '03') return emptyDtcReply;
      if (cmd == '07') return emptyDtcReply.replaceAll('43', '47');
      if (cmd.startsWith('02')) return 'NO DATA';
    }
    return super.answer(cmd);
  }

  @override
  Duration latency(String cmd) =>
      responses.containsKey(cmd) ? super.latency(cmd) : noDataLatency;
}

_ProfileCar _profile({
  required List<_Ecu> ecus,
  Duration ecuLatency = const Duration(milliseconds: 50),
  Duration noDataLatency = const Duration(milliseconds: 150),
  Map<String, String> overrides = const {},
  String? clearReply,
  String? adapterVoltage,
}) {
  final merged = <String, List<String>>{};
  for (final ecu in ecus) {
    for (final e in ecu.replies().entries) {
      (merged[e.key] ??= []).add(e.value);
    }
  }
  return _ProfileCar(
    protocol: '6',
    responses: {
      for (final e in merged.entries) e.key: e.value.join('\n'),
      ...overrides,
    },
    ecuLatency: ecuLatency,
    noDataLatency: noDataLatency,
    autoSearchTime: const Duration(seconds: 7),
    wrongProtocolReply: 'NO DATA',
    emptyDtcReply: List.filled(ecus.length, '43 00').join('\n'),
    clearReply: clearReply ?? List.filled(ecus.length, '44').join('\n'),
    adapterVoltage: adapterVoltage,
  );
}

/// [base] with some replies replaced (null = removed → NO DATA). Support
/// bitmaps are NOT regenerated.
_ProfileCar _variant(
  _ProfileCar base, {
  Map<String, String?> replies = const {},
  String? clearReply,
  String? Function(String cmd)? intercept,
}) {
  final responses = {...base.responses};
  for (final e in replies.entries) {
    if (e.value == null) {
      responses.remove(e.key);
    } else {
      responses[e.key] = e.value!;
    }
  }
  return _ProfileCar(
    protocol: base.protocol,
    responses: responses,
    ecuLatency: base.ecuLatency,
    autoSearchTime: base.autoSearchTime,
    wrongProtocolReply: base.wrongProtocolReply,
    noDataLatency: base.noDataLatency,
    emptyDtcReply: base.emptyDtcReply,
    clearReply: clearReply ?? base.clearReply,
    silent: base.silent,
    hangsOnce: base.hangsOnce,
    adapterVoltage: base.adapterVoltage,
    intercept: intercept ?? base.intercept,
  );
}

// ── Expected values ───────────────────────────────────────────────────────────

const _liveKeys = [
  'rpm', 'speedKmh', 'coolantTempC', 'throttlePct', 'fuelLevelPct', //
  'engineLoad', 'batteryVoltage', 'oilTempC', 'fuelTrimShortPct',
  'fuelTrimLongPct', 'fuelTrimShortB2', 'fuelTrimLongB2', 'o2B1S1Voltage',
  'o2B1S2Voltage', 'o2B2S1Voltage', 'intakeAirTempC', 'mapKpa',
  'timingAdvanceDeg', 'lambdaB1S1', 'fuelRailPressureKpa',
  'acceleratorPedalPct',
];

Map<String, double?> _fields(OBDLiveData d) => {
  'rpm': d.rpm,
  'speedKmh': d.speedKmh,
  'coolantTempC': d.coolantTempC,
  'throttlePct': d.throttlePct,
  'fuelLevelPct': d.fuelLevelPct,
  'engineLoad': d.engineLoad,
  'batteryVoltage': d.batteryVoltage,
  'oilTempC': d.oilTempC,
  'fuelTrimShortPct': d.fuelTrimShortPct,
  'fuelTrimLongPct': d.fuelTrimLongPct,
  'fuelTrimShortB2': d.fuelTrimShortB2,
  'fuelTrimLongB2': d.fuelTrimLongB2,
  'o2B1S1Voltage': d.o2B1S1Voltage,
  'o2B1S2Voltage': d.o2B1S2Voltage,
  'o2B2S1Voltage': d.o2B2S1Voltage,
  'intakeAirTempC': d.intakeAirTempC,
  'mapKpa': d.mapKpa,
  'timingAdvanceDeg': d.timingAdvanceDeg,
  'lambdaB1S1': d.lambdaB1S1,
  'fuelRailPressureKpa': d.fuelRailPressureKpa,
  'acceleratorPedalPct': d.acceleratorPedalPct,
};

/// All 21 live values; the ones not listed are expected to be null.
Map<String, double?> _live(Map<String, double> supported) {
  assert(supported.keys.every(_liveKeys.contains), supported.keys);
  return {for (final k in _liveKeys) k: supported[k]};
}

const _sparkNames = [
  'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Heated Catalyst', //
  'Evap System', 'Secondary Air', 'A/C System', 'O2 Sensor',
  'O2 Sensor Heater', 'EGR / VVT',
];
const _dieselNames = [
  'Misfire', 'Fuel System', 'Components', 'NMHC Catalyst', 'NOx / SCR', //
  'Boost Pressure', 'Exhaust Gas Sensor', 'PM Filter', 'EGR / VVT',
];

Map<String, MonitorStatus> _monitors({
  bool diesel = false,
  List<String> ready = const [],
  List<String> notReady = const [],
}) {
  final names = diesel ? _dieselNames : _sparkNames;
  assert([...ready, ...notReady].every(names.contains));
  return {
    for (final n in names)
      n: ready.contains(n)
          ? MonitorStatus.ready
          : notReady.contains(n)
          ? MonitorStatus.notReady
          : MonitorStatus.notApplicable,
  };
}

enum _Kind { spark, diesel, hybrid, ev }

class _Vehicle {
  const _Vehicle({
    required this.name,
    required this.kind,
    required this.build,
    required this.live,
    required this.dtcs,
    required this.obdVin,
    required this.plateVin,
    required this.make,
    required this.year,
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
    required this.freeze,
  });

  final String name;
  final _Kind kind;
  final _ProfileCar Function() build;
  final Map<String, double?> live;
  final List<String> dtcs;
  final String? obdVin;
  final String plateVin;

  /// Substring VinDecoder's manufacturer must contain.
  final String make;
  final String year;
  final bool milOn;
  final int dtcCount;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freeze;
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

// 1. MG5 2022, 1.5 NA MPI + CVT, Chinese-built for the GCC. CAN 11/500,
//    ECM + TCM. Narrow-band O2 (0x14/0x15). P1545 is an SAIC manufacturer
//    code (meaning UNVERIFIED). Fuel level 0x2F answered (UNVERIFIED).
final _mg5Vin = _vin('LSJW74C5?NZ012345');
final _mg5 = _Vehicle(
  name: 'MG5 2022 (1.5 MPI CVT)',
  kind: _Kind.spark,
  build: () => _profile(
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 65 00', // MIL, 2 DTCs; cat/evap/O2/heater all ready
          0x03: '02 00',
          0x04: '4D', // 30.2 %
          0x05: '82', // 90 °C
          0x06: '83', // +2.3 %
          0x07: '7C', // −3.1 %
          0x0B: '22', // 34 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '5F', // 55 °C (Gulf summer)
          0x11: '1F', // 12.2 %
          0x13: '03',
          0x14: '5A 80', // 0.45 V
          0x15: '8C FF', // 0.70 V
          0x1C: '06', // UNVERIFIED (J1979 has no China-6 value)
          0x1F: '00 5A',
          0x21: '00 0C',
          0x2F: 'A6', // 65.1 %
          0x30: '28',
          0x31: '03 E8',
          0x33: '64',
          0x42: '36 B0', // 14.0 V
          0x44: '80 00',
          0x46: '5A',
          0x49: '1F', // 12.2 %
          0x4C: '1F',
        },
        other: {
          '03': '43 02 03 01 15 45', // P0301, P1545
          '07': '47 01 01 71', // P0171 pending
          '0902': _canVinReply(_mg5Vin),
          '020C00': '42 0C 00 0F A0', // 1000 rpm
          '020D00': '42 0D 00 1E', // 30 km/h
          '020500': '42 05 00 85', // 93 °C
          '020400': '42 04 00 66', // 40 %
          '020F00': '42 0F 00 64', // 60 °C
          '021100': '42 11 00 26', // 14.9 %
          '020600': '42 06 00 8F', // +11.7 %
          '020B00': '42 0B 00 30', // 48 kPa
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '00'}, // CVT TCM
        other: {'03': '43 00', '07': '47 00'},
      ),
    ],
  ),
  live: _live({
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 90,
    'throttlePct': 12.157,
    'fuelLevelPct': 65.098,
    'engineLoad': 30.196,
    'batteryVoltage': 14.0,
    'fuelTrimShortPct': 2.344,
    'fuelTrimLongPct': -3.125,
    'o2B1S1Voltage': 0.45,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 55,
    'mapKpa': 34,
    'timingAdvanceDeg': 6,
    'acceleratorPedalPct': 12.157,
  }),
  dtcs: ['P0301', 'P1545', '~P0171'],
  obdVin: _mg5Vin,
  plateVin: _mg5Vin,
  make: 'MG',
  year: '2022',
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: [
    'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
    'O2 Sensor', 'O2 Sensor Heater',
  ]),
  freeze: {
    'RPM': '1000 rpm',
    'Speed': '30 km/h',
    'Coolant': '93°C',
    'Engine Load': '40.0%',
    'Air Temp': '60°C',
    'Throttle': '14.9%',
    'Fuel Trim': '11.7%',
    'MAP': '48 kPa',
  },
);

// 2. MG HS 2023 2.0T (SAIC 20L4E GDI turbo, 7-speed DCT), sold as RX5/HS in
//    the GCC. CAN 11/500, ECM + TCM. Wide-band upstream on 0x24 (no 0x14),
//    GDI rail pressure 0x23, oil temp 0x5C (all UNVERIFIED per engine).
//    P1520 is in the bundled DB with a Ford meaning (see DTC section).
final _hsVin = _vin('LSJA24G9?PG123456');
_ProfileCar _hsCar({String? clearReply}) => _profile(
  ecuLatency: const Duration(milliseconds: 80),
  clearReply: clearReply,
  ecus: [
    _Ecu(
      mode01: {
        0x01: '82 07 E5 01', // MIL, 2 DTCs; catalyst incomplete
        0x03: '02 00',
        0x04: '59', // 34.9 %
        0x05: '87', // 95 °C
        0x06: '7E', // −1.6 %
        0x07: '82', // +1.6 %
        0x0B: '91', // 145 kPa boost
        0x0C: '15 7C', // 1375 rpm
        0x0D: '48', // 72 km/h
        0x0E: '86', // +3°
        0x0F: '5A', // 50 °C
        0x10: '05 DC',
        0x11: '3A', // 22.7 %
        0x13: '03',
        0x15: '8C FF', // 0.70 V downstream (narrow-band)
        0x1C: '06',
        0x1F: '04 B0',
        0x21: '00 2E',
        0x23: '03 E8', // 10 000 kPa = 100 bar GDI
        0x24: '7D 70 66 66', // λ 0.980
        0x2F: '73', // 45.1 %
        0x30: '1E',
        0x31: '0B B8',
        0x33: '63',
        0x42: '37 78', // 14.2 V
        0x44: '7D 70',
        0x46: '5A',
        0x49: '3A', // 22.7 %
        0x4C: '3A',
        0x5C: '82', // 90 °C
      },
      other: {
        '03': '43 02 02 99 15 20', // P0299, P1520
        '07': '47 00',
        '0902': _canVinReply(_hsVin),
        '020C00': '42 0C 00 2E E0', // 3000 rpm
        '020D00': '42 0D 00 64', // 100 km/h
        '020500': '42 05 00 89', // 97 °C
        '020400': '42 04 00 E6', // 90.2 %
        '020F00': '42 0F 00 5F', // 55 °C
        '021100': '42 11 00 B3', // 70.2 %
        '020600': '42 06 00 7A', // −4.7 %
        '020B00': '42 0B 00 78', // 120 kPa
      },
    ),
    const _Ecu(
      mode01: {0x01: '81 04 00 00', 0x0D: '48'}, // DCT TCM: MIL req, 1 DTC
      other: {
        '03': '43 01 07 00', // P0700
        '07': '47 01 C1 00', // U0100 pending (lost comm with ECM)
      },
    ),
  ],
);
final _hs = _Vehicle(
  name: 'MG HS 2023 (2.0T GDI DCT)',
  kind: _Kind.spark,
  build: _hsCar,
  live: _live({
    'rpm': 1375,
    'speedKmh': 72,
    'coolantTempC': 95,
    'throttlePct': 22.745,
    'fuelLevelPct': 45.098,
    'engineLoad': 34.902,
    'batteryVoltage': 14.2,
    'oilTempC': 90,
    'fuelTrimShortPct': -1.5625,
    'fuelTrimLongPct': 1.5625,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 145,
    'timingAdvanceDeg': 3,
    'lambdaB1S1': 0.97998,
    'fuelRailPressureKpa': 10000,
    'acceleratorPedalPct': 22.745,
  }),
  dtcs: ['P0299', 'P1520', 'P0700', '~U0100'],
  obdVin: _hsVin,
  plateVin: _hsVin,
  make: 'MG',
  year: '2023',
  milOn: true,
  dtcCount: 3,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Evap System', 'O2 Sensor', //
      'O2 Sensor Heater', 'EGR / VVT',
    ],
    notReady: ['Catalyst'],
  ),
  freeze: {
    'RPM': '3000 rpm',
    'Speed': '100 km/h',
    'Coolant': '97°C',
    'Engine Load': '90.2%',
    'Air Temp': '55°C',
    'Throttle': '70.2%',
    'Fuel Trim': '-4.7%',
    'MAP': '120 kPa',
  },
);

// 3. MG ZS EV 2022 (BEV, Chinese-built). UNVERIFIED: whether the VCU/gateway
//    answers the functional 7DF mode 01 request at all. Modelled as a
//    MINIMAL answer: 0101 (components only), speed 0x0D, control-module
//    voltage 0x42 (12 V net, fed by the DC-DC) and fuel type 0x51 = 08
//    (electric). No rpm / coolant / throttle / load / fuel level exist.
//    Real SOC/HV-battery data is only reachable via mode 22 at header 781
//    (mgevs.com community), which this app does not use. DTCs: P0AA6 hybrid/
//    EV battery isolation fault, U0111 lost comm with BECM, P0A94 DC/DC
//    converter performance (pending) — all SAE-defined.
final _zsEvVin = _vin('LSJA24U6?NS054321');
final _zsEv = _Vehicle(
  name: 'MG ZS EV 2022 (BEV)',
  kind: _Kind.ev,
  build: () => _profile(
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 04 00 00', // MIL, 2 DTCs; components only
          0x0D: '1E', // 30 km/h
          0x42: '37 14', // 14.1 V
          0x51: '08', // fuel type: electric
        },
        other: {
          '03': '43 02 0A A6 C1 11', // P0AA6, U0111
          '07': '47 01 0A 94', // P0A94 pending
          '0902': _canVinReply(_zsEvVin), // UNVERIFIED
          '020D00': '42 0D 00 32', // 50 km/h (only PID in the frame)
        },
      ),
    ],
  ),
  live: _live({'speedKmh': 30, 'batteryVoltage': 14.1}),
  dtcs: ['P0AA6', 'U0111', '~P0A94'],
  obdVin: _zsEvVin,
  plateVin: _zsEvVin,
  make: 'MG',
  year: '2022',
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: ['Components']),
  freeze: {'Speed': '50 km/h'},
);

// 4. GAC Trumpchi GS8 2022, 2.0T GDI (4B20M1) + Aisin 8AT. CAN 11/500,
//    ECM + TCM. Wide-band upstream on 0x34 (ratio + current) only, rail
//    0x23, oil 0x5C. UNVERIFIED: the ESP module also answers functional
//    mode 03 (C1A01, manufacturer chassis code) but not mode 01.
final _gs8Vin = _vin('LMGFJ1S8?N1012345');
final _gs8 = _Vehicle(
  name: 'GAC GS8 2022 (2.0T GDI)',
  kind: _Kind.spark,
  build: () => _profile(
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 00',
          0x03: '02 00',
          0x04: '47', // 27.8 %
          0x05: '85', // 93 °C
          0x06: '81', // +0.8 %
          0x07: '7E', // −1.6 %
          0x0B: '26', // 38 kPa
          0x0C: '0D 48', // 850 rpm
          0x0D: '00',
          0x0E: '90', // +8°
          0x0F: '64', // 60 °C (parked in Gulf sun)
          0x10: '02 BC',
          0x11: '1A', // 10.2 %
          0x13: '03',
          0x15: '91 FF', // 0.725 V
          0x1C: '06',
          0x1F: '01 2C',
          0x21: '00 00',
          0x23: '01 90', // 4000 kPa = 40 bar idle GDI
          0x2F: '4D', // 30.2 %
          0x30: '0C',
          0x31: '05 DC',
          0x33: '63',
          0x34: '80 00 80 00', // λ 1.000
          0x42: '37 3C', // 14.14 V
          0x44: '80 00',
          0x46: '5F',
          0x49: '1A',
          0x4C: '1A',
          0x5C: '7F', // 87 °C
        },
        other: {
          '07': '47 01 04 20', // P0420 pending
          '0902': _canVinReply(_gs8Vin),
          '020C00': '42 0C 00 0C 80', // 800 rpm
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 5A', // 50 °C (cold start)
          '020400': '42 04 00 4D', // 30.2 %
          '020F00': '42 0F 00 5A', // 50 °C
          '021100': '42 11 00 1A', // 10.2 %
          '020600': '42 06 00 80', // 0 %
          '020B00': '42 0B 00 2A', // 42 kPa
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '00'},
        other: {'07': '47 00'},
      ),
    ],
    overrides: {
      // ECM (P0016, P1B00), TCM (none), ESP (C1A01) — UNVERIFIED ESP line.
      '03': '43 02 00 16 1B 00\n43 00\n43 01 5A 01',
    },
  ),
  live: _live({
    'rpm': 850,
    'speedKmh': 0,
    'coolantTempC': 93,
    'throttlePct': 10.196,
    'fuelLevelPct': 30.196,
    'engineLoad': 27.843,
    'batteryVoltage': 14.14,
    'oilTempC': 87,
    'fuelTrimShortPct': 0.78125,
    'fuelTrimLongPct': -1.5625,
    'o2B1S2Voltage': 0.725,
    'intakeAirTempC': 60,
    'mapKpa': 38,
    'timingAdvanceDeg': 8,
    'lambdaB1S1': 1.0,
    'fuelRailPressureKpa': 4000,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P0016', 'P1B00', 'C1A01', '~P0420'],
  obdVin: _gs8Vin,
  plateVin: _gs8Vin,
  make: 'GAC',
  year: '2022',
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: [
    'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
    'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT',
  ]),
  freeze: {
    'RPM': '800 rpm',
    'Speed': '0 km/h',
    'Coolant': '50°C',
    'Engine Load': '30.2%',
    'Air Temp': '50°C',
    'Throttle': '10.2%',
    'Fuel Trim': '0.0%',
    'MAP': '42 kPa',
  },
);

// 5. BAIC X7 2021, 1.5T + DCT. CAN 11/500, single ECM with a reduced PID set:
//    no fuel level, no oil temp, no pedal, and NO 0x42 (UNVERIFIED) → the
//    poll falls back to the adapter's ATRV (pin 16) reading.
final _x7Vin = _vin('LNBMDBAF?MU012345');
final _x7 = _Vehicle(
  name: 'BAIC X7 2021 (1.5T)',
  kind: _Kind.spark,
  build: () => _profile(
    adapterVoltage: '13.8V',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 65 04', // MIL, 2 DTCs; evap incomplete
          0x03: '02 00',
          0x04: '40', // 25.1 %
          0x05: '83', // 91 °C
          0x06: '80', // 0 %
          0x07: '85', // +3.9 %
          0x0B: '25', // 37 kPa
          0x0C: '0C 1C', // 775 rpm
          0x0D: '00',
          0x0E: '8E', // +7°
          0x0F: '5A', // 50 °C
          0x11: '1C', // 11.0 %
          0x13: '03',
          0x14: '78 80', // 0.60 V
          0x15: '96 FF', // 0.75 V
          0x1C: '06',
          0x1F: '00 B4',
          0x21: '00 08',
          0x30: '05',
          0x31: '01 F4',
          0x33: '64',
        },
        other: {
          '03': '43 02 05 07 C1 21', // P0507, U0121
          '07': '47 01 1C 00', // P1C00 pending
          '0902': _canVinReply(_x7Vin),
          '020C00': '42 0C 00 0C 1C',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 83',
          '020400': '42 04 00 40',
          '020F00': '42 0F 00 5A',
          '021100': '42 11 00 1C',
          '020600': '42 06 00 80',
          '020B00': '42 0B 00 25',
        },
      ),
    ],
  ),
  live: _live({
    'rpm': 775,
    'speedKmh': 0,
    'coolantTempC': 91,
    'throttlePct': 10.980,
    'engineLoad': 25.098,
    'batteryVoltage': 13.8, // ATRV
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 3.906,
    'o2B1S1Voltage': 0.60,
    'o2B1S2Voltage': 0.75,
    'intakeAirTempC': 50,
    'mapKpa': 37,
    'timingAdvanceDeg': 7,
  }),
  dtcs: ['P0507', 'U0121', '~P1C00'],
  obdVin: _x7Vin,
  plateVin: _x7Vin,
  make: 'BAIC',
  year: '2021',
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'O2 Sensor', //
      'O2 Sensor Heater',
    ],
    notReady: ['Evap System'],
  ),
  freeze: {
    'RPM': '775 rpm',
    'Speed': '0 km/h',
    'Coolant': '91°C',
    'Engine Load': '25.1%',
    'Air Temp': '50°C',
    'Throttle': '11.0%',
    'Fuel Trim': '0.0%',
    'MAP': '37 kPa',
  },
);

// 6. JAC T8 2022 pickup, 2.0 CTI diesel (Bosch EDC17 family, UNVERIFIED),
//    manual. CAN 11/500, single ECM. Diesel: 0101 byte B bit 3; no throttle
//    plate 0x11 (pedal 0x49 instead), no fuel trims / O2 / timing. China-6
//    style aftertreatment (DPF + SCR + EGR) modelled — GCC-spec emission
//    level is UNVERIFIED. 3 confirmed codes → ISO-TP multi-frame 03 reply.
final _t8Vin = _vin('LJ166A2H?N4012345');
final _t8 = _Vehicle(
  name: 'JAC T8 2022 (2.0 CTI diesel)',
  kind: _Kind.diesel,
  build: () => _profile(
    ecus: [
      _Ecu(
        mode01: {
          0x01: '83 0F EB 40', // MIL, 3 DTCs; CI; DPF incomplete
          0x04: '38', // 22.0 %
          0x05: '80', // 88 °C
          0x0B: '67', // 103 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0F: '5F', // 55 °C
          0x10: '01 F4',
          0x1C: '06',
          0x1F: '02 58',
          0x21: '00 21',
          0x23: '0B B8', // 30 000 kPa = 300 bar
          0x2C: '1A',
          0x2F: '99', // 60 %
          0x30: '04',
          0x31: '00 C8',
          0x33: '64',
          0x42: '37 3C', // 14.14 V
          0x49: '26', // 14.9 %
          0x5C: '7A', // 82 °C
        },
        other: {
          '03': '008\n'
              '0: 43 03 20 02 20 EE\n'
              '1: 10 11 00 00 00 00 00', // P2002, P20EE, P1011
          '07': '47 01 04 01', // P0401 pending
          '0902': _canVinReply(_t8Vin),
          '020C00': '42 0C 00 1F 40', // 2000 rpm
          '020D00': '42 0D 00 50', // 80 km/h
          '020500': '42 05 00 87', // 95 °C
          '020400': '42 04 00 B3', // 70.2 %
          '020F00': '42 0F 00 64', // 60 °C
          '020B00': '42 0B 00 AA', // 170 kPa
        },
      ),
    ],
  ),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 88,
    'fuelLevelPct': 60.0,
    'engineLoad': 21.961,
    'batteryVoltage': 14.14,
    'oilTempC': 82,
    'intakeAirTempC': 55,
    'mapKpa': 103,
    'fuelRailPressureKpa': 30000,
    'acceleratorPedalPct': 14.902,
  }),
  dtcs: ['P2002', 'P20EE', 'P1011', '~P0401'],
  obdVin: _t8Vin,
  plateVin: _t8Vin,
  make: 'JAC',
  year: '2022',
  milOn: true,
  dtcCount: 3,
  monitors: _monitors(
    diesel: true,
    ready: [
      'Misfire', 'Fuel System', 'Components', 'NMHC Catalyst', 'NOx / SCR', //
      'Boost Pressure', 'Exhaust Gas Sensor', 'EGR / VVT',
    ],
    notReady: ['PM Filter'],
  ),
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '80 km/h',
    'Coolant': '95°C',
    'Engine Load': '70.2%',
    'Air Temp': '60°C',
    'MAP': '170 kPa',
  },
);

// 7. Hongqi H5 2023, 1.5T GDI (CA4GB15TD) + 7DCT (FAW). CAN 11/500,
//    ECM + TCM. Wide-band 0x34, rail 0x23. UNVERIFIED: the BCM answers
//    functional mode 03 with a body code (B1A00).
final _h5Vin = _vin('LFPH4ACC?P1A12345');
final _h5 = _Vehicle(
  name: 'Hongqi H5 2023 (1.5T GDI)',
  kind: _Kind.spark,
  build: () => _profile(
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '81 07 E5 04', // MIL, 1 DTC; evap incomplete
          0x03: '02 00',
          0x04: '3D', // 23.9 %
          0x05: '86', // 94 °C
          0x06: '7F', // −0.8 %
          0x07: '80',
          0x0B: '1F', // 31 kPa
          0x0C: '0B 54', // 725 rpm
          0x0D: '00',
          0x0E: '8A', // +5°
          0x0F: '5A', // 50 °C
          0x10: '01 C2',
          0x11: '14', // 7.8 %
          0x13: '03',
          0x15: '8C FF',
          0x1C: '06',
          0x1F: '00 F0',
          0x21: '00 03',
          0x23: '01 2C', // 3000 kPa
          0x2F: '33', // 20 %
          0x30: '14',
          0x31: '07 D0',
          0x33: '64',
          0x34: '82 00 80 00', // λ 1.0156
          0x42: '37 78',
          0x44: '80 00',
          0x46: '5A',
          0x49: '14',
          0x4C: '14',
        },
        other: {
          '0902': _canVinReply(_h5Vin),
          '020C00': '42 0C 00 0B 54',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 86',
          '020400': '42 04 00 3D',
          '020F00': '42 0F 00 5A',
          '021100': '42 11 00 14',
          '020600': '42 06 00 7F',
          '020B00': '42 0B 00 1F',
        },
      ),
      const _Ecu(mode01: {0x01: '00 04 00 00', 0x0D: '00'}),
    ],
    overrides: {
      '03': '43 01 00 11\n43 00\n43 01 9A 00', // ECM P0011, TCM, BCM B1A00
      '07': '47 01 D3 00\n47 00', // ECM U1300 pending
    },
  ),
  live: _live({
    'rpm': 725,
    'speedKmh': 0,
    'coolantTempC': 94,
    'throttlePct': 7.843,
    'fuelLevelPct': 20.0,
    'engineLoad': 23.922,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': -0.78125,
    'fuelTrimLongPct': 0,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 31,
    'timingAdvanceDeg': 5,
    'lambdaB1S1': 1.015625,
    'fuelRailPressureKpa': 3000,
    'acceleratorPedalPct': 7.843,
  }),
  dtcs: ['P0011', 'B1A00', '~U1300'],
  obdVin: _h5Vin,
  plateVin: _h5Vin,
  make: 'Hongqi',
  year: '2023',
  milOn: true,
  dtcCount: 1,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'O2 Sensor', //
      'O2 Sensor Heater', 'EGR / VVT',
    ],
    notReady: ['Evap System'],
  ),
  freeze: {
    'RPM': '725 rpm',
    'Speed': '0 km/h',
    'Coolant': '94°C',
    'Engine Load': '23.9%',
    'Air Temp': '50°C',
    'Throttle': '7.8%',
    'Fuel Trim': '-0.8%',
    'MAP': '31 kPa',
  },
);

// 8. Dongfeng Aeolus Yixuan (Shine) 2022, 1.5T, Chinese-built for the GCC.
//    CAN 11/500, single ECM, reduced set (no fuel level / oil temp / bank 2),
//    narrow-band O2. U1101 is a Dongfeng manufacturer code whose bundled DB
//    text is Ford's "SCP (J1850)" meaning.
final _aeolusVin = _vin('LDP95H96?NE012345');
final _aeolus = _Vehicle(
  name: 'Dongfeng Aeolus Yixuan 2022 (1.5T)',
  kind: _Kind.spark,
  build: () => _profile(
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 65 00',
          0x03: '02 00',
          0x04: '45', // 27.1 %
          0x05: '84', // 92 °C
          0x06: '84', // +3.1 %
          0x07: '7B', // −3.9 %
          0x0B: '27', // 39 kPa
          0x0C: '0C E4', // 825 rpm
          0x0D: '00',
          0x0E: '92', // +9°
          0x0F: '5C', // 52 °C
          0x11: '17', // 9.0 %
          0x13: '03',
          0x14: '2D 80', // 0.225 V
          0x15: '82 FF', // 0.65 V
          0x1C: '06',
          0x21: '00 00',
          0x30: '0F',
          0x31: '02 58',
          0x33: '64',
          0x42: '36 E8', // 14.056 V
          0x49: '17',
        },
        other: {
          '03': '43 02 03 35 D1 01', // P0335, U1101
          '07': '47 01 01 28', // P0128 pending
          '0902': _canVinReply(_aeolusVin),
          '020C00': '42 0C 00 00 00', // 0 rpm: crank signal lost
          '020D00': '42 0D 00 3C', // 60 km/h
          '020500': '42 05 00 82',
          '020400': '42 04 00 00',
          '020F00': '42 0F 00 5F',
          '021100': '42 11 00 33',
          '020600': '42 06 00 80',
          '020B00': '42 0B 00 64',
        },
      ),
    ],
  ),
  live: _live({
    'rpm': 825,
    'speedKmh': 0,
    'coolantTempC': 92,
    'throttlePct': 9.020,
    'engineLoad': 27.059,
    'batteryVoltage': 14.056,
    'fuelTrimShortPct': 3.125,
    'fuelTrimLongPct': -3.906,
    'o2B1S1Voltage': 0.225,
    'o2B1S2Voltage': 0.65,
    'intakeAirTempC': 52,
    'mapKpa': 39,
    'timingAdvanceDeg': 9,
    'acceleratorPedalPct': 9.020,
  }),
  dtcs: ['P0335', 'U1101', '~P0128'],
  obdVin: _aeolusVin,
  plateVin: _aeolusVin,
  make: 'Dongfeng',
  year: '2022',
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: [
    'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
    'O2 Sensor', 'O2 Sensor Heater',
  ]),
  freeze: {
    'RPM': '0 rpm',
    'Speed': '60 km/h',
    'Coolant': '90°C',
    'Engine Load': '0.0%',
    'Air Temp': '55°C',
    'Throttle': '20.0%',
    'Fuel Trim': '0.0%',
    'MAP': '100 kPa',
  },
);

// 9. BYD Song Plus DM-i 2023 (PHEV, BYD472QA 1.5 Atkinson + EHS), driving at
//    40 km/h in EV mode: the engine is OFF → rpm 0, load 0, throttle 0, MAP
//    ≈ baro, trims 0, O2 0 V, coolant cool (engine seldom runs). Pedal 0x49
//    shows the driver demand. ECM + hybrid controller (HCU/VCU) on CAN
//    11/500. UNVERIFIED: 0x51 fuel type = 01 (gasoline) and the HCU's 0x5B
//    hybrid-battery remaining life (62 %); the app never asks for either.
//    PHEV readiness: catalyst / evap / O2 incomplete because the engine has
//    barely run. HCU codes: P0A7F hybrid battery pack deterioration (SAE)
//    and P1A34 (BYD manufacturer, meaning UNVERIFIED).
final _songVin = _vin('LC0C76C4?P0012345');
_ProfileCar _songCar({String? Function(String cmd)? intercept}) {
  final base = _profile(
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      const _Ecu(
        mode01: {
          0x01: '00 07 65 25', // no MIL (ECM); cat/evap/O2 incomplete
          0x03: '00 00', // fuel system: engine off
          0x04: '00', // 0 %
          0x05: '5A', // 50 °C
          0x06: '80',
          0x07: '80',
          0x0B: '64', // 100 kPa ≈ baro
          0x0C: '00 00', // 0 rpm
          0x0D: '28', // 40 km/h
          0x0E: '80', // 0°
          0x0F: '50', // 40 °C
          0x11: '00', // 0 %
          0x13: '03',
          0x14: '00 FF', // 0.00 V
          0x15: '00 FF', // 0.00 V
          0x1C: '06',
          0x1F: '00 00',
          0x21: '00 00',
          0x2F: '8C', // 54.9 %
          0x30: '02',
          0x31: '00 32',
          0x33: '64',
          0x42: '37 D4', // 14.292 V (DC-DC)
          0x46: '50',
          0x49: '33', // 20 % pedal
          0x51: '01', // UNVERIFIED (could be 0x10 hybrid gasoline)
        },
      ),
      const _Ecu(
        mode01: {
          0x01: '82 04 00 00', // HCU: MIL, 2 DTCs
          0x0D: '28',
          0x5B: '9E', // 62 % hybrid battery remaining life (UNVERIFIED)
        },
        other: {
          '020D00': '42 0D 00 3C', // 60 km/h when P0A7F was stored
        },
      ),
    ],
    overrides: {
      '03': '43 00\n43 02 0A 7F 1A 34', // ECM none; HCU P0A7F, P1A34
      '07': '47 01 04 20\n47 00', // ECM P0420 pending
      '0902': _canVinReply(_songVin),
    },
  );
  return intercept == null ? base : _variant(base, intercept: intercept);
}

final _song = _Vehicle(
  name: 'BYD Song Plus DM-i 2023 (PHEV, EV mode)',
  kind: _Kind.hybrid,
  build: _songCar,
  live: _live({
    'rpm': 0,
    'speedKmh': 40,
    'coolantTempC': 50,
    'throttlePct': 0,
    'fuelLevelPct': 54.902,
    'engineLoad': 0,
    'batteryVoltage': 14.292,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 0,
    'o2B1S1Voltage': 0,
    'o2B1S2Voltage': 0,
    'intakeAirTempC': 40,
    'mapKpa': 100,
    'timingAdvanceDeg': 0,
    'acceleratorPedalPct': 20.0,
  }),
  dtcs: ['P0A7F', 'P1A34', '~P0420'],
  obdVin: _songVin,
  plateVin: _songVin,
  make: 'BYD',
  year: '2023',
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    ready: ['Misfire', 'Fuel System', 'Components', 'O2 Sensor Heater'],
    notReady: ['Catalyst', 'Evap System', 'O2 Sensor'],
  ),
  freeze: {'Speed': '60 km/h'},
);

final _vehicles = [_mg5, _hs, _zsEv, _gs8, _x7, _t8, _h5, _aeolus, _song];

// 10. BYD Atto 3 2023 (BEV). UNVERIFIED but consistent with every community
//     tool found: no ECU answers the functional mode 01 request (all data via
//     mode 22 on ATSH7E7 / 7E4). The bus is awake (car ON / READY), so the
//     ELM327 prints NO DATA on ATSP6 and UNABLE TO CONNECT after the
//     auto-search, which walks J1850 / K-line / CAN (~9 s, UNVERIFIED).
final _atto3Vin = _vin('LGXCE4CB?P0012345');
SimCar _atto3Car() => const SimCar(
  protocol: null,
  wrongProtocolReply: 'NO DATA', // CAN frames ACKed, nobody answers
  ignitionOffReply: 'UNABLE TO CONNECT',
  autoSearchTime: Duration(seconds: 9),
  adapterVoltage: '13.9V',
);

/// A combustion CAN car with the ignition truly OFF: the OBD CAN bus is
/// asleep, nothing ACKs the frame → CAN ERROR on ATSP6 (ELM327 datasheet).
SimCar _ignitionOffCanCar() => const SimCar(
  protocol: null,
  wrongProtocolReply: 'CAN ERROR',
  ignitionOffReply: 'UNABLE TO CONNECT',
  autoSearchTime: Duration(seconds: 9),
);

// ── Test helpers ──────────────────────────────────────────────────────────────

const _pollOrder = [
  '010C', '010D', '0105', '0111', '012F', '0104', '0142', '015C', '0106', //
  '0107', '0108', '0109', '0114', '0115', '0118', '010F', '010B', '010E',
];

int _pidOf(String cmd) => int.parse(cmd.substring(2), radix: 16);

/// Mode 01 PIDs [car]'s 0100 / 0120 / 0140 bitmaps advertise (ORed over
/// every ECU line, following the J1979 chain).
Set<int> _advertised(SimCar car) {
  final out = <int>{};
  final re = RegExp(r'41 ([0-9A-F]{2})((?: [0-9A-F]{2}){4})');
  for (var base = 0; base <= 0x40; base += 0x20) {
    if (base != 0 && !out.contains(base)) break;
    for (final line in (car.responses['01${_h(base)}'] ?? '').split('\n')) {
      final m = re.firstMatch(line);
      if (m == null || m.group(1) != _h(base)) continue;
      final b = m.group(2)!.trim().split(' ').map(
            (x) => int.parse(x, radix: 16),
          ).toList();
      for (var i = 0; i < 32; i++) {
        if (b[i ~/ 8] & (0x80 >> (i % 8)) != 0) out.add(base + i + 1);
      }
    }
  }
  return out;
}

/// The exact first-poll command sequence for advertised PIDs [adv]: bitmap
/// requests, the regular PIDs in poll order (ATRV in the 0142 slot when 0142
/// isn't advertised), then 0124 (else 0134) without a narrow-band 0114,
/// 0123, 0149.
List<String> _expectedCycle(Set<int> adv, {bool bitmaps = true}) => [
  if (bitmaps && adv.contains(0x20)) '0120',
  if (bitmaps && adv.contains(0x40)) '0140',
  for (final p in _pollOrder)
    if (p == '0142' && !adv.contains(0x42))
      'ATRV'
    else if (adv.contains(_pidOf(p)))
      p,
  if (!adv.contains(0x14) && adv.contains(0x24)) '0124',
  if (!adv.contains(0x14) && !adv.contains(0x24) && adv.contains(0x34))
    '0134',
  if (adv.contains(0x23)) '0123',
  if (adv.contains(0x49)) '0149',
];

class _PollResult {
  const _PollResult(
    this.frames,
    this.cycle,
    this.period,
    this.firstCycle,
    this.secondCycle,
  );

  final List<OBDLiveData> frames;
  final Duration cycle;
  final Duration period;
  final List<String> firstCycle;
  final List<String> secondCycle;

  Map<String, double?> get first => _fields(frames[0]);
  Map<String, double?> get second => _fields(frames[1]);
}

_PollResult _poll(Rig rig) {
  final frames = <(Duration, OBDLiveData)>[];
  final cuts = <int>[rig.elm.commands.length];
  final sub = rig.adapter.liveDataStream.listen((d) {
    frames.add((rig.async.elapsed, d));
    cuts.add(rig.elm.commands.length);
  });
  final start = rig.async.elapsed;
  rig.adapter.startLiveData();
  while (frames.length < 2 &&
      rig.async.elapsed - start < const Duration(seconds: 120)) {
    rig.async.elapse(const Duration(milliseconds: 10));
  }
  rig.adapter.stopLiveData();
  sub.cancel();
  if (frames.length < 2) fail('fewer than 2 live frames in 120 s');
  return _PollResult(
    [frames[0].$2, frames[1].$2],
    frames[0].$1 - start - const Duration(seconds: 3),
    frames[1].$1 - frames[0].$1,
    rig.elm.commands.sublist(cuts[0], cuts[1]),
    rig.elm.commands.sublist(cuts[1], cuts[2]),
  );
}

void _expectLive(Map<String, double?> actual, Map<String, double?> expected) {
  for (final k in _liveKeys) {
    final e = expected[k];
    expect(actual[k], e == null ? isNull : closeTo(e, 0.01), reason: k);
  }
}

/// Connect, expecting failure; returns the exception and elapsed time.
(OBDConnectException, Duration) _failedConnect(Rig rig) {
  final t0 = rig.async.elapsed;
  try {
    rig.connect();
  } on OBDConnectException catch (e) {
    return (e, rig.async.elapsed - t0);
  }
  fail('connect() succeeded');
}

// ── DTC description expectations ──────────────────────────────────────────────

final _manufacturerRange =
    RegExp(r'^(?:P1[0-9A-F]{3}|P3[0-3][0-9A-F]{2}|[BCU][12][0-9A-F]{3})$');

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() {
    // ignore: avoid_print
    print('\n== Chinese group D (MG/GAC/BAIC/JAC/Hongqi/Dongfeng/BYD) '
        'measurements ==\n${_matrix.join('\n')}');
  });

  test('profile sanity: every profile VIN has a valid check digit and the '
      'right model-year character', () {
    for (final v in [..._vehicles.map((v) => v.plateVin), _atto3Vin]) {
      expect(_checkDigit(v), v[8], reason: v);
    }
    // EV profile: the bitmap chain reaches 0x42 / 0x51 via an empty 0x21+.
    final ev = _zsEv.build();
    expect(ev.responses['0100'], '41 00 80 08 00 01');
    expect(ev.responses['0120'], '41 20 00 00 00 01');
    expect(_advertised(ev), {0x01, 0x0D, 0x20, 0x40, 0x42, 0x51});
  });

  for (final v in _vehicles) {
    group('${v.name} [ISO 15765-4 CAN 11/500]', () {
      test('(a) connect: ATSP6 + 0100 on the first try, < 2 s', () {
        sim(v.build(), (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();
          final dt = rig.async.elapsed - t0;
          _log('${v.name}: connect ${_secs(dt)} s');
          expect(rig.adapter.isConnected, isTrue);
          expect(rig.adapter.connectionState, OBDConnectionState.connected);
          expect(rig.elm.commands,
              ['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100']);
          expect(dt, lessThan(const Duration(seconds: 2)));
        }, connect: false);
      });

      test('(b) poll: exact command sequence, every advertised PID decoded, '
          'unsupported null, poll < 3 s, refresh every 3 s', () {
        final car = v.build();
        final adv = _advertised(car);
        sim(car, (rig) {
          final p = _poll(rig);
          final n = v.live.values.whereType<double>().length;
          _log('${v.name}: poll ${_secs(p.cycle)} s, $n/21 values, '
              '${p.firstCycle.length} cmds [${p.firstCycle.join(' ')}], '
              'refresh ${_secs(p.period)} s');
          expect(p.firstCycle, _expectedCycle(adv));
          _expectLive(p.first, v.live);
          expect(p.cycle, lessThan(const Duration(seconds: 3)));
          // 3 s timer; frame 1→2 is shorter by the first poll's bitmap reads.
          expect(p.period, greaterThan(const Duration(milliseconds: 2500)));
          expect(p.period, lessThan(const Duration(milliseconds: 3100)));
          // Bitmaps are read once; the second cycle repeats the PIDs only.
          expect(p.secondCycle, _expectedCycle(adv, bitmaps: false));
          _expectLive(p.second, v.live);
        });
      });

      test('(c) DTCs: confirmed (03) + pending (07, "~")', () {
        sim(v.build(), (rig) {
          final codes = rig.drive(rig.adapter.getDtcs());
          _log('${v.name}: DTCs $codes');
          expect(codes, v.dtcs);
        });
      });

      test('(c) clear accepted (44) → no codes, no freeze frame', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
        });
      });

      test('(c) clear refused (7F 04 22, engine running) → false, codes kept',
          () {
        sim(_variant(v.build(), clearReply: '7F 04 22'), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(d) getVin() → VinDecoder country China + model year ${v.year}',
          () {
        sim(v.build(), (rig) {
          final vin = rig.drive(rig.adapter.getVin());
          final d = vin == null ? null : VinDecoder.decode(vin, now: _now);
          _log('${v.name}: getVin() → $vin → $d');
          expect(vin, v.obdVin);
          expect(d!['country'], 'China');
          expect(d['year'], v.year);
        });
      });

      test('(d) VinDecoder manufacturer for WMI ${v.plateVin.substring(0, 3)} '
          '→ ${v.make}', () {
        final d = VinDecoder.decode(v.plateVin, now: _now);
        expect(d['manufacturer'], contains(v.make));
      });

      test('(e) readiness (${v.kind.name})', () {
        sim(v.build(), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          _log('${v.name}: readiness MIL ${r.milOn}, ${r.dtcCount} DTCs, '
              '${r.compressionIgnition ? 'diesel' : 'spark'}, '
              '${r.monitors.where((m) => m.isApplicable).map((m) => '${m.name}:${m.isReady ? 'ok' : 'INC'}').join(', ')}');
          expect(r.compressionIgnition, v.kind == _Kind.diesel);
          expect(r.milOn, v.milOn);
          expect(r.dtcCount, v.dtcCount);
          expect({for (final m in r.monitors) m.name: m.status}, v.monitors);
        });
      });

      test('(f) freeze frame (mode 02, frame 00)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getFreezeFrame()), v.freeze);
        });
      });
    });
  }

  // ── DtcRepository: every code these cars report gets a description ────────

  group('DtcRepository descriptions (offline, bundled DB)', () {
    late DtcRepository repo;

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_connectivityChannel, (call) async {
        if (call.method == 'check') return ['none'];
        return null;
      });
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_connectivityChannel, null);
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DtcRepository.resetCaches();
      DtcRepository.httpClient =
          MockClient((_) async => http.Response('', 400));
      repo = DtcRepository();
    });

    final seen = <String>{};
    for (final v in _vehicles) {
      for (final raw in v.dtcs) {
        final code = raw.replaceFirst('~', '');
        if (!seen.add(code)) continue;
        final manufacturer = _manufacturerRange.hasMatch(code);
        test('$code (${v.name}) → '
            '${manufacturer ? 'manufacturer-specific label' : 'SAE description'}',
            () async {
          final desc = await repo.getDtcDescription(code);
          _log('DtcRepository $code → $desc');
          expect(desc, isNotNull);
          if (manufacturer) {
            expect(desc, contains('Manufacturer-specific'));
          } else {
            expect(desc, isNot(contains('Manufacturer-specific')));
          }
        });
      }
    }

    test('Arabic: a BYD manufacturer code still gets a (fallback) text', () async {
      final ar = await repo.getDtcDescription('P1A34', languageCode: 'ar');
      expect(ar, isNotNull);
    });
  });

  // ── BYD Atto 3 (BEV): no generic OBD-II answer ────────────────────────────

  group('BYD Atto 3 2023 (BEV, no mode 01 responder — UNVERIFIED)', () {
    // Bus awake (ATSP6 → NO DATA), auto search UNABLE TO CONNECT, ATRV
    // 13.9 V (DC-DC charging the 12 V battery in READY) → the car is ON but
    // has no mode 01 responder: noStandardObdData, not "turn ignition ON".
    test('(a) connect fails with noStandardObdData after the full search '
        '(ATRV 13.9 V confirms the car is ON)', () {
      sim(_atto3Car(), (rig) {
        final (e, dt) = _failedConnect(rig);
        _log('BYD Atto 3: connect FAILED after ${_secs(dt)} s: '
            '${e.reason.name} "${e.message}" '
            'cmds ${rig.elm.commands.join(' ')}');
        expect(e.reason, OBDFailureReason.noStandardObdData);
        expect(rig.elm.commands, [
          'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100', 'ATSP0', '0100',
          'ATRV',
        ]);
        expect(dt, greaterThan(const Duration(seconds: 9)));
        expect(dt, lessThan(const Duration(seconds: 11)));
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
        expect(rig.adapter.isConnected, isFalse);
      }, connect: false);
    });

    test('(b)-(f) after the failed connect nothing is readable: no live '
        'frame, no DTCs, no VIN, empty readiness, no freeze frame', () {
      sim(_atto3Car(), (rig) {
        _failedConnect(rig);
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        rig.async.elapse(const Duration(seconds: 10));
        rig.adapter.stopLiveData();
        sub.cancel();
        expect(frames, isEmpty);
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
        expect(rig.drive(rig.adapter.getVin()), isNull);
        expect(rig.drive(rig.adapter.getReadinessMonitors()).monitors, isEmpty);
        expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
      }, connect: false);
    });

    test('ignition really off on a combustion CAN car (bus asleep → CAN '
        'ERROR) still fails ecuNotResponding ("turn the ignition ON"), no '
        'ATRV needed', () {
      sim(_ignitionOffCanCar(), (rig) {
        final (e, dt) = _failedConnect(rig);
        _log('Ignition-off CAN car: connect FAILED after ${_secs(dt)} s: '
            '${e.reason.name}');
        expect(e.reason, OBDFailureReason.ecuNotResponding);
        expect(e.message, contains('ignition'));
        expect(rig.elm.commands, isNot(contains('ATRV')));
      }, connect: false);
    });

    test('a car that is ON (bus ACKs: NO DATA, not CAN ERROR) but has no '
        'mode 01 responder must not be told to "turn the ignition ON"', () {
      sim(_atto3Car(), (rig) {
        final (e, _) = _failedConnect(rig);
        expect(e.message, isNot(contains('ignition')));
        expect(e.reason, OBDFailureReason.noStandardObdData);
      }, connect: false);
    });

    test('(d) window VIN: country China, model year 2023', () {
      final d = VinDecoder.decode(_atto3Vin, now: _now);
      expect(d['country'], 'China');
      expect(d['year'], '2023');
    });

    test('(d) window VIN WMI LGX → BYD', () {
      expect(VinDecoder.decode(_atto3Vin, now: _now)['manufacturer'],
          contains('BYD'));
    });
  });

  // ── Brand-specific edge cases ──────────────────────────────────────────────

  group('edge cases', () {
    test('MG HS: ECM refuses mode 04 while the TCM accepts (44 / 7F 04 22) '
        '→ false, all codes kept', () {
      sim(_hsCar(clearReply: '44\n7F 04 22'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _hs.dtcs);
      });
    });

    test('MG HS: ECM 7F 04 78 (responsePending) then 44, TCM 44 → true', () {
      sim(_hsCar(clearReply: '7F 04 78\n44\n44'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
      });
    });

    test('MG HS: ECM and TCM 03 replies as interleaved ISO-TP frames → all '
        'codes', () {
      final car = _variant(_hs.build(), replies: {
        '03': '00A\n'
            '0: 43 04 02 99 15 20\n'
            '43 01 07 00\n'
            '1: 01 71 03 01 AA AA AA',
      });
      sim(car, (rig) {
        expect(
          rig.drive(rig.adapter.getDtcs()),
          unorderedEquals(
              ['P0299', 'P1520', 'P0171', 'P0301', 'P0700', '~U0100']),
        );
      });
    });

    test('GAC GS8: TCM answers 0902 with 17 x 00 before the ECM VIN → ECM VIN',
        () {
      final car = _variant(_gs8.build(), replies: {
        '0902': '${_canVinBytes(List.filled(17, 0))}\n${_canVinReply(_gs8Vin)}',
      });
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), _gs8Vin));
    });

    test('GAC GS8: ECM and TCM VIN frames interleaved → VIN', () {
      final l = _canVinReply(_gs8Vin).split('\n');
      final car = _variant(_gs8.build(), replies: {
        '0902': [l[0], l[1], l[0], l[1], l[2], l[2], l[3], l[3]].join('\n'),
      });
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), _gs8Vin));
    });

    test('BAIC X7 (no 0142): ATRV answered every poll; clone answering "?" '
        '→ battery null and ATRV dropped after two tries', () {
      final car = _x7.build();
      final clone = _ProfileCar(
        protocol: car.protocol,
        responses: car.responses,
        ecuLatency: car.ecuLatency,
        autoSearchTime: car.autoSearchTime,
        wrongProtocolReply: car.wrongProtocolReply,
        noDataLatency: car.noDataLatency,
        emptyDtcReply: car.emptyDtcReply,
        clearReply: car.clearReply,
      ); // adapterVoltage null → '?'
      sim(clone, (rig) {
        final p = _poll(rig);
        expect(p.first['batteryVoltage'], isNull);
        expect(p.firstCycle, contains('ATRV'));
        expect(p.secondCycle, contains('ATRV'));
        // Third poll: ATRV no longer sent.
        final before = rig.elm.commands.length;
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        while (frames.isEmpty) {
          rig.async.elapse(const Duration(milliseconds: 10));
        }
        rig.adapter.stopLiveData();
        sub.cancel();
        expect(rig.elm.commands.sublist(before), isNot(contains('ATRV')));
      });
    });

    test('JAC T8 diesel: no 0111 → throttle null, pedal 0149 + rail 0123 '
        'carry the driver demand / injection data', () {
      sim(_t8.build(), (rig) {
        final p = _poll(rig);
        expect(p.firstCycle, isNot(contains('0111')));
        expect(p.first['throttlePct'], isNull);
        expect(p.first['acceleratorPedalPct'], closeTo(14.902, 0.01));
        expect(p.first['fuelRailPressureKpa'], 30000);
      });
    });

    test('JAC T8 diesel: a spark-looking TCM line (automatic variant) first '
        '→ still diesel monitor names, counts summed', () {
      final car = _variant(_t8.build(),
          replies: {'0101': '41 01 81 04 00 00\n41 01 83 0F EB 40'});
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isTrue);
        expect(r.dtcCount, 4);
        expect({for (final m in r.monitors) m.name: m.status}, _t8.monitors);
      });
    });

    test('Hongqi H5: wide-band 0x34 only → 0134 polled (not 0114 / 0124)', () {
      sim(_h5.build(), (rig) {
        final p = _poll(rig);
        expect(p.firstCycle, contains('0134'));
        expect(p.firstCycle, isNot(contains('0124')));
        expect(p.firstCycle, isNot(contains('0114')));
        expect(p.first['lambdaB1S1'], closeTo(1.015625, 0.0001));
      });
    });

    test('Dongfeng Aeolus: 0902 NO DATA (VIN not supported by the ECM) → '
        'null; DTCs and readiness unaffected', () {
      final car = _variant(_aeolus.build(), replies: {'0902': null});
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
        expect(rig.drive(rig.adapter.getDtcs()), _aeolus.dtcs);
        expect(
            rig.drive(rig.adapter.getReadinessMonitors()).dtcCount, 2);
      });
    });

    test('Dongfeng Aeolus: freeze frame with 0 rpm at 60 km/h (crank signal '
        'lost, P0335) is reported as-is, not dropped', () {
      sim(_aeolus.build(), (rig) {
        final f = rig.drive(rig.adapter.getFreezeFrame());
        expect(f['RPM'], '0 rpm');
        expect(f['Speed'], '60 km/h');
      });
    });

    test('BYD Song Plus DM-i: engine off → rpm 0 (a value, not null) '
        'while speed 40; engine starts → next frame 1300 rpm', () {
      var reads = 0;
      final car = _songCar(intercept: (cmd) {
        if (cmd != '010C') return null;
        return reads++ == 0 ? '41 0C 00 00' : '41 0C 14 50';
      });
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.first['rpm'], 0);
        expect(p.first['speedKmh'], 40);
        expect(p.second['rpm'], 1300);
      });
    });

    test('BYD Song Plus DM-i: 0151 (fuel type) and 015B (hybrid battery '
        'remaining life) are advertised but never requested — the app has '
        'no hybrid-battery value to show', () {
      final car = _song.build();
      final adv = _advertised(car);
      expect(adv, containsAll([0x51, 0x5B]));
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.firstCycle, isNot(contains('0151')));
        expect(p.firstCycle, isNot(contains('015B')));
      });
    });

    test('BYD Song Plus DM-i: HCU (components only, MIL) + ECM → engine '
        'type and monitors from the ECM, MIL from the HCU', () {
      final car = _variant(_song.build(),
          replies: {'0101': '41 01 82 04 00 00\n41 01 00 07 65 25'});
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 2);
        expect(r.compressionIgnition, isFalse);
        expect({for (final m in r.monitors) m.name: m.status}, _song.monitors);
      });
    });

    test('MG ZS EV: dashboard gets only speed + 12 V voltage; rpm, coolant, '
        'throttle, load and fuel stay null (no stale values)', () {
      sim(_zsEv.build(), (rig) {
        final p = _poll(rig);
        expect(p.firstCycle, ['0120', '0140', '010D', '0142']);
        expect(p.first['speedKmh'], 30);
        expect(p.first['batteryVoltage'], closeTo(14.1, 0.001));
        for (final k in ['rpm', 'coolantTempC', 'throttlePct', 'engineLoad',
            'fuelLevelPct']) {
          expect(p.first[k], isNull, reason: k);
        }
      });
    });

    test('MG ZS EV: readiness is components-only (every emission monitor '
        'N/A) and reported as spark ignition', () {
      sim(_zsEv.build(), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.monitors.where((m) => m.isApplicable).map((m) => m.name),
            ['Components']);
        expect(r.compressionIgnition, isFalse);
      });
    });

    test('MG ZS EV variant: VCU silent on mode 01 (like the Atto 3, car '
        'READY) → connect fails noStandardObdData, ATRV asked', () {
      sim(_atto3Car(), (rig) {
        final (e, _) = _failedConnect(rig);
        expect(e.reason, OBDFailureReason.noStandardObdData);
        expect(rig.elm.commands.last, 'ATRV');
      }, connect: false);
    });

    test('VinDecoder: GAC Aion (LNA), Forthing (LGG), BYD LGX — country/year '
        'still decode', () {
      for (final t in ['LNAA2AA1?P5012345', 'LGG8D3D1?NL012345',
          'LGXCE4CB?P0012345']) {
        final d = VinDecoder.decode(_vin(t), now: _now);
        expect(d['country'], 'China', reason: t);
      }
      expect(VinDecoder.decode(_vin('LNAA2AA1?P5012345'), now: _now)['year'],
          '2023');
    });

    const addedWmis = [
      ('LNB', 'BAIC', 'LNBMDBAF?MU012345'),
      ('LJ1', 'JAC', 'LJ166A2H?N4012345'),
      ('LFP', 'Hongqi', 'LFPH4ACC?P1A12345'),
      ('LDP', 'Dongfeng', 'LDP95H96?NE012345'),
      ('LGG', 'Dongfeng', 'LGG8D3D1?NL012345'), // Forthing / Liuzhou
      ('LC0', 'BYD', 'LC0C76C4?P0012345'),
      ('LGX', 'BYD', 'LGXCE4CB?P0012345'),
      ('LNA', 'GAC', 'LNAA2AA1?P5012345'), // GAC Aion
    ];
    for (final (wmi, maker, tpl) in addedWmis) {
      test('VinDecoder WMI $wmi → $maker', () {
        expect(VinDecoder.decode(_vin(tpl), now: _now)['manufacturer'],
            contains(maker));
      });
    }
  });

  // ── Double-check (verifier V2): try to break the fixes ─────────────────────

  group('double-check', () {
    final httpRequests = <http.Request>[];

    setUpAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_connectivityChannel, (call) async {
        if (call.method == 'check') return ['none'];
        return null;
      });
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_connectivityChannel, null);
    });

    setUp(() {
      httpRequests.clear();
      SharedPreferences.setMockInitialValues({});
      DtcRepository.resetCaches();
      DtcRepository.httpClient = MockClient((r) async {
        httpRequests.add(r);
        return http.Response('', 400);
      });
    });

    // ---- VinDecoder: every new WMI for these brands → maker/country/year --
    // (template, brand substring, model year)
    const wmis = [
      ('LSJW74C5?NZ012345', 'MG', '2022'),
      ('LMGFJ1S8?N1012345', 'GAC', '2022'),
      ('LNAA2AA1?P5012345', 'GAC', '2023'), // GAC Aion
      ('LNBMDBAF?MU012345', 'BAIC', '2021'),
      ('LJ166A2H?N4012345', 'JAC', '2022'),
      ('LFPH4ACC?P1A12345', 'Hongqi', '2023'),
      ('LFBGE5D1?RA012345', 'FAW', '2024'),
      ('LDP95H96?NE012345', 'Dongfeng', '2022'),
      ('LGJE1EE1?SN012345', 'Dongfeng', '2025'),
      ('LGG8D3D1?NL012345', 'Dongfeng', '2022'), // Forthing
      ('LMXA14AF?TL012345', 'Dongfeng', '2026'), // Forthing
      ('LC0C76C4?P0012345', 'BYD', '2023'),
      ('LGXCE4CB?P0012345', 'BYD', '2023'),
      ('LPE19W2A?R0012345', 'BYD', '2024'),
    ];
    for (final (tpl, brand, year) in wmis) {
      final vin = _vin(tpl);
      test('WMI ${tpl.substring(0, 3)}: $vin → $brand / China / $year', () {
        final d = VinDecoder.decode(vin, now: _now);
        expect(d['manufacturer'], contains(brand));
        expect(d['country'], 'China');
        expect(d['year'], year);
        expect(VinDecoder.decode(vin.toLowerCase(), now: _now)['manufacturer'],
            d['manufacturer']);
      });
    }

    // ---- getVin(): GB 16735 check digit enforced ---------------------------

    String? readVin(String reply) {
      String? out;
      sim(_variant(_song.build(), replies: {'0902': reply}),
          (rig) => out = rig.drive(rig.adapter.getVin()));
      return out;
    }

    String wrongCheck(String vin) =>
        vin.replaceRange(8, 9, vin[8] == '1' ? '2' : '1');

    test('valid BYD / MG / GAC / Hongqi VINs are accepted from 0902', () {
      for (final vin in [_songVin, _hsVin, _gs8Vin, _h5Vin, _atto3Vin]) {
        expect(readVin(_canVinReply(vin)), vin);
      }
    });

    test('garbled Chinese VINs → null (bad check digit, single-character '
        'corruption, illegal letter I)', () {
      for (final vin in [_songVin, _hsVin, _x7Vin, _atto3Vin]) {
        expect(readVin(_canVinReply(wrongCheck(vin))), isNull, reason: vin);
      }
      // One serial character corrupted (5 → 6): weight 2, so the check
      // digit must change.
      final corrupt = _songVin.replaceRange(16, 17, '6');
      expect(_checkDigit(corrupt), isNot(corrupt[8]));
      expect(readVin(_canVinReply(corrupt)), isNull);
      expect(readVin(_canVinReply(_songVin.replaceRange(4, 5, 'I'))), isNull);
    });

    // ---- DtcRepository: manufacturer codes, hybrid codes ------------------

    const foreign = [
      'J1850', 'SCP', 'Ford', 'GM', 'Intake Manifold Runner', 'Invalid or', //
    ];
    final arabicScript = RegExp(r'[؀-ۿ]');

    for (final lang in ['en', 'ar']) {
      test('[$lang] P1520 / U1101 / P1A34 / P1545 / C1201 / B1300 → '
          'manufacturer label, no other-brand text', () async {
        final repo = DtcRepository();
        for (final code in [
          'P1520', 'U1101', 'P1A34', 'P1545', 'C1201', 'B1300', 'P1745',
        ]) {
          final d = await repo.getDtcDescription(code, languageCode: lang);
          expect(d, DtcRepository.manufacturerLabel(code, languageCode: lang),
              reason: code);
          if (lang == 'ar') expect(d, matches(arabicScript), reason: code);
          for (final f in foreign) {
            expect(d, isNot(contains(f)), reason: '$code contains "$f"');
          }
        }
        expect(httpRequests, isEmpty);
      });
    }

    test('getOtherBrandHint for P1520 is labelled as another brand\'s '
        'meaning; none for a BYD code the DB doesn\'t know', () async {
      final repo = DtcRepository();
      expect(await repo.getOtherBrandHint('P1520'),
          'On some brands (often Ford/GM) this code means: Intake Manifold '
          'Runner Control Circuit Malfunction');
      expect(await repo.getOtherBrandHint('P1520', languageCode: 'ar'),
          startsWith('لدى بعض العلامات التجارية'));
      expect(await repo.getOtherBrandHint('P1A34'), isNull);
      expect(await repo.getOtherBrandHint('P0A7F'), isNull); // SAE code
    });

    // Song Plus DM-i / ZS EV hybrid & EV codes: real text, EN + AR.
    const hybrid = {
      'P0A7F': 'Hybrid Battery Pack Deterioration',
      'P0AA6': 'Hybrid Battery Voltage System Isolation Fault',
      'P0A94': 'DC/DC Converter Performance',
      'P0A80': 'Replace Hybrid Battery Pack',
      'P0AFA': 'Hybrid Battery System Voltage Low',
    };
    for (final e in hybrid.entries) {
      test('${e.key} → "${e.value}" (EN) + a real Arabic description',
          () async {
        final repo = DtcRepository();
        final en = await repo.getDtcDescription(e.key);
        final ar = await repo.getDtcDescription(e.key, languageCode: 'ar');
        expect(en, e.value);
        expect(ar, matches(arabicScript));
        expect(ar, isNot(e.value));
        expect(ar, isNot(contains('رمز نظام الدفع الهجين/الكهربائي')),
            reason: 'generic label instead of a description');
        expect(httpRequests, isEmpty);
      });
    }

    test('all 648 SAE hybrid codes P0A00–P0C87 have a specific EN and AR '
        'description (never the generic label)', () async {
      final repo = DtcRepository();
      final missing = <String>[];
      for (var n = 0xA00; n <= 0xC87; n++) {
        final code = 'P0${n.toRadixString(16).toUpperCase()}';
        final en = await repo.getDtcDescription(code);
        final ar = await repo.getDtcDescription(code, languageCode: 'ar');
        if (en == null ||
            en.contains('Description not available') ||
            ar == null ||
            !arabicScript.hasMatch(ar) ||
            ar.contains('الوصف غير متوفر')) {
          missing.add(code);
        }
      }
      expect(missing, isEmpty);
      expect(httpRequests, isEmpty);
    });

    test('P0C88–P0DFF (not in the DB) → localized hybrid/EV category label '
        'offline, never null, no network', () async {
      final repo = DtcRepository();
      for (final code in ['P0C88', 'P0CFF', 'P0D00', 'P0D7F', 'P0DFF']) {
        final en = await repo.getDtcDescription(code);
        final ar = await repo.getDtcDescription(code, languageCode: 'ar');
        expect(en, DtcRepository.genericSaeLabel(code), reason: code);
        expect(en, startsWith('Hybrid/EV propulsion system code ($code)'));
        expect(ar, DtcRepository.genericSaeLabel(code, languageCode: 'ar'));
        expect(ar, startsWith('رمز نظام الدفع الهجين/الكهربائي ($code)'));
      }
      expect(httpRequests, isEmpty);
    });

    // ---- Connect matrix: EV / PHEV ----------------------------------------

    SimCar evSilent({
      String can = 'NO DATA',
      String auto = 'UNABLE TO CONNECT',
      String? volts = '13.9V',
    }) => SimCar(
      protocol: null,
      wrongProtocolReply: can,
      ignitionOffReply: auto,
      autoSearchTime: const Duration(seconds: 9),
      adapterVoltage: volts,
    );

    // (case, car, expected reason, ATRV expected in the commands)
    final matrix = [
      ('Atto 3 READY, 13.9 V', evSilent(),
          OBDFailureReason.noStandardObdData, true),
      ('Atto 3 parked, 12.4 V', evSilent(volts: '12.4V'),
          OBDFailureReason.ecuNotResponding, true),
      ('exactly 13.0 V (threshold)', evSilent(volts: '13.0V'),
          OBDFailureReason.noStandardObdData, true),
      ('12.9 V', evSilent(volts: '12.9V'),
          OBDFailureReason.ecuNotResponding, true),
      ('clone without ATRV ("?")', evSilent(volts: null),
          OBDFailureReason.ecuNotResponding, true),
      ('CAN ERROR on ATSP6, 13.9 V', evSilent(can: 'CAN ERROR'),
          OBDFailureReason.ecuNotResponding, false),
      ('NO DATA then BUS ERROR in the search, 13.9 V',
          evSilent(auto: 'BUS ERROR'),
          OBDFailureReason.ecuNotResponding, false),
      ('NO DATA on both attempts (confirmed without ATRV)',
          evSilent(auto: 'NO DATA', volts: '12.4V'),
          OBDFailureReason.noStandardObdData, false),
    ];
    for (final (name, car, reason, atrv) in matrix) {
      test('connect matrix: $name → ${reason.name}', () {
        sim(car, (rig) {
          final (e, dt) = _failedConnect(rig);
          _log('double-check $name: ${e.reason.name} after ${_secs(dt)} s, '
              'cmds ${rig.elm.commands.join(' ')}');
          expect(e.reason, reason);
          expect(rig.elm.commands.contains('ATRV'), atrv);
          if (reason == OBDFailureReason.noStandardObdData) {
            expect(e.message, isNot(contains('ignition')));
          } else {
            expect(e.message, contains('ignition'));
          }
          expect(rig.adapter.connectionState, OBDConnectionState.failed);
          expect(rig.adapter.isConnected, isFalse);
          expect(dt, lessThan(const Duration(seconds: 11)));
        }, connect: false);
      });
    }

    for (final v in [_song, _zsEv]) {
      test('${v.name}: still connects on ATSP6 (no ATRV), first poll < 3 s',
          () {
        sim(v.build(), (rig) {
          rig.connect();
          expect(rig.adapter.connectionState, OBDConnectionState.connected);
          expect(rig.elm.commands,
              ['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100']);
          final p = _poll(rig);
          _log('double-check ${v.name}: poll ${_secs(p.cycle)} s');
          expect(p.cycle, lessThan(const Duration(seconds: 3)));
          _expectLive(p.first, v.live);
        }, connect: false);
      });
    }
  });
}
