// Compatibility matrix, Chinese cars group A: the Changan family and the
// China-built Fords (Changan Ford, JMC Ford) sold in the Gulf, driven through
// the ELM327 simulator.
//
// Same house style as korean_chinese_cars_test.dart (which already covers the
// Changan CS75 Plus 2022, so it is not repeated here): each profile models
// what the car's ECU(s) answer — ELM protocol number, auto-search time, PID
// support bitmaps generated from the PIDs that really answer, NO DATA latency,
// extra responders on CAN, protocol-correct DTC / VIN / freeze-frame replies
// and engine-appropriate readiness bytes.
//
// Grounding: SAE J1979 / ISO 15765-4 / ISO 14230-4 formats and ELM327
// datasheet behaviour. China 5/6 (GB 18352.5 / GB 18352.6) OBD on modern cars
// is ISO 15765-4 CAN 11-bit 500k; China 3/4-era cars may use the K-line.
// WMIs per the ISO 3780-based WMI list on Wikibooks ("Vehicle Identification
// Numbers (VIN codes)/World Manufacturer Identifier (WMI)"): LS4 Changan
// MPV/SUV, LS5 Changan car, LS6 Changan/Deepal/Avatr, LSC Changan light truck,
// LVS Changan Ford, LJX JMC Ford. OEM per-model PID sets, latencies, VDS
// characters and manufacturer DTC meanings are NOT published; anything
// assumed is marked UNVERIFIED.
//
// Tests asserting the CORRECT behaviour that the app still gets wrong would be
// marked `skip: 'REGRESSION: …'`. None remain: the former `BUG:` skips (WMIs
// LS4 / LS6 / LSC / LJX / LXW / LVR, GB 16735 check digit, manufacturer-range
// DTC text, offline SAE fallback) were fixed in vin_decoder.dart,
// obd_adapter.dart and dtc_repository.dart and now always run; the
// "double-check" group at the end attacks those fixes.

import 'dart:convert';

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

/// ISO 3779 check digit (position 9) — mandatory in China under GB 16735.
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

/// 09 02 on ISO 15765-4, headers off: byte count 0x014 + three frames.
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

  /// Mode 01 PID → data bytes. Support bitmaps are generated from the keys.
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

/// [SimCar] built from several ECUs, with NO DATA latency and a mode 04 that
/// really clears (or, when refused, keeps) the stored codes.
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
    super.adapterVoltage,
  });

  final Duration noDataLatency;
  final String emptyDtcReply;
  final String clearReply;
  bool cleared = false;

  @override
  String answer(String cmd) {
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
  required String protocol,
  required List<_Ecu> ecus,
  bool kLine = false,
  Duration ecuLatency = const Duration(milliseconds: 50),
  Duration? noDataLatency,
  Duration autoSearchTime = const Duration(seconds: 7),
  Map<String, String> overrides = const {},
  String? adapterVoltage,
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
    responses['0100'] = 'BUS INIT: ...OK\n${responses['0100']}';
  }
  final emptyLine = kLine ? '43 00 00 00 00 00 00' : '43 00';
  return _ProfileCar(
    protocol: protocol,
    responses: responses,
    ecuLatency: ecuLatency,
    noDataLatency: noDataLatency ??
        (kLine
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 150)),
    autoSearchTime: autoSearchTime,
    wrongProtocolReply: kLine ? 'CAN ERROR' : 'NO DATA',
    emptyDtcReply: List.filled(ecus.length, emptyLine).join('\n'),
    clearReply: List.filled(ecus.length, '44').join('\n'),
    adapterVoltage: adapterVoltage,
  );
}

/// [base] with some replies replaced (null = removed → NO DATA) and/or a
/// different mode 04 answer. Bitmaps are NOT regenerated.
_ProfileCar _variant(
  _ProfileCar base, {
  Map<String, String?> replies = const {},
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
    adapterVoltage: base.adapterVoltage,
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

  /// getDtcs() result: confirmed first, pending prefixed with '~'.
  final List<String> dtcs;

  /// What 0902 should return (null = car doesn't support mode 09 PID 02).
  final String? obdVin;

  /// VIN stamped on the car (windshield / door plate).
  final String plateVin;
  final String make;
  final String year;
  final bool diesel;
  final bool milOn;
  final int dtcCount;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freeze;
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

// 1. Changan CS35 2014 (1st gen), 1.6 JL478QEE MPI, GCC spec.
//    UNVERIFIED: China 4-era Changan ECUs (Delphi MT20U2 / UAES ME7-family)
//    are commonly reported on ISO 14230-4 KWP fast init (ELM protocol 5) —
//    modelled here; some may already be CAN. Reduced PID set, nothing above
//    0x21. UNVERIFIED quirk: 0100 sets the "0x21–0x40 range exists" bit (for
//    0x21) but the ECU refuses 0120 with 7F 01 12. No 0142 → ATRV. No mode 09
//    → getVin() null.
final _cs35Vin = _vin('LS4ASB2E?EA012345'); // VDS UNVERIFIED
final _cs35 = _Vehicle(
  name: 'Changan CS35 2014 (1.6 MPI, K-line)',
  protocol: '5',
  protocolName: 'ISO 14230-4 KWP fast init',
  build: () => _profile(
    protocol: '5',
    kLine: true,
    ecuLatency: const Duration(milliseconds: 150),
    autoSearchTime: const Duration(milliseconds: 7500),
    adapterVoltage: '13.9V',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 65 04', // MIL, 2 DTCs; cat/evap/O2/heater; evap inc.
          0x03: '02 00',
          0x04: '4D', // 30.196 %
          0x05: '7E', // 86 °C
          0x06: '83', // +2.344 %
          0x07: '7C', // −3.125 %
          0x0B: '22', // 34 kPa
          0x0C: '0B 54', // 725 rpm
          0x0D: '00',
          0x0E: '8E', // +7°
          0x0F: '55', // 45 °C
          0x11: '1F', // 12.157 %
          0x13: '03',
          0x14: '50 80', // 0.40 V
          0x15: '96 FF', // 0.75 V
          0x1C: '06',
          0x21: '00 14',
        },
        other: {
          // ISO 14230-4: three codes per message, zero padded, no count byte.
          // P1336 meaning on this ECU UNVERIFIED.
          '03': '43 13 36 01 71 00 00', // P1336, P0171
          '07': '47 01 33 00 00 00 00', // P0133 pending
          '020C00': '42 0C 00 0F A0', // 1000 rpm
          '020D00': '42 0D 00 1E', // 30 km/h
          '020500': '42 05 00 7E', // 86 °C
          '020400': '42 04 00 4D', // 30.2 %
          '020F00': '42 0F 00 50', // 40 °C
          '021100': '42 11 00 1F', // 12.2 %
          '020600': '42 06 00 90', // +12.5 %
          '020B00': '42 0B 00 2A', // 42 kPa
        },
      ),
    ],
    overrides: {'0120': '7F 01 12'},
  ),
  connectMax: const Duration(seconds: 20),
  live: _live({
    'rpm': 725,
    'speedKmh': 0,
    'coolantTempC': 86,
    'throttlePct': 12.157,
    'engineLoad': 30.196,
    'batteryVoltage': 13.9, // ATRV
    'fuelTrimShortPct': 2.344,
    'fuelTrimLongPct': -3.125,
    'o2B1S1Voltage': 0.40,
    'o2B1S2Voltage': 0.75,
    'intakeAirTempC': 45,
    'mapKpa': 34,
    'timingAdvanceDeg': 7,
  }),
  dtcs: ['P1336', 'P0171', '~P0133'],
  obdVin: null,
  plateVin: _cs35Vin,
  make: 'Changan',
  year: '2014',
  diesel: false,
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
    'RPM': '1000 rpm',
    'Speed': '30 km/h',
    'Coolant': '86°C',
    'Engine Load': '30.2%',
    'Air Temp': '40°C',
    'Throttle': '12.2%',
    'Fuel Trim': '12.5%',
    'MAP': '42 kPa',
  },
);

