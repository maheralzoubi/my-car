// Compatibility matrix: Korean and Chinese vehicles (incl. Gulf / Middle-East
// market models) driven through the ELM327 simulator.
//
// Each profile models what that car's ECU(s) answer: ELM protocol number,
// auto-search time, PID support bitmaps (generated from the PIDs that really
// answer, so 0100/0120/0140 are always consistent), NO DATA for unsupported
// PIDs, extra ECUs on CAN, protocol-correct DTC / VIN / freeze-frame replies
// and engine-appropriate readiness bytes.
//
// Grounding: SAE J1979 / ISO 15765-4 / ISO 14230-4 formats and ELM327
// datasheet behaviour. Per-model PID sets and timings are NOT published by the
// OEMs; where a detail is a plausible assumption it says so ("UNCERTAIN").
//
// Tests asserting the CORRECT behaviour that the app still gets wrong would
// be marked `skip: 'REGRESSION: …'`. None remain: the former `BUG:` and
// `REGRESSION:` skips were fixed in obd_adapter.dart / vin_decoder.dart and
// now always run; the "double-check" group at the end attacks the latest
// fixes (Chinese WMIs, GB 16735 check digit, manufacturer DTC labels).

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/vin_decoder.dart';

import '../helpers/elm327_sim.dart';

// Fixed clock for VinDecoder's non-North-American model-year heuristic.
final _now = DateTime(2026, 11, 3);

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

/// ISO 3779 / 49 CFR 565 check digit (position 9). China's GB 16735 mandates
/// the same check digit; Korean VINs carry it too.
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

/// Same, from 17 raw bytes (lets tests send non-ASCII garbage).
String _canVinBytes(List<int> vin) {
  assert(vin.length == 17);
  final b = [0x49, 0x02, 0x01, ...vin];
  return '014\n'
      '0: ${_hx(b.sublist(0, 6))}\n'
      '1: ${_hx(b.sublist(6, 13))}\n'
      '2: ${_hx(b.sublist(13, 20))}';
}

/// 09 02 on ISO 9141-2 / ISO 14230-4: five messages "49 02 0N" + 4 bytes,
/// the first padded with three 00 bytes.
String _kLineVinReply(String vin) {
  final b = [0, 0, 0, ...vin.codeUnits];
  return [
    for (var i = 0; i < 5; i++)
      '49 02 ${_h(i + 1)} ${_hx(b.sublist(i * 4, i * 4 + 4))}',
  ].join('\n');
}

// ── ECU / vehicle profile model ───────────────────────────────────────────────

/// One ECU on the diagnostic bus.
class _Ecu {
  const _Ecu({required this.mode01, this.other = const {}});

  /// Mode 01 PID → data bytes it answers with. Support bitmaps (00/20/40/…)
  /// are generated from these keys — never list them here.
  final Map<int, String> mode01;

  /// Replies to everything else (03, 07, 02xx00, 0902 …).
  final Map<String, String> other;

  Map<String, String> replies() {
    final out = <String, String>{};
    final pids = mode01.keys.toSet();
    for (var base = 0; base <= 0xE0; base += 0x20) {
      // A range is only answered when the previous bitmap's last bit says so.
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
/// the ELM327 prints them with headers off), with realistic NO DATA timing
/// and a mode 04 that really clears the stored codes.
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
  });

  /// How long the ELM327 waits before printing NO DATA (its ST timer,
  /// default 0x32 × 4 ms ≈ 200 ms, shortened by adaptive timing).
  final Duration noDataLatency;

  /// What 03 / 07 return once codes are cleared (one line per ECU).
  final String emptyDtcReply;

  /// Reply to mode 04 (e.g. "44", or "7F 04 22" when the ECU refuses).
  final String clearReply;

  bool cleared = false;

  @override
  String answer(String cmd) {
    if (cmd == '04') {
      // An ECU clears when it answers 44 (a "7F 04 78" responsePending line
      // only precedes that final answer). Any other "7F 04 NN" means at least
      // one ECU refused, so the codes are modelled as still stored.
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
  Duration latency(String cmd) => responses.containsKey(cmd)
      ? super.latency(cmd)
      : noDataLatency;
}

_ProfileCar _profile({
  required String protocol,
  required List<_Ecu> ecus,
  bool kLine = false,
  Duration ecuLatency = const Duration(milliseconds: 50),
  Duration? noDataLatency,
  Duration autoSearchTime = const Duration(seconds: 7),
  Map<String, String> overrides = const {},
  Set<String> silent = const {},
  Set<String> hangsOnce = const {},
  String? clearReply,
}) {
  final merged = <String, List<String>>{};
  for (final ecu in ecus) {
    for (final e in ecu.replies().entries) {
      (merged[e.key] ??= []).add(e.value);
    }
  }
  final responses = {
    for (final e in merged.entries) e.key: e.value.join('\n'),
    ...overrides,
  };
  if (kLine) {
    // ISO 9141 / KWP: the first request after the search shows the init.
    responses['0100'] = 'BUS INIT: ...OK\n${responses['0100']}';
  }
  final emptyLine = kLine ? '43 00 00 00 00 00 00' : '43 00';
  return _ProfileCar(
    protocol: protocol,
    responses: responses,
    ecuLatency: ecuLatency,
    noDataLatency:
        noDataLatency ??
        (kLine
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 150)),
    autoSearchTime: autoSearchTime,
    // No CAN transceiver traffic on a K-line car: the ELM reports CAN ERROR.
    wrongProtocolReply: kLine ? 'CAN ERROR' : 'NO DATA',
    emptyDtcReply: List.filled(ecus.length, emptyLine).join('\n'),
    clearReply: clearReply ?? List.filled(ecus.length, '44').join('\n'),
    silent: silent,
    hangsOnce: hangsOnce,
  );
}

/// [base] with some replies replaced (null value = removed → NO DATA) and/or
/// some requests made to hang. Support bitmaps are NOT regenerated, so a
/// removed / hanging PID stays advertised — exactly the case under test.
_ProfileCar _variant(
  _ProfileCar base, {
  Map<String, String?> replies = const {},
  Set<String> silent = const {},
  Set<String> hangsOnce = const {},
  String? clearReply,
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
    silent: {...base.silent, ...silent},
    hangsOnce: {...base.hangsOnce, ...hangsOnce},
  );
}

// ── Expected values ───────────────────────────────────────────────────────────

const _liveKeys = [
  'rpm', 'speedKmh', 'coolantTempC', 'throttlePct', 'fuelLevelPct', //
  'engineLoad', 'batteryVoltage', 'oilTempC', 'fuelTrimShortPct',
  'fuelTrimLongPct', 'fuelTrimShortB2', 'fuelTrimLongB2', 'o2B1S1Voltage',
  'o2B1S2Voltage', 'o2B2S1Voltage', 'intakeAirTempC', 'mapKpa',
  'timingAdvanceDeg',
  // Extras (0124/0134, 0123, 0149): read only when the bitmap sets the bit.
  'lambdaB1S1', 'fuelRailPressureKpa', 'acceleratorPedalPct',
];

/// Fields filled by the extra PIDs (null when no readable bitmap).
const _extraKeys = ['lambdaB1S1', 'fuelRailPressureKpa', 'acceleratorPedalPct'];

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

/// All 18 polled values; the ones not listed are expected to be null
/// (PID unsupported by that car).
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

/// Expected monitor table: listed monitors ready / not ready, the rest N/A.
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

class _Vehicle {
  const _Vehicle({
    required this.name,
    required this.protocol,
    required this.protocolName,
    required this.build,
    required this.connectMax,
    required this.live,
    required this.dtcs,
    required this.obdVin,
    required this.plateVin,
    required this.make,
    required this.year,
    required this.country,
    required this.diesel,
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
    required this.freeze,
  });

  final String name;
  final String protocol;
  final String protocolName;
  final _ProfileCar Function() build;
  final Duration connectMax;
  final Map<String, double?> live;
  final List<String> dtcs;

  /// What 0902 should return (null = car doesn't support mode 09 PID 02).
  final String? obdVin;

