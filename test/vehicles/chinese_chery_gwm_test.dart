// Compatibility matrix, Chinese vehicles group C: Chery (Tiggo / Arrizo),
// Jetour, Exeed and Great Wall (Haval / GWM pickups / Tank), Gulf-market
// models, driven through the ELM327 simulator (test/helpers/elm327_sim.dart).
//
// Each profile models what that car's ECU(s) answer: ELM protocol number,
// auto-search time, PID support bitmaps (generated from the PIDs that really
// answer, so 0100/0120/0140 are always consistent), NO DATA for unsupported
// PIDs, extra ECUs on CAN (TCM, gateway), protocol-correct DTC / VIN /
// freeze-frame replies and engine-appropriate readiness bytes.
//
// Grounding: SAE J1979 / ISO 15765-4 / ISO 14230-4 formats, ELM327 datasheet
// behaviour, GB 18352.6 (China 6 → ISO 15765-4 CAN on every 2019+ car) and
// GB 16735 (Chinese VIN: position 9 check digit, position 10 model year).
// WMIs from the Wikibooks WMI list (LVV/LVT/LVU/LNN/HJR/LVM = Chery family,
// LGW = Great Wall, MNU = GWM Thailand, XZG = Haval Russia) and real listing
// VINs (LVUDB11BXMF001784 Jetour X70 2021, LVTDB21B6SH141150 Jetour X70 2025,
// HJRPBGFB9RF149510 Jetour X70 Plus 2024 — all three carry a valid check
// digit). Per-model PID sets, ECU latencies and VDS characters (positions
// 4–8) are NOT published by the OEMs: where a detail is a plausible
// assumption it says so ("UNVERIFIED"). Manufacturer-specific DTCs used here
// (P1006, U1300, C1000, B1000, P1745, U1101) are chosen for their range, not
// for a documented Chery/GWM meaning.
//
// Tests that once asserted correct behaviour the app got wrong (`skip: 'BUG:
// …'`) now run un-skipped against the fixes (Chinese WMIs in VinDecoder,
// manufacturer-range label in DtcRepository); any new app bug found is left as
// a test marked `skip: 'REGRESSION: …'`.

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

/// ISO 3779 check digit (position 9) — mandatory in China (GB 16735).
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

/// 09 02 on ISO 15765-4, headers off: ISO-TP byte count 0x014 + 3 frames.
String _canVinReply(String vin) => _canVinBytes(vin.codeUnits);

String _canVinBytes(List<int> vin) {
  assert(vin.length == 17);
  final b = [0x49, 0x02, 0x01, ...vin];
  return '014\n'
      '0: ${_hx(b.sublist(0, 6))}\n'
      '1: ${_hx(b.sublist(6, 13))}\n'
      '2: ${_hx(b.sublist(13, 20))}';
}

/// 09 02 on ISO 9141-2 / ISO 14230-4: five messages "49 02 0N" + 4 bytes.
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
  const _Ecu({this.mode01 = const {}, this.other = const {}});

  /// Mode 01 PID → data bytes. Support bitmaps are generated from the keys.
  /// Empty → the ECU does not answer mode 01 at all (e.g. a gateway that
  /// only forwards DTC requests).
  final Map<int, String> mode01;

  /// Replies to everything else (03, 07, 04, 02xx00, 0902 …).
  final Map<String, String> other;

  Map<String, String> replies() {
    final out = <String, String>{};
    final pids = mode01.keys.toSet();
    for (var base = 0; pids.isNotEmpty && base <= 0xE0; base += 0x20) {
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

/// A [SimCar] built from several ECUs, with realistic NO DATA timing and a
/// mode 04 that really clears the stored codes (only on an accepted clear).
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
  required String? protocol,
  required List<_Ecu> ecus,
  bool kLine = false,
  Duration ecuLatency = const Duration(milliseconds: 50),
  Duration? noDataLatency,
  Duration autoSearchTime = const Duration(seconds: 7),
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
  final responses = {
    for (final e in merged.entries) e.key: e.value.join('\n'),
    ...overrides,
  };
  if (kLine) {
    responses['0100'] = 'BUS INIT: ...OK\n${responses['0100']}';
  }
  final emptyLine = kLine ? '43 00 00 00 00 00 00' : '43 00';
  final dtcEcus = ecus.where((e) => e.other.containsKey('03')).length;
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
    emptyDtcReply: List.filled(dtcEcus, emptyLine).join('\n'),
    clearReply: clearReply ?? List.filled(dtcEcus, '44').join('\n'),
    adapterVoltage: adapterVoltage,
  );
}

