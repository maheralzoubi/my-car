// Compatibility matrix — Chinese cars, group B: the Geely group (Geely,
// Geometry, Lynk & Co, Proton) as sold in the Gulf, driven through the ELM327
// simulator. The Geely Coolray 2021 is covered in korean_chinese_cars_test.dart
// and is not repeated here.
//
// Each profile models what that car's ECU(s) answer: ELM protocol number,
// auto-search time, PID support bitmaps (generated from the PIDs that really
// answer, so 0100/0120/0140 are always consistent), NO DATA for unsupported
// PIDs (with realistic NO DATA latency), extra ECUs on CAN, protocol-correct
// DTC / VIN / freeze-frame replies and engine-appropriate readiness bytes.
//
// Grounding:
//  * SAE J1979 / ISO 15765-4 / ISO 14230-4 message formats, ELM327 datasheet
//    behaviour (SEARCHING…, BUS INIT, CAN ERROR, NO DATA, ATRV).
//  * China 6 (GB 18352.6) cars: ISO 15765-4 CAN 11-bit 500k.
//  * WMIs: L6T / LB3 = Geely (Wikibooks WMI list; real Lynk & Co 01 VINs
//    L6TCX2E7…, real Emgrand EC7 VIN L6T7824S1GN055117 — check digits verified),
//    L10 = Geely Emgrand (Wikibooks, vindecoder.site), PL1 = Proton (Wikibooks).
//    Monjaro LB3 prefix seen on Russian listings.
//  * Per-model PID sets, latencies and module layouts are NOT published by the
//    OEMs; every such detail is marked UNVERIFIED. VDS characters (VIN
//    positions 4–8) are synthetic except where noted.
//
// Where the app behaves wrongly the test still asserts the CORRECT behaviour
// and would be marked `skip: 'REGRESSION: …'`. None remain: the former `BUG:`
// skips (other brands' text for manufacturer-range codes, missing SAE hybrid
// block P0Axx, WMIs PL1 / L10) were fixed in dtc_repository.dart,
// assets/dtcmapping*.json and vin_decoder.dart and now always run; the
// "double-check" group at the end attacks those fixes.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// ISO 3779 check digit (position 9). China's GB 16735 mandates it; real
/// Geely / Lynk & Co VINs carry a correct one (verified on public VINs).
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
String _canVinReply(String vin) {
  final b = [0x49, 0x02, 0x01, ...vin.codeUnits];
  return '014\n'
      '0: ${_hx(b.sublist(0, 6))}\n'
      '1: ${_hx(b.sublist(6, 13))}\n'
      '2: ${_hx(b.sublist(13, 20))}';
}

/// 09 02 on ISO 14230-4: five messages "49 02 0N" + 4 bytes, the first
/// padded with three 00 bytes.
String _kLineVinReply(String vin) {
  final b = [0, 0, 0, ...vin.codeUnits];
  return [
    for (var i = 0; i < 5; i++)
      '49 02 ${_h(i + 1)} ${_hx(b.sublist(i * 4, i * 4 + 4))}',
  ].join('\n');
}

/// Mode 02 frame-00 replies for the eight freeze-frame PIDs the app reads
/// (raw data bytes as the ECU stores them; null = ECU answers NO DATA).
Map<String, String> _ffReplies({
  required String rpm,
  required String speed,
  required String coolant,
  required String load,
  required String iat,
  required String tps,
  required String trim,
  String? map,
}) => {
  '020C00': '42 0C 00 $rpm',
  '020D00': '42 0D 00 $speed',
  '020500': '42 05 00 $coolant',
  '020400': '42 04 00 $load',
  '020F00': '42 0F 00 $iat',
  '021100': '42 11 00 $tps',
  '020600': '42 06 00 $trim',
  if (map != null) '020B00': '42 0B 00 $map',
};

// ── ECU / vehicle profile model ───────────────────────────────────────────────

/// One ECU on the diagnostic bus.
class _Ecu {
  const _Ecu({this.mode01 = const {}, this.other = const {}});

  /// Mode 01 PID → data bytes it answers with. Support bitmaps (00/20/40/…)
  /// are generated from these keys — never list them here. An empty map =
  /// a module that ignores mode 01 entirely (e.g. a chassis module that only
  /// answers 03 / 07).
  final Map<int, String> mode01;

  /// Replies to everything else (03, 07, 02xx00, 0902 …).
  final Map<String, String> other;

  Map<String, String> replies() {
    final out = <String, String>{};
    final pids = mode01.keys.toSet();
    if (pids.isNotEmpty) {
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
/// a mode 04 that really clears the stored codes, and optional reply
/// sequences (a PID whose value changes from one request to the next).
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
    this.sequences = const {},
  });

  final Duration noDataLatency;
  final String emptyDtcReply;
  final String clearReply;

  /// Request → successive replies (the last one repeats).
  final Map<String, List<String>> sequences;
  final _seq = <String, int>{};

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
    final seq = sequences[cmd];
    if (seq != null) {
      final i = _seq[cmd] ?? 0;
      _seq[cmd] = i + 1;
      return seq[i.clamp(0, seq.length - 1)];
    }
    return super.answer(cmd);
  }

  @override
  Duration latency(String cmd) =>
      responses.containsKey(cmd) || sequences.containsKey(cmd)
      ? super.latency(cmd)
      : noDataLatency;
}

_ProfileCar _profile({
  required String? protocol,
  required List<_Ecu> ecus,
  bool kLine = false,
  Duration ecuLatency = const Duration(milliseconds: 60),
  Duration? noDataLatency,
  Duration autoSearchTime = const Duration(seconds: 7),
  Map<String, String> overrides = const {},
  Map<String, List<String>> sequences = const {},
  String? clearReply,
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
  if (kLine && responses['0100'] != null) {
    // ISO 14230 fast init: the first request after the search shows the init.
    responses['0100'] = 'BUS INIT: ...OK\n${responses['0100']}';
  }
  final emptyLine = kLine ? '43 00 00 00 00 00 00' : '43 00';
  final dtcModules = ecus.where((e) => e.other.containsKey('03')).length;
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
    wrongProtocolReply: kLine ? 'CAN ERROR' : 'NO DATA',
    emptyDtcReply: List.filled(
      dtcModules == 0 ? 1 : dtcModules,
      emptyLine,
    ).join('\n'),
    clearReply:
        clearReply ??
        List.filled(dtcModules == 0 ? 1 : dtcModules, '44').join('\n'),
    adapterVoltage: adapterVoltage,
    sequences: sequences,
  );
}

/// [base] with some replies replaced (null value = removed → NO DATA).
/// Support bitmaps are NOT regenerated.
_ProfileCar _variant(
  _ProfileCar base, {
  Map<String, String?> replies = const {},
  Map<String, List<String>>? sequences,
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
    sequences: sequences ?? base.sequences,
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

/// All polled values; the ones not listed are expected to be null.
Map<String, double?> _live(Map<String, double> supported) {
  assert(supported.keys.every(_liveKeys.contains), supported.keys);
  return {for (final k in _liveKeys) k: supported[k]};
}

const _sparkNames = [
  'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Heated Catalyst', //
  'Evap System', 'Secondary Air', 'A/C System', 'O2 Sensor',
  'O2 Sensor Heater', 'EGR / VVT',
];

Map<String, MonitorStatus> _monitors({
  List<String> ready = const [],
  List<String> notReady = const [],
}) {
  assert([...ready, ...notReady].every(_sparkNames.contains));
  return {
    for (final n in _sparkNames)
      n: ready.contains(n)
          ? MonitorStatus.ready
          : notReady.contains(n)
          ? MonitorStatus.notReady
          : MonitorStatus.notApplicable,
  };
}

const _stdReady = [
  'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
  'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT',
];

enum _Powertrain { spark, mildHybrid, ev }

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
    required this.powertrain,
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
    required this.freeze,
    this.atrvEveryPoll = false,
  });

  final String name;
  final String protocol;
  final String protocolName;
  final _ProfileCar Function() build;
  final Duration connectMax;
  final Map<String, double?> live;
  final List<String> dtcs;
  final String? obdVin;
  final String plateVin;
  final String make;
  final String year;
  final String country;
  final _Powertrain powertrain;
  final bool milOn;
  final int dtcCount;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freeze;

  /// No 0142: the adapter's ATRV (a real voltage) is read on every poll.
  final bool atrvEveryPoll;
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

