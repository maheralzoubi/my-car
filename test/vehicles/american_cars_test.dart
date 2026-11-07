// Compatibility matrix: American vehicles (incl. GCC-market models) driven
// through [ProductionOBDAdapter] + [VinDecoder] with the ELM327 simulator.
//
// Each vehicle is described once as a [Vehicle] (bus protocol, timings, one
// [Ecu] per emissions-related module). [VehicleCar] turns that description
// into ELM327-formatted replies per SAE J1979 / ISO 15765-4 / SAE J1850:
//   • 0100/0120/0140/0160 support bitmaps are *computed* from the PIDs each
//     ECU actually answers, so bitmaps and replies can never disagree;
//   • unsupported PIDs answer NO DATA after the ELM327's default ATST timeout
//     (0x32 × 4.096 ms ≈ 205 ms) instead of the ECU latency;
//   • mode 03/07 use the CAN count-byte format (ISO-TP multi-frame when
//     > 2 codes) or the J1850 three-codes-per-message, 00-padded format;
//   • mode 09 PID 02 uses ISO-TP (014 / 0: / 1: / 2:) on CAN and five
//     "49 02 0N" messages on J1850;
//   • mode 04 really clears: codes, freeze frame, MIL, and the
//     non-continuous readiness monitors reset to "incomplete".
//
// Where a detail of a specific vehicle is not documented well enough, the
// profile says so in a comment ("unverified") rather than presenting it as
// fact. Tests that exposed app bugs assert the correct behaviour; they were
// skipped with 'BUG: …' until the fixes landed and now always run. The
// 'regression' group probes those fixes; anything still wrong there is
// skipped with 'REGRESSION: …'.

import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/vin_decoder.dart';

import '../helpers/elm327_sim.dart';

// ── J1979 encoding helpers ────────────────────────────────────────────────────

String _hex(Iterable<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

String _h2(int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase();

int _u8(num x) => x.round().clamp(0, 255).toInt();

/// Physical value → mode 01/02 data bytes (SAE J1979 Appendix B formulas).
List<int> encodePid(int pid, double v) {
  switch (pid) {
    case 0x04 || 0x11 || 0x2F: // %
      return [_u8(v * 255 / 100)];
    case 0x05 || 0x0F || 0x5C: // °C, offset 40
      return [_u8(v + 40)];
    case >= 0x06 && <= 0x09: // fuel trim %
      return [_u8((v + 100) * 1.28)];
    case 0x0B || 0x0D: // kPa, km/h
      return [_u8(v)];
    case 0x0C: // rpm, 1/4 rpm per bit
      final r = (v * 4).round();
      return [r >> 8, r & 0xFF];
    case 0x0E: // timing advance, 0.5° per bit, offset -64°
      return [_u8((v + 64) * 2)];
    case 0x14 || 0x18: // upstream narrowband: V, STFT used (0x80 = 0 %)
      return [_u8(v * 200), 0x80];
    case 0x15: // downstream: V, 0xFF = not used for trim
      return [_u8(v * 200), 0xFF];
    case 0x42: // mV
      final r = (v * 1000).round();
      return [r >> 8, r & 0xFF];
  }
  throw ArgumentError('no encoder for PID ${_h2(pid)}');
}

/// Resolution (one LSB) of each polled PID, used as the closeTo tolerance.
const _lsb = <int, double>{
  0x04: 0.4,
  0x11: 0.4,
  0x2F: 0.4,
  0x05: 0,
  0x0F: 0,
  0x5C: 0,
  0x06: 0.8,
  0x07: 0.8,
  0x08: 0.8,
  0x09: 0.8,
  0x0B: 0,
  0x0D: 0,
  0x0C: 0.25,
  0x0E: 0.5,
  0x14: 0.005,
  0x15: 0.005,
  0x18: 0.005,
  0x42: 0.001,
  0x24: 1 / 32768,
  0x34: 1 / 32768,
  0x23: 10,
  0x49: 0.4,
};

/// J1979 decode of the extra live PIDs (wide-band O2, diesel rail pressure
/// and pedal), which the profiles keep as raw bytes in [Ecu.raw].
double? _decodeExtra(int pid, List<int> b) => switch (pid) {
  0x24 || 0x34 => (b[0] * 256 + b[1]) / 32768, // equivalence ratio λ
  0x23 => (b[0] * 256 + b[1]) * 10.0, // kPa
  0x49 => b[0] * 100 / 255, // %
  _ => null,
};

/// The 18 PIDs a live-data poll can read, in the order
/// ProductionOBDAdapter._poll sends them, with the field each fills. Only
/// those the 0100/0120/0140 support bitmaps advertise are actually sent.
final _pollPids = <(int, double? Function(OBDLiveData))>[
  (0x0C, (d) => d.rpm),
  (0x0D, (d) => d.speedKmh),
  (0x05, (d) => d.coolantTempC),
  (0x11, (d) => d.throttlePct),
  (0x2F, (d) => d.fuelLevelPct),
  (0x04, (d) => d.engineLoad),
  (0x42, (d) => d.batteryVoltage),
  (0x5C, (d) => d.oilTempC),
  (0x06, (d) => d.fuelTrimShortPct),
  (0x07, (d) => d.fuelTrimLongPct),
  (0x08, (d) => d.fuelTrimShortB2),
  (0x09, (d) => d.fuelTrimLongB2),
  (0x14, (d) => d.o2B1S1Voltage),
  (0x15, (d) => d.o2B1S2Voltage),
  (0x18, (d) => d.o2B2S1Voltage),
  (0x0F, (d) => d.intakeAirTempC),
  (0x0B, (d) => d.mapKpa),
  (0x0E, (d) => d.timingAdvanceDeg),
  // Extras, read only when the bitmap explicitly advertises them (0124 /
  // 0134 only without a narrow-band 0114; 0124 preferred).
  (0x24, (d) => d.lambdaB1S1),
  (0x34, (d) => d.lambdaB1S1),
  (0x23, (d) => d.fuelRailPressureKpa),
  (0x49, (d) => d.acceleratorPedalPct),
];

/// DTC string ("P0420", "P20EE") → the two J1979 bytes.
List<int> encodeDtc(String code) {
  final letter = 'PCBU'.indexOf(code[0]);
  final b1 =
      (letter << 6) | (int.parse(code[1]) << 4) | int.parse(code[2], radix: 16);
  return [b1, int.parse(code.substring(3), radix: 16)];
}

// ISO 3779 check digit (position 9).
const _translit = {
  'A': 1,
  'B': 2,
  'C': 3,
  'D': 4,
  'E': 5,
  'F': 6,
  'G': 7,
  'H': 8,
  'J': 1,
  'K': 2,
  'L': 3,
  'M': 4,
  'N': 5,
  'P': 7,
  'R': 9,
  'S': 2,
  'T': 3,
  'U': 4,
  'V': 5,
  'W': 6,
  'X': 7,
  'Y': 8,
  'Z': 9,
};
const _weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];

bool vinCheckDigitValid(String vin) {
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    final c = vin[i];
    sum += (int.tryParse(c) ?? _translit[c]!) * _weights[i];
  }
  final r = sum % 11;
  return vin[8] == (r == 10 ? 'X' : '$r');
}

// ── Readiness (PID 01) ────────────────────────────────────────────────────────

const _continuous = ['Misfire', 'Fuel System', 'Components'];
const _sparkBits = [
  'Catalyst',
  'Heated Catalyst',
  'Evap System',
  'Secondary Air',
  'A/C System',
  'O2 Sensor',
  'O2 Sensor Heater',
  'EGR / VVT',
];
const _ciBits = [
  'NMHC Catalyst',
  'NOx / SCR',
  null,
  'Boost Pressure',
  null,
  'Exhaust Gas Sensor',
  'PM Filter',
  'EGR / VVT',
];

class Readiness {
  const Readiness({
    this.diesel = false,
    required this.supported,
    this.incomplete = const {},
  });

  final bool diesel;
  final Set<String> supported;
  final Set<String> incomplete;

  List<String?> get _bits => diesel ? _ciBits : _sparkBits;

  /// Bytes B, C, D of PID 01 (byte A depends on the ECU's DTCs).
  List<int> bcd({required bool cleared}) {
    var b = diesel ? 0x08 : 0;
    var c = 0;
    var d = 0;
    for (var i = 0; i < 3; i++) {
      final n = _continuous[i];
      if (supported.contains(n)) b |= 1 << i;
      if (supported.contains(n) && incomplete.contains(n)) b |= 1 << (i + 4);
    }
    for (var i = 0; i < 8; i++) {
      final n = _bits[i];
      if (n == null || !supported.contains(n)) continue;
      c |= 1 << i;
      // Mode 04 resets every non-continuous monitor to "not complete".
      if (cleared || incomplete.contains(n)) d |= 1 << i;
    }
    return [b, c, d];
  }
}

// ── Vehicle model ─────────────────────────────────────────────────────────────

class Ecu {
  const Ecu(
    this.name, {
    this.live = const {},
    this.raw = const {},
    this.readiness,
    this.confirmed = const [],
    this.pending = const [],
    this.answersVin = false,
    this.freeze = const {},
  });

  final String name;

  /// Polled PIDs the ECU supports → physical value.
  final Map<int, double> live;

  /// Other supported mode 01 PIDs (not polled by the app) → raw data bytes.
  /// They only matter for the support bitmaps.
  final Map<int, List<int>> raw;

  final Readiness? readiness;
  final List<String> confirmed;
  final List<String> pending;
  final bool answersVin;

  /// Mode 02 frame 0 → physical values (only stored while a DTC is).
  final Map<int, double> freeze;

  Set<int> get supported => {
    ...live.keys,
    ...raw.keys,
    if (readiness != null) 0x01,
  };
}

enum Bus { can, j1850 }

class Vehicle {
  const Vehicle({
    required this.name,
    required this.protocol,
    required this.bus,
    required this.vin,
    required this.ecus,
    required this.expectedMake,
    required this.expectedYear,
    required this.expectedCountry,
    this.autoSearch = const Duration(seconds: 9),
    this.ecuLatency = const Duration(milliseconds: 60),
    this.noDataLatency = const Duration(milliseconds: 205),
    this.latencyOverrides = const {},
    this.wrongProtocolReply = 'NO DATA',
    this.clearReply = '44',
    this.tcmFirst = const {},
    this.vinInterleaved = false,
    this.interleaveDtcs = false,
    this.skips = const {},
  });

  final String name;
  final String protocol; // ELM327 protocol number
  final Bus bus;
  final String vin;
  final List<Ecu> ecus; // in default bus-arrival order (ECM first)
  final Matcher expectedMake;
  final String expectedYear;
  final String expectedCountry;
  final Duration autoSearch;
  final Duration ecuLatency;
  final Duration noDataLatency;
  final Map<String, Duration> latencyOverrides;
  final String wrongProtocolReply;