/// [base] with some replies replaced (null = removed → NO DATA). Bitmaps are
/// NOT regenerated, so a removed PID stays advertised.
_ProfileCar _variant(
  _ProfileCar base, {
  Map<String, String?> replies = const {},
  Set<String> silent = const {},
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

/// All 21 values; the ones not listed are expected to be null.
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

/// Spark monitors that are typically complete on a healthy China 6 petrol.
const _sparkReady = [
  'Misfire', 'Fuel System', 'Components', 'Catalyst', 'Evap System', //
  'O2 Sensor', 'O2 Sensor Heater',
];

class _Vehicle {
  const _Vehicle({
    required this.name,
    required this.protocol,
    required this.protocolName,
    required this.build,
    required this.connectMax,
    required this.live,
    required this.dtcs,
    required this.refuseClear,
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
  final List<String> dtcs;

  /// Mode 04 reply while the engine runs (ECM refuses, others may accept).
  final String refuseClear;

  /// What 0902 returns (null = no mode 09 PID 02 support).
  final String? obdVin;
  final String plateVin;

  /// Brand expected in VinDecoder's manufacturer string.
  final List<String> make;
  final String year;
  final bool diesel;
  final bool milOn;
  final int dtcCount;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freeze;
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

// 1. Chery Tiggo 2 Pro 2022, 1.5 MPI (SQRE4G15C), CVT, GCC. China 6 → CAN
//    11/500, single ECM. Narrow-band upstream O2 (0x14). MAP-based fuelling.
//    UNVERIFIED: fuel level 0x2F and pedal 0x49 reported by the ECM; VDS.
final _tiggo2Vin = _vin('LVVDB11B?NB012345');
final _tiggo2 = _Vehicle(
  name: 'Chery Tiggo 2 Pro 2022 (1.5 MPI)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecus: [
      _Ecu(
        mode01: {
          0x01: '82 07 65 00', // MIL on, 2 DTCs; cat/evap/O2/heater ready
          0x03: '02 00',
          0x04: '4D', // 30.2 %
          0x05: '82', // 90 °C
          0x06: '85', // +3.9 %
          0x07: '83', // +2.3 %
          0x0B: '24', // 36 kPa
          0x0C: '0C 80', // 800 rpm
          0x0D: '00',
          0x0E: '94', // +10°
          0x0F: '5A', // 50 °C (Gulf summer under-bonnet)
          0x11: '26', // 14.9 %
          0x13: '03',
          0x14: '5A 80', // 0.45 V
          0x15: '8C FF', // 0.70 V
          0x1C: '06',
          0x1F: '00 78',
          0x21: '00 0C',
          0x2F: '99', // 60 %
          0x30: '0A',
          0x31: '01 2C',
          0x33: '64',
          0x42: '37 14', // 14.1 V
          0x46: '50',
          0x49: '1A', // 10.2 %
        },
        other: {
          // P0171 + manufacturer-specific P1006 (not in the bundled DB).
          '03': '43 02 01 71 10 06',
          '07': '47 01 04 20', // P0420 pending
          '0902': _canVinReply(_tiggo2Vin),
          '020C00': '42 0C 00 0D 48', // 850 rpm
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 87', // 95 °C
          '020400': '42 04 00 4D', // 30.2 %
          '020F00': '42 0F 00 5F', // 55 °C
          '021100': '42 11 00 26', // 14.9 %
          '020600': '42 06 00 99', // +19.5 % (lean → P0171)
          '020B00': '42 0B 00 26', // 38 kPa
        },
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 90,
    'throttlePct': 14.902,
    'fuelLevelPct': 60.0,
    'engineLoad': 30.196,
    'batteryVoltage': 14.1,
    'fuelTrimShortPct': 3.906,
    'fuelTrimLongPct': 2.344,
    'o2B1S1Voltage': 0.45,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 36,
    'timingAdvanceDeg': 10,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P0171', 'P1006', '~P0420'],
  refuseClear: '7F 04 22',
  obdVin: _tiggo2Vin,
  plateVin: _tiggo2Vin,
  make: ['Chery'],
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: _sparkReady),
  freeze: {
    'RPM': '850 rpm',
    'Speed': '0 km/h',
    'Coolant': '95°C',
    'Engine Load': '30.2%',
    'Air Temp': '55°C',
    'Throttle': '14.9%',
    'Fuel Trim': '19.5%',
    'MAP': '38 kPa',
  },
);

// 2. Chery Tiggo 7 Pro 2023, 1.6 TGDI (SQRF4J16) + 7DCT, GCC. CAN 11/500,
//    ECM (7E8) + TCM (7E9). Wide-band upstream reported at 0x24 (no 0x14);
//    GDI rail pressure at 0x23. UNVERIFIED: that this ECM exposes 0x23/0x24
//    (vs 0x34) and oil temp 0x5C; WMI LVU for this model (Wikibooks lists LVU
//    for Chery Automobile, observed on Jetour listings); VDS.
final _tiggo7Vin = _vin('LVUDB21B?PD012345');
final _tiggo7 = _Vehicle(
  name: 'Chery Tiggo 7 Pro 2023 (1.6 TGDI, 7DCT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '81 07 E5 00', // MIL, 1 DTC; incl. EGR/VVT; all ready
          0x03: '02 00',
          0x04: '40', // 25.1 %
          0x05: '87', // 95 °C
          0x06: '80', // 0 %
          0x07: '7C', // −3.1 %
          0x0B: '23', // 35 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '55', // 45 °C
          0x10: '01 90',
          0x11: '1A', // 10.2 %
          0x13: '03',
          0x15: '8C FF', // 0.70 V downstream
          0x1C: '06',
          0x1F: '00 3C',
          0x21: '00 00',
          0x23: '01 F4', // 5000 kPa = 50 bar GDI idle rail
          0x24: '7E B8 66 66', // λ 0.990
          0x2F: '73', // 45.1 %
          0x30: '05',
          0x31: '00 C8',
          0x33: '64',
          0x3C: '11 94',
          0x42: '37 78', // 14.2 V
          0x44: '80 00',
          0x46: '55',
          0x49: '1A', // 10.2 %
          0x4C: '1A',
          0x5C: '7D', // 85 °C
        },
        other: {
          '03': '43 01 00 11', // P0011
          '07': '47 00',
          '0902': _canVinReply(_tiggo7Vin),
          '020C00': '42 0C 00 1F 40', // 2000 rpm
          '020D00': '42 0D 00 3C', // 60 km/h
          '020500': '42 05 00 82', // 90 °C
          '020400': '42 04 00 66', // 40 %
          '020F00': '42 0F 00 55', // 45 °C
          '021100': '42 11 00 33', // 20 %
          '020600': '42 06 00 80', // 0 %
          '020B00': '42 0B 00 78', // 120 kPa boost
        },
      ),
      const _Ecu(
        mode01: {0x01: '01 04 00 00', 0x0D: '00'}, // TCM: 1 DTC, no MIL req
        // P1745: manufacturer-specific (in the bundled DB with Ford's text).
        other: {'03': '43 01 17 45', '07': '47 00'},
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 95,
    'throttlePct': 10.196,
    'fuelLevelPct': 45.098,
    'engineLoad': 25.098,
    'batteryVoltage': 14.2,
    'oilTempC': 85,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': -3.125,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 45,
    'mapKpa': 35,
    'timingAdvanceDeg': 6,
    'lambdaB1S1': 0.98999,
    'fuelRailPressureKpa': 5000,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P0011', 'P1745'],
  refuseClear: '7F 04 22\n44',
  obdVin: _tiggo7Vin,
  plateVin: _tiggo7Vin,
  make: ['Chery'],
  year: '2023',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: [..._sparkReady, 'EGR / VVT']),
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '60 km/h',
    'Coolant': '90°C',
    'Engine Load': '40.0%',
    'Air Temp': '45°C',
    'Throttle': '20.0%',
    'Fuel Trim': '0.0%',
    'MAP': '120 kPa',
  },
);

// 3. Chery Tiggo 8 Pro 2022, 2.0 TGDI (SQRF4J20) + 7DCT, GCC. CAN 11/500,
//    ECM + TCM. Full OBD (the Korean/Chinese suite only checks its window
//    VIN). Wide-band at 0x34. ECM has 3 confirmed codes → ISO-TP multi-frame
//    (padding AA, UNVERIFIED); TCM's single frame U0100 arrives first; TCM
//    also has a pending manufacturer U1300. UNVERIFIED: WMI LNN for this
//    model (Wikibooks: LNN = Chery Automobile / Omoda / Jaecoo); VDS.
final _tiggo8Vin = _vin('LNNBDDEB?ND012345');
_ProfileCar _tiggo8Car() => _profile(
  protocol: '6',
  ecuLatency: const Duration(milliseconds: 80),
  ecus: [
    _Ecu(
      mode01: {
        0x01: '83 07 E5 80', // MIL, 3 DTCs; EGR/VVT incomplete
        0x03: '02 00',
        0x04: '4D', // 30.2 %
        0x05: '84', // 92 °C
        0x06: '7A', // −4.7 %
        0x07: '85', // +3.9 %
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
        0x21: '00 25',
        0x2F: 'BF', // 74.9 %
        0x30: '06',
        0x31: '02 BC',
        0x33: '64',
        0x34: '7F 00 80 00', // λ 0.992
        0x42: '37 78',
        0x44: '80 00',
        0x46: '50',
        0x49: '40', // 25.1 %
        0x4C: '40',
      },
      other: {
        '07': '47 00',
        '0902': _canVinReply(_tiggo8Vin),
        '020C00': '42 0C 00 2E E0', // 3000 rpm
        '020D00': '42 0D 00 64', // 100 km/h
        '020500': '42 05 00 87', // 95 °C
        '020400': '42 04 00 E6', // 90.2 %
        '020F00': '42 0F 00 5F', // 55 °C
        '021100': '42 11 00 B3', // 70.2 %
        '020600': '42 06 00 7A', // −4.7 %
        '020B00': '42 0B 00 78', // 120 kPa (underboost → P0299)
      },
    ),
    const _Ecu(
      mode01: {0x01: '01 04 00 00'}, // TCM: 1 confirmed code, no MIL req
      other: {'03': '43 00', '07': '47 01 D3 00'}, // U1300 pending
    ),
  ],
  overrides: {
    // TCM single frame (U0100) first, then the ECM's 8-byte ISO-TP reply:
    // P1006, P0299, P0016.
    '03': '43 01 C1 00\n'
        '008\n'
        '0: 43 03 10 06 02 99\n'
        '1: 00 16 AA AA AA AA AA',
    '07': '47 00\n47 01 D3 00',
  },
);
final _tiggo8 = _Vehicle(
  name: 'Chery Tiggo 8 Pro 2022 (2.0 TGDI, 7DCT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _tiggo8Car,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 1500,
    'speedKmh': 80,
    'coolantTempC': 92,
    'throttlePct': 25.098,
    'fuelLevelPct': 74.902,
    'engineLoad': 30.196,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': -4.6875,
    'fuelTrimLongPct': 3.906,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 140,
    'timingAdvanceDeg': 5,
    'lambdaB1S1': 0.99219,
    'acceleratorPedalPct': 25.098,
  }),
  dtcs: ['U0100', 'P1006', 'P0299', 'P0016', '~U1300'],
  refuseClear: '7F 04 22\n44',
  obdVin: _tiggo8Vin,
  plateVin: _tiggo8Vin,
  make: ['Chery'],
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 4,
  monitors: _monitors(ready: _sparkReady, notReady: ['EGR / VVT']),
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

// 4. Chery Tiggo (T11) 2012, 2.0 MPI (SQR484F), GCC. Pre-China-5 ECU on the
//    K-line. UNVERIFIED: ISO 14230-4 KWP2000 fast init (ELM protocol 5) —
//    some T11 ECUs may use ISO 9141-2 instead; no PID above 0x20 (so no
//    0142 → the app falls back to ATRV); no mode 09 (0902 NO DATA); VDS.
final _tiggo12Vin = _vin('LVVDB14B?CB012345');
_ProfileCar _tiggo12Car({String? atrv = '14.1V'}) => _profile(
  protocol: '5',
  kLine: true,
  ecuLatency: const Duration(milliseconds: 150),
  autoSearchTime: const Duration(milliseconds: 7500),
  adapterVoltage: atrv,
  ecus: [
    const _Ecu(
      mode01: {
        0x01: '83 07 65 04', // MIL, 3 DTCs; evap incomplete
        0x03: '02 00',
        0x04: '4D', // 30.2 %
        0x05: '7B', // 83 °C
        0x06: '7A', // −4.7 %
        0x07: '89', // +7.0 %
        0x0B: '21', // 33 kPa
        0x0C: '0D 48', // 850 rpm
        0x0D: '00',
        0x0E: '8C', // +6°
        0x0F: '50', // 40 °C
        0x11: '1F', // 12.2 %
        0x13: '03',
        0x14: '5A 80', // 0.45 V
        0x15: '8C FF', // 0.70 V
        0x1C: '06',
      },
      other: {
        // ISO 14230-4: 3 codes per message, zero padded, no count byte.
        '03': '43 01 71 10 06 03 00', // P0171, P1006, P0300
        '07': '47 04 20 00 00 00 00', // P0420 pending
        '020C00': '42 0C 00 0F A0', // 1000 rpm
        '020D00': '42 0D 00 1E', // 30 km/h
        '020500': '42 05 00 5A', // 50 °C
        '020400': '42 04 00 33', // 20 %
        '020F00': '42 0F 00 50', // 40 °C
        '021100': '42 11 00 1A', // 10.2 %
        '020600': '42 06 00 99', // +19.5 %
        '020B00': '42 0B 00 2D', // 45 kPa
      },
    ),
  ],
);
final _tiggo12 = _Vehicle(
  name: 'Chery Tiggo (T11) 2012 (2.0 MPI, K-line)',
  protocol: '5',
  protocolName: 'ISO 14230-4 KWP fast init',
  build: _tiggo12Car,
  connectMax: const Duration(seconds: 20),
  live: _live({
    'rpm': 850,
    'speedKmh': 0,
    'coolantTempC': 83,
    'throttlePct': 12.157,
    'engineLoad': 30.196,
    'batteryVoltage': 14.1, // ATRV (adapter pin 16), no PID 0142
    'fuelTrimShortPct': -4.6875,
    'fuelTrimLongPct': 7.031,
    'o2B1S1Voltage': 0.45,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 40,
    'mapKpa': 33,
    'timingAdvanceDeg': 6,
  }),
  dtcs: ['P0171', 'P1006', 'P0300', '~P0420'],
  refuseClear: '7F 04 22',
  obdVin: null,
  plateVin: _tiggo12Vin,
  make: ['Chery'],
  year: '2012',
  diesel: false,
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
    'Coolant': '50°C',
    'Engine Load': '20.0%',
    'Air Temp': '40°C',
    'Throttle': '10.2%',
    'Fuel Trim': '19.5%',
    'MAP': '45 kPa',
  },
);