// 1. Geely Emgrand EC7 2013, 1.8 (JL4G18), China 4 / GCC. UNVERIFIED: the
//    protocol of 2010–2014 Geely ECUs (Delphi MT20U2 / UAES M7.9.7 era) isn't
//    documented publicly; Chinese ECUs of that generation commonly use
//    ISO 14230-4 KWP2000 fast init on the K-line (ELM protocol 5) — modelled
//    here. Reduced PID set (nothing above 0x1C → no 0142, so the adapter's
//    ATRV is used). VIN: WMI L6T + VDS "7824S" from a real EC7 VIN
//    (L6T7824S1GN055117), 'D' = 2013.
final _ec7Vin = _vin('L6T7824S?DN012345');
final _ec7 = _Vehicle(
  name: 'Geely Emgrand EC7 2013 (1.8, K-line)',
  protocol: '5',
  protocolName: 'ISO 14230-4 KWP fast init',
  build: () => _profile(
    protocol: '5',
    kLine: true,
    ecuLatency: const Duration(milliseconds: 150),
    autoSearchTime: const Duration(milliseconds: 7500),
    adapterVoltage: '14.1V',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '83 07 65 04', // MIL on, 3 DTCs; evap incomplete
          0x03: '02 00',
          0x04: '4D', // 30.2 %
          0x05: '7E', // 86 °C
          0x06: '82', // +1.6 %
          0x07: '7C', // −3.1 %
          0x0B: '22', // 34 kPa
          0x0C: '0C 1C', // 775 rpm
          0x0D: '00',
          0x0E: '8E', // +7°
          0x0F: '52', // 42 °C
          0x11: '24', // 14.1 %
          0x13: '03',
          0x14: '78 80', // 0.60 V
          0x15: '96 FF', // 0.75 V
          0x1C: '06', // EOBD (UNVERIFIED for China 4)
        },
        other: {
          // ISO 14230-4: 3 codes per message, no count byte.
          '03': '43 01 30 15 45 03 00', // P0130, P1545, P0300
          '07': '47 01 71 00 00 00 00', // P0171
          '0902': _kLineVinReply(_ec7Vin), // UNVERIFIED (see variant)
          ..._ffReplies(
            rpm: '0F A0', speed: '1E', coolant: '7D', load: '4D', //
            iat: '50', tps: '26', trim: '8F', map: '28',
          ),
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 12),
  atrvEveryPoll: true,
  live: _live({
    'rpm': 775,
    'speedKmh': 0,
    'coolantTempC': 86,
    'throttlePct': 14.118,
    'engineLoad': 30.196,
    'batteryVoltage': 14.1, // ATRV
    'fuelTrimShortPct': 1.5625,
    'fuelTrimLongPct': -3.125,
    'o2B1S1Voltage': 0.60,
    'o2B1S2Voltage': 0.75,
    'intakeAirTempC': 42,
    'mapKpa': 34,
    'timingAdvanceDeg': 7,
  }),
  dtcs: ['P0130', 'P1545', 'P0300', '~P0171'],
  obdVin: _ec7Vin,
  plateVin: _ec7Vin,
  make: 'Geely',
  year: '2013',
  country: 'China',
  powertrain: _Powertrain.spark,
  milOn: true,
  dtcCount: 3,
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
    'Coolant': '85°C',
    'Engine Load': '30.2%',
    'Air Temp': '40°C',
    'Throttle': '14.9%',
    'Fuel Trim': '11.7%',
    'MAP': '40 kPa',
  },
);

// 2. Geely Emgrand 2022 (4th gen, SS11), 1.5 NA MPI (BHE15) + CVT, GCC.
//    CAN 11/500 (China 6). ECM + TCM. Narrow-band upstream O2 (UNVERIFIED),
//    no fuel level 0x2F / oil temp 0x5C from the ECM (UNVERIFIED — cluster
//    owns the fuel gauge on many Chinese cars).
final _emgrandVin = _vin('L6T78F4E?NN123456');
_ProfileCar _emgrandCar() => _profile(
  protocol: '6',
  ecuLatency: const Duration(milliseconds: 80),
  ecus: [
    _Ecu(
      mode01: {
        0x01: '81 07 E5 00', // MIL on, 1 DTC
        0x03: '02 00',
        0x04: '40', // 25.1 %
        0x05: '82', // 90 °C
        0x06: '7E', // −1.6 %
        0x07: '83', // +2.3 %
        0x0B: '20', // 32 kPa
        0x0C: '0D 48', // 850 rpm
        0x0D: '00',
        0x0E: '8C', // +6°
        0x0F: '55', // 45 °C
        0x11: '1F', // 12.2 %
        0x13: '03',
        0x14: '2D 80', // 0.225 V
        0x15: '9B FF', // 0.775 V
        0x1C: '06',
        0x1F: '01 2C',
        0x21: '00 00',
        0x2E: '00',
        0x30: '0C',
        0x31: '01 F4',
        0x33: '64',
        0x3C: '0F A0',
        0x42: '36 B0', // 14.0 V
        0x44: '80 00',
        0x46: '55',
        0x49: '22', // 13.3 %
        0x4C: '1F',
      },
      other: {
        '03': '43 01 04 20', // P0420
        '07': '47 00',
        '0902': _canVinReply(_emgrandVin),
        ..._ffReplies(
          rpm: '1F 40', speed: '50', coolant: '85', load: '4D', //
          iat: '55', tps: '1F', trim: '80', map: '2D',
        ),
      },
    ),
    const _Ecu(
      mode01: {0x01: '00 04 00 00', 0x0D: '00'},
      other: {'03': '43 00', '07': '47 01 C1 00'}, // TCM: U0100 pending
    ),
  ],
);
final _emgrand = _Vehicle(
  name: 'Geely Emgrand 2022 (1.5 MPI, CVT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _emgrandCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 850,
    'speedKmh': 0,
    'coolantTempC': 90,
    'throttlePct': 12.157,
    'engineLoad': 25.098,
    'batteryVoltage': 14.0,
    'fuelTrimShortPct': -1.5625,
    'fuelTrimLongPct': 2.34375,
    'o2B1S1Voltage': 0.225,
    'o2B1S2Voltage': 0.775,
    'intakeAirTempC': 45,
    'mapKpa': 32,
    'timingAdvanceDeg': 6,
    'acceleratorPedalPct': 13.333,
  }),
  dtcs: ['P0420', '~U0100'],
  obdVin: _emgrandVin,
  plateVin: _emgrandVin,
  make: 'Geely',
  year: '2022',
  country: 'China',
  powertrain: _Powertrain.spark,
  milOn: true,
  dtcCount: 1,
  monitors: _monitors(ready: _stdReady),
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '80 km/h',
    'Coolant': '93°C',
    'Engine Load': '30.2%',
    'Air Temp': '45°C',
    'Throttle': '12.2%',
    'Fuel Trim': '0.0%',
    'MAP': '45 kPa',
  },
);