  /// Per-ECU reply to mode 04 ('44' = positive, '7F 04 22' = rejected).
  final String clearReply;

  /// Requests the second ECU answers before the first.
  final Set<String> tcmFirst;

  /// Two ECUs' ISO-TP VIN replies interleave frame by frame (headers off).
  final bool vinInterleaved;

  /// The second ECU's single-frame mode 03 reply arrives between the first
  /// ECU's First Frame and its Consecutive Frame.
  final bool interleaveDtcs;

  /// Test id → skip reason.
  final Map<String, String> skips;

  Ecu get ecm => ecus.first;

  Vehicle copyWith({
    String? name,
    String? protocol,
    Duration? autoSearch,
    String? wrongProtocolReply,
    List<Ecu>? ecus,
    String? clearReply,
    Set<String>? tcmFirst,
    bool? interleaveDtcs,
  }) => Vehicle(
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    bus: bus,
    vin: vin,
    ecus: ecus ?? this.ecus,
    expectedMake: expectedMake,
    expectedYear: expectedYear,
    expectedCountry: expectedCountry,
    autoSearch: autoSearch ?? this.autoSearch,
    ecuLatency: ecuLatency,
    noDataLatency: noDataLatency,
    latencyOverrides: latencyOverrides,
    wrongProtocolReply: wrongProtocolReply ?? this.wrongProtocolReply,
    clearReply: clearReply ?? this.clearReply,
    tcmFirst: tcmFirst ?? this.tcmFirst,
    vinInterleaved: vinInterleaved,
    interleaveDtcs: interleaveDtcs ?? this.interleaveDtcs,
  );

  // ── Expected results (what a correct J1979 tester would report) ──────────

  List<String> get expectedDtcs {
    final confirmed = <String>[];
    for (final e in ecus) {
      for (final c in e.confirmed) {
        if (!confirmed.contains(c)) confirmed.add(c);
      }
    }
    final pending = <String>[];
    for (final e in ecus) {
      for (final p in e.pending) {
        if (!confirmed.contains(p) && !pending.contains('~$p')) {
          pending.add('~$p');
        }
      }
    }
    return [...confirmed, ...pending];
  }

  bool get diesel => ecm.readiness?.diesel ?? false;

  /// J1979 §6.1: a tester combines PID 01 across ECUs — MIL is on if any
  /// ECU says so, DTC counts add up, a monitor is supported if any ECU
  /// supports it and incomplete if any supporting ECU reports it incomplete.
  Map<String, MonitorStatus> expectedMonitors({bool cleared = false}) {
    final names = [
      ..._continuous,
      ...(diesel ? _ciBits : _sparkBits),
    ].whereType<String>();
    return {
      for (final n in names)
        n: () {
          final sup = ecus.where(
            (e) => e.readiness?.supported.contains(n) ?? false,
          );
          if (sup.isEmpty) return MonitorStatus.notApplicable;
          final nonContinuous = !_continuous.contains(n);
          final inc = sup.any(
            (e) =>
                e.readiness!.incomplete.contains(n) ||
                (cleared && nonContinuous),
          );
          return inc ? MonitorStatus.notReady : MonitorStatus.ready;
        }(),
    };
  }

  bool get expectedMil => ecus.any((e) => e.confirmed.isNotEmpty);
  int get expectedDtcCount => ecus.fold(0, (n, e) => n + e.confirmed.length);

  Map<String, String> get expectedFreeze {
    final f = ecm.freeze;
    final out = <String, String>{};
    String? fmt(int pid, List<int> b) => switch (pid) {
      0x0C => '${((b[0] * 256 + b[1]) / 4).toStringAsFixed(0)} rpm',
      0x0D => '${b[0]} km/h',
      0x05 => '${b[0] - 40}°C',
      0x04 => '${(b[0] * 100 / 255).toStringAsFixed(1)}%',
      0x0F => '${b[0] - 40}°C',
      0x11 => '${(b[0] * 100 / 255).toStringAsFixed(1)}%',
      0x06 => '${((b[0] / 1.28) - 100).toStringAsFixed(1)}%',
      0x0B => '${b[0]} kPa',
      _ => null,
    };
    const labels = {
      0x0C: 'RPM',
      0x0D: 'Speed',
      0x05: 'Coolant',
      0x04: 'Engine Load',
      0x0F: 'Air Temp',
      0x11: 'Throttle',
      0x06: 'Fuel Trim',
      0x0B: 'MAP',
    };
    for (final MapEntry(key: pid, value: label) in labels.entries) {
      final v = f[pid];
      if (v == null) continue;
      out[label] = fmt(pid, encodePid(pid, v))!;
    }
    return out;
  }
}

// ── SimCar backed by a Vehicle (stateful: mode 04 clears) ─────────────────────

class VehicleCar extends SimCar {
  /// [adapterVoltage] = the ELM327's ATRV reply (null → '?').
  VehicleCar(this.v, {super.adapterVoltage})
    : super(
        protocol: v.protocol,
        autoSearchTime: v.autoSearch,
        ecuLatency: v.ecuLatency,
        wrongProtocolReply: v.wrongProtocolReply,
      );

  final Vehicle v;
  bool cleared = false;

  @override
  String answer(String cmd) {
    if (cmd == '04') {
      if (v.clearReply == '44') cleared = true;
      return v.ecus.map((_) => v.clearReply).join('\n');
    }
    return respond(cmd);
  }

  @override
  Duration latency(String cmd) {
    if (cmd == '04') return v.ecuLatency;
    if (respond(cmd) == 'NO DATA') return v.noDataLatency;
    return v.latencyOverrides[cmd] ?? v.ecuLatency;
  }

  String respond(String cmd) {
    final ecus = v.tcmFirst.contains(cmd) ? v.ecus.reversed : v.ecus;
    final perEcu = [for (final e in ecus) ?_ecuReply(e, cmd)];
    if (perEcu.isEmpty) return 'NO DATA';

    if (perEcu.length == 2 && cmd == '0902' && v.vinInterleaved) {
      return _interleaveVin(perEcu[0], perEcu[1]);
    }
    if (perEcu.length == 2 &&
        cmd == '03' &&
        v.interleaveDtcs &&
        perEcu[0].length > 2) {
      final [a, b] = perEcu;
      return [a[0], a[1], ...b, ...a.skip(2)].join('\n');
    }
    return perEcu.expand((l) => l).join('\n');
  }

  /// "014 / 0: / 1: / 2:" from two ECUs, as the ELM327 prints them with
  /// headers off: both First Frames, then the Consecutive Frames pairwise.
  static String _interleaveVin(List<String> a, List<String> b) => [
    a[0],
    a[1],
    b[0],
    b[1],
    for (var i = 2; i < a.length; i++) ...[a[i], b[i]],
  ].join('\n');