// 2. Changan CS35 Plus 2021, 1.6 MPI (narrow-band O2), 6AT. CAN 11/500,
//    ECM + TCM. No oil temp 0x5C (UNVERIFIED). P1545 is a UAES-family
//    manufacturer code (meaning UNVERIFIED).
final _cs35PlusVin = _vin('LS4ASB3R?MA012345'); // VDS UNVERIFIED
final _cs35Plus = _Vehicle(
  name: 'Changan CS35 Plus 2021 (1.6 MPI)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '81 07 65 21', // MIL, 1 DTC; catalyst + O2 incomplete
          0x03: '02 00',
          0x04: '40', // 25.098 %
          0x05: '84', // 92 °C
          0x06: '7E', // −1.5625 %
          0x07: '85', // +3.906 %
          0x0B: '23', // 35 kPa
          0x0C: '0C 1C', // 775 rpm
          0x0D: '00',
          0x0E: '90', // +8°
          0x0F: '5F', // 55 °C
          0x10: '01 5E',
          0x11: '1A', // 10.196 %
          0x13: '03',
          0x14: '2D 80', // 0.225 V
          0x15: 'A0 FF', // 0.80 V
          0x1C: '06',
          0x1F: '00 B4',
          0x21: '00 00',
          0x2F: '99', // 60 %
          0x30: '0C',
          0x31: '01 F4',
          0x33: '63',
          0x42: '36 B0', // 14.0 V
          0x44: '80 00',
          0x46: '5A',
          0x49: '1A', // 10.196 %
          0x4C: '1A',
        },
        other: {
          '03': '43 01 15 45', // P1545
          '07': '47 01 01 71', // P0171 pending
          '0902': _canVinReply(_cs35PlusVin),
          '020C00': '42 0C 00 0C 1C',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 84',
          '020400': '42 04 00 40',
          '020F00': '42 0F 00 5F',
          '021100': '42 11 00 1A',
          '020600': '42 06 00 7E',
          '020B00': '42 0B 00 23',
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '00'}, // TCM
        other: {'03': '43 00', '07': '47 01 07 30'}, // P0730 pending
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 775,
    'speedKmh': 0,
    'coolantTempC': 92,
    'throttlePct': 10.196,
    'fuelLevelPct': 60.0,
    'engineLoad': 25.098,
    'batteryVoltage': 14.0,
    'fuelTrimShortPct': -1.5625,
    'fuelTrimLongPct': 3.906,
    'o2B1S1Voltage': 0.225,
    'o2B1S2Voltage': 0.80,
    'intakeAirTempC': 55,
    'mapKpa': 35,
    'timingAdvanceDeg': 8,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P1545', '~P0171', '~P0730'],
  obdVin: _cs35PlusVin,
  plateVin: _cs35PlusVin,
  make: 'Changan',
  year: '2021',
  diesel: false,
  milOn: true,
  dtcCount: 1,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Evap System', //
      'O2 Sensor Heater',
    ],
    notReady: ['Catalyst', 'O2 Sensor'],
  ),
  freeze: {
    'RPM': '775 rpm',
    'Speed': '0 km/h',
    'Coolant': '92°C',
    'Engine Load': '25.1%',
    'Air Temp': '55°C',
    'Throttle': '10.2%',
    'Fuel Trim': '-1.6%',
    'MAP': '35 kPa',
  },
);

// 3. Changan CS85 Coupe 2022, 2.0T Blue Whale GDI. CAN 11/500 behind a slow
//    central gateway: ~130 ms per answer, NO DATA after ~210 ms (UNVERIFIED
//    figures). Wide-band upstream sensor at 0x24 (no 0x14), rail pressure
//    0x23, oil temp 0x5C. U1102 = Changan network code (meaning UNVERIFIED).
final _cs85Vin = _vin('LS4ASE2A?NA012345'); // VDS UNVERIFIED
final _cs85 = _Vehicle(
  name: 'Changan CS85 Coupe 2022 (2.0T GDI, slow gateway)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 130),
    noDataLatency: const Duration(milliseconds: 210),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 80', // MIL, 2 DTCs; EGR/VVT incomplete
          0x03: '02 00',
          0x04: '4D', // 30.196 %
          0x05: '85', // 93 °C
          0x06: '81', // +0.78125 %
          0x07: '7E', // −1.5625 %
          0x0B: '96', // 150 kPa boost
          0x0C: '1B 58', // 1750 rpm
          0x0D: '5A', // 90 km/h
          0x0E: '88', // +4°
          0x0F: '5A', // 50 °C
          0x10: '06 40',
          0x11: '4D', // 30.196 %
          0x13: '03',
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x1F: '02 58',
          0x21: '00 0A',
          0x23: '03 E8', // 10 000 kPa (100 bar)
          0x24: '80 00 66 66', // λ 1.000
          0x2F: 'B3', // 70.196 %
          0x30: '20',
          0x31: '03 E8',
          0x33: '63',
          0x42: '37 14', // 14.1 V
          0x44: '80 00',
          0x46: '5A',
          0x49: '4D', // 30.196 %
          0x4C: '4D',
          0x5C: '82', // 90 °C
        },
        other: {
          '03': '43 02 02 99 D1 02', // P0299, U1102
          '07': '47 00',
          '0902': _canVinReply(_cs85Vin),
          '020C00': '42 0C 00 2E E0', // 3000 rpm
          '020D00': '42 0D 00 78', // 120 km/h
          '020500': '42 05 00 87',
          '020400': '42 04 00 E6',
          '020F00': '42 0F 00 5F',
          '021100': '42 11 00 B3',
          '020600': '42 06 00 7A',
          '020B00': '42 0B 00 64',
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 1750,
    'speedKmh': 90,
    'coolantTempC': 93,
    'throttlePct': 30.196,
    'fuelLevelPct': 70.196,
    'engineLoad': 30.196,
    'batteryVoltage': 14.1,
    'oilTempC': 90,
    'fuelTrimShortPct': 0.78125,
    'fuelTrimLongPct': -1.5625,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 150,
    'timingAdvanceDeg': 4,
    'lambdaB1S1': 1.0,
    'fuelRailPressureKpa': 10000,
    'acceleratorPedalPct': 30.196,
  }),
  dtcs: ['P0299', 'U1102'],
  obdVin: _cs85Vin,
  plateVin: _cs85Vin,
  make: 'Changan',
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
      'O2 Sensor', 'O2 Sensor Heater',
    ],
    notReady: ['EGR / VVT'],
  ),
  freeze: {
    'RPM': '3000 rpm',
    'Speed': '120 km/h',
    'Coolant': '95°C',
    'Engine Load': '90.2%',
    'Air Temp': '55°C',
    'Throttle': '70.2%',
    'Fuel Trim': '-4.7%',
    'MAP': '100 kPa',
  },
);