// 3. Geely Tugella 2022 (FY11), 2.0TD GDI (JLH-4G20TD, Drive-E derived) +
//    Aisin 8AT. CAN 11/500. GDI → fuel rail pressure 0x23 and a wide-band
//    upstream sensor on 0x24 (λ + voltage) — both UNVERIFIED for this ECU.
final _tugellaVin = _vin('L6T79R2E?NN012345');
final _tugella = _Vehicle(
  name: 'Geely Tugella 2022 (2.0TD GDI, 8AT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 00', // MIL on, 2 DTCs
          0x03: '02 00',
          0x04: '52', // 32.2 %
          0x05: '87', // 95 °C
          0x06: '84', // +3.1 %
          0x07: '7E', // −1.6 %
          0x0B: '78', // 120 kPa boost
          0x0C: '1A F4', // 1725 rpm
          0x0D: '46', // 70 km/h
          0x0E: '96', // +11°
          0x0F: '4E', // 38 °C
          0x10: '05 DC',
          0x11: '2E', // 18.0 %
          0x13: '03',
          0x15: 'A0 FF', // 0.80 V
          0x1C: '06',
          0x1F: '04 B0',
          0x21: '00 1E',
          0x23: '05 DC', // 15 000 kPa = 15 MPa (GDI)
          0x24: '81 06 66 66', // λ 1.008
          0x2E: '00',
          0x2F: 'A6', // 65.1 %
          0x30: '08',
          0x31: '03 20',
          0x33: '64',
          0x3C: '12 C0',
          0x42: '38 A4', // 14.5 V
          0x44: '80 00',
          0x45: '20',
          0x46: '4E',
          0x47: '2E',
          0x49: '2E', // 18.0 %
          0x4A: '17',
          0x4C: '2E',
          0x5C: '87', // 95 °C oil
        },
        other: {
          '03': '43 02 02 99 16 90', // P0299, P1690
          '07': '47 00',
          '0902': _canVinReply(_tugellaVin),
          ..._ffReplies(
            rpm: '27 10', speed: '5A', coolant: '8A', load: 'E6', //
            iat: '64', tps: 'CC', trim: '7A', map: '82',
          ),
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '46'},
        other: {'03': '43 00', '07': '47 01 07 41'}, // TCM: P0741 pending
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 1725,
    'speedKmh': 70,
    'coolantTempC': 95,
    'throttlePct': 18.039,
    'fuelLevelPct': 65.098,
    'engineLoad': 32.157,
    'batteryVoltage': 14.5,
    'oilTempC': 95,
    'fuelTrimShortPct': 3.125,
    'fuelTrimLongPct': -1.5625,
    'o2B1S2Voltage': 0.80,
    'intakeAirTempC': 38,
    'mapKpa': 120,
    'timingAdvanceDeg': 11,
    'lambdaB1S1': 1.00800,
    'fuelRailPressureKpa': 15000,
    'acceleratorPedalPct': 18.039,
  }),
  dtcs: ['P0299', 'P1690', '~P0741'],
  obdVin: _tugellaVin,
  plateVin: _tugellaVin,
  make: 'Geely',
  year: '2022',
  country: 'China',
  powertrain: _Powertrain.spark,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: _stdReady),
  freeze: {
    'RPM': '2500 rpm',
    'Speed': '90 km/h',
    'Coolant': '98°C',
    'Engine Load': '90.2%',
    'Air Temp': '60°C',
    'Throttle': '80.0%',
    'Fuel Trim': '-4.7%',
    'MAP': '130 kPa',
  },
);

// 4. Geely Monjaro 2023 (KX11, Xingyue L), 2.0TD (JLH-4G20TDB) + Aisin 8AT,
//    GCC. CAN 11/500. Wide-band upstream on 0x34 (λ + current), no 0x23
//    (UNVERIFIED). ECM has 3 confirmed codes → ISO-TP multi-frame; TCM has
//    P0700 (MIL request). WMI LB3 (seen on Russian-market Monjaro listings).
final _monjaroVin = _vin('LB37624T?PN012345');
_ProfileCar _monjaroCar({String? clearReply}) => _profile(
  protocol: '6',
  ecuLatency: const Duration(milliseconds: 80),
  clearReply: clearReply,
  ecus: [
    _Ecu(
      mode01: {
        0x01: '83 07 E5 01', // MIL on, 3 DTCs; catalyst incomplete
        0x03: '02 00',
        0x04: '38', // 22.0 %
        0x05: '85', // 93 °C
        0x06: '80',
        0x07: '82', // +1.6 %
        0x0B: '25', // 37 kPa
        0x0C: '0C E4', // 825 rpm
        0x0D: '00',
        0x0E: '90', // +8°
        0x0F: '5F', // 55 °C (Gulf summer)
        0x10: '01 90',
        0x11: '14', // 7.8 %
        0x13: '03',
        0x15: '8C FF', // 0.70 V
        0x1C: '06',
        0x1F: '00 B4',
        0x21: '00 00',
        0x2E: '00',
        0x2F: 'E6', // 90.2 %
        0x30: '04',
        0x31: '00 64',
        0x33: '64',
        0x34: '7E 00 80 00', // λ 0.984
        0x3C: '0F A0',
        0x42: '37 DC', // 14.3 V
        0x44: '80 00',
        0x46: '5F',
        0x49: '1A', // 10.2 %
        0x4C: '14',
        0x5C: '7A', // 82 °C oil
      },
      other: {
        '07': '47 01 D0 01', // U1001 pending
        '0902': _canVinReply(_monjaroVin),
        ..._ffReplies(
          rpm: '0C E4', speed: '00', coolant: '3C', load: '40', //
          iat: '46', tps: '0D', trim: '85', map: '28',
        ),
      },
    ),
    const _Ecu(
      mode01: {0x01: '81 04 00 00', 0x0D: '00'}, // TCM: MIL request, 1 DTC
      other: {'07': '47 00'},
    ),
  ],
  overrides: {
    // ECM: 3 codes in an ISO-TP multi-frame (padding AA, UNVERIFIED), then
    // the TCM's single frame.
    '03':
        '008\n'
        '0: 43 03 00 16 03 00\n'
        '1: 13 36 AA AA AA AA AA\n'
        '43 01 07 00',
  },
);
final _monjaro = _Vehicle(
  name: 'Geely Monjaro 2023 (2.0TD, 8AT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _monjaroCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 825,
    'speedKmh': 0,
    'coolantTempC': 93,
    'throttlePct': 7.843,
    'fuelLevelPct': 90.196,
    'engineLoad': 21.961,
    'batteryVoltage': 14.3,
    'oilTempC': 82,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 1.5625,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 55,
    'mapKpa': 37,
    'timingAdvanceDeg': 8,
    'lambdaB1S1': 0.984375,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P0016', 'P0300', 'P1336', 'P0700', '~U1001'],
  obdVin: _monjaroVin,
  plateVin: _monjaroVin,
  make: 'Geely',
  year: '2023',
  country: 'China',
  powertrain: _Powertrain.spark,
  milOn: true,
  dtcCount: 4, // 3 (ECM) + 1 (TCM)
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Evap System', 'O2 Sensor', //
      'O2 Sensor Heater', 'EGR / VVT',
    ],
    notReady: ['Catalyst'],
  ),
  freeze: {
    'RPM': '825 rpm',
    'Speed': '0 km/h',
    'Coolant': '20°C',
    'Engine Load': '25.1%',
    'Air Temp': '30°C',
    'Throttle': '5.1%',
    'Fuel Trim': '3.9%',
    'MAP': '40 kPa',
  },
);