  List<String>? _ecuReply(Ecu e, String cmd) {
    final can = v.bus == Bus.can;

    // ── Mode 01 ──
    if (cmd.length == 4 && cmd.startsWith('01')) {
      final pid = int.parse(cmd.substring(2), radix: 16);
      if (pid % 0x20 == 0) {
        final sup = e.supported;
        // 0x20/0x40/0x60 is only answered when the previous bitmap's last
        // bit says so, i.e. some PID above it is supported.
        if (pid != 0 && !sup.any((p) => p > pid)) return null;
        final bits = [0, 0, 0, 0];
        for (var i = 0; i < 32; i++) {
          final p = pid + 1 + i;
          final has = i == 31 ? sup.any((q) => q > p) : sup.contains(p);
          if (has) bits[i ~/ 8] |= 0x80 >> (i % 8);
        }
        return ['41 ${_h2(pid)} ${_hex(bits)}'];
      }
      if (pid == 0x01 && e.readiness != null) {
        final codes = cleared ? 0 : e.confirmed.length;
        final a = (codes > 0 ? 0x80 : 0) | codes;
        return [
          '41 01 ${_hex([a, ...e.readiness!.bcd(cleared: cleared)])}',
        ];
      }
      final live = e.live[pid];
      if (live != null) return ['41 ${_h2(pid)} ${_hex(encodePid(pid, live))}'];
      final raw = e.raw[pid];
      if (raw != null) return ['41 ${_h2(pid)} ${_hex(raw)}'];
      return null;
    }

    // ── Mode 03 / 07 ──
    if (cmd == '03' || cmd == '07') {
      final mode = cmd == '03' ? '43' : '47';
      final codes = cleared
          ? const <String>[]
          : (cmd == '03' ? e.confirmed : e.pending);
      final bytes = [for (final c in codes) ...encodeDtc(c)];
      if (can) {
        final payload = [int.parse(mode, radix: 16), codes.length, ...bytes];
        if (payload.length <= 7) return [_hex(payload)]; // single frame
        // ISO-TP: FF carries 6 data bytes, each CF 7 (last one padded).
        final lines = [payload.length.toRadixString(16).padLeft(3, '0')];
        lines.add('0: ${_hex(payload.take(6))}');
        var n = 1;
        for (var i = 6; i < payload.length; i += 7, n++) {
          final chunk = payload.skip(i).take(7).toList();
          while (chunk.length < 7) {
            chunk.add(0x00);
          }
          lines.add(
            '${(n % 16).toRadixString(16).toUpperCase()}: '
            '${_hex(chunk)}',
          );
        }
        return lines;
      }
      // J1850 / ISO 9141: three codes per message, padded with 00 00.
      final lines = <String>[];
      for (var i = 0; i < bytes.length || i == 0; i += 6) {
        final chunk = bytes.skip(i).take(6).toList();
        while (chunk.length < 6) {
          chunk.add(0x00);
        }
        lines.add('$mode ${_hex(chunk)}');
      }
      return lines;
    }

    // ── Mode 09 PID 02 (VIN) ──
    if (cmd == '0902') {
      if (!e.answersVin) return null;
      final ascii = v.vin.codeUnits;
      if (can) {
        final payload = [0x49, 0x02, 0x01, ...ascii]; // 20 bytes = 0x014
        return [
          '014',
          '0: ${_hex(payload.sublist(0, 6))}',
          '1: ${_hex(payload.sublist(6, 13))}',
          '2: ${_hex(payload.sublist(13, 20))}',
        ];
      }
      final data = [0, 0, 0, ...ascii]; // 20 bytes over 5 messages
      return [
        for (var m = 0; m < 5; m++)
          '49 02 ${_h2(m + 1)} ${_hex(data.sublist(m * 4, m * 4 + 4))}',
      ];
    }

    // ── Mode 02 frame 00 (freeze frame) ──
    if (cmd.length == 6 && cmd.startsWith('02') && cmd.endsWith('00')) {
      if (cleared || e.confirmed.isEmpty) return null;
      final pid = int.parse(cmd.substring(2, 4), radix: 16);
      if (pid == 0x02) {
        return ['42 02 00 ${_hex(encodeDtc(e.confirmed.first))}'];
      }
      final val = e.freeze[pid];
      if (val == null) return null;
      return ['42 ${_h2(pid)} 00 ${_hex(encodePid(pid, val))}'];
    }
    return null;
  }
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

// Supported-but-not-polled PIDs with plausible raw values.
const _fuelSysClosedLoop = [0x02, 0x00]; // PID 03
const _obd2Carb = [0x01]; // PID 1C = OBD-II as defined by CARB

const _gasStdCan = <int, List<int>>{
  0x03: _fuelSysClosedLoop,
  0x1C: _obd2Carb,
  0x1F: [0x01, 0x2C], // run time 300 s
  0x21: [0x00, 0x00], // distance with MIL on
  0x30: [0x0A], // warm-ups since clear
  0x31: [0x05, 0xDC], // 1500 km since clear
  0x33: [0x65], // baro 101 kPa
  0x3C: [0x11, 0x94], // catalyst temp B1S1
  0x41: [0x00, 0x07, 0xE5, 0x00], // monitor status this drive cycle
  0x43: [0x00, 0x40], // absolute load
  0x44: [0x80, 0x00], // commanded equivalence ratio 1.0
  0x45: [0x10], // relative throttle
  0x46: [0x4B], // ambient 35 °C (Gulf)
  0x47: [0x30], // absolute throttle B
  0x49: [0x26], // accelerator pedal D
  0x4A: [0x13], // accelerator pedal E
  0x4C: [0x10], // commanded throttle actuator
  0x51: [0x01], // fuel type: gasoline
};

/// 1. Ford Taurus 2022, Changan Ford (Hangzhou), GCC spec. 2.0 L EcoBoost
/// I4. ISO 15765-4 CAN 11-bit 500k (ELM protocol 6), single PCM answering
/// (transmission control assumed integrated in the PCM — unverified).
/// Upstream sensor is a wideband UEGO, so it reports via PID 34 and the
/// narrowband PID 14 answers NO DATA; no bank 2 on an I4. Oil temp PID 5C
/// modelled unsupported (unverified for this engine).
final taurus2022 = Vehicle(
  name: 'Ford Taurus 2022 (Changan, GCC)',
  protocol: '6',
  bus: Bus.can,
  vin: 'LVSHFFAC4NS123456', // LVS = Changan Ford; N = 2022
  expectedMake: equals('Ford (Changan)'),
  expectedYear: '2022',
  expectedCountry: 'China',
  ecus: [
    Ecu(
      'PCM',
      live: {
        0x04: 23.5,
        0x05: 92,
        0x06: 0.8,
        0x07: -2.3,
        0x0B: 34,
        0x0C: 725,
        0x0D: 0,
        0x0E: 12.5,
        0x0F: 46,
        0x11: 15.7,
        0x15: 0.72,
        0x2F: 62,
        0x42: 14.21,
      },
      raw: {
        ..._gasStdCan,
        0x10: [0x01, 0x2C], // MAF 3 g/s
        0x13: [0x03], // O2 sensors present: B1S1, B1S2
        0x34: [0x80, 0x00, 0x80, 0x00], // wideband B1S1
      },
      readiness: Readiness(
        supported: {
          ..._continuous,
          'Catalyst',
          'Evap System',
          'O2 Sensor',
          'O2 Sensor Heater',
          'EGR / VVT',
        },
        incomplete: {'Evap System'},
      ),
      confirmed: ['P0299'], // turbo underboost — common EcoBoost code
      pending: ['P0171'],
      answersVin: true,
      freeze: {
        0x0C: 2450,
        0x0D: 88,
        0x05: 95,
        0x04: 78.4,
        0x0F: 49,
        0x11: 42,
        0x06: -3.1,
        0x0B: 96,
      },
    ),
  ],
);

/// 2. Ford F-150 2018, 5.0 L Coyote V8 + 10R80. CAN 11-bit 500k. The 10R80
/// has its own TCM (7E9) which also answers mode 01/03 (its mode 01 PID
/// set is unverified; modelled as 0100/0101 only). Upstream UEGO sensors →
/// PIDs 14/18 NO DATA, bank-2 trims present.
final f150_2018 = Vehicle(
  name: 'Ford F-150 2018 5.0 V8',
  protocol: '6',
  bus: Bus.can,
  vin: '1FTEW1EP5JFA45871', // SuperCrew 4x4, J = 2018, F = Dearborn
  expectedMake: equals('Ford'),
  expectedYear: '2018',
  expectedCountry: 'United States',
  ecuLatency: Duration(milliseconds: 80),
  ecus: [
    Ecu(
      'PCM',
      live: {
        0x04: 19.6,
        0x05: 98,
        0x06: 1.6,
        0x07: 3.1,
        0x08: -0.8,
        0x09: 2.3,
        0x0B: 31,
        0x0C: 612,
        0x0D: 0,
        0x0E: 14,
        0x0F: 41,
        0x11: 13.3,
        0x15: 0.68,
        0x2F: 47.5,
        0x42: 14.05,
      },
      raw: {
        ..._gasStdCan,
        0x10: [0x02, 0x58],
        0x13: [0x33], // B1S1, B1S2, B2S1, B2S2
        0x19: [0x8C, 0xFF], // B2S2 narrowband
        0x34: [0x80, 0x00, 0x80, 0x00],
        0x38: [0x80, 0x00, 0x80, 0x00], // wideband B2S1
        0x3E: [0x11, 0x80],
      },
      readiness: Readiness(
        supported: {
          ..._continuous,
          'Catalyst',
          'Evap System',
          'O2 Sensor',
          'O2 Sensor Heater',
          'EGR / VVT',
        },
      ),
      // 3 codes → 8-byte payload → ISO-TP multi-frame.
      confirmed: ['P0300', 'P0316', 'P0420'],
      pending: ['P0430'],
      answersVin: true,
      freeze: {
        0x0C: 1830,
        0x0D: 64,
        0x05: 97,
        0x04: 55.3,
        0x0F: 40,
        0x11: 22.4,
        0x06: 3.9,
        0x0B: 58,
      },
    ),
    Ecu(
      'TCM',
      raw: {0x1C: _obd2Carb},
      readiness: Readiness(supported: {'Components'}),
      confirmed: ['P0729'], // gear 6 incorrect ratio
    ),
  ],
);

/// 3. Ford Explorer 2004, 4.0 L SOHC V6. SAE J1850 PWM 41.6 kbps (ELM
/// protocol 1); PCM controls the 5R55W, single responder. MAF-only engine
/// → PID 0B NO DATA; no 0120+ PIDs (pre-2005 PWM PCMs report little beyond
/// 0x20); 2F/42/5C not supported. Mode 09 VIN was only mandated from MY2005
/// (CARB 1968.2); whether this PCM answers 0902 is unverified — modelled as
/// supported so the J1850 VIN format is exercised.
final explorer2004 = Vehicle(
  name: 'Ford Explorer 2004 4.0 V6',
  protocol: '1',
  bus: Bus.j1850,
  vin: '1FMZU73E34UA38215', // E = 4.0 SOHC, 4 = 2004, U = Louisville
  expectedMake: equals('Ford'),
  expectedYear: '2004',
  expectedCountry: 'United States',
  // No CAN bus on pins 6/14: the ELM's protocol-6 frame is never ACKed.
  wrongProtocolReply: 'CAN ERROR',
  // ELM327 auto search tries J1850 PWM first: ~1–2 s on real chips.
  autoSearch: Duration(seconds: 2),
  ecuLatency: Duration(milliseconds: 90),
  latencyOverrides: {'0902': Duration(milliseconds: 300)},
  ecus: [
    Ecu(
      'PCM',
      live: {
        0x04: 21.2,
        0x05: 90,
        0x06: -1.6,
        0x07: 7.8,
        0x08: -0.8,
        0x09: 8.6,
        0x0C: 680,
        0x0D: 0,
        0x0E: 15,
        0x0F: 52,
        0x11: 9.4,
        0x14: 0.42,
        0x15: 0.71,
        0x18: 0.55,
      },
      raw: {
        0x03: _fuelSysClosedLoop,
        0x10: [0x01, 0xF4],
        0x13: [0x33],
        0x19: [0x8C, 0xFF],
        0x1C: _obd2Carb,
      },
      readiness: Readiness(
        supported: {
          ..._continuous, 'Catalyst', 'Evap System', 'O2 Sensor',
          'O2 Sensor Heater', 'EGR / VVT', // DPFE EGR
        },
        incomplete: {'Evap System'},
      ),
      // Lean both banks + EGR flow + evap — the classic 4.0 SOHC set.
      // 4 codes → two J1850 messages, the second padded.
      confirmed: ['P0171', 'P0174', 'P0401', 'P0455'],
      pending: ['P0300'],
      answersVin: true,
      freeze: {
        0x0C: 2140, 0x0D: 72, 0x05: 91, 0x04: 41.6, 0x0F: 48, 0x11: 18.8,
        0x06: 2.3, // 0x0B MAP: no MAP sensor → NO DATA
      },
    ),
  ],
);

/// 4. Chevrolet Tahoe 2006 (GMT800), 5.3 L LM7 V8. SAE J1850 VPW 10.4 kbps
/// (ELM protocol 2); the PCM also controls the 4L60-E, single responder.
/// Narrowband O2 sensors, MAF + MAP. 2F/42/5C not supported (unverified
/// for 2F; GM VPW PCMs of this era generally do not report fuel level).
/// No EGR on the 2006 LM7 (unverified).
final tahoe2006 = Vehicle(
  name: 'Chevrolet Tahoe 2006 5.3 V8',
  protocol: '2',
  bus: Bus.j1850,
  vin:
      '1GNEC13T86R204873', // 1GN = Chevrolet truck/MPV, 6 = 2006, R = Arlington
  expectedMake: equals('Chevrolet'),
  expectedYear: '2006',
  expectedCountry: 'United States',
  wrongProtocolReply: 'CAN ERROR',
  // Auto search fails PWM first, then finds VPW: ~3 s.
  autoSearch: Duration(seconds: 3),
  ecuLatency: Duration(milliseconds: 110),
  latencyOverrides: {'0902': Duration(milliseconds: 350)},
  ecus: [
    Ecu(
      'PCM',
      live: {
        0x04: 17.3,
        0x05: 94,
        0x06: 0,
        0x07: -1.6,
        0x08: 0.8,
        0x09: -2.3,
        0x0B: 32,
        0x0C: 575,
        0x0D: 0,
        0x0E: 18,
        0x0F: 47,
        0x11: 7.8,
        0x14: 0.61,
        0x15: 0.74,
        0x18: 0.38,
      },
      raw: {
        0x03: _fuelSysClosedLoop,
        0x10: [0x01, 0x90],
        0x13: [0x33],
        0x19: [0x8C, 0xFF],
        0x1C: _obd2Carb,
        0x1F: [0x00, 0xF0],
        0x21: [0x00, 0x00],
        0x2E: [0x00], // commanded evap purge
        0x30: [0x14],
        0x31: [0x0B, 0xB8],
        0x33: [0x64],
      },
      readiness: Readiness(
        supported: {
          ..._continuous,
          'Catalyst',
          'Evap System',
          'O2 Sensor',
          'O2 Sensor Heater',
        },
      ),
      confirmed: ['P0449'], // evap vent solenoid — common GMT800 code
      pending: ['P0174'],
      answersVin: true,
      freeze: {
        0x0C: 1450,
        0x0D: 56,
        0x05: 93,
        0x04: 33.7,
        0x0F: 44,
        0x11: 14.1,
        0x06: 4.7,
        0x0B: 46,
      },
    ),
  ],
);

/// 5. Chevrolet Silverado 1500 2020 (T1XX), 5.3 L L84 V8. CAN 11-bit 500k.
/// ECM (7E8) and TCM (7EA) both answer mode 01/03/07/04. GM TCMs answering
/// 0902 with the VIN is commonly observed on GM Global A trucks (not
/// verified for this exact vehicle); with ATH0 the two ISO-TP replies
/// interleave. Upstream wideband assumed (unverified) → PIDs 14/18 NO DATA.
final silverado2020 = Vehicle(
  name: 'Chevrolet Silverado 2020 5.3 V8',
  protocol: '6',
  bus: Bus.can,
  vin: '1GCUYDED8LZ158342', // L = 2020, Z = Fort Wayne
  expectedMake: equals('Chevrolet'),
  expectedYear: '2020',
  expectedCountry: 'United States',
  ecuLatency: Duration(milliseconds: 80),
  vinInterleaved: true,
  ecus: [
    Ecu(
      'ECM',
      live: {
        0x04: 16.9,
        0x05: 96,
        0x06: -0.8,
        0x07: 1.6,
        0x08: 0,
        0x09: 0.8,
        0x0B: 30,
        0x0C: 550,
        0x0D: 0,
        0x0E: 9.5,
        0x0F: 45,
        0x11: 16.5,
        0x15: 0.70,
        0x2F: 55.7,
        0x42: 14.38,
        0x5C: 102,
      },
      raw: {
        ..._gasStdCan,
        0x10: [0x01, 0xA4],
        0x13: [0x33],
        0x19: [0x8C, 0xFF],
        0x34: [0x80, 0x00, 0x80, 0x00],
        0x38: [0x80, 0x00, 0x80, 0x00],
      },
      readiness: Readiness(
        supported: {
          ..._continuous,
          'Catalyst',
          'Evap System',
          'O2 Sensor',
          'O2 Sensor Heater',
          'EGR / VVT',
        },
        incomplete: {'Catalyst', 'Evap System'},
      ),
      confirmed: ['P0521'], // oil pressure sensor performance
      pending: ['P0300'],
      answersVin: true,
      freeze: {
        0x0C: 2210,
        0x0D: 97,
        0x05: 99,
        0x04: 47.1,
        0x0F: 43,
        0x11: 20.4,
        0x06: -1.6,
        0x0B: 63,
      },
    ),
    Ecu(
      'TCM',
      live: {0x0D: 0},
      raw: {0x1C: _obd2Carb},
      readiness: Readiness(supported: {'Components'}),
      confirmed: ['P0842'], // trans fluid pressure switch A circuit low
      answersVin: true,
    ),
  ],
);

/// 6. GMC Yukon 2015 (K2XX), 5.3 L L83 V8 + 6L80. CAN 11-bit 500k. ECM +
/// TCM (7EA) answer mode 01/03. Whether the K2 TCM also reports the VIN is
/// unverified — modelled ECM-only. Narrowband upstream O2 assumed
/// (unverified). Healthy truck: no DTCs, all monitors complete, so no
/// freeze frame is stored.
final yukon2015 = Vehicle(
  name: 'GMC Yukon 2015 5.3 V8',
  protocol: '6',
  bus: Bus.can,
  vin: '1GKS2BKC3FR317625', // 1GK = GMC MPV, F = 2015, R = Arlington
  expectedMake: equals('GMC'),
  expectedYear: '2015',
  expectedCountry: 'United States',
  ecuLatency: Duration(milliseconds: 80),
  ecus: [
    Ecu(
      'ECM',
      live: {
        0x04: 18.4,
        0x05: 99,
        0x06: 1.6,
        0x07: -0.8,
        0x08: 0.8,
        0x09: 1.6,
        0x0B: 29,
        0x0C: 525,
        0x0D: 0,
        0x0E: 11,
        0x0F: 48,
        0x11: 15.3,
        0x14: 0.78,
        0x15: 0.69,
        0x18: 0.12,
        0x2F: 81.2,
        0x42: 14.27,
        0x5C: 96,
      },
      raw: {
        ..._gasStdCan,
        0x10: [0x01, 0xB8],
        0x13: [0x33],
        0x19: [0x8C, 0xFF],
      },
      readiness: Readiness(
        supported: {
          ..._continuous,
          'Catalyst',
          'Evap System',
          'O2 Sensor',
          'O2 Sensor Heater',
          'EGR / VVT',
        },
      ),
      answersVin: true,
    ),
    Ecu(
      'TCM',
      live: {0x0D: 0},
      raw: {0x1C: _obd2Carb},
      readiness: Readiness(supported: {'Components'}),
    ),
  ],
);

/// 7. Jeep Grand Cherokee 2016 (WK2), 3.6 L Pentastar V6. CAN 11-bit 500k.
/// Speed-density engine (MAP, no MAF → PID 10 unsupported), narrowband
/// switching O2 sensors. Modelled PCM-only; whether the 845RE TCM answers
/// functional mode 01 requests is unverified. PID 5C unsupported
/// (unverified).
final grandCherokee2016 = Vehicle(
  name: 'Jeep Grand Cherokee 2016 3.6 V6',
  protocol: '6',
  bus: Bus.can,
  vin:
      '1C4RJFAG9GC402918', // 1C4 = Chrysler MPV (Jeep), G = 2016, C = Jefferson North
  expectedMake: matches(RegExp('Jeep|Chrysler')),
  expectedYear: '2016',
  expectedCountry: 'United States',
  ecus: [
    Ecu(
      'PCM',
      live: {
        0x04: 20,
        0x05: 101,
        0x06: 0.8,
        0x07: -3.9,
        0x08: 1.6,
        0x09: -1.6,
        0x0B: 33,
        0x0C: 640,
        0x0D: 0,
        0x0E: 10,
        0x0F: 50,
        0x11: 12.5,
        0x14: 0.18,
        0x15: 0.66,
        0x18: 0.80,
        0x2F: 38,
        0x42: 13.92,
      },
      raw: {
        ..._gasStdCan,
        0x13: [0x33],
        0x19: [0x8C, 0xFF],
      },
      readiness: Readiness(
        supported: {
          ..._continuous,
          'Catalyst',
          'Evap System',
          'O2 Sensor',
          'O2 Sensor Heater',
        },
      ),
      confirmed: ['P0456'], // evap very small leak
      answersVin: true,
      freeze: {
        0x0C: 690,
        0x0D: 0,
        0x05: 88,
        0x04: 18,
        0x0F: 35,
        0x11: 12.2,
        0x06: 0,
        0x0B: 31,
      },
    ),
  ],
);

/// 8. Ram 2500 2019, 6.7 L Cummins turbo-diesel (Saltillo, Mexico). The
/// 2500 is chassis-dyno certified (< 14,000 lb GVWR), so it uses ISO
/// 15765-4 rather than J1939; 11-bit IDs assumed (some reports suggest
/// 29-bit for Cummins ECMs — unverified; see the 29-bit variant below).
/// Compression ignition: PID 01 byte B bit 3 set, no O2/fuel-trim/timing/
/// throttle PIDs (pedal via 49/4A instead), oil temp 5C unverified →
/// unsupported. Supports 0x61–0x63 torque PIDs so 0160 is answered.
final ram2500_2019 = Vehicle(
  name: 'Ram 2500 2019 6.7 Cummins diesel',
  protocol: '6',
  bus: Bus.can,
  vin: '3C6UR5DL0KG561037', // 3C6 = Ram (Mexico), K = 2019, G = Saltillo
  expectedMake: matches(RegExp('Ram|Dodge|Chrysler')),
  expectedYear: '2019',
  expectedCountry: 'Mexico',
  ecuLatency: Duration(milliseconds: 90),
  ecus: [
    Ecu(
      'ECM',
      live: {
        0x04: 12.5,
        0x05: 82,
        0x0B: 102,
        0x0C: 750,
        0x0D: 0,
        0x0F: 38,
        0x2F: 71,
        0x42: 14.45,
      },
      raw: {
        0x1F: [0x02, 0x58],
        0x21: [0x00, 0x00],
        0x23: [0x0B, 0xB8], // fuel rail pressure 30 MPa
        0x30: [0x0A],
        0x31: [0x07, 0xD0],
        0x33: [0x64],
        0x41: [0x00, 0x0F, 0xEB, 0x00],
        0x46: [0x48],
        0x49: [0x00], // pedal D at idle
        0x4A: [0x00],
        0x51: [0x04], // fuel type: diesel
        0x61: [0x8C], // driver demand torque
        0x62: [0x8C], // actual torque
        0x63: [0x05, 0x4C], // reference torque 1356 Nm
      },
      readiness: Readiness(
        diesel: true,
        supported: {
          ..._continuous,
          'NMHC Catalyst',
          'NOx / SCR',
          'Boost Pressure',
          'Exhaust Gas Sensor',
          'PM Filter',
          'EGR / VVT',
        },
        incomplete: {'NOx / SCR', 'PM Filter'},
      ),
      confirmed: ['P20EE'], // SCR NOx catalyst efficiency below threshold
      pending: ['P2459'], // DPF regeneration frequency
      answersVin: true,
      freeze: {
        0x0C: 1650, 0x0D: 105, 0x05: 88, 0x04: 64.3, 0x0F: 41,
        0x0B: 178, // boost
      },
    ),
  ],
);

final vehicles = [
  taurus2022,
  f150_2018,
  explorer2004,
  tahoe2006,
  silverado2020,
  yukon2015,
  grandCherokee2016,
  ram2500_2019,
];

// ── Test drivers ──────────────────────────────────────────────────────────────

const _handshake = ['ATE0', 'ATL0', 'ATS0', 'ATH0'];
final _results = <String, Map<String, String>>{};

String _secs(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

void _record(Vehicle v, String key, String value) =>
    (_results[v.name] ??= {})[key] = value;

/// Runs one poll and returns (frame, poll duration, commands sent).
/// [elm] = the adapter the rig's [ProductionOBDAdapter] is talking to now
/// (differs from rig.elm after a reconnect to another car).
(OBDLiveData, Duration, List<String>) _pollOnce(Rig rig, {FakeElm327? elm}) {
  final e = elm ?? rig.elm;
  final frames = <OBDLiveData>[];
  final sub = rig.adapter.liveDataStream.listen(frames.add);
  final skip = e.commands.length;
  final t0 = rig.async.elapsed;
  rig.adapter.startLiveData();
  // The first poll starts on the first 3 s timer tick.
  while (frames.isEmpty &&
      rig.async.elapsed - t0 < const Duration(seconds: 60)) {
    rig.async.elapse(const Duration(milliseconds: 10));
  }
  rig.adapter.stopLiveData();
  final took = rig.async.elapsed - t0 - const Duration(seconds: 3);
  final cmds = e.commands.sublist(skip);
  rig.async.elapse(const Duration(seconds: 30)); // let any stray poll finish
  sub.cancel();
  expect(frames, isNotEmpty, reason: 'no live-data frame within 60 s');
  return (frames.first, took, cmds);
}

/// PIDs advertised by the union of every ECU's support bitmaps.
bool _advertised(Vehicle v, int pid) =>
    v.ecus.any((e) => e.supported.contains(pid));

/// Whether a live poll requests [pid]: advertised, and for the wide-band
/// O2 PIDs only when 0114 is not (0124 wins over 0134).
bool _polled(Vehicle v, int pid) => switch (pid) {
  0x24 => _advertised(v, 0x24) && !_advertised(v, 0x14),
  0x34 =>
    _advertised(v, 0x34) && !_advertised(v, 0x14) && !_advertised(v, 0x24),
  _ => _advertised(v, pid),
};

/// What live poll number [poll] of a connection must send (J1979 §6.1 PID
/// 00/20/40 rules): 0120 only if some ECU's 0100 has bit 0x20 set, 0140
/// only if some ECU's 0120 has bit 0x40 set (both only on the first poll),
/// then every polled PID of the poll list, in poll order, and nothing else.
/// Without 0142 the adapter asks the ELM for ATRV in its slot; the sim
/// answers '?', so that stops after the second poll.
List<String> _expectedPollCmds(Vehicle v, {int poll = 1}) {
  bool anyAbove(int base) =>
      v.ecus.any((e) => e.supported.any((p) => p > base));
  return [
    if (poll == 1 && anyAbove(0x20)) '0120',
    if (poll == 1 && anyAbove(0x40)) '0140',
    for (final (pid, _) in _pollPids)
      if (pid == 0x42 && !_advertised(v, pid)) ...[
        if (poll <= 2) 'ATRV',
      ] else if (_polled(v, pid))
        '01${_h2(pid)}',
  ];
}

/// With headers off the first ECU's line wins; ECUs are in bus order.
double? _liveValue(Vehicle v, int pid) => v.ecus
    .map((e) => e.live[pid] ?? switch (e.raw[pid]) {
          final b? => _decodeExtra(pid, b),
          null => null,
        })
    .nonNulls
    .firstOrNull;

/// Every PID the car answers decodes to its value (within one LSB); every
/// other field is null. [except] = PIDs the test makes misbehave.
void _expectDecoded(Vehicle v, OBDLiveData d, {Set<int> except = const {}}) {
  for (final (pid, field) in _pollPids) {
    if (except.contains(pid)) continue;
    if (pid == 0x34) continue; // shares lambdaB1S1 with 0x24, checked there
    final want = pid == 0x24
        ? (_polled(v, 0x24)
              ? _liveValue(v, 0x24)
              : _polled(v, 0x34) ? _liveValue(v, 0x34) : null)
        : _polled(v, pid) ? _liveValue(v, pid) : null;
    final got = field(d);
    if (want == null) {
      expect(got, isNull, reason: 'PID ${_h2(pid)} is unsupported');
    } else {
      expect(got, closeTo(want, _lsb[pid]!), reason: 'PID ${_h2(pid)}');
    }
  }
}

/// [v] with some fields replaced (Vehicle.copyWith has no vin / expected*).
Vehicle _variant(
  Vehicle v, {
  required String name,
  String? vin,
  List<Ecu>? ecus,
  Matcher? expectedMake,
  String? expectedYear,
  String? expectedCountry,
  Set<String>? tcmFirst,
  bool? vinInterleaved,
}) => Vehicle(
  name: name,
  protocol: v.protocol,
  bus: v.bus,
  vin: vin ?? v.vin,
  ecus: ecus ?? v.ecus,
  expectedMake: expectedMake ?? v.expectedMake,
  expectedYear: expectedYear ?? v.expectedYear,
  expectedCountry: expectedCountry ?? v.expectedCountry,
  autoSearch: v.autoSearch,
  ecuLatency: v.ecuLatency,
  noDataLatency: v.noDataLatency,
  latencyOverrides: v.latencyOverrides,
  wrongProtocolReply: v.wrongProtocolReply,
  clearReply: v.clearReply,
  tcmFirst: tcmFirst ?? v.tcmFirst,
  vinInterleaved: vinInterleaved ?? v.vinInterleaved,
  interleaveDtcs: v.interleaveDtcs,
);

/// [e] after it executed mode 04: no codes / freeze frame, every
/// non-continuous monitor back to "incomplete".
Ecu _clearedEcu(Ecu e) {
  final r = e.readiness;
  return Ecu(
    e.name,
    live: e.live,
    raw: e.raw,
    answersVin: e.answersVin,
    readiness: r == null
        ? null
        : Readiness(
            diesel: r.diesel,
            supported: r.supported,
            incomplete: {
              ...r.incomplete,
              ...r.supported.where((n) => !_continuous.contains(n)),
            },
          ),
  );
}

/// [VehicleCar] with scripted deviations from the vehicle model.
class ScriptedCar extends VehicleCar {
  ScriptedCar(
    super.v, {
    this.overrides = const {},
    this.latencies = const {},
    this.clearReplies,
    Set<String> silent = const {},
    Set<String> hangsOnce = const {},
  }) : _silent = silent,
       _hangsOnce = hangsOnce;

  /// Request → reply replacing what the vehicle model would answer.
  final Map<String, String> overrides;

  /// Request → ECU latency replacing the vehicle's.
  final Map<String, Duration> latencies;

  /// Mode 04 replies in bus-arrival order as (ECU name, reply). An ECU
  /// whose final line is "44" clears its own codes; the others keep theirs.
  final List<(String, String)>? clearReplies;

  final Set<String> _silent;
  final Set<String> _hangsOnce;
  final clearedEcus = <String>{};

  @override
  Set<String> get silent => _silent;

  @override
  Set<String> get hangsOnce => _hangsOnce;

  @override
  String answer(String cmd) {
    final script = clearReplies;
    if (cmd != '04' || script == null) return super.answer(cmd);
    for (final (ecu, reply) in script) {
      if (reply.split('\n').last == '44') clearedEcus.add(ecu);
    }
    return script.map((r) => r.$2).join('\n');
  }

  @override
  Duration latency(String cmd) => latencies[cmd] ?? super.latency(cmd);

  @override
  String respond(String cmd) {
    final o = overrides[cmd];
    if (o != null) return o;
    if (clearedEcus.isEmpty) return super.respond(cmd);
    return VehicleCar(afterClear).respond(cmd);
  }

  /// The vehicle as it is after the ECUs in [clearedEcus] executed mode 04.
  Vehicle get afterClear => v.copyWith(
    ecus: [
      for (final e in v.ecus) clearedEcus.contains(e.name) ? _clearedEcu(e) : e,
    ],
  );
}

/// The ISO-TP lines one CAN ECU prints for 0902 with headers off.
List<String> _vinFrames(String vin) {
  final p = [0x49, 0x02, 0x01, ...vin.codeUnits];
  return [
    '014',
    '0: ${_hex(p.sublist(0, 6))}',
    '1: ${_hex(p.sublist(6, 13))}',
    '2: ${_hex(p.sublist(13, 20))}',
  ];
}

/// Disconnects [rig]'s adapter and connects the same adapter instance to a
/// new BLE ELM327 plugged into [car]. Returns the new rig (its elm).
Rig _reconnect(Rig rig, SimCar car) {
  rig.drive(rig.adapter.disconnect());
  final next = Rig.fff0(rig.async, FakeElm327(car));
  rig.drive(rig.adapter.connect(next.device));
  expect(rig.adapter.isConnected, isTrue);
  return next;
}

/// Starts live data for [ticks] polling periods and returns, per emitted
/// frame, the time from its 3 s timer tick to the frame.
List<Duration> _pollDurations(Rig rig, int ticks) {
  final t0 = rig.async.elapsed;
  final at = <Duration>[];
  final sub = rig.adapter.liveDataStream.listen(
    (_) => at.add(rig.async.elapsed - t0),
  );
  rig.adapter.startLiveData();
  rig.async.elapse(Duration(seconds: 3 * ticks) + const Duration(seconds: 3));
  rig.adapter.stopLiveData();
  rig.async.elapse(const Duration(seconds: 30));
  sub.cancel();
  return [
    for (var i = 0; i < at.length; i++) at[i] - Duration(seconds: 3 * (i + 1)),
  ];
}

void _vehicleTests(Vehicle v) {
  String? skip(String id) => v.skips[id];

  group(v.name, () {
    test('fixture sanity: VIN check digit valid, bitmaps consistent', () {
      expect(v.vin, hasLength(17));
      expect(vinCheckDigitValid(v.vin), isTrue, reason: v.vin);
      final car = VehicleCar(v);
      // Every PID the ECM answers is advertised by its bitmaps and vice versa.
      for (var pid = 1; pid < 0x80; pid++) {
        if (pid % 0x20 == 0) continue;
        final base = (pid - 1) ~/ 0x20 * 0x20;
        final bm = car.respond('01${_h2(base)}');
        final answered = v.ecus.any((e) => e.supported.contains(pid));
        var advertised = false;
        for (final line in bm.split('\n')) {
          if (!line.startsWith('41')) continue;
          final b = line.split(' ').skip(2).map((x) => int.parse(x, radix: 16));
          final i = pid - base - 1;
          if ((b.elementAt(i ~/ 8) >> (7 - i % 8)) & 1 == 1) advertised = true;
        }
        expect(advertised, answered, reason: 'PID ${_h2(pid)}');
      }
    });

    test('(a) connect', () {
      sim(VehicleCar(v), (rig) {
        final t0 = rig.async.elapsed;
        rig.connect();
        final took = rig.async.elapsed - t0;
        _record(v, 'connect', _secs(took));
        expect(rig.adapter.isConnected, isTrue);
        expect(rig.elm.activeProtocol, v.protocol);
        if (v.protocol == '6') {
          expect(rig.elm.commands, [..._handshake, 'ATSP6', '0100']);
          expect(took, lessThan(const Duration(seconds: 2)));
        } else {
          expect(rig.elm.commands, [
            ..._handshake,
            'ATSP6',
            '0100',
            'ATSP0',
            '0100',
          ]);
          expect(took, greaterThanOrEqualTo(v.autoSearch));
          expect(took, lessThan(v.autoSearch + const Duration(seconds: 3)));
        }
      }, connect: false);
    }, skip: skip('connect'));

    test(
      '(b) one live-data poll decodes supported PIDs, null otherwise',
      () {
        sim(VehicleCar(v), (rig) {
          final (d, took, cmds) = _pollOnce(rig);
          _record(v, 'poll', _secs(took));
          final unsupported = _pollPids
              .where((p) => !v.ecus.any((e) => e.live.containsKey(p.$1)))
              .length;
          _record(v, 'unsupported', '$unsupported/${_pollPids.length}');

          // No timeouts → no resync CRs. The first poll reads the 0120 / 0140
          // bitmaps (each only if the previous one advertises it), then sends
          // every PID the bitmaps advertise exactly once and nothing else.
          expect(cmds, _expectedPollCmds(v));
          _expectDecoded(v, d);
          expect(took, lessThan(const Duration(seconds: 6)));
        });
      },
      skip: skip('live'),
    );

    test('(c) DTCs: confirmed + pending, then clear', () {
      sim(VehicleCar(v), (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), v.expectedDtcs);
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        expect(rig.elm.commands.last, '04');
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isFalse);
        expect(r.dtcCount, 0);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, v.expectedMonitors(cleared: true));
        expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
      });
    }, skip: skip('dtc'));