// 4. Changan UNI-K 2023, 2.0T Blue Whale + Aisin 8AT. CAN 11/500 with THREE
//    responders: ECM, TCM and (UNVERIFIED) a gateway that answers functional
//    0100/0101 with an empty bitmap. Wide-band at 0x34, rail pressure 0x23.
//    TCM answers 0902 with 17 x 00 (not VIN-coded) before the ECM's real VIN
//    (UNVERIFIED). Only pending codes → no freeze frame stored.
//    WMI LS6 for the UNI line is UNVERIFIED (LS6 = Changan/Deepal/Avatr).
final _unikVin = _vin('LS6A3E0B?PA012345'); // VDS UNVERIFIED
final _unik = _Vehicle(
  name: 'Changan UNI-K 2023 (2.0T, ECM+TCM+gateway)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '00 07 E5 00', // no MIL, all complete
          0x03: '02 00',
          0x04: '38', // 21.961 %
          0x05: '87', // 95 °C
          0x06: '80', // 0 %
          0x07: '81', // +0.78125 %
          0x0B: '1F', // 31 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '64', // 60 °C (Gulf summer, heat-soaked intake)
          0x10: '01 90',
          0x11: '14', // 7.843 %
          0x13: '03',
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x1F: '00 3C',
          0x21: '00 00',
          0x23: '01 F4', // 5000 kPa
          0x2F: '66', // 40 %
          0x30: '10',
          0x31: '03 E8',
          0x33: '62',
          0x34: '7F 00 80 00', // λ 0.99219
          0x42: '36 4C', // 13.9 V
          0x44: '80 00',
          0x46: '64',
          0x49: '14', // 7.843 %
          0x4C: '14',
          0x5C: '7D', // 85 °C
        },
        other: {
          '03': '43 00',
          '07': '47 01 13 00', // P1300 pending (meaning UNVERIFIED)
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '00'}, // TCM
        other: {'03': '43 00', '07': '47 01 07 15'}, // P0715 pending
      ),
      const _Ecu(
        mode01: {0x01: '00 00 00 00'}, // gateway (UNVERIFIED)
        other: {'03': '43 00', '07': '47 00'},
      ),
    ],
    overrides: {
      '0902': '${_canVinBytes(List.filled(17, 0))}\n${_canVinReply(_unikVin)}',
    },
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 95,
    'throttlePct': 7.843,
    'fuelLevelPct': 40.0,
    'engineLoad': 21.961,
    'batteryVoltage': 13.9,
    'oilTempC': 85,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 0.78125,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 60,
    'mapKpa': 31,
    'timingAdvanceDeg': 6,
    'lambdaB1S1': 0.99219,
    'fuelRailPressureKpa': 5000,
    'acceleratorPedalPct': 7.843,
  }),
  dtcs: ['~P1300', '~P0715'],
  obdVin: _unikVin,
  plateVin: _unikVin,
  make: 'Changan',
  year: '2023',
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

// 5. Changan Alsvin 2021 (sedan), 1.5 MPI, narrow-band O2. CAN 11/500.
//    Very reduced PID set (UNVERIFIED): no fuel level, no 0x40 range at all
//    (so no 0142 → ATRV), no evap monitor (GCC-spec, UNVERIFIED).
final _alsvinVin = _vin('LS5A2AJE?MA012345'); // VDS UNVERIFIED
final _alsvin = _Vehicle(
  name: 'Changan Alsvin 2021 (1.5 MPI)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    adapterVoltage: '14.2V',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '81 07 61 00', // MIL, 1 DTC; cat/O2/heater, all complete
          0x03: '02 00',
          0x04: '3A', // 22.745 %
          0x05: '82', // 90 °C
          0x06: '7C', // −3.125 %
          0x07: '84', // +3.125 %
          0x0B: '21', // 33 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0E: '92', // +9°
          0x0F: '5A', // 50 °C
          0x11: '1C', // 10.980 %
          0x13: '03',
          0x14: '78 80', // 0.60 V
          0x15: '82 FF', // 0.65 V
          0x1C: '06',
          0x21: '00 1E',
        },
        other: {
          '03': '43 01 01 30', // P0130
          '07': '47 01 16 3A', // P163A pending (not in the local DB)
          '0902': _canVinReply(_alsvinVin),
          '020C00': '42 0C 00 0C 80',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 82',
          '020400': '42 04 00 3A',
          '020F00': '42 0F 00 5A',
          '021100': '42 11 00 1C',
          '020600': '42 06 00 7C',
          '020B00': '42 0B 00 21',
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 90,
    'throttlePct': 10.980,
    'engineLoad': 22.745,
    'batteryVoltage': 14.2, // ATRV
    'fuelTrimShortPct': -3.125,
    'fuelTrimLongPct': 3.125,
    'o2B1S1Voltage': 0.60,
    'o2B1S2Voltage': 0.65,
    'intakeAirTempC': 50,
    'mapKpa': 33,
    'timingAdvanceDeg': 9,
  }),
  dtcs: ['P0130', '~P163A'],
  obdVin: _alsvinVin,
  plateVin: _alsvinVin,
  make: 'Changan',
  year: '2021',
  diesel: false,
  milOn: true,
  dtcCount: 1,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'O2 Sensor', //
      'O2 Sensor Heater',
    ],
  ),
  freeze: {
    'RPM': '800 rpm',
    'Speed': '0 km/h',
    'Coolant': '90°C',
    'Engine Load': '22.7%',
    'Air Temp': '50°C',
    'Throttle': '11.0%',
    'Fuel Trim': '-3.1%',
    'MAP': '33 kPa',
  },
);

// 6. Changan Hunter 2022 (Kaicene F70) pickup, 2.0T petrol, 6MT (no TCM).
//    CAN 11/500. UNVERIFIED quirk: 0120 sets the 0x41–0x60 range bit but
//    the ECU refuses 0140 with 7F 01 12 → no 0142/0149, ATRV used.
//    UNVERIFIED: ABS module answers functional mode 03 with a C1xxx code.
//    WMI LSC (Changan light truck) UNVERIFIED for the Hunter.
final _hunterVin = _vin('LSCBB23D?NG012345'); // VDS UNVERIFIED
final _hunter = _Vehicle(
  name: 'Changan Hunter 2022 (2.0T pickup)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    adapterVoltage: '14.0V',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 65 04', // MIL, 2 DTCs; evap incomplete
          0x03: '02 00',
          0x04: '59', // 34.902 %
          0x05: '88', // 96 °C
          0x06: '80', // 0 %
          0x07: '7E', // −1.5625 %
          0x0B: '78', // 120 kPa
          0x0C: '15 18', // 1350 rpm
          0x0D: '3C', // 60 km/h
          0x0E: '86', // +3°
          0x0F: '64', // 60 °C
          0x10: '04 B0',
          0x11: '33', // 20 %
          0x13: '03',
          0x14: '64 80', // 0.50 V
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x1F: '01 2C',
          0x21: '00 32',
          0x2F: '4D', // 30.196 %
          0x33: '63',
          0x41: '00 07 E5 04', // only here to set the 0x40-range bit
        },
        other: {
          '07': '47 00',
          '0902': _canVinReply(_hunterVin),
          '020C00': '42 0C 00 17 70', // 1500 rpm
          '020D00': '42 0D 00 32', // 50 km/h
          '020500': '42 05 00 8C', // 100 °C
          '020400': '42 04 00 80', // 50.2 %
          '020F00': '42 0F 00 64', // 60 °C
          '021100': '42 11 00 4D', // 30.2 %
          '020600': '42 06 00 80', // 0 %
          '020B00': '42 0B 00 5A', // 90 kPa
        },
      ),
    ],
    overrides: {
      '0140': '7F 01 12',
      // ECM: P0016 + P1171 (meaning UNVERIFIED); ABS: C1123 (UNVERIFIED).
      '03': '43 02 00 16 11 71\n43 01 51 23',
    },
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 1350,
    'speedKmh': 60,
    'coolantTempC': 96,
    'throttlePct': 20.0,
    'fuelLevelPct': 30.196,
    'engineLoad': 34.902,
    'batteryVoltage': 14.0, // ATRV
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': -1.5625,
    'o2B1S1Voltage': 0.50,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 60,
    'mapKpa': 120,
    'timingAdvanceDeg': 3,
  }),
  dtcs: ['P0016', 'P1171', 'C1123'],
  obdVin: _hunterVin,
  plateVin: _hunterVin,
  make: 'Changan',
  year: '2022',
  diesel: false,
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
    'RPM': '1500 rpm',
    'Speed': '50 km/h',
    'Coolant': '100°C',
    'Engine Load': '50.2%',
    'Air Temp': '60°C',
    'Throttle': '30.2%',
    'Fuel Trim': '0.0%',
    'MAP': '90 kPa',
  },
);