// 5. Geely Okavango 2021 (VX11), 1.5TD 3-cyl (JLH-3G15TD) + 48 V BSG mild
//    hybrid, 7DCT. CAN 11/500. ECM reports fuel type 0x51 = 01 (gasoline —
//    UNVERIFIED whether an MHEV reports 01 or 0x11 hybrid gasoline); a
//    48 V hybrid/BSG controller answers functional requests with 0x5B
//    (battery pack SoC) and a pending P0AFA — UNVERIFIED. Engine auto-stop
//    at idle is normal (rpm 0 with ignition on).
final _okavangoVin = _vin('L6T75V2E?MN012345');
const _okavangoEcm = {
  0x01: '00 07 E5 20', // MIL off; O2 sensor monitor incomplete
  0x03: '02 00',
  0x04: '2E', // 18.0 %
  0x05: '80', // 88 °C
  0x06: '7F', // −0.8 %
  0x07: '80',
  0x0B: '1F', // 31 kPa
  0x0C: '0B 54', // 725 rpm
  0x0D: '00',
  0x0E: '86', // +3°
  0x0F: '5A', // 50 °C
  0x10: '01 2C',
  0x11: '10', // 6.3 %
  0x13: '03',
  0x15: '87 FF', // 0.675 V
  0x1C: '06',
  0x1F: '02 58',
  0x21: '00 00',
  0x2E: '00',
  0x2F: '73', // 45.1 %
  0x30: '20',
  0x31: '07 D0',
  0x33: '64',
  0x34: '80 00 80 00', // λ 1.000
  0x3C: '0F A0',
  0x42: '39 D0', // 14.8 V (DC/DC from the 48 V side)
  0x44: '80 00',
  0x46: '5A',
  0x49: '1A',
  0x4C: '10',
  0x51: '01', // fuel type: gasoline
  0x5C: '78', // 80 °C
};
_ProfileCar _okavangoCar({Map<String, List<String>> sequences = const {}}) =>
    _profile(
      protocol: '6',
      ecuLatency: const Duration(milliseconds: 80),
      sequences: sequences,
      ecus: [
        _Ecu(
          mode01: _okavangoEcm,
          other: {
            '03': '43 00',
            '07': '47 00',
            '0902': _canVinReply(_okavangoVin),
          },
        ),
        const _Ecu(
          mode01: {0x01: '00 04 00 00', 0x5B: '9C'}, // 61.2 % SoC (48 V)
          other: {'03': '43 00', '07': '47 01 0A FA'}, // P0AFA pending
        ),
      ],
    );
final _okavango = _Vehicle(
  name: 'Geely Okavango 2021 (1.5TD 48V MHEV)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _okavangoCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 725,
    'speedKmh': 0,
    'coolantTempC': 88,
    'throttlePct': 6.275,
    'fuelLevelPct': 45.098,
    'engineLoad': 18.039,
    'batteryVoltage': 14.8,
    'oilTempC': 80,
    'fuelTrimShortPct': -0.78125,
    'fuelTrimLongPct': 0,
    'o2B1S2Voltage': 0.675,
    'intakeAirTempC': 50,
    'mapKpa': 31,
    'timingAdvanceDeg': 3,
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['~P0AFA'],
  obdVin: _okavangoVin,
  plateVin: _okavangoVin,
  make: 'Geely',
  year: '2021',
  country: 'China',
  powertrain: _Powertrain.mildHybrid,
  milOn: false,
  dtcCount: 0,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
      'O2 Sensor Heater', 'EGR / VVT',
    ],
    notReady: ['O2 Sensor'],
  ),
  freeze: const {},
);

// 6. Geometry C 2022 (Geely BEV, 70 kWh). UNVERIFIED either way: China 6 OBD
//    rules don't cover BEVs, and several Chinese BEVs' OBD ports answer no
//    J1979 request at all (modelled in the "EV, silent OBD port" group). This
//    profile is the other documented-in-the-wild case: a VCU answering a
//    J1979 subset — 0101 all zero (no emission monitors), speed, module
//    voltage, ambient temp, fuel type 0x51 = 08 (electric), 0x5B SoC — and a
//    pending P0AA6 (HV isolation fault). WMI LB3 (Geometry under LB3,
//    Wikibooks).
final _geometryVin = _vin('LB37752Z?NH012345');
final _geometry = _Vehicle(
  name: 'Geometry C 2022 (BEV, VCU answers J1979 subset)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '00 00 00 00',
          0x0D: '32', // 50 km/h
          0x42: '36 B0', // 14.0 V (DC/DC)
          0x46: '55',
          0x51: '08', // electric
          0x5B: 'B3', // 70.2 % SoC
        },
        other: {
          '03': '43 00',
          '07': '47 01 0A A6', // P0AA6 pending
          '0902': _canVinReply(_geometryVin),
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({'speedKmh': 50, 'batteryVoltage': 14.0}),
  dtcs: ['~P0AA6'],
  obdVin: _geometryVin,
  plateVin: _geometryVin,
  make: 'Geely',
  year: '2022',
  country: 'China',
  powertrain: _Powertrain.ev,
  milOn: false,
  dtcCount: 0,
  monitors: _monitors(),
  freeze: const {},
);

// 7. Lynk & Co 01 2023, 2.0TD (Drive-E VEP4 derived) + 8AT, GCC. CAN 11/500.
//    WMI L6T + VDS "CX2E7" from real 01 VINs (L6TCX2E71NE030436…). ECM
//    advertises BOTH 0x24 and 0x34 and no 0x14 (UNVERIFIED) → the app must
//    pick 0x24. ECM + TCM both answer 0902 (Volvo-style, UNVERIFIED). A
//    chassis module and a body module answering functional 03 with C/B
//    codes are UNVERIFIED (seen on some CAN cars; modelled to exercise
//    C1xxx / B1xxx handling).
final _lynkVin = _vin('L6TCX2E7?PE012345');
final _lynk = _Vehicle(
  name: 'Lynk & Co 01 2023 (2.0TD, 8AT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 90),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 00', // MIL on, 2 DTCs
          0x03: '02 00',
          0x04: '33', // 20.0 %
          0x05: '83', // 91 °C
          0x06: '81', // +0.8 %
          0x07: '7D', // −2.3 %
          0x0B: '23', // 35 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8A', // +5°
          0x0F: '50', // 40 °C
          0x10: '01 90',
          0x11: '0D', // 5.1 %
          0x13: '03',
          0x15: '91 FF', // 0.725 V
          0x1C: '06',
          0x1F: '00 78',
          0x21: '00 00',
          0x23: '07 D0', // 20 000 kPa = 20 MPa
          0x24: '7F 80 66 66', // λ 0.996
          0x2E: '00',
          0x2F: 'CC', // 80.0 %
          0x30: '0F',
          0x31: '02 58',
          0x33: '64',
          0x34: '7F 80 80 00', // same λ via current
          0x3C: '0F A0',
          0x42: '37 14', // 14.1 V
          0x44: '80 00',
          0x46: '50',
          0x49: '1C', // 11.0 %
          0x4C: '0D',
          0x5C: '73', // 75 °C
        },
        other: {
          '03': '43 02 04 20 13 00', // P0420, P1300
          '07': '47 00',
          '0902': _canVinReply(_lynkVin),
          ..._ffReplies(
            rpm: '1F 40', speed: '64', coolant: '87', load: '4D', //
            iat: '50', tps: '26', trim: '7E', map: '32',
          ),
        },
      ),
      _Ecu(
        mode01: const {0x01: '00 04 00 00', 0x0D: '00'},
        other: {'03': '43 00', '07': '47 00', '0902': _canVinReply(_lynkVin)},
      ),
      const _Ecu(other: {'03': '43 01 50 01', '07': '47 00'}), // C1001
      const _Ecu(other: {'03': '43 01 93 18', '07': '47 00'}), // B1318
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 91,
    'throttlePct': 5.098,
    'fuelLevelPct': 80.0,
    'engineLoad': 20.0,
    'batteryVoltage': 14.1,
    'oilTempC': 75,
    'fuelTrimShortPct': 0.78125,
    'fuelTrimLongPct': -2.34375,
    'o2B1S2Voltage': 0.725,
    'intakeAirTempC': 40,
    'mapKpa': 35,
    'timingAdvanceDeg': 5,
    'lambdaB1S1': 0.99609,
    'fuelRailPressureKpa': 20000,
    'acceleratorPedalPct': 10.980,
  }),
  dtcs: ['P0420', 'P1300', 'C1001', 'B1318'],
  obdVin: _lynkVin,
  plateVin: _lynkVin,
  // L6T is shared by Geely, Lynk & Co and Zeekr: the WMI alone can only
  // say "Geely".
  make: 'Geely',
  year: '2023',
  country: 'China',
  powertrain: _Powertrain.spark,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: _stdReady),
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '100 km/h',
    'Coolant': '95°C',
    'Engine Load': '30.2%',
    'Air Temp': '40°C',
    'Throttle': '14.9%',
    'Fuel Trim': '-1.6%',
    'MAP': '50 kPa',
  },
);