// 5. Jetour X70 2022, 1.5T (SQRE4T15C, port injection → narrow-band O2), GCC.
//    CAN 11/500 behind a central gateway: ~140 ms per answer, NO DATA after
//    ~205 ms (UNVERIFIED). Reduced PID set: no fuel level (cluster owns it),
//    no oil temp (UNVERIFIED). UNVERIFIED: the gateway also forwards the
//    ABS (C1000) / BCM (B1000) pending codes on a functional mode 07.
//    VIN: WMI LVT + VDS "DB21B" taken from a real Jetour X70 listing VIN
//    (LVTDB21B6SH141150), model year N = 2022.
final _jetourVin = _vin('LVTDB21B?NH012345');
_ProfileCar _jetourCar({String? clearReply}) => _profile(
  protocol: '6',
  ecuLatency: const Duration(milliseconds: 140),
  noDataLatency: const Duration(milliseconds: 205),
  clearReply: clearReply,
  ecus: [
    _Ecu(
      mode01: {
        0x01: '81 07 65 00', // MIL, 1 DTC; all ready
        0x03: '02 00',
        0x04: '59', // 34.9 %
        0x05: '84', // 92 °C
        0x06: '80',
        0x07: '81', // +0.8 %
        0x0B: '1E', // 30 kPa
        0x0C: '0C 80', // 800 rpm
        0x0D: '00',
        0x0E: '90', // +8°
        0x0F: '5F', // 55 °C
        0x11: '1A', // 10.2 %
        0x13: '03',
        0x14: '14 80', // 0.10 V
        0x15: 'A0 FF', // 0.80 V
        0x1C: '06',
        0x21: '00 00',
        0x30: '02',
        0x31: '00 32',
        0x33: '63',
        0x42: '36 B0', // 14.0 V
        0x49: '1A', // 10.2 %
      },
      other: {
        '03': '43 01 05 07', // P0507 idle high
        '07': '47 00',
        '0902': _canVinReply(_jetourVin),
        '020C00': '42 0C 00 0F A0', // 1000 rpm
        '020D00': '42 0D 00 00',
        '020500': '42 05 00 87', // 95 °C
        '020400': '42 04 00 33', // 20 %
        '020F00': '42 0F 00 64', // 60 °C
        '021100': '42 11 00 1A', // 10.2 %
        '020600': '42 06 00 80', // 0 %
        '020B00': '42 0B 00 21', // 33 kPa
      },
    ),
    // Gateway: answers DTC requests only (no mode 01).
    const _Ecu(other: {'03': '43 00', '07': '47 02 50 00 90 00'}),
  ],
);
final _jetour = _Vehicle(
  name: 'Jetour X70 2022 (1.5T)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500 (gateway)',
  build: _jetourCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 92,
    'throttlePct': 10.196,
    'engineLoad': 34.902,
    'batteryVoltage': 14.0,
    'fuelTrimShortPct': 0,
    'fuelTrimLongPct': 0.78125,
    'o2B1S1Voltage': 0.10,
    'o2B1S2Voltage': 0.80,
    'intakeAirTempC': 55,
    'mapKpa': 30,
    'timingAdvanceDeg': 8,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P0507', '~C1000', '~B1000'],
  refuseClear: '7F 04 22\n44',
  obdVin: _jetourVin,
  plateVin: _jetourVin,
  make: ['Jetour', 'Chery'],
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 1,
  monitors: _monitors(ready: _sparkReady),
  freeze: {
    'RPM': '1000 rpm',
    'Speed': '0 km/h',
    'Coolant': '95°C',
    'Engine Load': '20.0%',
    'Air Temp': '60°C',
    'Throttle': '10.2%',
    'Fuel Trim': '0.0%',
    'MAP': '33 kPa',
  },
);

// 6. Exeed TXL 2022, 1.6 TGDI + 7DCT, GCC. CAN 11/500, ECM + TCM. Codes just
//    cleared at the dealer: MIL off, catalyst / evap / EGR-VVT monitors
//    incomplete, one pending evap code, no freeze frame. ECM advertises BOTH
//    wide-band PIDs 0x24 and 0x34 (UNVERIFIED) → only 0124 must be polled.
//    UNVERIFIED: VDS (WMI LVT per Wikibooks: Chery Automobile / Exeed /
//    Jetour).
final _exeedVin = _vin('LVTDD24B?ND012345');
final _exeed = _Vehicle(
  name: 'Exeed TXL 2022 (1.6 TGDI, 7DCT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '00 07 E5 85', // no MIL; cat/evap/EGR incomplete
          0x03: '02 00',
          0x04: '40', // 25.1 %
          0x05: '82', // 90 °C
          0x06: '7E', // −1.6 %
          0x07: '80', // 0 %
          0x0B: '23', // 35 kPa
          0x0C: '0B B8', // 750 rpm
          0x0D: '00',
          0x0E: '8C', // +6°
          0x0F: '64', // 60 °C (parked in the sun)
          0x10: '01 90',
          0x11: '1A',
          0x13: '03',
          0x15: '8C FF',
          0x1C: '06',
          0x1F: '00 1E',
          0x21: '00 00',
          0x24: '80 00 66 66', // λ 1.000
          0x2F: '80', // 50.2 %
          0x30: '00',
          0x31: '00 05',
          0x33: '64',
          0x34: '80 00 80 00',
          0x42: '37 78', // 14.2 V
          0x44: '80 00',
          0x46: '5A',
          0x49: '1A',
          0x4C: '1A',
          0x5C: '82', // 90 °C
        },
        other: {
          '03': '43 00',
          '07': '47 01 04 56', // P0456 pending
          '0902': _canVinReply(_exeedVin),
        },
      ),
      const _Ecu(
        mode01: {0x01: '00 04 00 00'},
        other: {'03': '43 00', '07': '47 00'},
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 90,
    'throttlePct': 10.196,
    'fuelLevelPct': 50.196,
    'engineLoad': 25.098,
    'batteryVoltage': 14.2,
    'oilTempC': 90,
    'fuelTrimShortPct': -1.5625,
    'fuelTrimLongPct': 0,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 60,
    'mapKpa': 35,
    'timingAdvanceDeg': 6,
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['~P0456'],
  refuseClear: '7F 04 22\n44',
  obdVin: _exeedVin,
  plateVin: _exeedVin,
  make: ['Exeed', 'Chery'],
  year: '2022',
  diesel: false,
  milOn: false,
  dtcCount: 0,
  monitors: _monitors(
    ready: [
      'Misfire', 'Fuel System', 'Components', 'O2 Sensor', //
      'O2 Sensor Heater',
    ],
    notReady: ['Catalyst', 'Evap System', 'EGR / VVT'],
  ),
  freeze: const {},
);