    test('(d1) getVin() reads ${v.vin}', () {
      sim(VehicleCar(v), (rig) {
        expect(rig.drive(rig.adapter.getVin()), v.vin);
      });
    }, skip: skip('vin'));

    test('(d2) VinDecoder: make / model year / country', () {
      sim(VehicleCar(v), (rig) {
        final vin = rig.drive(rig.adapter.getVin());
        expect(vin, isNotNull);
        final info = VinDecoder.decode(vin!, now: DateTime(2026, 11, 3));
        expect(info['manufacturer'], v.expectedMake);
        expect(info['year'], v.expectedYear);
        expect(info['country'], v.expectedCountry);
      });
    }, skip: skip('vinDecode'));

    test(
      '(e) readiness monitors (spark vs compression ignition), MIL',
      () {
        sim(VehicleCar(v), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.compressionIgnition, v.diesel);
          expect(r.milOn, v.expectedMil);
          expect({
            for (final m in r.monitors) m.name: m.status,
          }, v.expectedMonitors());
        });
      },
      skip: skip('readiness'),
    );

    test('(e2) readiness DTC count summed over all ECUs', () {
      sim(VehicleCar(v), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.dtcCount, v.expectedDtcCount);
      });
    }, skip: skip('dtcCount'));

    test('(f) freeze frame', () {
      sim(VehicleCar(v), (rig) {
        expect(rig.drive(rig.adapter.getFreezeFrame()), v.expectedFreeze);
      });
    }, skip: skip('freeze'));
  });
}