// 8. Proton X70 2021 (CKD, Tanjung Malim), 1.8 TGDi (Geely JLE-4G18TD) +
//    7DCT. Geely Boyue-based. CAN 11/500. WMI PL1 = Proton, Malaysia
//    (Wikibooks). UNVERIFIED: whether Proton uses position 10 as the model
//    year (the app reports 'Unknown' for the Malaysia region, which is the
//    safe answer) and whether the ECU is coded with the PL1 VIN. The ECU
//    stores no MAP in its freeze frame (020B00 NO DATA, UNVERIFIED).
final _x70Vin = _vin('PL1BT6KN?MB012345');
final _x70 = _Vehicle(
  name: 'Proton X70 2021 (1.8 TGDi, CKD Malaysia)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 E5 00', // MIL on, 2 DTCs
          0x03: '02 00',
          0x04: '3A', // 22.7 %
          0x05: '84', // 92 °C
          0x06: '80',
          0x07: '84', // +3.1 %
          0x0B: '22', // 34 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '5A', // 50 °C
          0x11: '1A', // 10.2 %
          0x13: '03',
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x1F: '00 5A',
          0x21: '00 00',
          0x23: '03 E8', // 10 000 kPa
          0x2E: '00',
          0x2F: '99', // 60.0 %
          0x30: '05',
          0x31: '01 2C',
          0x33: '64',
          0x34: '80 00 80 00', // λ 1.000
          0x3C: '0F A0',
          0x42: '37 78', // 14.2 V
          0x44: '80 00',
          0x46: '5A',
          0x49: '1A', // 10.2 %
          0x4C: '1A',
        },
        other: {
          '03': '43 02 03 01 16 02', // P0301, P1602
          '07': '47 00',
          '0902': _canVinReply(_x70Vin),
          ..._ffReplies(
            rpm: '0C 80', speed: '00', coolant: '7D', load: '40', //
            iat: '5A', tps: '1A', trim: '79',
          ),
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00', 0x0D: '00'},
        other: {'03': '43 00', '07': '47 00'},
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 92,
    'throttlePct': 10.196,
    'fuelLevelPct': 60.0,
    'engineLoad': 22.745,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 3.125,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 34,
    'timingAdvanceDeg': 6,
    'lambdaB1S1': 1.0,
    'fuelRailPressureKpa': 10000,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P0301', 'P1602'],
  obdVin: _x70Vin,
  plateVin: _x70Vin,
  make: 'Proton',
  year: VinDecoder.unknown,
  country: 'Malaysia',
  powertrain: _Powertrain.spark,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: _stdReady),
  freeze: {
    'RPM': '800 rpm',
    'Speed': '0 km/h',
    'Coolant': '85°C',
    'Engine Load': '25.1%',
    'Air Temp': '50°C',
    'Throttle': '10.2%',
    'Fuel Trim': '-5.5%',
  },
);

final _vehicles = [
  _ec7,
  _emgrand,
  _tugella,
  _monjaro,
  _okavango,
  _geometry,
  _lynk,
  _x70,
];

// ── Test helpers ──────────────────────────────────────────────────────────────

/// The 18 regular live PIDs in the order ProductionOBDAdapter._poll sends them.
const _pollOrder = [
  '010C', '010D', '0105', '0111', '012F', '0104', '0142', '015C', '0106', //
  '0107', '0108', '0109', '0114', '0115', '0118', '010F', '010B', '010E',
];

int _pidOf(String cmd) => int.parse(cmd.substring(2), radix: 16);

/// Mode 01 PIDs [car]'s 0100 / 0120 / 0140 bitmaps advertise, ORed over every
/// ECU line, following the J1979 chain.
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

/// Live requests poll number [poll] must send for the advertised [adv] PIDs:
/// regular PIDs in poll order, ATRV in the 0142 slot when 0142 isn't
/// advertised (every poll when the adapter answers a real voltage, else only
/// the first two), then 0124 (else 0134) only without 0114, 0123, 0149.
List<String> _expectedPolled(
  Set<int> adv, {
  bool atrvEveryPoll = false,
  int poll = 1,
}) {
  final reg = _pollOrder.where((p) => adv.contains(_pidOf(p)));
  return [
    for (final p in _pollOrder)
      if (p == '0142' && !reg.contains(p)) ...[
        if (atrvEveryPoll || poll <= 2) 'ATRV',
      ] else if (reg.contains(p))
        p,
    if (!adv.contains(0x14) && adv.contains(0x24)) '0124',
    if (!adv.contains(0x14) && !adv.contains(0x24) && adv.contains(0x34))
      '0134',
    if (adv.contains(0x23)) '0123',
    if (adv.contains(0x49)) '0149',
  ];
}

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
  final a = rig.adapter;
  final e = rig.elm;
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

void _expectLive(Map<String, double?> actual, Map<String, double?> expected) {
  for (final k in _liveKeys) {
    final e = expected[k];
    expect(actual[k], e == null ? isNull : closeTo(e, 0.01), reason: k);
  }
}

const _manufacturerRange =
    r'^(?:P1[0-9A-F]{3}|P3[0-3][0-9A-F]{2}|[BCU][12][0-9A-F]{3})$';