// 7. Haval Jolion 2022, 1.5T (GW4G15K) + 7DCT, Chinese-built for GCC. CAN
//    11/500, ECM + TCM. Wide-band at 0x34. TCM stores a manufacturer U1101
//    (in the bundled DB with Ford's "SCP (J1850)" text). UNVERIFIED: VDS,
//    fuel level 0x2F from the ECM.
final _jolionVin = _vin('LGWEEUA5?NE012345');
final _jolion = _Vehicle(
  name: 'Haval Jolion 2022 (1.5T, 7DCT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: () => _profile(
    protocol: '6',
    ecuLatency: const Duration(milliseconds: 80),
    ecus: [
      _Ecu(
        mode01: {
          0x01: '81 07 E5 00', // MIL, 1 DTC; all ready incl. EGR/VVT
          0x03: '02 00',
          0x04: '40', // 25.1 %
          0x05: '87', // 95 °C
          0x06: '83', // +2.3 %
          0x07: '7C', // −3.1 %
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
          0x21: '00 08',
          0x2F: '80', // 50.2 %
          0x30: '10',
          0x31: '03 E8',
          0x33: '64',
          0x34: '80 00 80 00', // λ 1.000
          0x42: '37 78',
          0x44: '80 00',
          0x46: '50',
          0x49: '1A',
          0x4C: '1A',
        },
        other: {
          '03': '43 01 21 87', // P2187 lean at idle
          '07': '47 00',
          '0902': _canVinReply(_jolionVin),
          '020C00': '42 0C 00 0B B8', // 750 rpm
          '020D00': '42 0D 00 00',
          '020500': '42 05 00 8C', // 100 °C
          '020400': '42 04 00 26', // 14.9 %
          '020F00': '42 0F 00 50', // 40 °C
          '021100': '42 11 00 0D', // 5.1 %
          '020600': '42 06 00 99', // +19.5 %
          '020B00': '42 0B 00 1E', // 30 kPa
        },
      ),
      const _Ecu(
        mode01: {0x01: '01 04 00 00'},
        other: {'03': '43 01 D1 01', '07': '47 00'}, // U1101
      ),
    ],
  ),
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 750,
    'speedKmh': 0,
    'coolantTempC': 95,
    'throttlePct': 10.196,
    'fuelLevelPct': 50.196,
    'engineLoad': 25.098,
    'batteryVoltage': 14.2,
    'fuelTrimShortPct': 2.344,
    'fuelTrimLongPct': -3.125,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 50,
    'mapKpa': 38,
    'timingAdvanceDeg': 6,
    'lambdaB1S1': 1.0,
    'acceleratorPedalPct': 10.196,
  }),
  dtcs: ['P2187', 'U1101'],
  refuseClear: '7F 04 22\n44',
  obdVin: _jolionVin,
  plateVin: _jolionVin,
  make: ['Great Wall', 'Haval'],
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(ready: [..._sparkReady, 'EGR / VVT']),
  freeze: {
    'RPM': '750 rpm',
    'Speed': '0 km/h',
    'Coolant': '100°C',
    'Engine Load': '14.9%',
    'Air Temp': '40°C',
    'Throttle': '5.1%',
    'Fuel Trim': '19.5%',
    'MAP': '30 kPa',
  },
);

// 8. Haval H9 2022, 2.0T GDI (GW4C20B) + 8AT, 4WD, GCC. CAN 11/500, ECM + TCM.
//    Wide-band at 0x24, GDI rail at 0x23, oil temp at 0x5C (all UNVERIFIED).
//    TCM has a confirmed P0730 with MIL request. UNVERIFIED: VDS.
final _h9Vin = _vin('LGWFF7A6?NE012345');
_ProfileCar _h9Car({String? protocol = '6'}) => _profile(
  protocol: protocol,
  ecuLatency: const Duration(milliseconds: 80),
  ecus: [
    _Ecu(
      mode01: {
        0x01: '82 07 65 00', // MIL, 2 DTCs
        0x03: '02 00',
        0x04: '4D', // 30.2 %
        0x05: '87', // 95 °C
        0x06: '85', // +3.9 %
        0x07: '83', // +2.3 %
        0x0B: '28', // 40 kPa
        0x0C: '0C 80', // 800 rpm
        0x0D: '00',
        0x0E: '90', // +8°
        0x0F: '5F', // 55 °C
        0x10: '02 58',
        0x11: '1F', // 12.2 %
        0x13: '03',
        0x15: '8C FF',
        0x1C: '06',
        0x1F: '01 2C',
        0x21: '00 10',
        0x23: '02 58', // 6000 kPa
        0x24: '83 33 66 66', // λ 1.025
        0x2F: '4D', // 30.2 %
        0x30: '08',
        0x31: '01 90',
        0x33: '62',
        0x42: '37 14', // 14.1 V
        0x44: '80 00',
        0x46: '55',
        0x49: '24', // 14.1 %
        0x4C: '1F',
        0x5C: '7F', // 87 °C
      },
      other: {
        '03': '43 02 00 16 03 00', // P0016, P0300
        '07': '47 01 01 28', // P0128 pending
        '0902': _canVinReply(_h9Vin),
        '020C00': '42 0C 00 1F 40', // 2000 rpm
        '020D00': '42 0D 00 50', // 80 km/h
        '020500': '42 05 00 87', // 95 °C
        '020400': '42 04 00 80', // 50.2 %
        '020F00': '42 0F 00 5F', // 55 °C
        '021100': '42 11 00 4D', // 30.2 %
        '020600': '42 06 00 85', // +3.9 %
        '020B00': '42 0B 00 64', // 100 kPa
      },
    ),
    const _Ecu(
      mode01: {0x01: '81 04 00 00'}, // TCM: MIL request, 1 code
      other: {'03': '43 01 07 30', '07': '47 00'}, // P0730
    ),
  ],
);
final _h9 = _Vehicle(
  name: 'Haval H9 2022 (2.0T GDI, 8AT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _h9Car,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 95,
    'throttlePct': 12.157,
    'fuelLevelPct': 30.196,
    'engineLoad': 30.196,
    'batteryVoltage': 14.1,
    'oilTempC': 87,
    'fuelTrimShortPct': 3.906,
    'fuelTrimLongPct': 2.344,
    'o2B1S2Voltage': 0.70,
    'intakeAirTempC': 55,
    'mapKpa': 40,
    'timingAdvanceDeg': 8,
    'lambdaB1S1': 1.02499,
    'fuelRailPressureKpa': 6000,
    'acceleratorPedalPct': 14.118,
  }),
  dtcs: ['P0016', 'P0300', 'P0730', '~P0128'],
  refuseClear: '7F 04 22\n44',
  obdVin: _h9Vin,
  plateVin: _h9Vin,
  make: ['Great Wall', 'Haval'],
  year: '2022',
  diesel: false,
  milOn: true,
  dtcCount: 3,
  monitors: _monitors(ready: _sparkReady),
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '80 km/h',
    'Coolant': '95°C',
    'Engine Load': '50.2%',
    'Air Temp': '55°C',
    'Throttle': '30.2%',
    'Fuel Trim': '3.9%',
    'MAP': '100 kPa',
  },
);

// 9. GWM Poer (Cannon) 2022, 2.0TD diesel (GW4D20M) + ZF 8AT, Levant/Iraq/
//    GCC. CAN 11/500, ECM + TCM. Compression ignition: 0101 byte B bit 3;
//    no throttle (0x11), fuel trims, O2 voltage or timing advance; rail
//    pressure 0x23 and pedal 0x49 instead. Euro 5 with DPF, no SCR
//    (UNVERIFIED — market dependent). Oil temp 0x5C and VDS UNVERIFIED.
final _poerVin = _vin('LGWDBE17?NB012345');
const _poerEcm = _Ecu(
  mode01: {
    0x01: '82 0F E9 40', // MIL, 2 DTCs; CI; NMHC/boost/EGS/PM/EGR; PM inc.
    0x04: '33', // 20 %
    0x05: '82', // 90 °C
    0x0B: '66', // 102 kPa
    0x0C: '0C 80', // 800 rpm
    0x0D: '00',
    0x0F: '55', // 45 °C
    0x10: '02 BC',
    0x1C: '06',
    0x1F: '01 2C',
    0x21: '00 30',
    0x23: '0B B8', // 30 000 kPa = 300 bar
    0x2C: '33',
    0x30: '08',
    0x31: '01 90',
    0x33: '64',
    0x42: '37 78', // 14.2 V
    0x49: '24', // 14.1 %
    0x5C: '82', // 90 °C
  },
  other: {
    '03': '43 02 20 02 00 87', // P2002 DPF efficiency, P0087 rail low
    '07': '47 01 24 63', // P2463 soot accumulation pending
    '020C00': '42 0C 00 1F 40', // 2000 rpm
    '020D00': '42 0D 00 46', // 70 km/h
    '020500': '42 05 00 87', // 95 °C
    '020400': '42 04 00 CC', // 80 %
    '020F00': '42 0F 00 5F', // 55 °C
    '020B00': '42 0B 00 A0', // 160 kPa
  },
);
const _poerTcm = _Ecu(
  mode01: {0x01: '00 04 00 00'},
  other: {'03': '43 00', '07': '47 00'},
);
_ProfileCar _poerCar({bool tcmFirst = false}) => _profile(
  protocol: '6',
  ecuLatency: const Duration(milliseconds: 80),
  ecus: tcmFirst
      ? [_poerTcm, _withVin(_poerEcm, _poerVin)]
      : [_withVin(_poerEcm, _poerVin), _poerTcm],
);
_Ecu _withVin(_Ecu e, String vin) =>
    _Ecu(mode01: e.mode01, other: {...e.other, '0902': _canVinReply(vin)});