// 7. Ford Taurus 2022 (Changan Ford, Hangzhou), 2.0T EcoBoost. CAN 11/500,
//    PCM + TCM (both answer 0902). Ford PCMs advertise a rich PID set incl.
//    fuel level, oil temp, wide-band at 0x34 (UNVERIFIED for this engine).
//    P1450 is Ford's "unable to bleed up fuel tank vacuum".
final _taurusVin = _vin('LVSHFFAL?NF012345'); // VDS UNVERIFIED
final _taurus = _Vehicle(
  name: 'Ford Taurus 2022 (Changan Ford, 2.0T)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 04', // MIL, 2 DTCs; evap incomplete
          0x03: '02 00',
          0x04: '33', // 20 %
          0x05: '86', // 94 °C
          0x06: '7F', // −0.78125 %
          0x07: '82', // +1.5625 %
          0x0B: '20', // 32 kPa
          0x0C: '0A F0', // 700 rpm
          0x0D: '00',
          0x0E: '94', // +10°
          0x0F: '5F', // 55 °C
          0x10: '01 2C',
          0x11: '1F', // 12.157 %
          0x13: '03',
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x1F: '04 B0',
          0x21: '00 00',
          0x2F: 'CC', // 80 %
          0x30: '30',
          0x31: '07 D0',
          0x33: '63',
          0x34: '80 00 80 00', // λ 1.000
          0x42: '37 DC', // 14.3 V
          0x44: '80 00',
          0x46: '5F',
          0x49: '22', // 13.333 %
          0x4C: '1F',
          0x5C: '7E', // 86 °C
        },
        other: {
          '03': '43 02 14 50 C1 01', // P1450, U0101
          '07': '47 00',
          '0902': _canVinReply(_taurusVin),
          '020C00': '42 0C 00 0A F0',
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 64',
          '020400': '42 04 00 33',
          '020F00': '42 0F 00 5F',
          '021100': '42 11 00 1F',
          '020600': '42 06 00 7F',
          '020B00': '42 0B 00 20',
        },
      ),
      _Ecu(
        mode01: const {0x01: '00 04 00 00', 0x0D: '00'}, // TCM
        other: {
          '03': '43 00',
          '07': '47 00',
          '0902': _canVinReply(_taurusVin),
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 700,
    'speedKmh': 0,
    'coolantTempC': 94,
    'throttlePct': 12.157,
    'fuelLevelPct': 80.0,
    'engineLoad': 20.0,
    'batteryVoltage': 14.3,
    'oilTempC': 86,
    'fuelTrimShortPct': -0.78125,
    'fuelTrimLongPct': 1.5625,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 55,
    'mapKpa': 32,
    'timingAdvanceDeg': 10,
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 13.333,
  }),
  dtcs: ['P1450', 'U0101'],
  obdVin: _taurusVin,
  plateVin: _taurusVin,
  make: 'Ford',
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'O2 Sensor', //
      'O2 Sensor Heater', 'EGR / VVT',
    ],
    notReady: ['Evap System'],
  ),
  freeze: {
    'RPM': '700 rpm',
    'Speed': '0 km/h',
    'Coolant': '60°C',
    'Engine Load': '20.0%',
    'Air Temp': '55°C',
    'Throttle': '12.2%',
    'Fuel Trim': '-0.8%',
    'MAP': '32 kPa',
  },
);

// 8. Ford Territory 2023 (2nd gen, JMC Ford, Nanchang), 1.5T EcoBoost GDI +
//    7DCT. CAN 11/500, ECM + TCM. Freshly reconnected battery: no codes,
//    catalyst / O2 / heater / EGR incomplete. ECM advertises BOTH 0x24 and
//    0x34 (UNVERIFIED) → the app must prefer 0124.
final _territoryVin = _vin('LJXCU2BH?PS012345'); // VDS UNVERIFIED
final _territory = _Vehicle(
  name: 'Ford Territory 2023 (JMC Ford, 1.5T)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '00 07 E5 E1', // no MIL; cat/O2/heater/EGR incomplete
          0x03: '02 00',
          0x04: '2E', // 18.039 %
          0x05: '73', // 75 °C
          0x06: '88', // +6.25 %
          0x07: '80', // 0 %
          0x0B: '1C', // 28 kPa
          0x0C: '0D 48', // 850 rpm
          0x0D: '00',
          0x0E: '8A', // +5°
          0x0F: '4B', // 35 °C
          0x10: '01 2C',
          0x11: '12', // 7.059 %
          0x13: '03',
          0x15: '6E FF', // 0.55 V
          0x1C: '06',
          0x1F: '00 1E',
          0x21: '00 00',
          0x23: '01 C2', // 4500 kPa
          0x24: '7E B8 66 66', // λ 0.98999
          0x2F: '1A', // 10.196 %
          0x30: '00',
          0x31: '00 00',
          0x33: '63',
          0x34: '80 00 80 00', // λ 1.000 (must NOT be used: 0124 wins)
          0x42: '33 90', // 13.2 V
          0x44: '80 00',
          0x46: '4B',
          0x49: '12', // 7.059 %
          0x4C: '12',
          0x5C: '64', // 60 °C
        },
        other: {
          '03': '43 00',
          '07': '47 00',
          '0902': _canVinReply(_territoryVin),
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '00'}, // TCM
        other: {'03': '43 00', '07': '47 00'},
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 850,
    'speedKmh': 0,
    'coolantTempC': 75,
    'throttlePct': 7.059,
    'fuelLevelPct': 10.196,
    'engineLoad': 18.039,
    'batteryVoltage': 13.2,
    'oilTempC': 60,
    'fuelTrimShortPct': 6.25,
    'fuelTrimLongPct': 0,
    'o2B1S2Voltage': 0.55,
    'intakeAirTempC': 35,
    'mapKpa': 28,
    'timingAdvanceDeg': 5,
    'lambdaB1S1': 0.98999,
    'fuelRailPressureKpa': 4500,
    'acceleratorPedalPct': 7.059,
  }),
  dtcs: const [],
  obdVin: _territoryVin,
  plateVin: _territoryVin,
  make: 'Ford',
  year: '2023',
  diesel: false,
  milOn: false,
  dtcCount: 0,
  monitors: _monitors(
    ready: ['Misfire', 'Fuel System', 'Components', 'Evap System'],
    notReady: ['Catalyst', 'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT'],
  ),
  freeze: const {},
);

final _vehicles = [
  _cs35,
  _cs35Plus,
  _cs85,
  _unik,
  _alsvin,
  _hunter,
  _taurus,
  _territory,
];

// Changan Hunter 2.5TD diesel (Kaicene F70 diesel). UNVERIFIED for the GCC
// (sold in other export markets). CAN 11/500, Bosch EDC17-family: no throttle
// 0x11, no O2 / trims / timing; rail 0x23 + pedal 0x49.
_ProfileCar _hunterDieselCar() => _profile(
  protocol: '6',
  ecus: [
    const _Ecu(
      mode01: {
        0x01: '81 0F A9 08', // MIL, 1 DTC; CI; NMHC/boost/EGS/EGR; boost inc.
        0x04: '40', // 25.098 %
        0x05: '82', // 90 °C
        0x0B: '66', // 102 kPa
        0x0C: '0C 80', // 800 rpm
        0x0D: '00',
        0x0F: '5A', // 50 °C
        0x1C: '06',
        0x21: '00 05',
        0x23: '0B B8', // 30 000 kPa (300 bar)
        0x42: '37 14', // 14.1 V
        0x49: '1F', // 12.157 %
      },
      other: {'03': '43 01 00 87', '07': '47 00'}, // P0087
    ),
  ],
);

// ── Test helpers ──────────────────────────────────────────────────────────────