  /// VIN stamped on the car (windshield / door plate).
  final String plateVin;
  final String make;
  final String year;
  final String country;
  final bool diesel;
  final bool milOn;
  final int dtcCount;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freeze;
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

// 1. Hyundai Elantra HD 2008, 1.6 Gamma MPI (MAP sensor), Gulf/general-market
//    spec. UNCERTAIN: US-market 2008 Elantras are CAN (EPA mandate for MY2008);
//    GCC / general-export Hyundais of this generation commonly use ISO 14230-4
//    KWP2000 fast init on the K-line (ELM protocol 5) — modelled here.
final _elantraVin = _vin('KMHDT41C?8U512345');
final _elantra = _Vehicle(
  name: 'Hyundai Elantra HD 2008 (GCC, 1.6 MPI)',
  protocol: '5',
  protocolName: 'ISO 14230-4 KWP fast init',
  build: () => _profile(
    protocol: '5',
    kLine: true,
    // 10.4 kbaud K-line + P2 timing: ~150 ms per request/answer.
    ecuLatency: const Duration(milliseconds: 150),
    // ELM walks J1850 PWM/VPW, ISO 9141 5-baud, KWP 5-baud, then KWP fast.
    autoSearchTime: const Duration(milliseconds: 7500),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '84 07 65 04', // MIL on, 4 DTCs; spark; evap incomplete
          0x03: '02 00',
          0x04: '4D', // 30.2 %
          0x05: '7B', // 83 °C
          0x06: '83', // +2.3 %
          0x07: '7A', // −4.7 %
          0x0B: '21', // 33 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '50', // 40 °C (Gulf ambient)
          0x11: '26', // 14.9 %
          0x13: '03', // O2 B1S1 + B1S2 present
          0x14: '5A 80', // 0.45 V
          0x15: '8C FF', // 0.70 V
          0x1C: '06', // EOBD (UNCERTAIN for GCC)
          0x21: '00 2A', // 42 km with MIL on
          // No 0x2F / 0x42 / 0x5C: 2008-era ECU, nothing above 0x21.
        },
        other: {
          // ISO 14230-4: fixed 3-codes-per-message, zero padded, no count.
          '03': '43 01 34 03 00 04 20\n43 04 41 00 00 00 00',
          '07': '47 03 04 00 00 00 00',
          // UNCERTAIN: many pre-CAN Hyundai ECUs don't answer mode 09 at all
          // (see the "no 0902" variant below); format per ISO 14230-4.
          '0902': _kLineVinReply(_elantraVin),
          '020C00': '42 0C 00 0F A0', // 1000 rpm
          '020D00': '42 0D 00 28', // 40 km/h
          '020500': '42 05 00 82', // 90 °C
          '020400': '42 04 00 33', // 20 %
          '020F00': '42 0F 00 4B', // 35 °C
          '021100': '42 11 00 1A', // 10.2 %
          '020600': '42 06 00 90', // +12.5 % (lean → P0134 context)
          '020B00': '42 0B 00 2D', // 45 kPa
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 20),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 83,
    'throttlePct': 14.902,
    'engineLoad': 30.196,
    'fuelTrimShortPct': 2.344,
    'fuelTrimLongPct': -4.6875,
    'o2B1S1Voltage': 0.45,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 40,
    'mapKpa': 33,
    'timingAdvanceDeg': 6,
  }),
  dtcs: ['P0134', 'P0300', 'P0420', 'P0441', '~P0304'],
  obdVin: _elantraVin,
  plateVin: _elantraVin,
  make: 'Hyundai',
  year: '2008',
  country: 'South Korea',
  diesel: false,
  milOn: true,
  dtcCount: 4,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'O2 Sensor', //
      'O2 Sensor Heater',
    ],
    notReady: ['Evap System'],
  ),
  freeze: {
    'RPM': '1000 rpm',
    'Speed': '40 km/h',
    'Coolant': '90°C',
    'Engine Load': '20.0%',
    'Air Temp': '35°C',
    'Throttle': '10.2%',
    'Fuel Trim': '12.5%',
    'MAP': '45 kPa',
  },
);

// 2. Hyundai Tucson 2022 (NX4), 1.6 T-GDi, Korean-built (GCC). CAN 11-bit
//    500k. ECM (7E8) + TCM (7E9) both answer functional requests.
//    Upstream sensor is a wide-band A/F sensor → reported at PID 0x34, not
//    0x14 (UNCERTAIN per engine, typical for GDI engines). Hyundai/Kia ECMs
//    commonly don't report fuel level 0x2F (cluster owns it) — UNCERTAIN.
final _tucsonVin = _vin('KM8J3CA4?NU187654');
const _tucsonEcmMode01 = {
  0x01: '82 07 E5 01', // MIL on, 2 DTCs; catalyst incomplete
  0x03: '02 00',
  0x04: '40', // 25.1 %
  0x05: '87', // 95 °C
  0x06: '80', // 0 %
  0x07: '85', // +3.9 %
  0x0B: '23', // 35 kPa
  0x0C: '1F 40', // 2000 rpm
  0x0D: '3C', // 60 km/h
  0x0E: '94', // +10°
  0x0F: '46', // 30 °C
  0x10: '01 F4',
  0x11: '33', // 20 %
  0x13: '03',
  0x15: '8C FF', // 0.70 V downstream
  0x1C: '06',
  0x1F: '02 58',
  0x21: '00 00',
  0x2E: '00',
  0x30: '05',
  0x31: '01 2C',
  0x33: '64',
  0x34: '80 00 80 00', // λ 1.000, 0 mA (wide-band upstream)
  0x3C: '11 94',
  0x42: '37 78', // 14.2 V
  0x44: '80 00',
  0x46: '4B',
  0x49: '1A',
  0x4C: '33',
};
const _tucsonEcmOther = {
  '03': '43 02 01 71 03 01', // P0171, P0301 (count byte)
  '07': '47 01 04 20', // P0420 pending
  '020C00': '42 0C 00 0C 80',
  '020D00': '42 0D 00 00',
  '020500': '42 05 00 8C',
  '020400': '42 04 00 26',
  '020F00': '42 0F 00 50',
  '021100': '42 11 00 0D',
  '020600': '42 06 00 99',
  '020B00': '42 0B 00 1E',
};
final _tucsonTcm = _Ecu(
  mode01: {0x01: '00 04 00 00', 0x0D: '3C'},
  other: {'03': '43 00', '07': '47 00'},
);
_ProfileCar _tucsonCar({String? clearReply}) => _profile(
  protocol: '6',
  // ELM waits for further responders after the first one.
  ecuLatency: const Duration(milliseconds: 80),
  ecus: [
    _Ecu(
      mode01: _tucsonEcmMode01,
      other: {..._tucsonEcmOther, '0902': _canVinReply(_tucsonVin)},
    ),
    _tucsonTcm,
  ],
  clearReply: clearReply,
);
final _tucson = _Vehicle(
  name: 'Hyundai Tucson 2022 (1.6 T-GDi)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _tucsonCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 10.196,
    'rpm': 2000,
    'speedKmh': 60,
    'coolantTempC': 95,
    'throttlePct': 20.0,
    'engineLoad': 25.098,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 3.906,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 30,
    'mapKpa': 35,
    'timingAdvanceDeg': 10,
  }),
  dtcs: ['P0171', 'P0301', '~P0420'],
  obdVin: _tucsonVin,
  plateVin: _tucsonVin,
  make: 'Hyundai',
  year: '2022',
  country: 'South Korea',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Evap System', 'O2 Sensor', //
      'O2 Sensor Heater', 'EGR / VVT',
    ],
    notReady: ['Catalyst'],
  ),
  freeze: {
    'RPM': '800 rpm',
    'Speed': '0 km/h',
    'Coolant': '100°C',
    'Engine Load': '14.9%',
    'Air Temp': '40°C',
    'Throttle': '5.1%',
    'Fuel Trim': '19.5%',
    'MAP': '30 kPa',
  },
);

// 3. Kia Sportage 2019 (QL), 2.0 Nu MPI (narrow-band O2), Korean-built.
//    CAN 11/500, ECM + TCM. ECM has 3 confirmed codes → ISO-TP multi-frame
//    (padding byte AA — padding value is OEM-specific, UNCERTAIN); TCM has a
//    confirmed P0741 and its single frame arrives first.
final _sportageVin = _vin('KNDPM3AC?K7523456');
final _sportage = _Vehicle(
  name: 'Kia Sportage 2019 (2.0 MPI)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '83 07 65 04', // MIL on, 3 DTCs (ECM); evap incomplete
          0x03: '02 00',
          0x04: '33', // 20 %
          0x05: '5A', // 50 °C
          0x06: '7C', // −3.1 %
          0x07: '80', // 0 %
          0x0B: '1E', // 30 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '90', // +8°
          0x0F: '5A', // 50 °C
          0x11: '1A', // 10.2 %
          0x13: '03',
          0x14: '14 80', // 0.10 V
          0x15: 'A0 FF', // 0.80 V
          0x1C: '06',
          0x1F: '00 3C',
          0x21: '00 00',
          0x2E: '00',
          0x30: '0A',
          0x31: '00 C8',
          0x33: '62',
          0x3C: '0F A0',
          0x42: '35 E8', // 13.8 V
          0x44: '80 00',
          0x46: '50',
          0x49: '1A',
          0x4C: '1A',
        },
        other: {
          '07': '47 00',
          '0902': _canVinReply(_sportageVin),
          '020C00': '42 0C 00 0A F0',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 5F',
          '020400': '42 04 00 4D',
          '020F00': '42 0F 00 5A',
          '021100': '42 11 00 1A',
          '020600': '42 06 00 7C',
          '020B00': '42 0B 00 21',
        },
      ),
      _Ecu(
        mode01: {0x01: '81 04 00 00', 0x0D: '00'}, // TCM: MIL req, 1 DTC
        other: {
          '07': '47 00',
          // UNCERTAIN whether Kia TCMs answer 0902; if they do, ISO-TP
          // replies from both ECUs could interleave (see report).
          '0902': _canVinReply(_sportageVin),
        },
      ),
    ],
    overrides: {
      // TCM single frame first, then ECM's 8-byte ISO-TP reply.
      '03':
          '43 01 07 41\n'
          '008\n'
          '0: 43 03 00 11 01 28\n'
          '1: 04 56 AA AA AA AA AA',
    },
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'acceleratorPedalPct': 10.196,
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 50,
    'throttlePct': 10.196,
    'engineLoad': 20.0,
    'batteryVoltage': 13.8,
    'fuelTrimShortPct': -3.125,
    'fuelTrimLongPct': 0,
    'o2B1S1Voltage': 0.10,
    'o2B1S2Voltage': 0.80,
    'intakeAirTempC': 50,
    'mapKpa': 30,
    'timingAdvanceDeg': 8,
  }),
  dtcs: ['P0741', 'P0011', 'P0128', 'P0456'],
  obdVin: _sportageVin,
  plateVin: _sportageVin,
  make: 'Kia',
  year: '2019',
  country: 'South Korea',
  diesel: false,
  milOn: true,
  dtcCount: 4, // 3 (ECM) + 1 (TCM)
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'O2 Sensor', //
      'O2 Sensor Heater',
    ],
    notReady: ['Evap System'],
  ),
  freeze: {
    'RPM': '700 rpm',
    'Speed': '0 km/h',
    'Coolant': '55°C',
    'Engine Load': '30.2%',
    'Air Temp': '50°C',
    'Throttle': '10.2%',
    'Fuel Trim': '-3.1%',
    'MAP': '33 kPa',
  },
);