void main() {
  for (final v in vehicles) {
    _vehicleTests(v);
  }

  // ── Variants: realistic but timing- or condition-dependent behaviour ──────

  group('variants', () {
    test('Silverado: TCM answers PID 01 before the ECM → readiness and MIL '
        'must still reflect the ECM', () {
      final v = silverado2020.copyWith(tcmFirst: {'0101'});
      sim(VehicleCar(v), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, v.expectedMonitors());
      });
    });

    test('Silverado: TCM single-frame mode 03 reply lands between the ECM\'s '
        'ISO-TP frames → no code lost', () {
      final v = silverado2020.copyWith(
        interleaveDtcs: true,
        ecus: [
          Ecu(
            'ECM',
            live: silverado2020.ecm.live,
            raw: silverado2020.ecm.raw,
            readiness: silverado2020.ecm.readiness,
            confirmed: const ['P0521', 'P0300', 'P0420'],
            answersVin: true,
          ),
          silverado2020.ecus[1],
        ],
      );
      sim(VehicleCar(v), (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), [
          'P0521',
          'P0300',
          'P0420',
          'P0842',
        ]);
      });
    });

    test('F-150: ECU rejects mode 04 (7F 04 22, engine running) → '
        'clearDtcs() reports failure', () {
      // J1979 lets an ECU refuse mode 04 when conditions are not correct
      // (e.g. engine running). Whether this F-150 PCM does so is unverified;
      // the app must not report success either way.
      final v = f150_2018.copyWith(clearReply: '7F 04 22');
      sim(VehicleCar(v), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), v.expectedDtcs);
      });
    });

    test('Ram 2500 diesel: poll skips PIDs the 0100/0120/0140 bitmaps mark '
        'unsupported', () {
      sim(VehicleCar(ram2500_2019), (rig) {
        final (_, _, cmds) = _pollOnce(rig);
        for (final pid in [
          0x06,
          0x07,
          0x08,
          0x09,
          0x0E,
          0x11,
          0x14,
          0x15,
          0x18,
          0x5C,
        ]) {
          expect(cmds, isNot(contains('01${_h2(pid)}')));
        }
      });
    });

    test('Ram 2500 diesel, hypothetical 29-bit CAN (ELM protocol 7): '
        'ATSP6 → NO DATA, ATSP0 finds protocol 7 within the 20 s window', () {
      // Unverified for this truck; exercises the fallback path only.
      final v = ram2500_2019.copyWith(
        name: 'Ram 2500 (hypothetical 29-bit CAN)',
        protocol: '7',
        // Auto search walks 1–6 first; K-line slow inits make this ~10 s.
        autoSearch: const Duration(seconds: 10),
        wrongProtocolReply: 'NO DATA',
      );
      sim(VehicleCar(v), (rig) {
        final t0 = rig.async.elapsed;
        rig.connect();
        _record(v, 'connect', _secs(rig.async.elapsed - t0));
        expect(rig.adapter.isConnected, isTrue);
        expect(rig.elm.activeProtocol, '7');
        expect(rig.drive(rig.adapter.getVin()), v.vin);
        expect(rig.drive(rig.adapter.getDtcs()), v.expectedDtcs);
      }, connect: false);
    });

    test('Silverado: VIN when the two ECUs reply sequentially (not '
        'interleaved) is read correctly', () {
      // Shows the interleaving, not multi-ECU per se, breaks _parseVin.
      final v = Vehicle(
        name: 'Silverado sequential VIN',
        protocol: '6',
        bus: Bus.can,
        vin: silverado2020.vin,
        ecus: silverado2020.ecus,
        expectedMake: silverado2020.expectedMake,
        expectedYear: silverado2020.expectedYear,
        expectedCountry: silverado2020.expectedCountry,
      );
      sim(VehicleCar(v), (rig) {
        expect(rig.drive(rig.adapter.getVin()), v.vin);
      });
    });

    test('GMC Sierra WMI 1GT decodes as GMC', () {
      final info = VinDecoder.decode(
        '1GTU9FEL0LZ100001',
        now: DateTime(2026, 11, 3),
      );
      expect(info['manufacturer'], 'GMC');
    });
  });

  _regressionTests();

  tearDownAll(() {
    final b = StringBuffer(
      '\nvehicle | connect s | poll s (1st, incl. '
      'bitmaps) | poll s (steady) | unsupported\n',
    );
    for (final MapEntry(key: name, value: r) in _results.entries) {
      b.writeln(
        '$name | ${r['connect'] ?? '-'} | ${r['poll'] ?? '-'} | '
        '${r['poll2'] ?? '-'} | ${r['unsupported'] ?? '-'}',
      );
    }
    // ignore: avoid_print
    print(b);
  });
}