/// The 18 regular live PIDs in the order ProductionOBDAdapter._poll sends them.
const _pollOrder = [
  '010C', '010D', '0105', '0111', '012F', '0104', '0142', '015C', '0106', //
  '0107', '0108', '0109', '0114', '0115', '0118', '010F', '010B', '010E',
];

int _pidOf(String cmd) => int.parse(cmd.substring(2), radix: 16);

/// Mode 01 PIDs advertised by [car]'s 0100 / 0120 / 0140 bitmaps (ORed over
/// every ECU line, following the J1979 range chain).
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

/// Live requests a poll must send for the advertised PIDs [adv]: regular
/// PIDs in poll order, ATRV in the 0142 slot when 0142 isn't advertised,
/// then 0124 (else 0134) only without 0114, 0123, 0149.
List<String> _expectedPolled(Set<int> adv) => [
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
  final Duration cycle;
  final Duration period;
  final List<String> firstCycle;
  final List<String> secondCycle;

  Map<String, double?> get first => _fields(frames[0]);
  Map<String, double?> get second => _fields(frames[1]);

  List<String> get polled =>
      firstCycle.where((c) => !_isBitmapReq(c)).toList();
}

/// Starts polling, waits for two frames, stops.
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

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

final _mfrLabel = RegExp(r'^Manufacturer-specific code \((\w{5})\)');
final _mfrRange =
    RegExp(r'^(?:P1[0-9A-F]{3}|P3[0-3][0-9A-F]{2}|[BCU][12][0-9A-F]{3})$');

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Offline: DtcRepository must answer from the bundled DB / label alone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, (call) async {
      if (call.method == 'check') return ['none'];
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    DtcRepository.rapidApiKeyOverride = null;
    // ignore: avoid_print
    print('\n== Changan / China-built Ford measurements ==\n'
        '${_matrix.join('\n')}');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DtcRepository.resetCaches();
    DtcRepository.rapidApiKeyOverride = '';
  });

  for (final v in _vehicles) {
    group('${v.name} [${v.protocolName}]', () {
      test('(a) connect establishes protocol ${v.protocol}', () {
        sim(v.build(), (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();
          final dt = rig.async.elapsed - t0;
          _log('${v.name}: connect ${_secs(dt)} s '
              '[${rig.elm.commands.join(' ')}]');
          expect(rig.adapter.isConnected, isTrue);
          expect(rig.adapter.connectionState, OBDConnectionState.connected);
          expect(rig.elm.activeProtocol, v.protocol);
          expect(dt, lessThan(v.connectMax));
        }, connect: false);
      });

      test('(b) live poll: exact command sequence, every advertised PID '
          'decoded, < 3 s, refresh every 3 s', () {
        final car = v.build();
        final adv = _advertised(car);
        sim(car, (rig) {
          final p = _poll(rig);
          _log('${v.name}: poll ${_secs(p.cycle)} s, ${p.polled.length} '
              'requests [${p.firstCycle.join(' ')}], refresh '
              '${_secs(p.period)} s');
          expect(p.firstCycle.where(_isBitmapReq), _expectedBitmapReqs(adv));
          expect(p.polled, _expectedPolled(adv));
          _expectLive(p.first, v.live);
          expect(p.cycle, lessThan(const Duration(seconds: 3)));
          expect(p.period, lessThan(const Duration(milliseconds: 3100)));
          // Bitmaps are read once; the second cycle repeats the same PIDs.
          expect(p.secondCycle, p.polled);
          _expectLive(p.second, v.live);
        });
      });

      test('(c) DTCs: confirmed (03) + pending (07)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(c) clear accepted (44) → no codes, no freeze frame', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
          expect(rig.elm.commands.last, '04');
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
        });
      });

      test('(c) clear refused (7F 04 22, engine running) → false, codes '
          'kept', () {
        final base = v.build();
        final others = base.emptyDtcReply.split('\n').length - 1;
        final car = _variant(base,
            clearReply: ['7F 04 22', ...List.filled(others, '44')].join('\n'));
        sim(car, (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(c) DtcRepository describes every code read (offline)', () async {
        final repo = DtcRepository();
        for (final raw in v.dtcs) {
          final code = raw.replaceFirst('~', '');
          final d = await repo.getDtcDescription(code);
          _log('${v.name}: $code → ${d ?? 'null'}');
          expect(d, isNotNull, reason: code);
          expect(d!.trim(), isNotEmpty, reason: code);
          final label = _mfrLabel.firstMatch(d);
          if (label != null) {
            expect(_mfrRange.hasMatch(code), isTrue, reason: code);
            expect(label.group(1), code);
          }
        }
      });

      test('(d) VIN via 0902 → VinDecoder country China + model year', () {
        sim(v.build(), (rig) {
          final vin = rig.drive(rig.adapter.getVin());
          _log('${v.name}: getVin() → $vin');
          expect(vin, v.obdVin);
          final plate = VinDecoder.decode(v.plateVin, now: _now);
          _log('${v.name}: VinDecoder(${v.plateVin}) → $plate');
          expect(_checkDigit(v.plateVin), v.plateVin[8]);
          expect(plate['country'], 'China');
          expect(plate['year'], v.year);
          if (vin == null) return;
          final d = VinDecoder.decode(vin, now: _now);
          expect(d['country'], 'China');
          expect(d['year'], v.year);
        });
      });

      test('(d) VinDecoder maker for WMI ${v.plateVin.substring(0, 3)} → '
          '${v.make}', () {
        final d = VinDecoder.decode(v.plateVin, now: _now);
        expect(d['manufacturer'], contains(v.make));
      });

      test('(e) readiness (${v.diesel ? 'diesel' : 'spark'}), MIL, count',
          () {
        sim(v.build(), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.compressionIgnition, v.diesel);
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

  // ── Brand-specific edge cases ──────────────────────────────────────────────

  group('edge cases', () {
    test('CS35 2014 K-line: CAN probe fails fast (CAN ERROR) then auto '
        'search finds KWP; 0120 refused (7F 01 12) → no 0140, ATRV used', () {
      final car = _cs35.build();
      sim(car, (rig) {
        rig.connect();
        expect(rig.elm.commands, containsAllInOrder(
            ['ATSP6', '0100', 'ATSP0', '0100']));
        final p = _poll(rig);
        expect(p.firstCycle.where(_isBitmapReq), ['0120']);
        expect(p.polled, contains('ATRV'));
        expect(p.polled, isNot(contains('0142')));
        expect(p.polled, isNot(contains('012F')));
      }, connect: false);
    });

    test('CS35 2014: no mode 09 support → getVin() null, DTCs still read',
        () {
      sim(_cs35.build(), (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
        expect(rig.drive(rig.adapter.getDtcs()), _cs35.dtcs);
      });
    });

    test('CS35 2014 clone without ATRV ("?") → battery null, asked only on '
        'the first two polls', () {
      final base = _cs35.build();
      final car = _ProfileCar(
        protocol: base.protocol,
        responses: base.responses,
        ecuLatency: base.ecuLatency,
        autoSearchTime: base.autoSearchTime,
        wrongProtocolReply: base.wrongProtocolReply,
        noDataLatency: base.noDataLatency,
        emptyDtcReply: base.emptyDtcReply,
        clearReply: base.clearReply,
      );
      sim(car, (rig) {
        final cuts = <int>[rig.elm.commands.length];
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen((d) {
          frames.add(d);
          cuts.add(rig.elm.commands.length);
        });
        rig.adapter.startLiveData();
        while (frames.length < 3) {
          rig.async.elapse(const Duration(milliseconds: 10));
        }
        rig.adapter.stopLiveData();
        sub.cancel();
        List<String> cycle(int i) =>
            rig.elm.commands.sublist(cuts[i], cuts[i + 1]);
        expect(cycle(0), contains('ATRV'));
        expect(cycle(1), contains('ATRV'));
        expect(cycle(2), isNot(contains('ATRV')));
        expect(frames.last.batteryVoltage, isNull);
        expect(frames.last.rpm, closeTo(725, 0.01));
      });
    });

    test('CS85 Coupe slow gateway: every reply 130 ms → poll still < 3 s',
        () {
      sim(_cs85.build(), (rig) {
        final p = _poll(rig);
        expect(p.polled.length, 17);
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('UNI-K: TCM answers 0902 with 17 x 00 before the ECM VIN → ECM VIN',
        () {
      sim(_unik.build(), (rig) {
        expect(rig.drive(rig.adapter.getVin()), _unikVin);
      });
    });

    test('UNI-K: gateway / TCM 0101 lines first → still spark, all ECM '
        'monitors', () {
      final car = _variant(_unik.build(), replies: {
        '0101': '41 01 00 00 00 00\n41 01 00 04 00 00\n41 01 00 07 E5 00',
      });
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isFalse);
        expect({for (final m in r.monitors) m.name: m.status}, _unik.monitors);
      });
    });

    test('Hunter: 0140 refused (7F 01 12) → no 0142 / 0149, ATRV instead, '
        'cycle < 3 s', () {
      sim(_hunter.build(), (rig) {
        final p = _poll(rig);
        expect(p.firstCycle.where(_isBitmapReq), ['0120', '0140']);
        expect(p.polled, isNot(contains('0142')));
        expect(p.polled, isNot(contains('0149')));
        expect(p.polled, contains('ATRV'));
        expect(p.first['batteryVoltage'], closeTo(14.0, 0.01));
      });
    });

    test('Hunter: ABS C-code line in mode 03 merged with the ECM codes', () {
      sim(_hunter.build(), (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), contains('C1123'));
      });
    });

    test('Hunter 2.5TD diesel (UNVERIFIED for GCC): diesel readiness + rail '
        'pressure + pedal', () {
      final car = _hunterDieselCar();
      final adv = _advertised(car);
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isTrue);
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 1);
        expect(
          {for (final m in r.monitors) m.name: m.status},
          _monitors(
            diesel: true,
            ready: [
              'Misfire', 'Fuel System', 'Components', 'NMHC Catalyst', //
              'Exhaust Gas Sensor', 'EGR / VVT',
            ],
            notReady: ['Boost Pressure'],
          ),
        );
        final p = _poll(rig);
        expect(p.polled, _expectedPolled(adv));
        _expectLive(p.first, _live({
          'rpm': 800,
          'speedKmh': 0,
          'coolantTempC': 90,
          'engineLoad': 25.098,
          'batteryVoltage': 14.1,
          'intakeAirTempC': 50,
          'mapKpa': 102,
          'fuelRailPressureKpa': 30000,
          'acceleratorPedalPct': 12.157,
        }));
        expect(rig.drive(rig.adapter.getDtcs()), ['P0087']);
      });
    });

    test('Territory: 0124 and 0134 both advertised → 0124 used, not 0134', () {
      sim(_territory.build(), (rig) {
        final p = _poll(rig);
        expect(p.polled, contains('0124'));
        expect(p.polled, isNot(contains('0134')));
        expect(p.first['lambdaB1S1'], closeTo(0.98999, 0.0001));
      });
    });

    test('Taurus: PCM and TCM both answer 0902 → one VIN', () {
      sim(_taurus.build(), (rig) {
        expect(rig.drive(rig.adapter.getVin()), _taurusVin);
      });
    });

    test('Taurus: PCM refuses, TCM accepts (44 after 7F 04 22) → false', () {
      final car = _variant(_taurus.build(), clearReply: '44\n7F 04 22');
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _taurus.dtcs);
      });
    });

    // GB 16735 makes the position-9 check digit mandatory in China, so a VIN
    // from an 'L' WMI with a wrong check digit is corrupted (e.g. one byte
    // garbled on a noisy clone) and must not be shown as the car's VIN.
    test('CS35 Plus: 0902 VIN with one corrupted serial digit (valid '
        'alphabet, wrong GB 16735 check digit) → null', () {
      final bad = _cs35PlusVin.replaceRange(16, 17,
          _cs35PlusVin[16] == '5' ? '6' : '5');
      expect(_checkDigit(bad) == bad[8], isFalse);
      final car = _variant(_cs35Plus.build(),
          replies: {'0902': _canVinReply(bad)});
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), isNull));
    });

    // ── VinDecoder: China-built WMIs seen in the GCC ────────────────────────

    const wmiTable = [
      ('LS5A2AJE?MA012345', 'Changan', '2021'),
      ('LVSHFFAL?NF012345', 'Ford', '2022'),
      ('LS4ASB3R?MA012345', 'Changan', '2021'),
      ('LS6A3E0B?PA012345', 'Changan', '2023'),
      ('LSCBB23D?NG012345', 'Changan', '2022'),
      ('LJXCU2BH?PS012345', 'Ford', '2023'),
      ('LXWCU2BH?PS012345', 'Ford', '2023'),
      ('LVRHDAEJ?NN012345', 'Mazda', '2022'),
    ];
    for (final (tpl, maker, year) in wmiTable) {
      test('VinDecoder ${tpl.substring(0, 3)} → $maker / China / $year', () {
        final d = VinDecoder.decode(_vin(tpl), now: _now);
        expect(d['country'], 'China');
        expect(d['year'], year);
        expect(d['manufacturer'], contains(maker));
      });
    }

    test('VinDecoder: country + year still decode for unknown Changan WMIs',
        () {
      for (final (tpl, _, year) in wmiTable) {
        final d = VinDecoder.decode(_vin(tpl), now: _now);
        expect(d['country'], 'China', reason: tpl);
        expect(d['year'], year, reason: tpl);
      }
    });

    // ── DtcRepository: Chinese manufacturer-specific codes ──────────────────

    test('DtcRepository: Chinese manufacturer codes never null / blank '
        '(offline)', () async {
      final repo = DtcRepository();
      for (final code in [
        'P1545', 'P163A', 'P1300', 'P1336', 'P1171', 'U1102', 'U1001', //
        'B1342', 'B1D00', 'C1123', 'C1201', 'P3001', 'U2100', 'B2F00',
      ]) {
        final d = await repo.getDtcDescription(code);
        _log('DtcRepository $code → ${d ?? 'null'}');
        expect(d, isNotNull, reason: code);
        expect(d!.trim(), isNotEmpty, reason: code);
      }
      expect(await repo.getDtcDescription('P1545'),
          startsWith('Manufacturer-specific code (P1545)'));
    });

    // The bundled DB carries P1xxx / U1xxx / B1xxx meanings of other brands
    // (mostly Ford/GM: "SCP (J1850)…", "PATS…"). Shown to a Changan owner
    // they are simply wrong, and getDtcDescription has no make parameter.
    test('DtcRepository: Changan U1102 must not get a Ford J1850 SCP '
        'meaning — manufacturer-range hits should be flagged as brand-'
        'specific', () async {
      final d = await DtcRepository().getDtcDescription('U1102');
      expect(d, isNot(contains('J1850')));
      expect(d, contains('Manufacturer-specific'));
    });

    // Changan's UNI-K iDD / Deepal plug-in hybrids report SAE P0Axx hybrid
    // codes. (When this test was written P0A80 was missing from the bundled
    // DB; the SAE hybrid block P0A00–P0C87 is now bundled, and codes still
    // missing get a generic label — see the double-check group.)
    test('DtcRepository: SAE hybrid code P0A80 (UNI-K iDD / Deepal) offline '
        '→ never null', () async {
      final d = await DtcRepository().getDtcDescription('P0A80');
      expect(d, isNotNull);
      expect(d!.trim(), isNotEmpty);
    });
  });

  // ── Double-check: adversarial probes of the vin_decoder / obd_adapter /
  //    dtc_repository fixes, for the Changan family and China-built Fords ──

  group('double-check', () {
    // Every Changan-group / China-built-Ford WMI the decoder now knows.
    const wmis = [
      ('LS4', 'Changan'), ('LS5', 'Changan'), ('LS6', 'Changan'),
      ('LSC', 'Changan'), ('LVS', 'Ford'), ('LJX', 'Ford'), ('LXW', 'Ford'),
      ('LVR', 'Mazda'), ('LEF', 'JMC'),
    ];
    const years = {'E': '2014', 'L': '2020', 'N': '2022', 'S': '2025', //
      'T': '2026', 'V': '2027'};

    test('every Changan-group WMI → maker + China + model year (pos 10) for '
        'six model years', () {
      for (final (wmi, maker) in wmis) {
        for (final y in years.entries) {
          final vin = _vin('${wmi}AB3D4?${y.key}A012345');
          final d = VinDecoder.decode(vin, now: _now);
          expect(d['manufacturer'], contains(maker), reason: vin);
          expect(d['manufacturer'], isNot(VinDecoder.unknown), reason: vin);
          expect(d['country'], 'China', reason: vin);
          expect(d['year'], y.value, reason: vin);
        }
      }
    });

    test('Changan Ford / JMC Ford / Changan Mazda WMIs are not labelled as '
        'plain Changan and vice versa', () {
      String m(String wmi) =>
          VinDecoder.decode(_vin('${wmi}AB3D4?NA012345'), now: _now)
              ['manufacturer']!;
      for (final w in ['LS4', 'LS5', 'LS6', 'LSC']) {
        expect(m(w), isNot(contains('Ford')), reason: w);
        expect(m(w), isNot(contains('Mazda')), reason: w);
      }
      expect(m('LJX'), isNot(contains('Changan')));
      expect(m('LXW'), isNot(contains('Changan')));
    });

    // getVin() on the CS35 Plus (CAN), 0902 replaced by [vin].
    String? obdVin(String vin) {
      String? got;
      sim(_variant(_cs35Plus.build(), replies: {'0902': _canVinReply(vin)}),
          (rig) => got = rig.drive(rig.adapter.getVin()));
      return got;
    }

    // A different VIN character with a different GB 16735 value (so the
    // check digit really breaks; e.g. A↔J share value 1 and would not).
    String garble(String c) {
      int val(String x) => int.tryParse(x) ?? _translit[x]!;
      return '0123456789ABCDEFGHJKLMNPRSTUVWXYZ'
          .split('')
          .firstWhere((x) => x != c && val(x) != val(c));
    }

    test('valid Changan-family VINs from 0902 are accepted (all 8 profiles '
        '+ every WMI)', () {
      for (final v in _vehicles) {
        expect(obdVin(v.plateVin), v.plateVin, reason: v.name);
      }
      for (final (wmi, _) in wmis) {
        final vin = _vin('${wmi}AB3D4?NA012345');
        expect(obdVin(vin), vin, reason: vin);
      }
    });

    test('CS35 Plus VIN garbled at ANY one of positions 2–17 (check digit '
        'now wrong) → getVin() null', () {
      for (var i = 1; i < 17; i++) {
        final bad = _cs35PlusVin.replaceRange(i, i + 1,
            garble(_cs35PlusVin[i]));
        expect(_checkDigit(bad) == bad[8], isFalse, reason: bad);
        expect(obdVin(bad), isNull, reason: 'position ${i + 1}: $bad');
      }
    });

    test('garbled serial digit on every Changan-group WMI → null (LS4 / LS5 '
        '/ LS6 / LSC / LVS / LJX / LXW / LVR / LEF)', () {
      for (final (wmi, _) in wmis) {
        final ok = _vin('${wmi}AB3D4?NA012345');
        final bad = ok.replaceRange(15, 16, garble(ok[15]));
        expect(obdVin(bad), isNull, reason: bad);
      }
    });

    test('first character garbled L → H (still a GB 16735 region) → null',
        () {
      final bad = _cs35PlusVin.replaceRange(0, 1, 'H');
      expect(_checkDigit(bad) == bad[8], isFalse);
      expect(obdVin(bad), isNull);
    });

    test('Chinese VIN with a Korean-style letter at position 9 (D / P / R) '
        '→ null; a correct "X" check digit → accepted', () {
      for (final c in ['D', 'P', 'R']) {
        expect(obdVin(_cs35PlusVin.replaceRange(8, 9, c)), isNull, reason: c);
      }
      var n = 0;
      late String x;
      do {
        x = _vin('LS4ASB3R?MA0123${(n++).toString().padLeft(2, '0')}');
      } while (x[8] != 'X');
      expect(obdVin(x), x);
      // …and the same VIN with a digit where the X belongs → null.
      expect(obdVin(x.replaceRange(8, 9, '0')), isNull);
    });

    test('K-line CS35 2014 variant answering a garbled 5-message 0902 → '
        'null; the intact one → VIN', () {
      String kLine(String vin) {
        final b = [0, 0, 0, ...vin.codeUnits];
        return [
          for (var i = 0; i < 5; i++)
            '49 02 ${_h(i + 1)} ${_hx(b.sublist(i * 4, i * 4 + 4))}',
        ].join('\n');
      }
      final bad = _cs35Vin.replaceRange(12, 13, garble(_cs35Vin[12]));
      for (final (vin, want) in [(_cs35Vin, _cs35Vin), (bad, null)]) {
        final car = _variant(_cs35.build(), replies: {'0902': kLine(vin)});
        sim(car, (rig) {
          expect(rig.drive(rig.adapter.getVin()), want, reason: vin);
        });
      }
    });

    // Manufacturer-range codes a Changan / Changan-Ford can report. Several
    // have Ford/GM meanings in the bundled DB (U1102 / U1001 "SCP (J1850)",
    // P1690 wastegate, B1342 "ECU is defective", C1201 ABS valve …).
    const mfrCodes = [
      'P1545', 'P163A', 'P1300', 'P1336', 'P1171', 'P1690', 'U1102', //
      'U1001', 'B1342', 'B1D00', 'C1123', 'C1201', 'P3001', 'U2100', 'B2F00',
      'P30FF', 'P33FF', 'C2F00', 'U2FFF',
    ];
    const foreign = ['J1850', 'SCP', 'Ford', 'GM', 'PATS', 'Wastegate', //
      'فورد', 'جنرال'];

    Future<(Map<String, dynamic>, Map<String, dynamic>)> db() async => (
      jsonDecode(await rootBundle.loadString('assets/dtcmapping.json'))
          as Map<String, dynamic>,
      jsonDecode(await rootBundle.loadString('assets/dtcmapping_ar.json'))
          as Map<String, dynamic>,
    );

    test('manufacturer codes, EN: exactly the localized manufacturer label, '
        'no other brand\'s DB text', () async {
      final (en, _) = await db();
      final repo = DtcRepository();
      for (final code in mfrCodes) {
        final d = (await repo.getDtcDescription(code))!;
        expect(d, DtcRepository.manufacturerLabel(code), reason: code);
        expect(d, contains('($code)'));
        for (final f in foreign) {
          expect(d, isNot(contains(f)), reason: '$code → $d');
        }
        final dbText = en[code] as String?;
        if (dbText != null) expect(d, isNot(contains(dbText)), reason: code);
      }
    });

    test('manufacturer codes, AR: Arabic manufacturer label, no other brand\'s '
        'DB text (EN or AR)', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      final arabic = RegExp(r'[؀-ۿ]');
      for (final code in mfrCodes) {
        final d = (await repo.getDtcDescription(code, languageCode: 'ar'))!;
        expect(d, DtcRepository.manufacturerLabel(code, languageCode: 'ar'),
            reason: code);
        expect(d, matches(arabic));
        expect(d, contains(code));
        expect(d, isNot(contains('Manufacturer-specific')));
        for (final f in foreign) {
          expect(d, isNot(contains(f)), reason: '$code → $d');
        }
        for (final t in [en[code], ar[code]].whereType<String>()) {
          expect(d, isNot(contains(t)), reason: code);
        }
      }
    });

    test('lower-case / padded input " u1102 " → same manufacturer label; '
        'malformed "U11O2" / "U1102X" → null', () async {
      final repo = DtcRepository();
      expect(await repo.getDtcDescription(' u1102 '),
          DtcRepository.manufacturerLabel('U1102'));
      expect(await repo.getDtcDescription('U11O2'), isNull);
      expect(await repo.getDtcDescription('U1102X'), isNull);
    });

    test('range boundaries: P3400 (SAE) → DB text, P33FF (manufacturer) → '
        'label, P2A00 / U3000 (SAE, not bundled) → generic SAE label',
        () async {
      final (en, _) = await db();
      final repo = DtcRepository();
      expect(await repo.getDtcDescription('P3400'), en['P3400']);
      expect(await repo.getDtcDescription('P33FF'),
          DtcRepository.manufacturerLabel('P33FF'));
      expect(await repo.getDtcDescription('P2A00'),
          DtcRepository.genericSaeLabel('P2A00'));
      expect(await repo.getDtcDescription('U3000'),
          startsWith('Network communication code (U3000)'));
    });

    test('stale cached Ford text in device storage (dtc_en_ / dtc_ar_ from an '
        'older build) is never shown for U1102', () async {
      SharedPreferences.setMockInitialValues({
        'dtc_en_U1102': 'SCP (J1850) Invalid or Missing Data for Primary Id',
        'dtc_ar_U1102': 'SCP (J1850) غير صالح',
      });
      DtcRepository.resetCaches();
      final repo = DtcRepository();
      expect(await repo.getDtcDescription('U1102'),
          DtcRepository.manufacturerLabel('U1102'));
      expect(await repo.getDtcDescription('U1102', languageCode: 'ar'),
          DtcRepository.manufacturerLabel('U1102', languageCode: 'ar'));
    });

    test('online with an API key: a manufacturer code never reaches the '
        'network (no Ford answer can leak in)', () async {
      var calls = 0;
      DtcRepository.httpClient = MockClient((req) async {
        calls++;
        return http.Response(
            '{"definition":"SCP (J1850) Invalid Data (Ford)"}', 200);
      });
      DtcRepository.rapidApiKeyOverride = 'test-key';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_connectivityChannel, (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(_connectivityChannel,
            (call) async => call.method == 'check' ? ['none'] : null);
        DtcRepository.httpClient = http.Client();
        DtcRepository.rapidApiKeyOverride = '';
      });
      final repo = DtcRepository();
      for (final code in ['U1102', 'P1545', 'B1342', 'C2F00']) {
        expect(await repo.getDtcDescription(code),
            DtcRepository.manufacturerLabel(code));
        expect(await repo.getDtcDescription(code, languageCode: 'ar'),
            DtcRepository.manufacturerLabel(code, languageCode: 'ar'));
      }
      expect(calls, 0);
      // Control: the rig really is online — an unbundled SAE code does call.
      expect(await repo.getDtcDescription('P2A00'), isNotNull);
      expect(calls, 1);
    });

    test('getOtherBrandHint: Ford text only as a labelled hint (EN + AR); '
        'null for SAE codes and for manufacturer codes without a DB entry',
        () async {
      final repo = DtcRepository();
      final en = await repo.getOtherBrandHint('U1102');
      expect(en, startsWith('On some brands (often Ford/GM) this code means: '));
      expect(en, contains('J1850'));
      final ar = await repo.getOtherBrandHint('U1102', languageCode: 'ar');
      expect(ar, startsWith('لدى بعض العلامات التجارية'));
      expect(await repo.getOtherBrandHint('P0171'), isNull);
      expect(await repo.getOtherBrandHint('P3400'), isNull);
      expect(await repo.getOtherBrandHint('P1545'), isNull); // not in the DB
      expect(await repo.getOtherBrandHint('B1D00', languageCode: 'ar'),
          isNull);
    });

    test('UNI-K iDD / Deepal hybrid codes P0A00–P0C87: real bundled '
        'descriptions in EN and AR (not the generic label)', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      final arabic = RegExp(r'[؀-ۿ]');
      for (final code in ['P0A80', 'P0A7F', 'P0A94', 'P0AA6', 'P0B24', //
        'P0C78', 'P0A00', 'P0C87']) {
        final e = (await repo.getDtcDescription(code))!;
        expect(e, en[code], reason: code);
        expect(e, isNot(contains('Hybrid/EV propulsion system code')));
        final a = (await repo.getDtcDescription(code, languageCode: 'ar'))!;
        expect(a, ar[code], reason: code);
        expect(a, matches(arabic), reason: code);
        expect(a, isNot(contains('رمز نظام الدفع الهجين')), reason: code);
      }
    });

    test('hybrid block beyond the bundled range (P0C88–P0DFF) → localized '
        'hybrid/EV label in EN and AR; P0E00 is not called hybrid', () async {
      final repo = DtcRepository();
      for (final code in ['P0C88', 'P0C90', 'P0CFF', 'P0D00', 'P0D27', //
        'P0DFF']) {
        final e = await repo.getDtcDescription(code);
        expect(e, DtcRepository.genericSaeLabel(code), reason: code);
        expect(e, startsWith('Hybrid/EV propulsion system code ($code)'));
        final a = await repo.getDtcDescription(code, languageCode: 'ar');
        expect(a, DtcRepository.genericSaeLabel(code, languageCode: 'ar'));
        expect(a, startsWith('رمز نظام الدفع الهجين/الكهربائي ($code)'));
      }
      expect(await repo.getDtcDescription('P0E00'),
          startsWith('Powertrain (engine/transmission) code (P0E00)'));
    });

    // ── Connect: classifying a silent ECU ─────────────────────────────────

    (OBDConnectException, List<String>) failConnect(SimCar car) {
      OBDConnectException? err;
      late List<String> cmds;
      sim(car, (rig) {
        try {
          rig.connect();
        } on OBDConnectException catch (e) {
          err = e;
        }
        expect(err, isNotNull, reason: 'connect must fail');
        cmds = [...rig.elm.commands];
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
        expect(rig.adapter.isConnected, isFalse);
      }, connect: false);
      return (err!, cmds);
    }

    test('ignition-off Changan CS35 Plus: CAN ERROR on the CAN probe → '
        'ecuNotResponding, ATRV never asked (even at 13.9 V)', () {
      final (e, cmds) = failConnect(const SimCar(
        wrongProtocolReply: 'CAN ERROR',
        adapterVoltage: '13.9V',
      ));
      expect(e.reason, OBDFailureReason.ecuNotResponding);
      expect(cmds, isNot(contains('ATRV')));
    });

    test('ignition-off CS35 2014 (K-line): CAN ERROR then BUS INIT: ...ERROR '
        '→ ecuNotResponding, no ATRV', () {
      final (e, cmds) = failConnect(const SimCar(
        wrongProtocolReply: 'CAN ERROR',
        ignitionOffReply: 'BUS INIT: ...ERROR',
        adapterVoltage: '13.9V',
      ));
      expect(e.reason, OBDFailureReason.ecuNotResponding);
      expect(cmds, isNot(contains('ATRV')));
    });

    test('ignition-off CS35 Plus whose gateway still ACKs (NO DATA) on a '
        'resting 12.4 V battery → ecuNotResponding, ATRV asked once', () {
      final (e, cmds) = failConnect(const SimCar(adapterVoltage: '12.4V'));
      expect(e.reason, OBDFailureReason.ecuNotResponding);
      expect(cmds.where((c) => c == 'ATRV'), hasLength(1));
    });

    test('successful connect of every Changan profile never sends ATRV; '
        'polls still < 3 s', () {
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