// 4. Hyundai H1 / Grand Starex 2016, 2.5 CRDi (D4CB) diesel, Levant/GCC.
//    CAN 11/500, single ECM. Diesel: 0101 byte B bit 3 set; no O2 voltage,
//    fuel-trim or timing-advance PIDs; MAP ≈ baro at idle, boost under load;
//    no throttle PID 0x11 (pedal at 0x49 instead). Emission level (Euro 4/5,
//    DPF or not) varies by market — modelled without DPF/SCR (UNCERTAIN).
final _h1Vin = _vin('KMJWA37K?GU812345');
final _h1 = _Vehicle(
  name: 'Hyundai H1 2016 (2.5 CRDi diesel)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 0F A9 80', // MIL, 2 DTCs; CI; NMHC/boost/EGS/EGR; EGR inc.
          0x04: '33', // 20 %
          0x05: '82', // 90 °C
          0x0B: '65', // 101 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0F: '50', // 40 °C
          0x10: '02 58',
          0x1C: '06',
          0x1F: '01 2C',
          0x21: '00 10',
          0x23: '0A 8C', // 270 bar rail
          0x2C: '33',
          0x30: '08',
          0x31: '01 90',
          0x33: '64',
          0x42: '37 78', // 14.2 V
          0x49: '24',
        },
        other: {
          '03': '43 02 00 87 04 01', // P0087, P0401
          '07': '47 01 02 99', // P0299 pending
          '0902': _canVinReply(_h1Vin),
          '020C00': '42 0C 00 1F 40',
          '020D00': '42 0D 00 46',
          '020500': '42 05 00 87',
          '020400': '42 04 00 CC',
          '020F00': '42 0F 00 5F',
          '020B00': '42 0B 00 A0',
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'fuelRailPressureKpa': 27000,
    'acceleratorPedalPct': 14.118,
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 90,
    'engineLoad': 20.0,
    'batteryVoltage': 14.2,
    'intakeAirTempC': 40,
    'mapKpa': 101,
  }),
  dtcs: ['P0087', 'P0401', '~P0299'],
  obdVin: _h1Vin,
  plateVin: _h1Vin,
  make: 'Hyundai',
  year: '2016',
  country: 'South Korea',
  diesel: true,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    diesel: true,
    ready: [
      'Misfire', 'Fuel System', 'Components', 'NMHC Catalyst', //
      'Boost Pressure', 'Exhaust Gas Sensor',
    ],
    notReady: ['EGR / VVT'],
  ),
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '70 km/h',
    'Coolant': '95°C',
    'Engine Load': '80.0%',
    'Air Temp': '55°C',
    'MAP': '160 kPa',
  },
);

// 5. Changan CS75 Plus 2022, 1.5T GDI (Blue Whale), Chinese-built for GCC.
//    CAN 11/500, single ECM (UAES/Bosch-family). Reduced PID set: no oil temp,
//    no bank 2, wide-band upstream (0x34). Fuel level 0x2F supported
//    (UNCERTAIN).
final _changanVin = _vin('LS5A3DKR?NA012345');
final _changan = _Vehicle(
  name: 'Changan CS75 Plus 2022 (1.5T)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '81 07 E5 00',
          0x03: '02 00',
          0x04: '40', // 25.1 %
          0x05: '87', // 95 °C
          0x06: '80',
          0x07: '83', // +2.3 %
          0x0B: '28', // 40 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '5A', // 50 °C
          0x10: '01 90',
          0x11: '1A',
          0x13: '03',
          0x15: '8C FF',
          0x1C: '06',
          0x1F: '00 78',
          0x21: '00 05',
          0x2F: '40', // 25.1 %
          0x30: '03',
          0x31: '00 64',
          0x33: '63',
          0x34: '80 00 80 00',
          0x42: '37 78',
          0x44: '80 00',
          0x46: '50',
          0x49: '1A',
          0x4C: '1A',
        },
        other: {
          '03': '43 01 00 16', // P0016 cam/crank correlation
          '07': '47 00',
          '0902': _canVinReply(_changanVin),
          '020C00': '42 0C 00 0B B8',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 5A',
          '020400': '42 04 00 40',
          '020F00': '42 0F 00 50',
          '021100': '42 11 00 1A',
          '020600': '42 06 00 80',
          '020B00': '42 0B 00 28',
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 10.196,
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 95,
    'throttlePct': 10.196,
    'fuelLevelPct': 25.098,
    'engineLoad': 25.098,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 2.344,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 40,
    'timingAdvanceDeg': 6,
  }),
  dtcs: ['P0016'],
  obdVin: _changanVin,
  plateVin: _changanVin,
  make: 'Changan',
  year: '2022',
  country: 'China',
  diesel: false,
  milOn: true,
  dtcCount: 1,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
      'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT',
    ],
  ),
  freeze: {
    'RPM': '750 rpm',
    'Speed': '0 km/h',
    'Coolant': '50°C',
    'Engine Load': '25.1%',
    'Air Temp': '40°C',
    'Throttle': '10.2%',
    'Fuel Trim': '0.0%',
    'MAP': '40 kPa',
  },
);

// 6. MG ZS 2021 (SAIC), 1.5 NSE MPI, narrow-band O2. CAN 11/500. Reduced PID
//    set (no fuel level, no oil temp, no bank 2). Freshly reconnected battery:
//    all non-continuous monitors incomplete, one pending code.
//    WORST CASE / UNCERTAIN: 015C never gets a prompt back. A genuine ELM327
//    always ends with NO DATA; this models cheap clones reported to hang on
//    some gateway-fronted ECUs, to measure what one hung PID costs.
//    The base profile does NOT advertise 015C (bitmaps come from the PIDs
//    that answer), so a bitmap-aware poll never sends it. [_mgCar] with
//    `advertiseOil: true` is the variant where the ECM's 0140 bitmap DOES
//    advertise 015C and the request still hangs — the bare-CR resync path.
final _mgVin = _vin('LSJA24U6?MN012345');
_ProfileCar _mgCar({
  bool advertiseOil = false,
  Set<String> silent = const {'015C'},
  Set<String> hangsOnce = const {},
}) => _profile(
    protocol: '6',
    silent: silent,
    hangsOnce: hangsOnce,
    ecus: [
      _Ecu(
        mode01: {
          if (advertiseOil) 0x5C: '7D', // 85 °C (when it answers at all)
          0x01: '00 07 65 65', // no MIL; cat/evap/O2/heater incomplete
          0x03: '02 00',
          0x04: '4D', // 30.2 %
          0x05: '82', // 90 °C
          0x06: '85', // +3.9 %
          0x07: '7C', // −3.1 %
          0x0B: '24', // 36 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0E: '94', // +10°
          0x0F: '55', // 45 °C
          0x11: '26', // 14.9 %
          0x13: '03',
          0x14: '5A 80', // 0.45 V
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x21: '00 00',
          0x30: '01',
          0x31: '00 02',
          0x33: '64',
          0x42: '36 B0', // 14.0 V
        },
        other: {
          '03': '43 00',
          '07': '47 01 05 07', // P0507 idle high (pending)
          '0902': _canVinReply(_mgVin),
        },
      ),
    ],
  );
final _mg = _Vehicle(
  name: 'MG ZS 2021 (1.5 MPI)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _mgCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 90,
    'throttlePct': 14.902,
    'engineLoad': 30.196,
    'batteryVoltage': 14.0,
    'fuelTrimShortPct': 3.906,
    'fuelTrimLongPct': -3.125,
    'o2B1S1Voltage': 0.45,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 45,
    'mapKpa': 36,
    'timingAdvanceDeg': 10,
  }),
  dtcs: ['~P0507'],
  obdVin: _mgVin,
  plateVin: _mgVin,
  make: 'MG',
  year: '2021',
  country: 'China',
  diesel: false,
  milOn: false,
  dtcCount: 0,
  monitors: _monitors(
    ready: ['Misfire', 'Fuel System', 'Components'],
    notReady: ['Catalyst', 'Evap System', 'O2 Sensor', 'O2 Sensor Heater'],
  ),
  freeze: const {},
);