// ── Regression: adversarial checks of the obd_adapter / vin_decoder fixes ────

/// The 0100 reply of [v] with bit 0x20 forced on: a PCM whose bitmap claims
/// a 0x21–0x40 range it then refuses (seen on some early-2000s PCMs).
String _bit20Forced(Vehicle v) {
  final line = VehicleCar(v).respond('0100');
  final b = line
      .split(' ')
      .skip(2)
      .map((x) => int.parse(x, radix: 16))
      .toList();
  b[3] |= 0x01;
  return '41 00 ${_hex(b)}';
}

/// Silverado ECM with three confirmed codes (multi-frame mode 03 reply).
final _ecm3 = Ecu(
  'ECM',
  live: silverado2020.ecm.live,
  raw: silverado2020.ecm.raw,
  readiness: silverado2020.ecm.readiness,
  confirmed: const ['P0521', 'P0300', 'P0420'],
  answersVin: true,
);

Ecu _tcm(List<String> confirmed) => Ecu(
  'TCM',
  live: const {0x0D: 0},
  raw: const {0x1C: _obd2Carb},
  readiness: const Readiness(supported: {'Components'}),
  confirmed: confirmed,
);

void _regressionTests() {
  group('regression', () {
    // ── Fix 1: support bitmaps ────────────────────────────────────────────

    for (final v in vehicles) {
      test('${v.name}: first poll (incl. bitmaps) and steady polls each '
          'finish inside the 3 s interval, no tick skipped', () {
        sim(VehicleCar(v), (rig) {
          final d = _pollDurations(rig, 3);
          expect(d.length, greaterThanOrEqualTo(3));
          for (final x in d.take(3)) {
            expect(x, greaterThan(Duration.zero));
            expect(x, lessThan(const Duration(seconds: 3)));
          }
          _record(v, 'poll2', _secs(d[1]));
        });
      });
    }

    test('Ram 2500 → Yukon on the same adapter instance: support is re-read '
        'on reconnect (Yukon gets all 18 PIDs, not Ram\'s diesel subset)', () {
      sim(VehicleCar(ram2500_2019), (rig) {
        final (_, _, c1) = _pollOnce(rig);
        expect(c1, _expectedPollCmds(ram2500_2019));
        final next = _reconnect(rig, VehicleCar(yukon2015));
        final (d, _, c2) = _pollOnce(rig, elm: next.elm);
        expect(c2, _expectedPollCmds(yukon2015));
        _expectDecoded(yukon2015, d);
      });
    });

    test('Yukon → Ram 2500 on the same adapter instance: Ram polls only its '
        'own PIDs and shows no Yukon values (fuel trims, O2, timing, oil)', () {
      sim(VehicleCar(yukon2015), (rig) {
        _pollOnce(rig);
        final next = _reconnect(rig, VehicleCar(ram2500_2019));
        final (d, _, c2) = _pollOnce(rig, elm: next.elm);
        expect(c2, _expectedPollCmds(ram2500_2019));
        _expectDecoded(ram2500_2019, d); // unsupported fields must be null
      });
    });

    test('Silverado: bitmap advertises 015C but the ECM answers NO DATA → '
        'oil temp null, everything else decoded, 015C still asked each '
        'poll, bitmaps read only once', () {
      final car = ScriptedCar(silverado2020, overrides: {'015C': 'NO DATA'});
      sim(car, (rig) {
        final (d1, t1, c1) = _pollOnce(rig);
        expect(c1, _expectedPollCmds(silverado2020));
        expect(d1.oilTempC, isNull);
        _expectDecoded(silverado2020, d1, except: {0x5C});
        expect(t1, lessThan(const Duration(seconds: 3)));
        final (d2, _, c2) = _pollOnce(rig);
        expect(c2, _expectedPollCmds(silverado2020, poll: 2));
        expect(d2.oilTempC, isNull);
      });
    });

    for (final (label, car) in [
      ('NO DATA', ScriptedCar(taurus2022, overrides: {'0120': 'NO DATA'})),
      (
        'no reply at all (adapter timeout)',
        ScriptedCar(taurus2022, silent: {'0120'}),
      ),
    ]) {
      test('Taurus: 0120 gets $label although 0100 advertises it → '
          'fallback polls 0x21–0x60 instead of dropping 2F / 42', () {
        sim(car, (rig) {
          final (d, _, cmds) = _pollOnce(rig);
          final polled = cmds
              .where((c) => c.length == 4 && c != '0120' && c != '0140')
              .toList();
          // 0x01–0x20 still filtered by 0100; nothing advertised skipped.
          // The extras need a readable bitmap bit, so 0134 / 0149 are not
          // asked without 0120.
          for (final (pid, _) in _pollPids) {
            final cmd = '01${_h2(pid)}';
            if (const {0x23, 0x24, 0x34, 0x49}.contains(pid)) {
              expect(polled, isNot(contains(cmd)));
            } else if (_advertised(taurus2022, pid)) {
              expect(polled, contains(cmd));
            } else if (pid <= 0x20) {
              expect(polled, isNot(contains(cmd)));
            }
          }
          _expectDecoded(taurus2022, d, except: {0x24, 0x49});
          expect(d.lambdaB1S1, isNull);
          expect(d.acceleratorPedalPct, isNull);
        });
      });
    }

    test('Explorer 2004 (J1850 PWM): 0100 wrongly sets bit 0x20 and 0120 '
        'answers 7F 01 12 → range treated as unsupported, 2F/42/5C not '
        'polled, every advertised PID still decoded', () {
      final car = ScriptedCar(
        explorer2004,
        overrides: {'0100': _bit20Forced(explorer2004), '0120': '7F 01 12'},
      );
      sim(car, (rig) {
        final (d, took, cmds) = _pollOnce(rig);
        expect(cmds, ['0120', ..._expectedPollCmds(explorer2004)]);
        _expectDecoded(explorer2004, d);
        expect(took, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Silverado: ECM answers 0120 but the TCM sends 7F 01 12 → the '
        'ECM\'s 0x21–0x60 PIDs are still polled (negative reply of one ECU '
        'must not erase another\'s bitmap)', () {
      final ecmOnly = silverado2020.copyWith(ecus: [silverado2020.ecm]);
      final car = ScriptedCar(
        silverado2020,
        overrides: {'0120': '${VehicleCar(ecmOnly).respond('0120')}\n7F 01 12'},
      );
      sim(car, (rig) {
        final (d, _, cmds) = _pollOnce(rig);
        expect(cmds, _expectedPollCmds(silverado2020));
        _expectDecoded(silverado2020, d);
      });
    });

    test('two ECUs with different bitmaps: TCM alone reports speed (0D) and '
        'module voltage (42), ECM has nothing above 0x20 → union polled, '
        '0120/0140 answered by the TCM only', () {
      final ecmLow = Ecu(
        'ECM',
        live: {
          for (final MapEntry(:key, :value) in silverado2020.ecm.live.entries)
            if (key < 0x20 && key != 0x0D) key: value,
        },
        raw: {
          for (final MapEntry(:key, :value) in silverado2020.ecm.raw.entries)
            if (key < 0x20) key: value,
        },
        readiness: silverado2020.ecm.readiness,
        answersVin: true,
      );
      final v = _variant(
        silverado2020,
        name: 'Silverado (TCM-only 0D/42)',
        ecus: [
          ecmLow,
          const Ecu(
            'TCM',
            live: {0x0D: 37, 0x42: 14.1},
            raw: {0x1C: _obd2Carb},
            readiness: Readiness(supported: {'Components'}),
          ),
        ],
      );
      final car = VehicleCar(v);
      expect(car.respond('0120').split('\n'), hasLength(1)); // TCM only
      sim(car, (rig) {
        final (d, _, cmds) = _pollOnce(rig);
        expect(cmds, _expectedPollCmds(v));
        expect(cmds, containsAll(['0120', '0140', '010D', '0142']));
        expect(d.speedKmh, 37);
        _expectDecoded(v, d);
      });
    });

    // ── Wide-band O2 / diesel extras, ATRV battery fallback ──────────────

    test('Taurus (UEGO, no 0114): upstream λ read from 0134; pedal from '
        '0149', () {
      sim(VehicleCar(taurus2022), (rig) {
        final (d, _, cmds) = _pollOnce(rig);
        expect(cmds, containsAll(['0134', '0149']));
        expect(cmds, isNot(contains('0114')));
        expect(d.o2B1S1Voltage, isNull);
        expect(d.lambdaB1S1, 1.0);
        expect(d.acceleratorPedalPct, closeTo(14.9, 0.01)); // 0x26
        expect(d.fuelRailPressureKpa, isNull);
      });
    });

    test('Yukon (narrow-band 0114): no wide-band request, λ stays null', () {
      sim(VehicleCar(yukon2015), (rig) {
        final (d, _, cmds) = _pollOnce(rig);
        expect(cmds, isNot(contains('0124')));
        expect(cmds, isNot(contains('0134')));
        expect(d.o2B1S1Voltage, closeTo(0.78, 0.005));
        expect(d.lambdaB1S1, isNull);
      });
    });

    test('Ram 2500 diesel: rail pressure (0123) and pedal (0149) decode', () {
      sim(VehicleCar(ram2500_2019), (rig) {
        final (d, took, cmds) = _pollOnce(rig);
        expect(cmds.sublist(cmds.length - 2), ['0123', '0149']);
        expect(d.fuelRailPressureKpa, 30000); // 0x0BB8 × 10 kPa = 30 MPa
        expect(d.acceleratorPedalPct, 0);
        expect(d.throttlePct, isNull);
        expect(took, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Explorer 2004 (no 0142): battery from the adapter\'s ATRV on every '
        'poll', () {
      sim(VehicleCar(explorer2004, adapterVoltage: '12.3V'), (rig) {
        final (d1, _, c1) = _pollOnce(rig);
        expect(c1, _expectedPollCmds(explorer2004));
        expect(c1, isNot(contains('0142')));
        expect(d1.batteryVoltage, 12.3);
        _pollOnce(rig);
        final (d3, _, c3) = _pollOnce(rig);
        expect(c3, contains('ATRV')); // a real reading never gives up
        expect(d3.batteryVoltage, 12.3);
      });
    });

    test('Explorer 2004 on a clone without ATRV ("?"): asked on the first '
        'two polls only, battery null', () {
      sim(VehicleCar(explorer2004), (rig) {
        final (_, _, c1) = _pollOnce(rig);
        final (_, _, c2) = _pollOnce(rig);
        final (d3, _, c3) = _pollOnce(rig);
        expect(c1, contains('ATRV'));
        expect(c2, _expectedPollCmds(explorer2004, poll: 2));
        expect(c3, _expectedPollCmds(explorer2004, poll: 3));
        expect(c3, isNot(contains('ATRV')));
        expect(d3.batteryVoltage, isNull);
      });
    });

    test('Explorer 2004: 0100 bit 0x20 clear → no 0120 and no 2F/42/5C', () {
      sim(VehicleCar(explorer2004), (rig) {
        final (_, _, cmds) = _pollOnce(rig);
        for (final c in ['0120', '0140', '012F', '0142', '015C']) {
          expect(cmds, isNot(contains(c)));
        }
      });
    });

    // ── Fix 9: recovery after a hung / slow command ───────────────────────

    test('Tahoe (J1850 VPW): 0114 hangs once (no reply, no prompt) → the '
        'next PID\'s real answer is kept, 0114 decodes on the next poll', () {
      final car = ScriptedCar(tahoe2006, hangsOnce: {'0114'});
      sim(car, (rig) {
        final (d1, _, c1) = _pollOnce(rig);
        expect(c1, contains(''), reason: 'resync CR expected');
        expect(d1.o2B1S1Voltage, isNull);
        _expectDecoded(tahoe2006, d1, except: {0x14});
        final (d2, _, _) = _pollOnce(rig);
        _expectDecoded(tahoe2006, d2);
      });
    });

    test('Tahoe: 0118 never answered (clone stays silent, CR repeats it) → '
        'every later PID still decoded', () {
      final car = ScriptedCar(tahoe2006, silent: {'0118'});
      sim(car, (rig) {
        final (d, _, _) = _pollOnce(rig);
        expect(d.o2B2S1Voltage, isNull);
        _expectDecoded(tahoe2006, d, except: {0x18});
      });
    });

    test('Tahoe: 0114 answers after 1.2 s (> 800 ms timeout) → STOPPED is '
        'swallowed, 0115 and later PIDs decoded, not shifted by one', () {
      final car = ScriptedCar(
        tahoe2006,
        latencies: {'0114': const Duration(milliseconds: 1200)},
      );
      sim(car, (rig) {
        final (d, _, _) = _pollOnce(rig);
        expect(d.o2B1S1Voltage, isNull);
        _expectDecoded(tahoe2006, d, except: {0x14});
        expect(rig.drive(rig.adapter.getDtcs()), tahoe2006.expectedDtcs);
      });
    });

    // ── Fix 2: clearDtcs() ────────────────────────────────────────────────

    test('Taurus: mode 04 answered 7F 04 78 (response pending) then 44 after '
        '2.5 s → true, codes and freeze frame gone', () {
      final car = ScriptedCar(
        taurus2022,
        clearReplies: [('PCM', '7F 04 78\n44')],
        latencies: {'04': const Duration(milliseconds: 2500)},
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
        expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isFalse);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, taurus2022.expectedMonitors(cleared: true));
      });
    });

    test('Taurus: 7F 04 78 then 7F 04 22 → false, codes still there', () {
      final car = ScriptedCar(
        taurus2022,
        clearReplies: [('PCM', '7F 04 78\n7F 04 22')],
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), taurus2022.expectedDtcs);
      });
    });

    test('Taurus: mode 04 gets NO DATA → false', () {
      final car = ScriptedCar(taurus2022, clearReplies: [('PCM', 'NO DATA')]);
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), taurus2022.expectedDtcs);
      });
    });

    for (final order in [
      [('ECM', '44'), ('TCM', '7F 04 22')],
      [('TCM', '7F 04 22'), ('ECM', '44')],
    ]) {
      test('Silverado: ${order.map((e) => '${e.$1} ${e.$2}').join(', ')} → '
          'false; TCM code remains, readiness reflects the partial clear', () {
        final car = ScriptedCar(silverado2020, clearReplies: order);
        sim(car, (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
          final after = car.afterClear;
          expect(rig.drive(rig.adapter.getDtcs()), after.expectedDtcs);
          expect(after.expectedDtcs, ['P0842']);
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, isTrue);
          expect(r.dtcCount, 1);
          expect({
            for (final m in r.monitors) m.name: m.status,
          }, after.expectedMonitors());
        });
      });
    }

    // ── Fix 3: readiness merge ────────────────────────────────────────────

    test('Silverado: only the TCM answers 0101 → spark, MIL from the TCM, '
        'Components only, everything else N/A', () {
      final tcmOnly = silverado2020.copyWith(ecus: [silverado2020.ecus[1]]);
      final car = ScriptedCar(
        silverado2020,
        overrides: {'0101': VehicleCar(tcmOnly).respond('0101')},
      );
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isFalse);
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 1);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, tcmOnly.expectedMonitors());
      });
    });

    test('Ram 2500 diesel + 68RFE TCM (spark bit clear) answering 0101 '
        'first → still compression ignition, diesel monitors, counts '
        'summed', () {
      final v = ram2500_2019.copyWith(
        ecus: [
          ram2500_2019.ecm,
          _tcm(const ['P0700']),
        ],
        tcmFirst: {'0101'},
      );
      sim(VehicleCar(v), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.compressionIgnition, isTrue);
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 2);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, v.expectedMonitors());
      });
    });

    // ── Fix 4: headers-off ISO-TP reassembly ─────────────────────────────

    String crossed(Vehicle v) {
      final car = VehicleCar(v);
      final a = car._ecuReply(v.ecus[0], '03')!;
      final b = car._ecuReply(v.ecus[1], '03')!;
      // ECM FF, TCM FF, then the TCM's CFs overtake the ECM's.
      return [a[0], a[1], b[0], b[1], ...b.skip(2), ...a.skip(2)].join('\n');
    }

    test('Silverado: both ECUs send 3-code ISO-TP mode 03 replies and the '
        'TCM\'s consecutive frame overtakes the ECM\'s → all 6 codes', () {
      final v = silverado2020.copyWith(
        ecus: [
          _ecm3,
          _tcm(const ['P0842', 'P0700', 'P0751']),
        ],
      );
      sim(ScriptedCar(v, overrides: {'03': crossed(v)}), (rig) {
        expect(
          rig.drive(rig.adapter.getDtcs()),
          unorderedEquals(v.expectedDtcs),
        );
      });
    });

    test('Silverado: ECM 3-code and TCM 5-code ISO-TP replies (different '
        'lengths) with crossed consecutive frames → all 8 codes', () {
      final v = silverado2020.copyWith(
        ecus: [
          _ecm3,
          _tcm(const ['P0842', 'P0700', 'P0751', 'P0756', 'P0716']),
        ],
      );
      sim(ScriptedCar(v, overrides: {'03': crossed(v)}), (rig) {
        expect(
          rig.drive(rig.adapter.getDtcs()),
          unorderedEquals(v.expectedDtcs),
        );
      });
    });

    // ── Fix 5: VIN reassembly + validation ───────────────────────────────

    final a = _vinFrames(silverado2020.vin);
    for (final (label, lines) in [
      (
        'both byte-count lines first',
        [a[0], a[0], a[1], a[1], a[2], a[2], a[3], a[3]],
      ),
      (
        'TCM consecutive frames overtake the ECM\'s',
        [a[0], a[1], a[0], a[1], a[2], a[2], a[3], a[3]],
      ),
      (
        'TCM first, then ECM, interleaved',
        [a[0], a[1], a[0], a[2], a[1], a[3], a[2], a[3]],
      ),
      (
        'TCM single frame "7F 09 11" between ECM frames',
        [a[0], a[1], '7F 09 11', a[2], a[3]],
      ),
    ]) {
      test(
        'Silverado VIN, ECM + TCM replies $label → ${silverado2020.vin}',
        () {
          final car = ScriptedCar(
            silverado2020,
            overrides: {'0902': lines.join('\n')},
          );
          sim(car, (rig) {
            expect(rig.drive(rig.adapter.getVin()), silverado2020.vin);
          });
        },
      );
    }

    test('Silverado: TCM carries a donor-truck VIN, frames interleaved, ECM '
        'first on the bus (7E8 wins arbitration) → the ECM\'s VIN', () {
      const donor = '1GCUYDEDXLZ110003'; // valid check digit 'X'
      final e = _vinFrames(silverado2020.vin);
      final t = _vinFrames(donor);
      final car = ScriptedCar(
        silverado2020,
        overrides: {
          '0902': [e[0], e[1], t[0], t[1], e[2], t[2], e[3], t[3]].join('\n'),
        },
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), silverado2020.vin);
      });
    });

    test('Silverado: unprogrammed service ECM reports an all-zero VIN, TCM '
        'the real one → the real VIN, never "00000000000000000"', () {
      final z = _vinFrames('0' * 17);
      final t = _vinFrames(silverado2020.vin);
      final car = ScriptedCar(
        silverado2020,
        overrides: {
          '0902': [...z, ...t].join('\n'),
        },
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), silverado2020.vin);
      });
    });

    for (final (base, vin, make, year) in [
      (yukon2015, '1GCUYDEDXLZ110003', 'Chevrolet', '2020'),
      (explorer2004, '1FMZU73EX4UA10007', 'Ford', '2004'),
    ]) {
      test('${base.bus.name.toUpperCase()}: VIN with check digit "X" '
          '($vin) is accepted and decoded', () {
        expect(vinCheckDigitValid(vin), isTrue);
        final v = _variant(base, name: 'X check digit', vin: vin);
        sim(VehicleCar(v), (rig) {
          final got = rig.drive(rig.adapter.getVin());
          expect(got, vin);
          final info = VinDecoder.decode(got!, now: DateTime(2026, 11, 3));
          expect(info['manufacturer'], make);
          expect(info['year'], year);
          expect(info['country'], 'United States');
        });
      });
    }

    test('Ford Focus built in Saarlouis (WMI WF0, no check digit: position 9 '
        'is a letter) → VIN accepted; decoded Ford / Germany / year '
        'Unknown', () {
      const vin = 'WF0DXXGCBDHR12345';
      final v = _variant(taurus2022, name: 'Ford Focus (EU)', vin: vin);
      sim(VehicleCar(v), (rig) {
        final got = rig.drive(rig.adapter.getVin());
        expect(got, vin);
        final info = VinDecoder.decode(got!, now: DateTime(2026, 11, 3));
        expect(info['manufacturer'], 'Ford');
        expect(info['country'], 'Germany');
        expect(info['year'], VinDecoder.unknown);
      });
    });

    test('Silverado: VIN with one corrupted character (check digit no longer '
        'matches) → null, not a wrong VIN', () {
      const bad = '1GCUYDED8LZ158343';
      expect(vinCheckDigitValid(bad), isFalse);
      final car = ScriptedCar(
        silverado2020,
        overrides: {'0902': _vinFrames(bad).join('\n')},
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
      });
    });

    // ── Fixes 6–8: VinDecoder on common American WMIs (GCC market) ───────

    for (final (vin, make, country) in [
      ('1GCUYDED8LZ158342', 'Chevrolet', 'United States'),
      ('1GNEC13T86R204873', 'Chevrolet', 'United States'),
      ('1GKS2BKC3FR317625', 'GMC', 'United States'),
      ('1GTU9FEL0LZ100001', 'GMC', 'United States'),
      ('1C4RJFAG9GC402918', 'Jeep', 'United States'),
      ('3C6UR5DL0KG561037', 'Ram', 'Mexico'),
      ('1FTEW1EP5JFA45871', 'Ford', 'United States'),
    ]) {
      test('VinDecoder: $vin → $make / $country', () {
        final info = VinDecoder.decode(vin, now: DateTime(2026, 11, 3));
        expect(info['country'], country);
        expect(info['manufacturer'], matches(RegExp(make)));
      });
    }

    // Common in the GCC market (Charger/Challenger/300, Edge, Lincoln,
    // Buick, Tesla, Equinox/Terrain from CAMI, Journey, GM Korea Chevrolet)
    // but still missing from the WMI table → "Unknown". Country is right.
    for (final (vin, make, country) in [
      ('2C3CDXBG0KH500001', 'Chrysler|Dodge', 'Canada'),
      ('2FMPK4J90KBA00001', 'Ford', 'Canada'),
      ('1LN6L9TK0H5600001', 'Lincoln', 'United States'),
      ('5LMJJ3LT0LEL00001', 'Lincoln', 'United States'),
      ('1G4ZN5SS0HU100001', 'Buick', 'United States'),
      ('5YJ3E1EA0LF000001', 'Tesla', 'United States'),
      ('2GNAXUEV0L6100001', 'Chevrolet', 'Canada'),
      ('2GKALMEK0H6100001', 'GMC', 'Canada'),
      ('3C4PDCAB0JT100001', 'Dodge|Chrysler', 'Mexico'),
      ('KL1TD5DE0BB100001', 'Chevrolet', 'South Korea'),
    ]) {
      test('VinDecoder: $vin → $make / $country', () {
        final info = VinDecoder.decode(vin, now: DateTime(2026, 11, 3));
        expect(info['country'], country);
        expect(info['manufacturer'], matches(RegExp(make)));
      });
    }
  });
}