final _poer = _Vehicle(
  name: 'GWM Poer 2022 (2.0TD diesel, 8AT)',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  build: _poerCar,
  connectMax: const Duration(seconds: 2),
  live: _live({
    'rpm': 800,
    'speedKmh': 0,
    'coolantTempC': 90,
    'engineLoad': 20.0,
    'batteryVoltage': 14.2,
    'oilTempC': 90,
    'intakeAirTempC': 45,
    'mapKpa': 102,
    'fuelRailPressureKpa': 30000,
    'acceleratorPedalPct': 14.118,
  }),
  dtcs: ['P2002', 'P0087', '~P2463'],
  refuseClear: '7F 04 22\n44',
  obdVin: _poerVin,
  plateVin: _poerVin,
  make: ['Great Wall'],
  year: '2022',
  diesel: true,
  milOn: true,
  dtcCount: 2,
  monitors: _monitors(
    diesel: true,
    ready: [
      'Misfire', 'Fuel System', 'Components', 'NMHC Catalyst', //
      'Boost Pressure', 'Exhaust Gas Sensor', 'EGR / VVT',
    ],
    notReady: ['PM Filter'],
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

final _vehicles = [
  _tiggo2,
  _tiggo7,
  _tiggo8,
  _tiggo12,
  _jetour,
  _exeed,
  _jolion,
  _h9,
  _poer,
];

// ── Test helpers ──────────────────────────────────────────────────────────────

/// The 18 regular live PIDs in the order ProductionOBDAdapter._poll sends them.
const _pollOrder = [
  '010C', '010D', '0105', '0111', '012F', '0104', '0142', '015C', '0106', //
  '0107', '0108', '0109', '0114', '0115', '0118', '010F', '010B', '010E',
];

int _pidOf(String cmd) => int.parse(cmd.substring(2), radix: 16);

/// Mode 01 PIDs [car]'s 0100 / 0120 / 0140 bitmaps advertise (all ECUs).
Set<int> _advertised(SimCar car) {
  final out = <int>{};
  final re = RegExp(r'41 ([0-9A-F]{2})((?: [0-9A-F]{2}){4})');
  for (var base = 0; base <= 0x40; base += 0x20) {
    if (base != 0 && !out.contains(base)) break;
    for (final line in (car.responses['01${_h(base)}'] ?? '').split('\n')) {
      final m = re.firstMatch(line);
      if (m == null || m.group(1) != _h(base)) continue;
      final b = m
          .group(2)!
          .trim()
          .split(' ')
          .map((x) => int.parse(x, radix: 16))
          .toList();
      for (var i = 0; i < 32; i++) {
        if (b[i ~/ 8] & (0x80 >> (i % 8)) != 0) out.add(base + i + 1);
      }
    }
  }
  return out;
}

/// Live requests poll number [poll] must send: advertised regular PIDs in
/// order, ATRV in the 0142 slot when 0142 isn't advertised (every poll when
/// the adapter answers it, else only the first two), then the extras.
List<String> _expectedPolled(
  Set<int> adv, {
  int poll = 1,
  bool atrvAnswers = false,
}) {
  final reg = _pollOrder.where((p) => adv.contains(_pidOf(p)));
  return [
    for (final p in _pollOrder)
      if (p == '0142' && !reg.contains(p)) ...[
        if (atrvAnswers || poll <= 2) 'ATRV',
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

/// Starts polling, waits for [count] frames (≥ 2), stops.
_PollResult _poll(Rig rig, {int count = 2, List<OBDLiveData>? all}) {
  final frames = <(Duration, OBDLiveData)>[];
  final cuts = <int>[rig.elm.commands.length];
  final sub = rig.adapter.liveDataStream.listen((d) {
    frames.add((rig.async.elapsed, d));
    cuts.add(rig.elm.commands.length);
  });
  final start = rig.async.elapsed;
  rig.adapter.startLiveData();
  while (frames.length < count &&
      rig.async.elapsed - start < const Duration(seconds: 120)) {
    rig.async.elapse(const Duration(milliseconds: 10));
  }
  rig.adapter.stopLiveData();
  sub.cancel();
  if (frames.length < count) fail('fewer than $count live frames in 120 s');
  all?.addAll(frames.map((f) => f.$2));
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

Map<String, double?> _liveWith(_Vehicle v, Map<String, double?> changes) =>
    {...v.live, ...changes};

final _mfrRange =
    RegExp(r'^(?:P1[0-9A-F]{3}|P3[0-3][0-9A-F]{2}|[BCU][12][0-9A-F]{3})$');

String _mfrLabel(String code) =>
    'Manufacturer-specific code ($code). Meaning varies by vehicle brand. '
    'Check your vehicle\'s service manual or dealer.';

// ── Tests ─────────────────────────────────────────────────────────────────────

const _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final httpRequests = <http.Request>[];

  setUpAll(() {
    // DtcRepository: offline, no stored translations, failing HTTP.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, (call) async {
      if (call.method == 'check') return ['none'];
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    DtcRepository.resetCaches();
    DtcRepository.httpClient = MockClient((r) async {
      httpRequests.add(r);
      return http.Response('', 400);
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivityChannel, null);
    // ignore: avoid_print
    print('\n== Chery / Jetour / Exeed / GWM measurements ==\n'
        '${_matrix.join('\n')}');
  });

  for (final v in _vehicles) {
    group('${v.name} [${v.protocolName}]', () {
      test('(a) connect establishes protocol ${v.protocol}', () {
        sim(v.build(), (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();
          final dt = rig.async.elapsed - t0;
          _log('${v.name}: connect ${_secs(dt)} s');
          expect(rig.adapter.isConnected, isTrue);
          expect(rig.adapter.connectionState, OBDConnectionState.connected);
          expect(rig.elm.activeProtocol, v.protocol);
          expect(dt, lessThan(v.connectMax));
        }, connect: false);
      });

      test('(b) live poll: exact advertised-PID sequence, every value '
          'decoded, poll < 3 s, refresh every 3 s', () {
        final car = v.build();
        final adv = _advertised(car);
        final atrv = car.adapterVoltage != null;
        sim(car, (rig) {
          final p = _poll(rig);
          final nulls = v.live.values.where((x) => x == null).length;
          _log('${v.name}: poll ${_secs(p.cycle)} s '
              '(${_liveKeys.length - nulls} values, ${p.polled.length} '
              'requests: ${p.polled.join(' ')}), refresh ${_secs(p.period)} s');
          expect(p.firstCycle.where(_isBitmapReq), _expectedBitmapReqs(adv));
          expect(p.polled, _expectedPolled(adv, atrvAnswers: atrv));
          expect(p.secondCycle,
              _expectedPolled(adv, poll: 2, atrvAnswers: atrv));
          _expectLive(p.first, v.live);
          _expectLive(p.second, v.live);
          expect(p.cycle, lessThan(const Duration(seconds: 3)));
          expect(p.period, lessThan(const Duration(milliseconds: 3100)));
          expect(p.period, greaterThan(const Duration(milliseconds: 2500)));
        });
      });

      test('(c) DTCs: confirmed (03) + pending (07)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(c) DtcRepository has a description or the manufacturer label '
          'for every code', () async {
        final repo = DtcRepository();
        for (final raw in v.dtcs) {
          final code = raw.replaceFirst('~', '');
          final d = await repo.getDtcDescription(code);
          _log('${v.name}: $code → $d');
          expect(d, isNotNull, reason: code);
          expect(d, isNotEmpty, reason: code);
        }
        expect(httpRequests, isEmpty);
      });

      test('(c) manufacturer-specific codes get the manufacturer label, not '
          'another brand\'s meaning', () async {
        final repo = DtcRepository();
        for (final raw in v.dtcs) {
          final code = raw.replaceFirst('~', '');
          if (!_mfrRange.hasMatch(code)) continue;
          expect(await repo.getDtcDescription(code), _mfrLabel(code),
              reason: code);
        }
      });

      test('(c) clear accepted (44) → true, no codes, no freeze frame', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
          expect(rig.elm.commands.last, '04');
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
        });
      });

      test('(c) clear refused (7F 04 22, engine running) → false, codes '
          'kept', () {
        sim(_variant(v.build(), clearReply: v.refuseClear), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      });

      test('(d) getVin() → VinDecoder country China + model year', () {
        sim(v.build(), (rig) {
          final vin = rig.drive(rig.adapter.getVin());
          expect(vin, v.obdVin);
          final decoded = vin ?? v.plateVin; // no mode 09 → plate VIN
          expect(_checkDigit(decoded), decoded[8], reason: 'check digit');
          final d = VinDecoder.decode(decoded, now: _now);
          _log('${v.name}: getVin() → $vin; decode → $d');
          expect(d['country'], 'China');
          expect(d['year'], v.year);
        });
      });

      test('(d) VinDecoder maker for WMI ${v.plateVin.substring(0, 3)}', () {
        final d = VinDecoder.decode(v.plateVin, now: _now);
        expect(d['manufacturer'], anyOf([for (final m in v.make) contains(m)]));
      });

      test('(e) readiness (${v.diesel ? 'diesel' : 'spark'}) + MIL + count',
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

  group('Chery edge cases', () {
    test('Tiggo 2012 K-line: CAN 11/500 attempt fails (CAN ERROR), auto '
        'search lands on KWP; connect takes the search time but < 20 s', () {
      sim(_tiggo12Car(), (rig) {
        final t0 = rig.async.elapsed;
        rig.connect();
        final dt = rig.async.elapsed - t0;
        expect(rig.elm.commands.where((c) => c.startsWith('ATSP')),
            ['ATSP6', 'ATSP0']);
        expect(rig.elm.activeProtocol, '5');
        expect(dt, greaterThan(const Duration(milliseconds: 7500)));
        expect(dt, lessThan(const Duration(seconds: 20)));
      }, connect: false);
    });

    test('Tiggo 2012 K-line, clone adapter without ATRV ("?") → battery '
        'null, ATRV dropped after 2 polls, rest decoded', () {
      final car = _tiggo12Car(atrv: null);
      final adv = _advertised(car);
      sim(car, (rig) {
        final frames = <OBDLiveData>[];
        final p = _poll(rig, count: 3, all: frames);
        expect(p.polled, _expectedPolled(adv));
        expect(p.secondCycle, _expectedPolled(adv, poll: 2));
        expect(rig.elm.commands.where((c) => c == 'ATRV').length, 2);
        _expectLive(_fields(frames[2]),
            _liveWith(_tiggo12, {'batteryVoltage': null}));
      });
    });

    test('Tiggo 2012 variant whose ECU does answer mode 09 (K-line, five '
        '49 02 0N messages) → VIN reassembled, Chery / 2012', () {
      final car = _variant(_tiggo12Car(),
          replies: {'0902': _kLineVinReply(_tiggo12Vin)});
      sim(car, (rig) {
        final vin = rig.drive(rig.adapter.getVin());
        expect(vin, _tiggo12Vin);
        final d = VinDecoder.decode(vin!, now: _now);
        expect(d['manufacturer'], 'Chery');
        expect(d['year'], '2012');
      });
    });

    test('Tiggo 7 Pro GDI (spark): wide-band 0124 and rail pressure 0123 '
        'are polled and decoded on a petrol engine', () {
      sim(_tiggo7.build(), (rig) {
        final p = _poll(rig);
        expect(p.polled, containsAll(['0124', '0123', '0149']));
        expect(p.polled, isNot(contains('0114')));
        expect(p.first['lambdaB1S1'], closeTo(0.98999, 0.0001));
        expect(p.first['fuelRailPressureKpa'], 5000);
      });
    });

    test('Tiggo 8 Pro: TCM answers 0902 with 17 x 00 (not VIN-coded) before '
        'the ECM VIN → ECM VIN', () {
      final car = _variant(_tiggo8Car(), replies: {
        '0902': '${_canVinBytes(List.filled(17, 0))}\n'
            '${_canVinReply(_tiggo8Vin)}',
      });
      sim(car, (rig) => expect(rig.drive(rig.adapter.getVin()), _tiggo8Vin));
    });

    test('Tiggo 8 Pro: TCM single frame BETWEEN the ECM ISO-TP frames → all '
        '4 confirmed codes', () {
      final car = _variant(_tiggo8Car(), replies: {
        '03': '008\n'
            '0: 43 03 10 06 02 99\n'
            '43 01 C1 00\n'
            '1: 00 16 AA AA AA AA AA',
      });
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getDtcs()),
            unorderedEquals(['P1006', 'P0299', 'P0016', 'U0100', '~U1300']));
      });
    });

    test('Exeed TXL: both 0124 and 0134 advertised → only 0124 polled', () {
      final car = _exeed.build();
      expect(_advertised(car), containsAll([0x24, 0x34]));
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.polled, contains('0124'));
        expect(p.polled, isNot(contains('0134')));
        expect(p.first['lambdaB1S1'], closeTo(1.0, 0.001));
      });
    });

    test('Jetour X70 behind a slow gateway (140 ms answers, 205 ms NO DATA): '
        'first poll incl. 0120/0140 still < 3 s', () {
      sim(_jetour.build(), (rig) {
        final p = _poll(rig);
        expect(p.firstCycle.where(_isBitmapReq), ['0120', '0140']);
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Jetour X70: gateway forwards pending chassis/body codes → C1000 / '
        'B1000 parsed, manufacturer label shown', () async {
      sim(_jetour.build(), (rig) {
        final codes = rig.drive(rig.adapter.getDtcs());
        expect(codes, containsAll(['~C1000', '~B1000']));
      });
      final repo = DtcRepository();
      expect(await repo.getDtcDescription('C1000'), _mfrLabel('C1000'));
      expect(await repo.getDtcDescription('B1000'), _mfrLabel('B1000'));
    });

    test('Jetour X70: ECM 7F 04 78 (responsePending) then 44, gateway 44 → '
        'true, codes gone', () {
      sim(_jetourCar(clearReply: '7F 04 78\n44\n44'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
      });
    });

    test('Jetour X70: gateway 44 but ECM 7F 04 22 → false, codes kept', () {
      sim(_jetourCar(clearReply: '44\n7F 04 22'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), _jetour.dtcs);
      });
    });
  });

  group('Great Wall edge cases', () {
    test('Haval Jolion: 012F advertised but ECM answers NO DATA → fuel null, '
        'everything else right, still < 3 s', () {
      final car = _variant(_jolion.build(), replies: {'012F': null});
      sim(car, (rig) {
        final p = _poll(rig);
        expect(p.polled, contains('012F'));
        _expectLive(p.first, _liveWith(_jolion, {'fuelLevelPct': null}));
        expect(p.cycle, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Haval H9, ignition off → OBDConnectException(ecuNotResponding), '
        'state failed', () {
      sim(_h9Car(protocol: null), (rig) {
        Object? error;
        try {
          rig.connect();
        } catch (e) {
          error = e;
        }
        expect(error, isA<OBDConnectException>());
        expect((error! as OBDConnectException).reason,
            OBDFailureReason.ecuNotResponding);
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
        expect(rig.adapter.isConnected, isFalse);
      }, connect: false);
    });

    test('Haval H9: oil temp 015C and GDI rail 0123 decoded', () {
      sim(_h9.build(), (rig) {
        final p = _poll(rig);
        expect(p.first['oilTempC'], 87);
        expect(p.first['fuelRailPressureKpa'], 6000);
      });
    });

    test('GWM Poer diesel: TCM 0101 line (spark-looking) answers first → '
        'still diesel, diesel monitor names, MIL/count merged', () {
      sim(_poerCar(tcmFirst: true), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isTrue);
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 2);
        expect({for (final m in r.monitors) m.name: m.status}, _poer.monitors);
      });
    });

    test('GWM Poer diesel: no throttle PID → throttle null, pedal 0149 and '
        'rail 0123 (300 bar) carry the driver demand / fuel system', () {
      sim(_poer.build(), (rig) {
        final p = _poll(rig);
        expect(p.polled, isNot(contains('0111')));
        expect(p.polled, isNot(contains('0124')));
        expect(p.polled, isNot(contains('0134')));
        expect(p.first['throttlePct'], isNull);
        expect(p.first['acceleratorPedalPct'], closeTo(14.118, 0.01));
        expect(p.first['fuelRailPressureKpa'], 30000);
      });
    });

    test('GWM Poer diesel: freeze frame without throttle / fuel-trim PIDs → '
        'only the 6 answered fields', () {
      sim(_poer.build(), (rig) {
        final f = rig.drive(rig.adapter.getFreezeFrame());
        expect(f.keys, isNot(contains('Throttle')));
        expect(f.keys, isNot(contains('Fuel Trim')));
        expect(f.length, 6);
      });
    });
  });

  group('DtcRepository: manufacturer-specific ranges', () {
    // Not in the bundled DB → generic label (offline, no network call).
    for (final code in ['P1006', 'U1300', 'B1000', 'C1000']) {
      test('$code (absent from DB) → manufacturer label', () async {
        expect(await DtcRepository().getDtcDescription(code), _mfrLabel(code));
      });
    }
    // In the bundled DB with another brand's meaning.
    for (final code in ['P1745', 'U1101', 'P1336', 'C1201', 'B1300']) {
      test('$code (in DB with another brand\'s text) → manufacturer label on '
          'a Chery/GWM', () async {
        expect(await DtcRepository().getDtcDescription(code), _mfrLabel(code));
      });
    }
    // Formerly documented the bug (U1101 came back as Ford's "SCP (J1850)
    // Invalid or Missing Data…"). Fixed: the DB text is only reachable as a
    // labelled other-brand hint, never as the description.
    test('collision codes no longer return another brand\'s text; it is '
        'only offered as a labelled hint', () async {
      final repo = DtcRepository();
      final u1101 = await repo.getDtcDescription('U1101');
      _log('U1101 on a Haval → "$u1101"');
      expect(u1101, _mfrLabel('U1101'));
      expect(u1101, isNot(contains('J1850')));
      expect(u1101, isNot(contains('SCP')));
      final hint = await repo.getOtherBrandHint('U1101');
      expect(hint, startsWith('On some brands (often Ford/GM) this code '
          'means: '));
      expect(hint, contains('J1850'));
    });
  });

  group('VinDecoder: Chery / Jetour / Exeed / GWM WMIs', () {
    // (template or real VIN, accepted makers, country, model year or null)
    const ok = [
      ('LVVDB11B?NB012345', ['Chery'], 'China', '2022'), // Tiggo 2 Pro
      ('LVVDB14B?CB012345', ['Chery'], 'China', '2012'), // Tiggo T11
      ('LGWEEUA5?NE012345', ['Great Wall', 'Haval'], 'China', '2022'),
      ('LGWFFUA6?PE012345', ['Great Wall', 'Tank'], 'China', '2023'), // Tank
      ('LGWDBE17?NB012345', ['Great Wall', 'GWM'], 'China', '2022'), // Poer
    ];
    for (final (tpl, makers, country, year) in ok) {
      test('$tpl → ${makers.first} / $country / $year', () {
        final d = VinDecoder.decode(_vin(tpl), now: _now);
        expect(d['manufacturer'], anyOf([for (final m in makers) contains(m)]));
        expect(d['country'], country);
        expect(d['year'], year);
      });
    }

    // Real listing VINs (check digits verified) and Wikibooks WMIs.
    const added = [
      ('LVTDB21B6SH141150', ['Jetour', 'Chery'], 'China', '2025'), // X70
      ('LVUDB11BXMF001784', ['Jetour', 'Chery'], 'China', '2021'), // X70
      ('HJRPBGFB9RF149510', ['Jetour', 'Chery'], 'China', '2024'), // X70+
      ('LVTDD24B?ND012345', ['Exeed', 'Chery'], 'China', '2022'),
      ('LNNBDDEB?ND012345', ['Chery', 'Omoda'], 'China', '2022'),
      ('LVMDB11B?NB012345', ['Chery'], 'China', '2022'), // Chery Commercial
      ('MNUFF7A6?NE012345', ['Great Wall', 'GWM'], 'Thailand', null),
      ('XZGFF7A6?NE012345', ['Great Wall', 'Haval'], 'Russia', null),
    ];
    for (final (tpl, makers, country, year) in added) {
      final vin = tpl.contains('?') ? _vin(tpl) : tpl;
      test('$vin: country $country${year == null ? '' : ', year $year'}', () {
        expect(_checkDigit(vin), vin[8]);
        final d = VinDecoder.decode(vin, now: _now);
        expect(d['country'], country);
        if (year != null) expect(d['year'], year);
      });
      test('$vin → maker ${makers.join(' / ')}', () {
        final d = VinDecoder.decode(vin, now: _now);
        expect(d['manufacturer'], anyOf([for (final m in makers) contains(m)]));
      });
    }
  });

  // ── Double-check (verifier V2): try to break the fixes ─────────────────────

  group('double-check', () {
    // ---- VinDecoder: every Chery-group / GWM WMI → maker, country, year ----
    // (template, brand substring, country, model year)
    const wmis = [
      ('LVVDB11B?NB012345', 'Chery', 'China', '2022'),
      ('LVTDB21B?SH141150', 'Chery', 'China', '2025'), // Jetour / Exeed
      ('LVUDB11B?MF001784', 'Chery', 'China', '2021'), // Jetour / Omoda
      ('LNNBDDEB?ND012345', 'Chery', 'China', '2022'), // Omoda / Jaecoo
      ('HJRPBGFB?RF149510', 'Jetour', 'China', '2024'), // H-row WMI
      ('LVMDB11B?TB012345', 'Chery', 'China', '2026'), // Chery Commercial
      ('L2CCA1AB?LB012345', 'Chery', 'China', '2020'), // Chery JLR
      ('LGWEEUA5?NE012345', 'Great Wall Motor (GWM)', 'China', '2022'),
      ('MNUFF7A6?NE012345', 'Great Wall Motor (GWM)', 'Thailand', 'Unknown'),
      ('XZGFF7A6?NE012345', 'Great Wall', 'Russia', 'Unknown'),
    ];
    for (final (tpl, brand, country, year) in wmis) {
      final vin = _vin(tpl);
      test('WMI ${tpl.substring(0, 3)}: $vin → $brand / $country / $year',
          () {
        final d = VinDecoder.decode(vin, now: _now);
        expect(d['manufacturer'], contains(brand));
        expect(d['manufacturer'], isNot(VinDecoder.unknown));
        expect(d['country'], country);
        expect(d['year'], year);
        // Case-insensitive: a lower-case VIN (manual entry) decodes the same.
        final lower = VinDecoder.decode(vin.toLowerCase(), now: _now);
        expect(lower['manufacturer'], d['manufacturer']);
        expect(lower['country'], d['country']);
        expect(lower['year'], d['year']);
      });
    }

    test('every GWM line under LGW (Haval, Tank, Wey, Ora, Poer / Wingle '
        'pickups) shows exactly "Great Wall Motor (GWM)"', () {
      const gwm = {
        'Haval H6': 'LGWEF6A5?NH012345',
        'Haval Jolion': 'LGWEEUA5?NE012345',
        'Haval H9': 'LGWFF7A6?NE012345',
        'Tank 300': 'LGWFFUA6?PE012345',
        'Tank 500': 'LGWFFVA8?RE012345',
        'Wey Coffee 01': 'LGWFFWA2?PE012345',
        'Ora Good Cat': 'LGWEEXA1?MR012345',
        'Poer pickup': 'LGWDBE17?NB012345',
        'Wingle 7 pickup': 'LGWCA2G7?KB012345',
      };
      for (final e in gwm.entries) {
        final d = VinDecoder.decode(_vin(e.value), now: _now);
        expect(d['manufacturer'], 'Great Wall Motor (GWM)', reason: e.key);
        expect(d['country'], 'China', reason: e.key);
      }
    });

    // ---- getVin(): check digit enforced for L / H (China) WMIs -------------

    String? readVin(String reply) {
      String? out;
      sim(_variant(_h9Car(), replies: {'0902': reply}),
          (rig) => out = rig.drive(rig.adapter.getVin()));
      return out;
    }

    /// [vin] with position 9 replaced by a wrong check digit.
    String wrongCheck(String vin) {
      final bad = vin[8] == '1' ? '2' : '1';
      return vin.replaceRange(8, 9, bad);
    }

    test('valid LGW / LVV / LVT / LNN VINs read over CAN are accepted', () {
      for (final vin in [_h9Vin, _tiggo2Vin, _jetourVin, _tiggo8Vin]) {
        expect(readVin(_canVinReply(vin)), vin);
      }
    });

    test('garbled Chinese VIN (wrong check digit / swapped characters / '
        'illegal letter O) → null, never a wrong VIN', () {
      final bad = wrongCheck(_h9Vin);
      expect(_checkDigit(bad), isNot(bad[8]));
      expect(readVin(_canVinReply(bad)), isNull);

      // Two serial characters swapped in transit.
      final swapped = _h9Vin.replaceRange(12, 14,
          '${_h9Vin[13]}${_h9Vin[12]}');
      final swapped2 = swapped == _h9Vin
          ? _h9Vin.replaceRange(11, 12, 'Z')
          : swapped;
      expect(_checkDigit(swapped2), isNot(swapped2[8]), reason: swapped2);
      expect(readVin(_canVinReply(swapped2)), isNull);

      expect(readVin(_canVinReply(_h9Vin.replaceRange(11, 12, 'O'))),
          isNull);
      // K-line framing of a bad VIN is rejected the same way.
      expect(readVin(_kLineVinReply(wrongCheck(_tiggo12Vin))), isNull);
    });

    test('a bad ECU VIN followed by the correct one → the correct one', () {
      final reply = '${_canVinReply(wrongCheck(_h9Vin))}\n'
          '${_canVinReply(_h9Vin)}';
      expect(readVin(reply), _h9Vin);
    });

    test('HJR (H-row, Jetour) check digit: real VIN accepted, altered '
        'check digit rejected', () {
      const real = 'HJRPBGFB9RF149510';
      expect(_checkDigit(real), '9');
      expect(readVin(_canVinReply(real)), real);
      expect(readVin(_canVinReply(wrongCheck(real))), isNull);
      final d = VinDecoder.decode(real, now: _now);
      expect(d['manufacturer'], contains('Jetour'));
      expect(d['country'], 'China');
      expect(d['year'], '2024');
    });

    test('check digit "X" (remainder 10) is accepted on a Chinese VIN', () {
      String? xVin;
      for (var n = 0; n < 1000 && xVin == null; n++) {
        final v = _vin('LGWEF6A5?NH${n.toString().padLeft(6, '0')}');
        if (v[8] == 'X') xVin = v;
      }
      expect(xVin, isNotNull);
      expect(readVin(_canVinReply(xVin!)), xVin);
      expect(readVin(_canVinReply(xVin.replaceRange(8, 9, '0'))), isNull);
    });

    test('GWM Thailand (MNU): position 9 is not a mandatory check digit '
        'outside China/North America → still accepted', () {
      final thai = wrongCheck(_vin('MNUFF7A6?NE012345'));
      expect(readVin(_canVinReply(thai)), thai);
    });

    // ---- DtcRepository: manufacturer ranges never show another brand ------

    const foreign = [
      'J1850', 'SCP', 'Ford', 'GM', 'Line Pressure', 'Intake Manifold', //
      'ABS Inlet', 'Power Door', 'Crank',
    ];
    const mfrCodes = [
      'P1745', 'U1101', 'P1520', 'C1201', 'B1300', 'P1336', 'P1006', //
      'U1300', 'C1000', 'B1000', 'P3000', 'P33FF', 'U2100', 'B2000', 'C2FFF',
    ];
    final arabicScript = RegExp(r'[؀-ۿ]');

    test('precondition: the collision codes really are in the bundled DB '
        'with another brand\'s text', () async {
      for (final c in ['P1745', 'U1101', 'P1520', 'C1201', 'B1300', 'P1336']) {
        expect(await DtcRepository().getOtherBrandHint(c), isNotNull,
            reason: c);
      }
    });

    for (final lang in ['en', 'ar']) {
      test('[$lang] manufacturer codes → localized manufacturer label, no '
          'other-brand text', () async {
        final repo = DtcRepository();
        for (final code in mfrCodes) {
          final d = await repo.getDtcDescription(code, languageCode: lang);
          expect(d, DtcRepository.manufacturerLabel(code, languageCode: lang),
              reason: code);
          expect(d, contains(code), reason: code);
          if (lang == 'ar') {
            expect(d, matches(arabicScript), reason: code);
          } else {
            expect(d, _mfrLabel(code), reason: code);
          }
          for (final f in foreign) {
            expect(d, isNot(contains(f)), reason: '$code contains "$f"');
          }
        }
        expect(httpRequests, isEmpty);
      });
    }

    test('sloppy input (" u1101 ", "p1745") is normalized, still the '
        'manufacturer label', () async {
      final repo = DtcRepository();
      expect(await repo.getDtcDescription(' u1101 '), _mfrLabel('U1101'));
      expect(await repo.getDtcDescription('p1745', languageCode: 'ar'),
          DtcRepository.manufacturerLabel('P1745', languageCode: 'ar'));
    });

    test('range boundaries: P3400 / P2xxx / P0xxx / U0xxx are SAE (not the '
        'manufacturer label); malformed → null', () async {
      final repo = DtcRepository();
      for (final c in ['P3400', 'P2263', 'P0300', 'U0100', 'C0035', 'B0001']) {
        final d = await repo.getDtcDescription(c);
        expect(d, isNotNull, reason: c);
        expect(d, isNot(contains('Manufacturer-specific')), reason: c);
      }
      for (final c in ['P174', 'P17455', 'Z1745', 'P4000', '', 'P1G45']) {
        expect(await repo.getDtcDescription(c), isNull, reason: c);
      }
    });

    test('getOtherBrandHint is clearly labelled (EN + AR) and only for '
        'manufacturer codes the DB knows', () async {
      final repo = DtcRepository();
      final en = await repo.getOtherBrandHint('P1745');
      expect(en, 'On some brands (often Ford/GM) this code means: '
          'Line Pressure Solenoid System');
      final ar = await repo.getOtherBrandHint('U1101', languageCode: 'ar');
      expect(ar, startsWith('لدى بعض العلامات التجارية (غالباً فورد/جنرال '
          'موتورز) يعني هذا الرمز: '));
      expect(ar, contains('J1850'));
      // Never a hint for SAE codes, unknown manufacturer codes or junk.
      expect(await repo.getOtherBrandHint('P0300'), isNull);
      expect(await repo.getOtherBrandHint('P1006'), isNull);
      expect(await repo.getOtherBrandHint('U1300'), isNull);
      expect(await repo.getOtherBrandHint('garbage'), isNull);
      // Asking for the hint does not change the description.
      expect(await repo.getDtcDescription('P1745'), _mfrLabel('P1745'));
    });

    // ---- Connect: combustion cars that are OFF still get ecuNotResponding --

    OBDConnectException failConnect(SimCar car, {List<String>? cmds}) {
      OBDConnectException? err;
      sim(car, (rig) {
        try {
          rig.connect();
        } on OBDConnectException catch (e) {
          err = e;
        }
        cmds?.addAll(rig.elm.commands);
      }, connect: false);
      if (err == null) fail('connect() succeeded');
      return err!;
    }

    test('Haval H9 OFF, gateway ACKs (NO DATA), resting battery 12.4 V → '
        'ATRV asked, ecuNotResponding', () {
      final cmds = <String>[];
      final e = failConnect(
        const SimCar(
          protocol: null,
          wrongProtocolReply: 'NO DATA',
          ignitionOffReply: 'UNABLE TO CONNECT',
          adapterVoltage: '12.4V',
        ),
        cmds: cmds,
      );
      expect(e.reason, OBDFailureReason.ecuNotResponding);
      expect(e.message, contains('ignition'));
      expect(cmds.last, 'ATRV');
    });

    test('Tiggo 2012 K-line OFF (CAN ERROR, then BUS INIT: ...ERROR) even '
        'with 14.1 V on pin 16 → ecuNotResponding, no ATRV', () {
      final cmds = <String>[];
      final e = failConnect(
        const SimCar(
          protocol: null,
          wrongProtocolReply: 'CAN ERROR',
          ignitionOffReply: 'BUS INIT: ...ERROR',
          adapterVoltage: '14.1V',
        ),
        cmds: cmds,
      );
      expect(e.reason, OBDFailureReason.ecuNotResponding);
      expect(cmds, isNot(contains('ATRV')));
    });

    test('every profile still connects without ATRV in the handshake, and '
        'every first poll is < 3 s', () {
      var worst = Duration.zero;
      for (final v in _vehicles) {
        sim(v.build(), (rig) {
          rig.connect();
          expect(rig.elm.commands, isNot(contains('ATRV')), reason: v.name);
          expect(rig.adapter.isConnected, isTrue, reason: v.name);
          final p = _poll(rig);
          if (p.cycle > worst) worst = p.cycle;
          expect(p.cycle, lessThan(const Duration(seconds: 3)),
              reason: v.name);
        }, connect: false);
      }
      _log('double-check: worst first poll ${_secs(worst)} s');
    });
  });
}