// 7. Geely Coolray 2021, 1.5TD 3-cyl (Volvo-derived), Chinese-built for GCC.
//    CAN 11/500. "Slow" ECU behind a gateway: ~140 ms per answer (J1979
//    allows P2CAN 50 ms; still inside the ELM's ~200 ms window) and ELM NO
//    DATA after ~205 ms. Latency figures are UNCERTAIN (not published).
final _geelyVin = _vin('L6T7944Z?MN012345');
final _geely = _Vehicle(
  name: 'Geely Coolray 2021 (1.5TD)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 140),
    noDataLatency: const Duration(milliseconds: 205),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 00',
          0x03: '02 00',
          0x04: '59', // 34.9 %
          0x05: '84', // 92 °C
          0x06: '80',
          0x07: '81', // +0.8 %
          0x0B: '8C', // 140 kPa boost
          0x0C: '17 70', // 1500 rpm
          0x0D: '50', // 80 km/h
          0x0E: '8A', // +5°
          0x0F: '5A', // 50 °C
          0x10: '07 D0',
          0x11: '40', // 25.1 %
          0x13: '03',
          0x15: '8C FF',
          0x1C: '06',
          0x1F: '03 84',
          0x21: '00 00',
          0x2F: 'BF', // 74.9 %
          0x30: '06',
          0x31: '02 BC',
          0x33: '64',
          0x34: '7F 00 80 00',
          0x42: '37 78',
          0x44: '80 00',
          0x46: '50',
          0x49: '40',
          0x4C: '40',
          0x5C: '7D', // 85 °C (UNCERTAIN)
        },
        other: {
          '03': '43 02 02 99 C1 01', // P0299, U0101
          '07': '47 00',
          '0902': _canVinReply(_geelyVin),
          '020C00': '42 0C 00 2E E0',
          '020D00': '42 0D 00 64',
          '020500': '42 05 00 87',
          '020400': '42 04 00 E6',
          '020F00': '42 0F 00 5F',
          '021100': '42 11 00 B3',
          '020600': '42 06 00 7A',
          '020B00': '42 0B 00 78',
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'lambdaB1S1': 0.99219,
    'acceleratorPedalPct': 25.098,
    'rpm': 1500,
    'speedKmh': 80,
    'coolantTempC': 92,
    'throttlePct': 25.098,
    'fuelLevelPct': 74.902,
    'engineLoad': 34.902,
    'batteryVoltage': 14.2,
    'oilTempC': 85,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 0.78125,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 140,
    'timingAdvanceDeg': 5,
  }),
  dtcs: ['P0299', 'U0101'],
  obdVin: _geelyVin,
  plateVin: _geelyVin,
  make: 'Geely',
  year: '2021',
  country: 'China',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
      'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT',
    ],
  ),
  freeze: {
    'RPM': '3000 rpm',
    'Speed': '100 km/h',
    'Coolant': '95°C',
    'Engine Load': '90.2%',
    'Air Temp': '55°C',
    'Throttle': '70.2%',
    'Fuel Trim': '-4.7%',
    'MAP': '120 kPa',
  },
);

// 8. Haval H6 2021 (3rd gen), 1.5T, Chinese-built for GCC. CAN 11/500.
//    No stored codes. UNCERTAIN: several Gulf-market Chinese units are
//    reported not to answer mode 09 PID 02 → 0902 NO DATA modelled.
final _havalVin = _vin('LGWEF6A5?MH012345');
final _haval = _Vehicle(
  name: 'Haval H6 2021 (1.5T)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '00 07 E5 00',
          0x03: '02 00',
          0x04: '40', // 25.1 %
          0x05: '87', // 95 °C
          0x06: '80',
          0x07: '80',
          0x0B: '26', // 38 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '5A', // 50 °C
          0x11: '1A',
          0x13: '03',
          0x15: '8C FF',
          0x1C: '06',
          0x1F: '00 3C',
          0x21: '00 00',
          0x2F: '80', // 50.2 %
          0x30: '10',
          0x31: '03 E8',
          0x33: '64',
          0x34: '80 00 80 00',
          0x42: '37 78',
          0x44: '80 00',
          0x46: '50',
          0x49: '1A',
          0x4C: '1A',
        },
        other: {'03': '43 00', '07': '47 00'},
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 10.196,
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 95,
    'throttlePct': 10.196,
    'fuelLevelPct': 50.196,
    'engineLoad': 25.098,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 0,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 38,
    'timingAdvanceDeg': 6,
  }),
  dtcs: const [],
  obdVin: null,
  plateVin: _havalVin,
  make: 'Great Wall (Haval)',
  year: '2021',
  country: 'China',
  diesel: false,
  milOn: false,
  dtcCount: 0,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
      'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT',
    ],
  ),
  freeze: const {},
);

final _vehicles = [
  _elantra,
  _tucson,
  _sportage,
  _h1,
  _changan,
  _mg,
  _geely,
  _haval,
];

// ── Test helpers ──────────────────────────────────────────────────────────────

/// The 18 live PIDs in the order ProductionOBDAdapter._poll requests them.
const _pollOrder = [
  '010C', '010D', '0105', '0111', '012F', '0104', '0142', '015C', '0106', //
  '0107', '0108', '0109', '0114', '0115', '0118', '010F', '010B', '010E',
];

int _pidOf(String cmd) => int.parse(cmd.substring(2), radix: 16);

/// Mode 01 PIDs [car]'s 0100 / 0120 / 0140 bitmaps advertise, ORed over every
/// ECU line, following the J1979 chain (a range only exists when the previous
/// bitmap's last bit says so).
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

/// Live requests poll [poll] must send for the advertised [adv] PIDs (or
/// [regular] when given — e.g. a range the adapter falls back to polling):
/// the regular PIDs in poll order, ATRV in the 0142 slot when 0142 isn't
/// among them (the sim answers '?', so only on the first two polls), then
/// the extras: 0124 (else 0134) only without a narrow-band 0114, 0123, 0149.
List<String> _expectedPolled(
  Set<int> adv, {
  Iterable<String>? regular,
  int poll = 1,
}) {
  final reg = regular ?? _pollOrder.where((p) => adv.contains(_pidOf(p)));
  return [
    for (final p in _pollOrder)
      if (p == '0142' && !reg.contains(p)) ...[
        if (poll <= 2) 'ATRV',
      ] else if (reg.contains(p))
        p,
    if (!adv.contains(0x14) && adv.contains(0x24)) '0124',
    if (!adv.contains(0x14) && !adv.contains(0x24) && adv.contains(0x34))
      '0134',
    if (adv.contains(0x23)) '0123',
    if (adv.contains(0x49)) '0149',
  ];
}

/// Bitmap requests the first poll must make for [adv].
List<String> _expectedBitmapReqs(Set<int> adv) => [
  if (adv.contains(0x20)) '0120',
  if (adv.contains(0x40)) '0140',
];

bool _isBitmapReq(String c) => c == '0120' || c == '0140' || c == '0160';

class _PollResult {
  const _PollResult(
    this.frames,
    this.cycle,
    this.period,
    this.firstCycle,
    this.secondCycle,
  );

  final List<OBDLiveData> frames;

  /// How long the first poll took, from its 3 s timer tick.
  final Duration cycle;

  /// Frame-to-frame refresh period.
  final Duration period;

  /// Commands the ELM327 received during the first / second poll.
  final List<String> firstCycle;
  final List<String> secondCycle;

  Map<String, double?> get first => _fields(frames[0]);
  Map<String, double?> get second => _fields(frames[1]);

  /// First-cycle commands minus the bitmap requests (0120 / 0140).
  List<String> get polled =>
      firstCycle.where((c) => !_isBitmapReq(c)).toList();
}

/// Starts polling, waits for two frames, stops. [adapter] / [elm] default to
/// the rig's own (overridden when one adapter is moved to another car).
_PollResult _poll(Rig rig, {OBDAdapter? adapter, FakeElm327? elm}) {
  final a = adapter ?? rig.adapter;
  final e = elm ?? rig.elm;
  final frames = <(Duration, OBDLiveData)>[];
  final cuts = <int>[e.commands.length];
  final sub = a.liveDataStream.listen((d) {
    frames.add((rig.async.elapsed, d));
    cuts.add(e.commands.length);
  });
  final start = rig.async.elapsed;
  a.startLiveData();
  while (frames.length < 2 &&
      rig.async.elapsed - start < const Duration(seconds: 120)) {
    rig.async.elapse(const Duration(milliseconds: 10));
  }
  a.stopLiveData();
  sub.cancel();
  if (frames.length < 2) fail('fewer than 2 live frames in 120 s');
  return _PollResult(
    [frames[0].$2, frames[1].$2],
    frames[0].$1 - start - const Duration(seconds: 3),
    frames[1].$1 - frames[0].$1,
    e.commands.sublist(cuts[0], cuts[1]),
    e.commands.sublist(cuts[1], cuts[2]),
  );
}