/// What a correct description looks like: non-empty, and for codes in a
/// manufacturer-controlled range, flagged as manufacturer-specific (their
/// meaning differs per brand, so another brand's text must not be shown as
/// if it applied to this car).
void _expectGoodDescription(String code, String? desc) {
  expect(desc, isNotNull, reason: '$code has no description');
  expect(desc!.trim(), isNotEmpty, reason: code);
  if (RegExp(_manufacturerRange).hasMatch(code)) {
    expect(desc, contains('Manufacturer-specific'), reason: '$code → $desc');
  }
}

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // DtcRepository: offline (connectivity "none"), empty preferences.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, (call) async {
      if (call.method == 'check') return ['none'];
      return null;
    });
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DtcRepository.resetCaches();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    // ignore: avoid_print
    print('\n== Geely-group compatibility measurements ==\n'
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
          expect(rig.adapter.connectionState, OBDConnectionState.connected);
          expect(rig.elm.activeProtocol, v.protocol);
          expect(dt, lessThan(v.connectMax));
        }, connect: false);
      });

      test('(b) one live poll: exact command sequence, every advertised PID '
          'decoded, unsupported → null, poll < 3 s, refresh every 3 s', () {
        final car = v.build();
        final adv = _advertised(car);
        sim(car, (rig) {
          final p = _poll(rig);
          final supported = v.live.values.where((x) => x != null).length;
          _log('${v.name}: poll ${_secs(p.cycle)} s ($supported values, '
              '${p.polled.length} requests: ${p.polled.join(' ')}), '
              'refresh every ${_secs(p.period)} s');
          expect(p.firstCycle.where(_isBitmapReq), _expectedBitmapReqs(adv));
          expect(
            p.polled,
            _expectedPolled(adv, atrvEveryPoll: v.atrvEveryPoll),
          );
          _expectLive(p.first, v.live);
          _expectLive(p.second, v.live);
          expect(p.cycle, lessThan(const Duration(seconds: 3)));
          expect(p.period, lessThan(const Duration(milliseconds: 3100)));
          // 3 s timer; frame 1 → 2 is a little shorter only because the
          // first poll also read the 0120 / 0140 bitmaps.
          expect(p.period, greaterThan(const Duration(milliseconds: 2500)));
          expect(p.secondCycle.where(_isBitmapReq), isEmpty);
          expect(
            p.secondCycle,
            _expectedPolled(adv, atrvEveryPoll: v.atrvEveryPoll, poll: 2),
          );
        });
      });

      test('(c) DTCs: confirmed (mode 03) + pending (mode 07)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      for (final c in [for (final c in v.dtcs) c.replaceFirst('~', '')]) {
        test('(c) DtcRepository describes $c correctly', () async {
          final d = await DtcRepository().getDtcDescription(c);
          _log('${v.name}: $c → $d');
          _expectGoodDescription(c, d);
        });
      }

      test('(c) clear (mode 04 → 44) → true, no codes, no freeze frame', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
          expect(rig.elm.commands.last, '04');
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
        });
      });

      test('(c) clear refused (7F 04 22 conditionsNotCorrect) → false, '
          'codes kept', () {
        sim(_variant(v.build(), clearReply: '7F 04 22'), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(d) VIN via 0902 → country ${v.country}, model year ${v.year}',
          () {
        sim(v.build(), (rig) {
          final vin = rig.drive(rig.adapter.getVin());
          _log('${v.name}: getVin() → $vin');
          expect(vin, v.obdVin);
          if (vin == null) return;
          expect(_checkDigit(vin), vin[8], reason: 'profile VIN check digit');
          final d = VinDecoder.decode(vin, now: _now);
          _log('${v.name}: VinDecoder → $d');
          expect(d['country'], v.country);
          expect(d['year'], v.year);
        });
      });

      test('(d) VinDecoder maker for WMI ${v.plateVin.substring(0, 3)} → '
          '${v.make}', () {
        final d = VinDecoder.decode(v.plateVin, now: _now);
        expect(d['manufacturer'], contains(v.make));
      });

      test('(e) readiness monitors (${v.powertrain.name})', () {
        sim(v.build(), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.compressionIgnition, isFalse);
          expect({for (final m in r.monitors) m.name: m.status}, v.monitors);
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

  // ── Brand-specific edge cases ──────────────────────────────────────────────

  group('Emgrand EC7 2013 (K-line)', () {
    test('CAN 11/500 attempt answers CAN ERROR, then the auto search finds '
        'KWP: exact connect sequence', () {
      sim(_ec7.build(), (rig) {
        rig.connect();
        expect(rig.elm.commands, [
          'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100', 'ATSP0', '0100', //
        ]);
        expect(rig.elm.activeProtocol, '5');
      }, connect: false);
    });

    test('no 0120: the 0x21+ range is never requested, ATRV every poll', () {
      sim(_ec7.build(), (rig) {
        final p = _poll(rig);
        expect(p.firstCycle, isNot(contains('0120')));
        expect(p.firstCycle.where((c) => c == 'ATRV'), hasLength(1));
        expect(p.secondCycle.where((c) => c == 'ATRV'), hasLength(1));
        expect(p.first['batteryVoltage'], closeTo(14.1, 0.001));
      });
    });

    test('ECU without mode 09 → getVin() null, DTCs undisturbed', () {
      sim(_variant(_ec7.build(), replies: {'0902': null}), (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
        expect(rig.drive(rig.adapter.getDtcs()), _ec7.dtcs);
      });
    });

    test('clone adapter without ATRV ("?") → batteryVoltage null, ATRV '
        'dropped after two polls', () {
      final base = _ec7.build();
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
        final p = _poll(rig);
        expect(p.first['batteryVoltage'], isNull);
        expect(p.firstCycle, contains('ATRV'));
        final third = rig.elm.commands.length;
        // A third poll: no ATRV any more.
        rig.adapter.startLiveData();
        rig.async.elapse(const Duration(milliseconds: 4500));
        rig.adapter.stopLiveData();
        expect(rig.elm.commands.sublist(third), isNot(contains('ATRV')));
      });
    });

    test('VinDecoder: WMI L10 (Geely Emgrand brand, 2009–2014) → Geely', () {
      final d = VinDecoder.decode(_vin('L10M2E2C?DA012345'), now: _now);
      expect(d['country'], 'China');
      expect(d['year'], '2013');
      expect(d['manufacturer'], contains('Geely'));
    });
  });

  group('Emgrand 2022', () {
    test('TCM pending U0100 (lost comm with ECM) is labelled pending', () {
      sim(_emgrandCar(), (rig) {
        final codes = rig.drive(rig.adapter.getDtcs());
        expect(codes.where((c) => c.startsWith('~')), ['~U0100']);
      });
    });
  });

  group('Monjaro 2023', () {
    test('engine running: ECM refuses mode 04 (7F 04 22), TCM accepts '
        '(44) → false, codes kept', () {
      sim(_monjaroCar(clearReply: '7F 04 22\n44'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _monjaro.dtcs);
      });
    });

    test('gateway answers the first 0100 with 7F 01 78 (responsePending) '
        'before the bitmaps → connect OK, bitmap parsed', () {
      final base = _monjaroCar();
      final car = _variant(
        base,
        replies: {'0100': '7F 01 78\n${base.responses['0100']}'},
      );
      final adv = _advertised(base);
      sim(car, (rig) {
        rig.connect();
        expect(rig.adapter.isConnected, isTrue);
        final p = _poll(rig);
        expect(p.polled, _expectedPolled(adv));
        _expectLive(p.first, _monjaro.live);
      }, connect: false);
    });

    test('VinDecoder: LB3 window VIN → Geely / China / 2023', () {
      final d = VinDecoder.decode(_monjaroVin, now: _now);
      expect(d['manufacturer'], 'Geely');
      expect(d['country'], 'China');
      expect(d['year'], '2023');
    });
  });

  group('Okavango 48V MHEV', () {
    test('engine auto-stop between polls → rpm 0 shown (not the previous '
        'value), speed 0; hybrid PIDs 0151 / 015B never polled', () {
      sim(
        _okavangoCar(
          sequences: {
            '010C': ['41 0C 0B 54', '41 0C 00 00'],
          },
        ),
        (rig) {
          final p = _poll(rig);
          expect(p.first['rpm'], 725);
          expect(p.second['rpm'], 0);
          expect([...p.firstCycle, ...p.secondCycle],
              isNot(anyOf(contains('0151'), contains('015B'))));
        },
      );
    });

    test('hybrid controller\'s bitmap lines (0x5B only) merge with the ECM\'s '
        '→ ECM PIDs still polled', () {
      final car = _okavangoCar();
      expect(car.responses['0140']!.split('\n'), hasLength(2));
      expect(_advertised(car), containsAll([0x42, 0x49, 0x5B, 0x5C]));
    });
  });

  group('Geometry C BEV', () {
    test('VCU subset: only 010D + 0142 polled, engine values null, '
        'readiness all N/A (no emission monitors)', () {
      sim(_geometry.build(), (rig) {
        final p = _poll(rig);
        expect(p.polled, ['010D', '0142']);
        expect(p.first['rpm'], isNull);
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.monitors.every((m) => !m.isApplicable), isTrue);
        expect(r.milOn, isFalse);
      });
    });

    // CAN 0100 → NO DATA (frame ACKed: bus awake), auto search → UNABLE TO
    // CONNECT (not NO DATA), and this clone answers ATRV with "?" → nothing
    // confirms the car is ON, so classifySilentEcu stays on ecuNotResponding
    // (the "switch to READY" advice). ATRV is now asked once in exactly this
    // ambiguous case, hence the trailing 'ATRV'.
    test('silent OBD port (no ECU answers J1979 on any protocol) → '
        'OBDConnectException(ecuNotResponding) after CAN + full auto search '
        '+ one ATRV (unanswered), state failed, no half-open link', () {
      final car = _profile(protocol: null, ecus: const []);
      sim(car, (rig) {
        final t0 = rig.async.elapsed;
        Object? error;
        try {
          rig.connect();
        } catch (e) {
          error = e;
        }
        final dt = rig.async.elapsed - t0;
        _log('Geometry C (silent OBD port): connect failed after '
            '${_secs(dt)} s with $error; commands '
            '${rig.elm.commands.join(' ')}');
        expect(
          error,
          isA<OBDConnectException>().having(
            (e) => e.reason,
            'reason',
            OBDFailureReason.ecuNotResponding,
          ),
        );
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
        expect(rig.adapter.isConnected, isFalse);
        expect(rig.device.disconnectCalls, 1);
        expect(rig.elm.commands, [
          'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100', 'ATSP0', '0100', //
          'ATRV',
        ]);
        expect(dt, lessThan(const Duration(seconds: 10)));
      }, connect: false);
    });
  });

  group('Lynk & Co 01', () {
    test('0124 and 0134 both advertised, no 0114 → λ read from 0124 only', () {
      sim(_lynk.build(), (rig) {
        final p = _poll(rig);
        expect(p.polled, contains('0124'));
        expect(p.polled, isNot(contains('0134')));
        expect(p.first['lambdaB1S1'], closeTo(0.99609, 0.0001));
      });
    });

    test('ECM and TCM both answer 0902 with interleaved ISO-TP frames → '
        'one valid VIN', () {
      final b = [0x49, 0x02, 0x01, ..._lynkVin.codeUnits];
      String f(int i) => i == 0
          ? '0: ${_hx(b.sublist(0, 6))}'
          : i == 1
          ? '1: ${_hx(b.sublist(6, 13))}'
          : '2: ${_hx(b.sublist(13, 20))}';
      final interleaved =
          ['014', f(0), '014', f(0), f(1), f(1), f(2), f(2)].join('\n');
      sim(_variant(_lynk.build(), replies: {'0902': interleaved}), (rig) {
        expect(rig.drive(rig.adapter.getVin()), _lynkVin);
      });
    });

    test('four modules answer 03 (ECM multi-code + TCM empty + chassis C1001 '
        '+ body B1318) → all codes, ECM first', () {
      sim(_lynk.build(), (rig) {
        expect(rig.drive(rig.adapter.getDtcs()),
            ['P0420', 'P1300', 'C1001', 'B1318']);
      });
    });
  });

  group('Proton X70', () {
    test('freeze frame without MAP (020B00 NO DATA) → MAP omitted, the rest '
        'decoded', () {
      sim(_x70.build(), (rig) {
        final ff = rig.drive(rig.adapter.getFreezeFrame());
        expect(ff.containsKey('MAP'), isFalse);
        expect(ff, hasLength(7));
      });
    });

    test('VinDecoder: PL1 → country Malaysia; year not guessed', () {
      final d = VinDecoder.decode(_x70Vin, now: _now);
      expect(d['country'], 'Malaysia');
      expect(d['year'], VinDecoder.unknown);
    });
  });

  group('profile sanity', () {
    test('generated bitmaps match the answered PIDs', () {
      expect(_advertised(_ec7.build()).contains(0x20), isFalse);
      expect(_ec7.build().responses['0100'], startsWith('BUS INIT: ...OK\n'));
      expect(_advertised(_tugella.build()), containsAll([0x23, 0x24, 0x5C]));
      expect(_advertised(_geometry.build()), {0x01, 0x0D, 0x20, 0x40, 0x42, //
        0x46, 0x51, 0x5B});
      for (final v in _vehicles) {
        expect(_checkDigit(v.plateVin), v.plateVin[8], reason: v.name);
      }
    });
  });

  // ── Double-check: adversarial probes of the vin_decoder / obd_adapter /
  //    dtc_repository fixes for the Geely group ─────────────────────────────

  group('double-check', () {
    const years = {'D': '2013', 'L': '2020', 'M': '2021', 'P': '2023', //
      'S': '2025', 'V': '2027'};

    test('Geely WMIs L6T / LB3 / L10 → Geely + China + model year (six '
        'years each)', () {
      for (final wmi in ['L6T', 'LB3', 'L10']) {
        for (final y in years.entries) {
          final vin = _vin('${wmi}7624T?${y.key}N012345');
          final d = VinDecoder.decode(vin, now: _now);
          expect(d['manufacturer'], contains('Geely'), reason: vin);
          expect(d['country'], 'China', reason: vin);
          expect(d['year'], y.value, reason: vin);
        }
      }
    });

    test('Proton PL1 → Proton + Malaysia, year never guessed (any pos-10 '
        'char)', () {
      for (final y in years.keys) {
        final d = VinDecoder.decode(_vin('PL1BT6KN?${y}B012345'), now: _now);
        expect(d['manufacturer'], 'Proton');
        expect(d['country'], 'Malaysia');
        expect(d['year'], VinDecoder.unknown, reason: y);
      }
    });

    // getVin() on the Monjaro (CAN), 0902 replaced by [vin].
    String? obdVin(String vin) {
      String? got;
      sim(_variant(_monjaroCar(), replies: {'0902': _canVinReply(vin)}),
          (rig) => got = rig.drive(rig.adapter.getVin()));
      return got;
    }

    // A different VIN character with a different GB 16735 value.
    String garble(String c) {
      int val(String x) => int.tryParse(x) ?? _translit[x]!;
      return '0123456789ABCDEFGHJKLMNPRSTUVWXYZ'
          .split('')
          .firstWhere((x) => x != c && val(x) != val(c));
    }

    test('every Geely-group profile VIN is accepted intact from 0902', () {
      for (final v in _vehicles) {
        expect(obdVin(v.plateVin), v.plateVin, reason: v.name);
      }
      final l10 = _vin('L10M2E2C?DA012345');
      expect(obdVin(l10), l10);
    });

    test('Okavango / Geometry C / Lynk / Monjaro / Tugella / L10 VIN with '
        'one garbled character (positions 2–17) → getVin() null', () {
      for (final good in [_okavangoVin, _geometryVin, _lynkVin, _monjaroVin,
        _tugellaVin, _vin('L10M2E2C?DA012345')]) {
        for (var i = 1; i < 17; i++) {
          final bad = good.replaceRange(i, i + 1, garble(good[i]));
          expect(_checkDigit(bad) == bad[8], isFalse, reason: bad);
          expect(obdVin(bad), isNull, reason: 'position ${i + 1}: $bad');
        }
      }
    });

    test('Geely VIN with a letter (not X) at position 9 → null; a correct X '
        'check digit → accepted', () {
      for (final c in ['A', 'D', 'P', 'R']) {
        expect(obdVin(_lynkVin.replaceRange(8, 9, c)), isNull, reason: c);
      }
      var n = 0;
      late String x;
      do {
        x = _vin('L6TCX2E7?PE0123${(n++).toString().padLeft(2, '0')}');
      } while (x[8] != 'X');
      expect(obdVin(x), x);
    });

    test('EC7 K-line 5-message 0902 with a garbled byte → null, intact → '
        'VIN', () {
      final bad = _ec7Vin.replaceRange(13, 14, garble(_ec7Vin[13]));
      for (final (vin, want) in [(_ec7Vin, _ec7Vin), (bad, null)]) {
        sim(_variant(_ec7.build(), replies: {'0902': _kLineVinReply(vin)}),
            (rig) {
          expect(rig.drive(rig.adapter.getVin()), want, reason: vin);
        });
      }
    });

    test('Proton X70 (Malaysia, check digit optional): a PL1 VIN whose '
        'position 9 doesn\'t compute is still accepted', () {
      final odd = _x70Vin.replaceRange(8, 9, garble(_x70Vin[8]));
      expect(_checkDigit(odd) == odd[8], isFalse);
      expect(obdVin(odd), odd);
    });

    // Manufacturer-range codes from the Geely-group profiles, plus a few
    // more; most have Ford/GM meanings in the bundled DB.
    const mfrCodes = [
      'P1690', 'P1336', 'U1001', 'P1300', 'B1318', 'P1602', 'C1001', //
      'U1102', 'P1171', 'B1342', 'C1201', 'P3001', 'U2100', 'P33FF',
    ];
    const foreign = ['J1850', 'SCP', 'Ford', 'GM', 'PATS', 'Wastegate', //
      'Immobilizer', 'فورد', 'جنرال'];

    Future<(Map<String, dynamic>, Map<String, dynamic>)> db() async => (
      jsonDecode(await rootBundle.loadString('assets/dtcmapping.json'))
          as Map<String, dynamic>,
      jsonDecode(await rootBundle.loadString('assets/dtcmapping_ar.json'))
          as Map<String, dynamic>,
    );

    test('manufacturer codes, EN + AR: exactly the localized label, never '
        'another brand\'s DB text', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      final arabic = RegExp(r'[؀-ۿ]');
      for (final code in mfrCodes) {
        final e = (await repo.getDtcDescription(code))!;
        final a = (await repo.getDtcDescription(code, languageCode: 'ar'))!;
        expect(e, DtcRepository.manufacturerLabel(code), reason: code);
        expect(a, DtcRepository.manufacturerLabel(code, languageCode: 'ar'),
            reason: code);
        expect(e, startsWith('Manufacturer-specific code ($code)'));
        expect(a, matches(arabic));
        expect(a, contains(code));
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

    test('getOtherBrandHint exposes the DB text only behind its label', ()
        async {
      final (en, _) = await db();
      final repo = DtcRepository();
      for (final code in ['P1690', 'P1336', 'U1001', 'P1602']) {
        final h = await repo.getOtherBrandHint(code);
        expect(h, 'On some brands (often Ford/GM) this code means: '
            '${en[code]}');
      }
      expect(await repo.getOtherBrandHint('P0AFA'), isNull); // SAE
    });

    test('Okavango P0AFA + Geometry C P0AA6 and neighbouring EV codes: real '
        'descriptions in EN and AR', () async {
      final (en, ar) = await db();
      final repo = DtcRepository();
      final arabic = RegExp(r'[؀-ۿ]');
      for (final code in ['P0AFA', 'P0AA6', 'P0AA1', 'P0A94', 'P0A7F', //
        'P0ABF', 'P0B24', 'P0C78']) {
        final e = await repo.getDtcDescription(code);
        expect(e, isNotNull, reason: code);
        expect(e, en[code], reason: code);
        expect(e, isNot(startsWith('Hybrid/EV propulsion system code')));
        final a = await repo.getDtcDescription(code, languageCode: 'ar');
        expect(a, ar[code], reason: code);
        expect(a, matches(arabic), reason: code);
        expect(a, isNot(startsWith('رمز نظام الدفع الهجين/الكهربائي')));
      }
      expect(await repo.getDtcDescription('P0AFA'),
          contains('Hybrid Battery'));
      expect(await repo.getDtcDescription('P0AA6'), contains('Isolation'));
    });

    test('every bundled P0A00–P0C87 code has an Arabic entry with Arabic '
        'script (648 codes)', () async {
      final (en, ar) = await db();
      final hybrid =
          en.keys.where((k) => RegExp(r'^P0[A-C]').hasMatch(k)).toList();
      expect(hybrid, hasLength(648));
      for (final k in hybrid) {
        expect(ar[k], matches(RegExp(r'[؀-ۿ]')), reason: k);
      }
    });

    test('P0C88–P0DFF (unbundled hybrid/EV) → localized hybrid label, EN + '
        'AR', () async {
      final repo = DtcRepository();
      for (final code in ['P0C88', 'P0C9A', 'P0CFF', 'P0D00', 'P0D6E', //
        'P0DFF']) {
        expect(await repo.getDtcDescription(code),
            startsWith('Hybrid/EV propulsion system code ($code)'));
        expect(await repo.getDtcDescription(code, languageCode: 'ar'),
            startsWith('رمز نظام الدفع الهجين/الكهربائي ($code)'));
      }
    });

    // ── Connect: Geometry C / EV classification ───────────────────────────

    (OBDConnectException, List<String>, int) failConnect(SimCar car) {
      OBDConnectException? err;
      late List<String> cmds;
      late int disconnects;
      sim(car, (rig) {
        try {
          rig.connect();
        } on OBDConnectException catch (e) {
          err = e;
        }
        expect(err, isNotNull, reason: 'connect must fail');
        cmds = [...rig.elm.commands];
        disconnects = rig.device.disconnectCalls;
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
        expect(rig.adapter.isConnected, isFalse);
      }, connect: false);
      return (err!, cmds, disconnects);
    }

    const handshake = [
      'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100', 'ATSP0', '0100', //
    ];

    test('Geometry C READY, VCU silent on J1979: CAN NO DATA + ATRV 13.9 V '
        '→ noStandardObdData', () {
      final (e, cmds, disc) =
          failConnect(_profile(protocol: null, ecus: const [],
              adapterVoltage: '13.9V'));
      expect(e.reason, OBDFailureReason.noStandardObdData);
      expect(e.suggestsCloneAdapter, isFalse);
      expect(e.message, contains('electric'));
      expect(cmds, [...handshake, 'ATRV']);
      expect(disc, 1);
    });

    test('Geometry C variants that must stay ecuNotResponding: silent + no '
        'voltage, resting 12.6 V, 12.99 V', () {
      for (final volts in [null, '12.6V', '12.99V']) {
        final (e, cmds, _) = failConnect(
            _profile(protocol: null, ecus: const [], adapterVoltage: volts));
        expect(e.reason, OBDFailureReason.ecuNotResponding, reason: volts);
        expect(cmds, [...handshake, 'ATRV'], reason: volts);
      }
    });

    test('ATRV threshold: exactly 13.0 V and "13,9V" (comma) → '
        'noStandardObdData', () {
      for (final volts in ['13.0V', '13,9V']) {
        final (e, _, _) = failConnect(
            _profile(protocol: null, ecus: const [], adapterVoltage: volts));
        expect(e.reason, OBDFailureReason.noStandardObdData, reason: volts);
      }
    });

    test('auto search also ends on NO DATA → noStandardObdData without '
        'asking ATRV (even on a clone without it)', () {
      final (e, cmds, _) = failConnect(const SimCar(
        ignitionOffReply: 'NO DATA',
      ));
      expect(e.reason, OBDFailureReason.noStandardObdData);
      expect(cmds, handshake);
    });

    test('bus error on either attempt wins over a charging voltage: CAN '
        'ERROR / BUS INIT: ...ERROR at 13.9 V → ecuNotResponding, no ATRV',
        () {
      for (final car in const [
        SimCar(wrongProtocolReply: 'CAN ERROR', adapterVoltage: '13.9V'),
        SimCar(ignitionOffReply: 'BUS INIT: ...ERROR', adapterVoltage: '13.9V'),
        SimCar(
          wrongProtocolReply: 'CAN ERROR',
          ignitionOffReply: 'NO DATA',
          adapterVoltage: '13.9V',
        ),
      ]) {
        final (e, cmds, _) = failConnect(car);
        expect(e.reason, OBDFailureReason.ecuNotResponding,
            reason: '${car.wrongProtocolReply} / ${car.ignitionOffReply}');
        expect(cmds, handshake);
      }
    });

    test('no NO DATA anywhere (adapter timeouts) → ecuNotResponding, no '
        'ATRV', () {
      final (e, cmds, _) = failConnect(const SimCar(
        wrongProtocolReply: 'UNABLE TO CONNECT',
        adapterVoltage: '13.9V',
      ));
      expect(e.reason, OBDFailureReason.ecuNotResponding);
      expect(cmds, handshake);
    });

    test('classifySilentEcu: readVoltage consulted only in the ambiguous '
        'case', () async {
      var reads = 0;
      Future<double?> v() async {
        reads++;
        return 14.0;
      }
      final c = ProductionOBDAdapter.classifySilentEcu;
      expect(await c('NO DATA', 'NO DATA', readVoltage: v),
          OBDFailureReason.noStandardObdData);
      expect(await c('CAN ERROR', 'NO DATA', readVoltage: v),
          OBDFailureReason.ecuNotResponding);
      expect(await c('NO DATA', 'BUS INIT: ...ERROR', readVoltage: v),
          OBDFailureReason.ecuNotResponding);
      expect(await c('?', 'UNABLE TO CONNECT', readVoltage: v),
          OBDFailureReason.ecuNotResponding);
      expect(reads, 0);
      expect(await c('NO DATA', 'UNABLE TO CONNECT', readVoltage: v),
          OBDFailureReason.noStandardObdData);
      expect(reads, 1);
    });

    test('Geometry C VCU that answers the J1979 subset still connects '
        'normally: no ATRV in connect, poll < 3 s', () {
      sim(_geometry.build(), (rig) {
        rig.connect();
        expect(rig.elm.commands, isNot(contains('ATRV')));
        expect(rig.adapter.isConnected, isTrue);
        final p = _poll(rig);
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      }, connect: false);
    });

    test('every Geely-group profile: successful connect sends no ATRV; poll '
        '< 3 s', () {
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