void _expectLive(Map<String, double?> actual, Map<String, double?> expected,
    {Set<String> except = const {}}) {
  for (final k in _liveKeys) {
    if (except.contains(k)) continue;
    final e = expected[k];
    expect(actual[k], e == null ? isNull : closeTo(e, 0.01), reason: k);
  }
}

/// Expected live values of [v] with some fields overridden.
Map<String, double?> _liveWith(_Vehicle v, Map<String, double?> changes) =>
    {...v.live, ...changes};

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDownAll(() {
    // ignore: avoid_print
    print('\n== Korean/Chinese compatibility measurements ==\n'
        '${_matrix.join('\n')}');
  });

  for (final v in _vehicles) {
    group('${v.name} [${v.protocolName}]', () {
      test('(a) connect establishes protocol ${v.protocol}', () {
        sim(v.build(), (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();
          final dt = rig.async.elapsed - t0;
          _log('${v.name}: connect ${_secs(dt)} s, commands '
              '${rig.elm.commands.join(' ')}');
          expect(rig.adapter.isConnected, isTrue);
          expect(rig.elm.activeProtocol, v.protocol);
          expect(dt, lessThan(v.connectMax));
        }, connect: false);
      });

      // Polled commands are exactly the PIDs the car's bitmaps advertise (plus
      // the 0120 / 0140 bitmap requests the chain calls for), and every
      // supported PID decodes to the right value, unsupported ones to null.
      test('(b) one live poll sends only advertised PIDs and decodes every '
          'supported one, null otherwise', () {
        final car = v.build();
        final adv = _advertised(car);
        sim(car, (rig) {
          final p = _poll(rig);
          final nulls = v.live.values.where((x) => x == null).length;
          _log('${v.name}: poll ${_secs(p.cycle)} s '
              '(${_liveKeys.length - nulls} supported / $nulls unsupported, '
              '${p.polled.length} PIDs sent), '
              'refresh every ${_secs(p.period)} s');
          expect(p.firstCycle.where(_isBitmapReq), _expectedBitmapReqs(adv));
          expect(p.polled, _expectedPolled(adv));
          _expectLive(p.first, v.live);
        });
      });

      test('(c) DTCs: confirmed (mode 03) + pending (mode 07)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(c) clear (mode 04) → no codes, no freeze frame afterwards', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
          expect(rig.elm.commands.last, '04');
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
        });
      });

      test('(d) VIN via 0902 → model year + country', () {
        sim(v.build(), (rig) {
          final vin = rig.drive(rig.adapter.getVin());
          _log('${v.name}: getVin() → $vin');
          expect(vin, v.obdVin);
          if (vin == null) return;
          expect(_checkDigit(vin), vin[8], reason: 'profile VIN check digit');
          final d = VinDecoder.decode(vin, now: _now);
          expect(d['year'], v.year);
          expect(d['country'], v.country);
        });
      });

      test('(d) VinDecoder manufacturer for WMI ${v.plateVin.substring(0, 3)}',
          () {
        final d = VinDecoder.decode(v.plateVin, now: _now);
        _log('${v.name}: VinDecoder(${v.plateVin}) → $d');
        expect(d['manufacturer'], contains(v.make.split(' ').first));
      });

      test('(e) readiness monitors (${v.diesel ? 'diesel' : 'spark'})', () {
        sim(v.build(), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.compressionIgnition, v.diesel);
          expect({for (final m in r.monitors) m.name: m.status}, v.monitors);
        });
      });

      test('(e) readiness MIL + confirmed DTC count', () {
        sim(v.build(), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, v.milOn);
          expect(r.dtcCount, v.dtcCount);
        });
      });

      test('(f) freeze frame (mode 02, frame 00)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getFreezeFrame()), v.freeze);
        });
      });
    });
  }

  // ── Extra per-vehicle scenarios ────────────────────────────────────────────

  group('extra scenarios', () {
    test('Elantra 2008 K-line variant without mode 09 → getVin() null, '
        'nothing else disturbed', () {
      final car = _variant(_elantra.build(), replies: {'0902': null});
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
        expect(rig.drive(rig.adapter.getDtcs()), _elantra.dtcs);
      });
    });

    test('Tucson 2022, engine running: ECM refuses mode 04 (7F 04 22 '
        'conditionsNotCorrect) → clearDtcs() must report failure', () {
      sim(_tucsonCar(clearReply: '7F 04 22\n44'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _tucson.dtcs);
      });
    });

    test('Chery Tiggo 8 2022 window VIN (WMI LVV) → manufacturer Chery', () {
      final vin = _vin('LVVDB21B?ND012345');
      final d = VinDecoder.decode(vin, now: _now);
      expect(d['country'], 'China');
      expect(d['year'], '2022');
      expect(d['manufacturer'], 'Chery');
    });

    test('Chery Tiggo 8 2022 window VIN: country + year decode', () {
      final d = VinDecoder.decode(_vin('LVVDB21B?ND012345'), now: _now);
      expect(d['country'], 'China');
      expect(d['year'], '2022');
    });

    test('Haval H6 window VIN decodes year/country (no OBD VIN available)',
        () {
      final d = VinDecoder.decode(_havalVin, now: _now);
      expect(d['country'], 'China');
      expect(d['year'], '2021');
    });

    // Formerly the MG ZS `(b) live fuelTrimShortPct decoded` BUG test. On the
    // base profile 015C is not advertised, so fix #1 alone avoids the hang;
    // the advertised-and-hanging case is in the regression group below.
    test('MG ZS 2021: live fuelTrimShortPct decoded', () {
      sim(_mg.build(), (rig) {
        final p = _poll(rig);
        expect(p.first['fuelTrimShortPct'], closeTo(3.906, 0.01));
        expect(p.firstCycle, isNot(contains('015C')));
      });
    });

    test('profile sanity: generated 0100 bitmap matches the answered PIDs', () {
      final car = _tucson.build();
      // ECM line first; PIDs 01 03 04 05 06 07 0B 0C 0D 0E 0F 10 11 13 15 1C
      // 1F + next-range bit.
      expect(car.responses['0100']!.split('\n').first, '41 00 BE 3F A8 13');
      expect(car.responses['0100']!.split('\n').last, '41 00 80 08 00 00');
      expect(car.responses.containsKey('0160'), isFalse);
      expect(_elantra.build().responses['0140'], isNull);
      expect(_advertised(_mgCar()).contains(0x5C), isFalse);
      expect(_advertised(_mgCar(advertiseOil: true)).contains(0x5C), isTrue);
    });
  });

  // ── Regression: adversarial checks of the obd_adapter / vin_decoder fixes ──

  group('regression', () {
    // ── #1 PID support bitmaps ──────────────────────────────────────────────

    for (final v in _vehicles) {
      test('poll cycle < 3 s interval and bitmaps read once: ${v.name}', () {
        sim(v.build(), (rig) {
          final p = _poll(rig);
          _log('${v.name}: [regression] first poll ${_secs(p.cycle)} s, '
              'refresh ${_secs(p.period)} s');
          expect(p.cycle, lessThan(const Duration(seconds: 3)));
          expect(p.period, lessThan(const Duration(milliseconds: 3100)));
          // Support is read on the first poll only.
          expect(p.secondCycle.where(_isBitmapReq), isEmpty);
          expect(p.secondCycle, p.polled);
          _expectLive(p.second, v.live);
        });
      });
    }

    test('Elantra K-line: 0100 advertises 0120 but 0120 answers NO DATA → '
        'that range (and 0x40+) falls back to polling, values still right, '
        'cycle < 3 s', () {
      final car = _variant(_elantra.build(), replies: {'0120': null});
      final adv0 = _advertised(_elantra.build()).where((p) => p <= 0x20);
      sim(car, (rig) {
        final p = _poll(rig);
        _log('Elantra 0120 NO DATA: poll ${_secs(p.cycle)} s, sent '
            '${p.polled.join(' ')}');
        expect(p.firstCycle.where(_isBitmapReq), ['0120']); // no 0140
        expect(p.polled, [
          for (final c in _pollOrder)
            if (_pidOf(c) > 0x20 || adv0.contains(_pidOf(c))) c,
        ]);
        expect(p.polled, containsAll(['012F', '0142', '015C']));
        _expectLive(p.first, _elantra.live);
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Elantra K-line: 0120 refused with negative response 7F 01 12 '
        '(ISO 14230 ECU has no 0x21+ range) → range treated as unsupported: '
        'no 0140, no 012F/0142/015C, cycle < 3 s', () {
      final car = _variant(_elantra.build(), replies: {'0120': '7F 01 12'});
      final adv0 = _advertised(_elantra.build()).where((p) => p <= 0x20);
      sim(car, (rig) {
        final p = _poll(rig);
        _log('Elantra 0120 → 7F 01 12: poll ${_secs(p.cycle)} s');
        expect(p.firstCycle.where(_isBitmapReq), ['0120']);
        expect(
          p.polled,
          _expectedPolled(
            const {},
            regular: _pollOrder.where((c) => adv0.contains(_pidOf(c))),
          ),
        );
        expect(p.polled, contains('ATRV')); // no 0142 → adapter voltage
        _expectLive(p.first, _elantra.live);
        _expectLive(p.second, _elantra.live);
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Elantra K-line: one module refuses 0120 (7F 01 12) while the ECM '
        'answers 41 20 → the real bitmap wins, nothing dropped', () {
      final base = _elantra.build();
      final car = _variant(base,
          replies: {'0120': '7F 01 12\n${base.responses['0120']}'});
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.polled, _expectedPolled(_advertised(base)));
        _expectLive(p.first, _elantra.live);
      });
    });

    test('Changan: unparseable 0100 bitmap (stray header bytes "7E8 06") → '
        'per-range fallback polls all 18 PIDs, values still right', () {
      final base = _changan.build();
      final car = _variant(
        base,
        replies: {'0100': '7E8 06 ${base.responses['0100']}'},
      );
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.firstCycle.where(_isBitmapReq), isEmpty);
        // The extras need an explicit bit in a readable bitmap.
        expect(p.polled, _pollOrder);
        _expectLive(
          p.first,
          _liveWith(_changan, {for (final k in _extraKeys) k: null}),
        );
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Haval: bitmap advertises 012F but the ECM answers NO DATA (cluster '
        'owns fuel level) → fuel null, everything else right', () {
      final car = _variant(_haval.build(), replies: {'012F': null});
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.polled, contains('012F'));
        _expectLive(p.first, _liveWith(_haval, {'fuelLevelPct': null}));
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Tucson-like ECM + TCM, TCM line first, different bitmaps: speed '
        'only from the TCM, 0120/0140 only from the ECM → union polled', () {
      final car = _profile(
        protocol: '6',
        ecuLatency: const Duration(milliseconds: 80),
        ecus: [
          const _Ecu(mode01: {0x01: '00 04 00 00', 0x0D: '3C'}),
          _Ecu(
            mode01: {..._tucsonEcmMode01}..remove(0x0D),
            other: _tucsonEcmOther,
          ),
        ],
      );
      // The first (TCM) line advertises only PIDs 01 + 0D: NOT the 0x21+
      // range (last bit 0), so 0120 / 0140 must come from the ECM line.
      expect(car.responses['0100']!.split('\n').first, '41 00 80 08 00 00');
      expect(car.responses['010D'], '41 0D 3C'); // TCM only
      final adv = _advertised(car);
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.firstCycle.where(_isBitmapReq), ['0120', '0140']);
        expect(p.polled, _expectedPolled(adv));
        expect(p.polled, containsAll(['010D', '0142']));
        _expectLive(p.first, _tucson.live);
      });
    });

    test('reconnect Tucson → Geely on the same adapter re-reads support: '
        'Geely-only PIDs (012F, 015C) are polled and decoded', () {
      sim(_tucson.build(), (rig) {
        final p1 = _poll(rig);
        expect(p1.polled, isNot(contains('012F')));
        expect(p1.polled, isNot(contains('015C')));
        rig.drive(rig.adapter.disconnect());

        final geely = _geely.build();
        final other = Rig.fff0(rig.async, FakeElm327(geely));
        rig.drive(rig.adapter.connect(other.device));
        final p2 = _poll(rig, elm: other.elm);
        expect(p2.firstCycle.where(_isBitmapReq), ['0120', '0140']);
        expect(p2.polled, _expectedPolled(_advertised(geely)));
        _expectLive(p2.first, _geely.live);
      });
    });

    test('reconnect Geely → Tucson: Tucson is not polled for Geely-only '
        'PIDs', () {
      sim(_geely.build(), (rig) {
        _poll(rig);
        rig.drive(rig.adapter.disconnect());
        final tucson = _tucson.build();
        final other = Rig.fff0(rig.async, FakeElm327(tucson));
        rig.drive(rig.adapter.connect(other.device));
        final p2 = _poll(rig, elm: other.elm);
        expect(p2.polled, _expectedPolled(_advertised(tucson)));
      });
    });

    test('reconnect Geely → Tucson: Tucson frame shows no Geely values for '
        'PIDs Tucson lacks (fuel level, oil temp)', () {
      sim(_geely.build(), (rig) {
        _poll(rig);
        rig.drive(rig.adapter.disconnect());
        final other = Rig.fff0(rig.async, FakeElm327(_tucson.build()));
        rig.drive(rig.adapter.connect(other.device));
        final p2 = _poll(rig, elm: other.elm);
        _expectLive(p2.first, _tucson.live);
      });
    });

    // ── #9 hung command recovery (clone that never prompts) ────────────────

    test('MG ZS variant: 0140 advertises 015C and 015C hangs (no prompt) → '
        'next PID 0106 (STFT) still decoded, every cycle', () {
      final car = _mgCar(advertiseOil: true);
      expect(_advertised(car).contains(0x5C), isTrue);
      sim(car, (rig) {
        final p = _poll(rig);
        _log('MG ZS 015C advertised + hanging: first poll '
            '${_secs(p.cycle)} s, refresh ${_secs(p.period)} s, sent '
            '${p.firstCycle.join(' ')}');
        expect(p.polled, contains('015C'));
        expect(p.polled, contains('')); // bare-CR resync after the hang
        _expectLive(p.first, _mg.live); // oil null, STFT 3.906
        _expectLive(p.second, _mg.live);
        expect(p.first['fuelTrimShortPct'], closeTo(3.906, 0.01));
        // The adapter is usable afterwards.
        expect(rig.drive(rig.adapter.getDtcs()), _mg.dtcs);
        expect(rig.drive(rig.adapter.getVin()), _mgVin);
      });
    });

    test('MG ZS variant: 015C hangs only once (answers when repeated) → '
        'STFT decoded on the first poll, oil temp on the second', () {
      final car = _mgCar(
        advertiseOil: true,
        silent: const {},
        hangsOnce: const {'015C'},
      );
      sim(car, (rig) {
        final p = _poll(rig);
        _expectLive(p.first, _mg.live);
        _expectLive(p.second, _liveWith(_mg, {'oilTempC': 85}));
      });
    });

    test('Haval clone: advertised 012F hangs → 0104 (engine load) right '
        'after it is still decoded, later commands unaffected', () {
      final car = _variant(_haval.build(), silent: {'012F'});
      sim(car, (rig) {
        final p = _poll(rig);
        _log('Haval 012F hanging: first poll ${_secs(p.cycle)} s');
        _expectLive(p.first, _liveWith(_haval, {'fuelLevelPct': null}));
        _expectLive(p.second, _liveWith(_haval, {'fuelLevelPct': null}));
        expect(rig.drive(rig.adapter.getReadinessMonitors()).monitors.length,
            11);
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
      });
    });

    // ── #2 clearDtcs() ──────────────────────────────────────────────────────

    test('Tucson: TCM 44 first, then ECM 7F 04 22 → false, codes kept', () {
      sim(_tucsonCar(clearReply: '44\n7F 04 22'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _tucson.dtcs);
      });
    });

    test('Tucson: ECM 7F 04 78 (responsePending) then 44, TCM 44 → true, '
        'codes gone', () {
      sim(_tucsonCar(clearReply: '7F 04 78\n44\n44'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
      });
    });

    test('Tucson: only 7F 04 78, final answer never comes → false', () {
      sim(_tucsonCar(clearReply: '7F 04 78'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
      });
    });

    test('Tucson: mode 04 NO DATA → false', () {
      sim(_tucsonCar(clearReply: 'NO DATA'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _tucson.dtcs);
      });
    });

    // ── #3 readiness merged over ECUs ───────────────────────────────────────

    test('Tucson: gearbox 0101 line first → MIL/count/monitors from the '
        'merge, engine type from the ECM', () {
      final car = _variant(_tucson.build(),
          replies: {'0101': '41 01 00 04 00 00\n41 01 82 07 E5 01'});
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 2);
        expect(r.compressionIgnition, isFalse);
        expect({for (final m in r.monitors) m.name: m.status},
            _tucson.monitors);
      });
    });

    test('Tucson: only the gearbox answers 0101 (ECM reply cut off by '
        'adaptive timing) → components only, MIL off, 0 codes', () {
      final car =
          _variant(_tucson.build(), replies: {'0101': '41 01 00 04 00 00'});
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isFalse);
        expect(r.dtcCount, 0);
        expect(r.compressionIgnition, isFalse);
        expect({for (final m in r.monitors) m.name: m.status},
            _monitors(ready: ['Components']));
      });
    });

    test('Sportage: TCM (MIL request, 1 code) answers first → MIL on, '
        'count 3 + 1, ECM monitors', () {
      final car = _variant(_sportage.build(),
          replies: {'0101': '41 01 81 04 00 00\n41 01 83 07 65 04'});
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 4);
        expect({for (final m in r.monitors) m.name: m.status},
            _sportage.monitors);
      });
    });

    test('H1 diesel + spark-looking TCM answering first → still diesel, '
        'diesel monitor names, counts summed', () {
      final car = _variant(_h1.build(),
          replies: {'0101': '41 01 81 04 00 00\n41 01 82 0F A9 80'});
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isTrue);
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 3);
        expect({for (final m in r.monitors) m.name: m.status}, _h1.monitors);
      });
    });

    // ── #4 headers-off ISO-TP reassembly ────────────────────────────────────

    test('Sportage 03: TCM single frame BETWEEN the ECM\'s ISO-TP frames → '
        'all 4 codes', () {
      final car = _variant(_sportage.build(), replies: {
        '03': '008\n'
            '0: 43 03 00 11 01 28\n'
            '43 01 07 41\n'
            '1: 04 56 AA AA AA AA AA',
      });
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getDtcs()),
            unorderedEquals(['P0011', 'P0128', 'P0456', 'P0741']));
      });
    });

    test('Sportage 03: ECM and TCM both multi-frame, frames interleaved → '
        'all 6 codes', () {
      final car = _variant(_sportage.build(), replies: {
        '03': '008\n'
            '0: 43 03 00 11 01 28\n'
            '008\n'
            '0: 43 03 07 41 07 42\n'
            '1: 04 56 AA AA AA AA AA\n'
            '1: 07 43 AA AA AA AA AA',
      });
      sim(car, (rig) {
        expect(
          rig.drive(rig.adapter.getDtcs()),
          unorderedEquals(
              ['P0011', 'P0128', 'P0456', 'P0741', 'P0742', 'P0743']),
        );
      });
    });

    // ── #5 VIN reassembly + validation ──────────────────────────────────────

    test('Sportage 0902: ECM and TCM VIN frames interleaved → VIN', () {
      final l = _canVinReply(_sportageVin).split('\n');
      final car = _variant(_sportage.build(), replies: {
        '0902': [l[0], l[1], l[0], l[1], l[2], l[2], l[3], l[3]].join('\n'),
      });
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), _sportageVin);
      });
    });

    test('Sportage 0902: TCM answers 17 x 00 (not coded), ECM the VIN → '
        'ECM VIN', () {
      final car = _variant(_sportage.build(), replies: {
        '0902': '${_canVinBytes(List.filled(17, 0))}\n'
            '${_canVinReply(_sportageVin)}',
      });
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), _sportageVin);
      });
    });

    test('Haval: 0902 answers 17 x FF → null', () {
      final car = _variant(_haval.build(),
          replies: {'0902': _canVinBytes(List.filled(17, 0xFF))});
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), isNull));
    });

    test('Haval: 0902 VIN with an O (not in the VIN alphabet) → null', () {
      final car = _variant(_haval.build(), replies: {
        '0902': _canVinReply(_havalVin.replaceRange(11, 12, 'O')),
      });
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), isNull));
    });

    test('Haval: 0902 one frame short (ISO-TP cut off) → null', () {
      final l = _canVinReply(_havalVin).split('\n');
      final car = _variant(_haval.build(),
          replies: {'0902': [l[0], l[1], l[2]].join('\n')});
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), isNull));
    });

    test('Haval: replacement ECU not VIN-coded answers "00000000000000000" '
        '(ASCII) → null, not a fake VIN', () {
      final car = _variant(_haval.build(),
          replies: {'0902': _canVinReply('0' * 17)});
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), isNull));
    });

    test('Haval: ECU filler VIN of one repeated letter ("AAAA…") → null', () {
      final car = _variant(_haval.build(),
          replies: {'0902': _canVinReply('A' * 17)});
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), isNull));
    });

    // ── #6-8 VinDecoder ─────────────────────────────────────────────────────

    const vinTable = [
      ('KMHDT41C?8U512345', 'Hyundai', 'South Korea', '2008'),
      ('KM8J3CA4?NU187654', 'Hyundai', 'South Korea', '2022'),
      ('KMJWA37K?GU812345', 'Hyundai', 'South Korea', '2016'),
      ('KNAFE121?55123456', 'Kia', 'South Korea', '2005'),
      ('KNDPM3AC?K7523456', 'Kia', 'South Korea', '2019'),
      ('KNMA4C2B?TP012345', 'Renault Samsung', 'South Korea', '2026'),
      ('LS5A3DKR?NA012345', 'Changan', 'China', '2022'),
      ('LS5A3DKR?VA012345', 'Changan', 'China', '2027'), // MY ahead
      ('LSJA24U6?MN012345', 'MG', 'China', '2021'),
      ('L6T7944Z?MN012345', 'Geely', 'China', '2021'),
      ('LVVDB21B?ND012345', 'Chery', 'China', '2022'),
      // LGW is GWM's umbrella WMI (Haval, Tank, Wey, Ora, Poer): the WMI
      // alone can't tell a Haval from a GWM pickup, so the decoder now says
      // 'Great Wall Motor (GWM)' for both (formerly 'Haval' here).
      ('LGWEF6A5?MH012345', 'Great Wall Motor (GWM)', 'China', '2021'),
      ('LGWEF6A5?PH012345', 'Great Wall', 'China', '2023'),
    ];
    for (final (tpl, maker, country, year) in vinTable) {
      test('VinDecoder $tpl → $maker / $country / $year', () {
        final d = VinDecoder.decode(_vin(tpl), now: _now);
        expect(d['manufacturer'], contains(maker));
        expect(d['country'], country);
        expect(d['year'], year);
      });
    }

    test('VinDecoder: Korean brands built abroad get the plant country', () {
      String c(String t) => VinDecoder.decode(_vin(t), now: _now)['country']!;
      expect(c('MALC381C?LM012345'), 'India'); // Hyundai India
      expect(c('TMAJ3811?LJ012345'), 'Czech Republic'); // Hyundai Czech
      expect(c('NLHA851A?LZ012345'), 'Turkey'); // Hyundai Assan
      expect(c('U5YPG814?LL012345'), 'Slovakia'); // Kia Slovakia
      expect(c('LBEHDAFB?LY012345'), 'China'); // Beijing Hyundai
      final us = VinDecoder.decode(_vin('5NPE34AF?LH012345'), now: _now);
      expect(us['country'], 'United States');
      expect(us['year'], '2020'); // 49 CFR 565: pos 7 alpha → 2010 cycle
    });

    test('VinDecoder: Hyundai/Kia/Chinese WMIs common in the GCC → maker', () {
      String m(String t) =>
          VinDecoder.decode(_vin(t), now: _now)['manufacturer']!;
      expect(m('MALC381C?LM012345'), contains('Hyundai')); // India
      expect(m('5NPE34AF?LH012345'), contains('Hyundai')); // Alabama
      expect(m('TMAJ3811?LJ012345'), contains('Hyundai')); // Czech
      expect(m('NLHA851A?LZ012345'), contains('Hyundai')); // Turkey
      expect(m('U5YPG814?LL012345'), contains('Kia')); // Slovakia
      expect(m('LBEHDAFB?LY012345'), contains('Hyundai')); // Beijing Hyundai
      expect(m('LB37624S?NX012345'), contains('Geely')); // Geely Automobile
      expect(m('LMGFE1G8?N1012345'), contains('GAC')); // GAC Trumpchi
    });
  });

  // ── Double-check: adversarial probes of the vin_decoder / obd_adapter /
  //    dtc_repository fixes for Korean and Chinese brands ──────────────────

  group('double-check', () {
    const connectivity =
        MethodChannel('dev.fluttercommunity.plus/connectivity');
    // The rest of this file needs no binding; only DtcRepository (rootBundle,
    // connectivity / shared_preferences channels) does, so it is set up here.
    TestDefaultBinaryMessenger messenger() {
      TestWidgetsFlutterBinding.ensureInitialized();
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    }

    setUp(() {
      // DtcRepository offline, empty storage.
      messenger().setMockMethodCallHandler(connectivity,
          (call) async => call.method == 'check' ? ['none'] : null);
      SharedPreferences.setMockInitialValues({});
      DtcRepository.resetCaches();
      DtcRepository.rapidApiKeyOverride = '';
    });

    tearDown(() {
      messenger().setMockMethodCallHandler(connectivity, null);
      DtcRepository.rapidApiKeyOverride = null;
    });

    // New Chinese (row L / H) WMIs → expected maker substring.
    const chinaWmis = [
      ('LS4', 'Changan'), ('LS6', 'Changan'), ('LSC', 'Changan'),
      ('LJX', 'Ford'), ('LXW', 'Ford'), ('LEF', 'JMC'), ('LVR', 'Mazda'),
      ('LVT', 'Chery'), ('LVU', 'Chery'), ('LNN', 'Chery'),
      ('HJR', 'Jetour'), ('LVM', 'Chery'), ('L2C', 'Chery'),
      ('LNB', 'BAIC'), ('LJ1', 'JAC'), ('LFP', 'FAW'), ('LFB', 'FAW'),
      ('LDP', 'Dongfeng'), ('LGJ', 'Dongfeng'), ('LGG', 'Dongfeng'),
      ('LMX', 'Dongfeng'), ('LC0', 'BYD'), ('LGX', 'BYD'), ('LPE', 'BYD'),
      ('LNA', 'GAC'), ('L10', 'Geely'), ('LGW', 'Great Wall'),
      ('LS5', 'Changan'), ('LSJ', 'MG'), ('L6T', 'Geely'), ('LB3', 'Geely'),
      ('LVV', 'Chery'), ('LMG', 'GAC'),
    ];
    const years = {'E': '2014', 'L': '2020', 'N': '2022', 'R': '2024', //
      'T': '2026', 'V': '2027'};

    test('every Chinese WMI (rows L and H) → maker + China + model year',
        () {
      for (final (wmi, maker) in chinaWmis) {
        for (final y in years.entries) {
          final vin = _vin('${wmi}AB3D4?${y.key}A012345');
          final d = VinDecoder.decode(vin, now: _now);
          expect(d['manufacturer'], contains(maker), reason: vin);
          expect(d['country'], 'China', reason: vin);
          expect(d['year'], y.value, reason: vin);
        }
      }
    });

    test('Chinese brands built outside China: maker + plant country, year '
        'not guessed (MNU Thailand, XZG Russia, PL1 Malaysia)', () {
      for (final (wmi, maker, country) in const [
        ('MNU', 'Great Wall', 'Thailand'),
        ('XZG', 'Haval', 'Russia'),
        ('PL1', 'Proton', 'Malaysia'),
      ]) {
        final d = VinDecoder.decode(_vin('${wmi}AB3D4?NA012345'), now: _now);
        expect(d['manufacturer'], contains(maker), reason: wmi);
        expect(d['country'], country, reason: wmi);
        expect(d['year'], VinDecoder.unknown, reason: wmi);
      }
    });

    // getVin() on the Tucson (CAN), 0902 replaced by [vin].
    String? obdVin(String vin) {
      String? got;
      sim(_variant(_tucsonCar(), replies: {'0902': _canVinReply(vin)}),
          (rig) => got = rig.drive(rig.adapter.getVin()));
      return got;
    }

    String garble(String c) {
      int val(String x) => int.tryParse(x) ?? _translit[x]!;
      return '0123456789ABCDEFGHJKLMNPRSTUVWXYZ'
          .split('')
          .firstWhere((x) => x != c && val(x) != val(c));
    }

    test('Chinese VINs: intact → accepted; one serial digit garbled (check '
        'digit wrong) → null, for every row-L / row-H WMI', () {
      for (final (wmi, _) in chinaWmis) {
        final ok = _vin('${wmi}AB3D4?NA012345');
        expect(obdVin(ok), ok, reason: ok);
        final bad = ok.replaceRange(14, 15, garble(ok[14]));
        expect(_checkDigit(bad) == bad[8], isFalse, reason: bad);
        expect(obdVin(bad), isNull, reason: bad);
      }
    });

    test('profile VINs (Changan / MG / Geely / Haval) garbled at any of '
        'positions 2–17 → null', () {
      for (final good in [_changanVin, _mgVin, _geelyVin, _havalVin]) {
        for (var i = 1; i < 17; i++) {
          final bad = good.replaceRange(i, i + 1, garble(good[i]));
          expect(obdVin(bad), isNull, reason: 'position ${i + 1}: $bad');
        }
      }
    });

    test('Jetour HJR (row H) VIN: wrong check digit → null, right one → '
        'accepted', () {
      final ok = _vin('HJRPBGJB?PB012345');
      expect(obdVin(ok), ok);
      expect(obdVin(ok.replaceRange(8, 9, garble(ok[8]))), isNull);
    });

    test('Korean VINs: a letter at position 9 (domestic D / P / R) and a '
        'non-computing digit are still accepted', () {
      for (final good in [_tucsonVin, _sportageVin, _elantraVin, _h1Vin,
        _vin('KNMA4C2B?TP012345')]) {
        for (final c in ['D', 'P', 'R']) {
          final v = good.replaceRange(8, 9, c);
          expect(obdVin(v), v, reason: v);
        }
        final odd = good.replaceRange(8, 9, garble(good[8]));
        expect(_checkDigit(odd) == odd[8], isFalse);
        expect(obdVin(odd), odd, reason: odd);
      }
    });

    test('Korean VINs still rejected for alphabet / filler errors (I, O, Q, '
        '"KKKK…")', () {
      for (final c in ['I', 'O', 'Q']) {
        expect(obdVin(_tucsonVin.replaceRange(12, 13, c)), isNull, reason: c);
      }
      expect(obdVin('K' * 17), isNull);
    });

    test('Hyundai built in Alabama (5NP, North America): garbled → null; '
        'built in India (MAL, check digit optional) → accepted', () {
      final us = _vin('5NPE34AF?LH012345');
      expect(obdVin(us), us);
      expect(obdVin(us.replaceRange(13, 14, garble(us[13]))), isNull);
      final india = _vin('MALC381C?LM012345');
      final oddIndia = india.replaceRange(13, 14, garble(india[13]));
      expect(obdVin(oddIndia), oddIndia);
    });

    // Manufacturer-range codes Hyundai / Kia / MG / Haval / Changan report;
    // many collide with Ford/GM entries in the bundled DB.
    const mfrCodes = [
      'P1326', 'P1529', 'P1693', 'P1167', 'C1611', 'U1110', 'B1602', //
      'P1115', 'P1604', 'P1386', 'B2501', 'P1450', 'U2100', 'P3001',
    ];
    const foreign = ['J1850', 'SCP', 'PATS', 'Ford', 'GM', 'SCAIR', //
      'فورد', 'جنرال'];

    Future<(Map<String, dynamic>, Map<String, dynamic>)> db() async => (
      jsonDecode(await rootBundle.loadString('assets/dtcmapping.json'))
          as Map<String, dynamic>,
      jsonDecode(await rootBundle.loadString('assets/dtcmapping_ar.json'))
          as Map<String, dynamic>,
    );

    test('Korean / Chinese manufacturer codes, EN + AR: the localized label, '
        'never another brand\'s DB text', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      final arabic = RegExp(r'[؀-ۿ]');
      for (final code in mfrCodes) {
        final e = (await repo.getDtcDescription(code))!;
        final a = (await repo.getDtcDescription(code, languageCode: 'ar'))!;
        expect(e, DtcRepository.manufacturerLabel(code), reason: code);
        expect(a, DtcRepository.manufacturerLabel(code, languageCode: 'ar'),
            reason: code);
        expect(a, matches(arabic));
        for (final f in foreign) {
          expect(e, isNot(contains(f)), reason: '$code EN → $e');
          expect(a, isNot(contains(f)), reason: '$code AR → $a');
        }
        for (final t in [en[code], ar[code]].whereType<String>()) {
          expect(e, isNot(contains(t)), reason: code);
          expect(a, isNot(contains(t)), reason: code);
        }
      }
    });

    test('SAE codes from the profiles keep their real DB description (EN + '
        'Arabic), never the manufacturer label', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      final codes = {
        for (final v in _vehicles)
          for (final c in v.dtcs) c.replaceFirst('~', ''),
      };
      for (final code in codes) {
        expect(await repo.getDtcDescription(code), en[code], reason: code);
        final a = await repo.getDtcDescription(code, languageCode: 'ar');
        expect(a, ar[code], reason: code);
        expect(a, matches(RegExp(r'[؀-ۿ]')), reason: code);
      }
    });

    test('Kia Niro / Ioniq hybrid codes: bundled P0Axx real text (EN + AR); '
        'P0D27 → hybrid label', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      for (final code in ['P0A0F', 'P0AA6', 'P0A7A']) {
        expect(await repo.getDtcDescription(code), en[code]);
        expect(await repo.getDtcDescription(code, languageCode: 'ar'),
            ar[code]);
      }
      expect(await repo.getDtcDescription('P0D27'),
          startsWith('Hybrid/EV propulsion system code (P0D27)'));
      expect(await repo.getDtcDescription('P0D27', languageCode: 'ar'),
          startsWith('رمز نظام الدفع الهجين/الكهربائي (P0D27)'));
    });

    test('ignition-off Elantra K-line (CAN ERROR, BUS INIT: ...ERROR) → '
        'ecuNotResponding, no ATRV', () {
      sim(const SimCar(
        wrongProtocolReply: 'CAN ERROR',
        ignitionOffReply: 'BUS INIT: ...ERROR',
        adapterVoltage: '12.3V',
      ), (rig) {
        expect(
          () => rig.connect(),
          throwsA(isA<OBDConnectException>().having(
              (e) => e.reason, 'reason', OBDFailureReason.ecuNotResponding)),
        );
        expect(rig.elm.commands, isNot(contains('ATRV')));
      }, connect: false);
    });

    test('every Korean / Chinese profile: successful connect sends no ATRV; '
        'poll < 3 s', () {
      for (final v in _vehicles) {
        sim(v.build(), (rig) {
          rig.connect();
          expect(rig.elm.commands, isNot(contains('ATRV')), reason: v.name);
          final p = _poll(rig);
          expect(p.cycle, lessThan(const Duration(seconds: 3)),
              reason: v.name);
        }, connect: false);
      }
    });
  });
}
