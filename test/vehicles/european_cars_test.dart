// Compatibility matrix: European / EOBD vehicles (incl. models common in the
// Gulf / Middle East) driven through [ProductionOBDAdapter] + [VinDecoder]
// with the simulated BLE ELM327 from test/helpers/elm327_sim.dart.
//
// Profiles are built from SAE J1979 / ISO 15031-5 (EOBD) message formats and
// commonly documented behaviour of these vehicles. Where a detail is not
// verified for the exact ECU it is marked "unverified" in a comment.
//
// General modelling choices (apply to every profile):
//  • The app sends ATH0 (headers off), so replies are written header-less.
//    With headers off 11-bit and 29-bit CAN replies look identical.
//  • A PID the ECU does not support gets no ECU reply; J1979 forbids negative
//    responses for unsupported mode 01 PIDs. The ELM327 then prints NO DATA
//    after its own timeout (ATST default 0x32 × 4 ms ≈ 200 ms; longer on
//    K-line). That is modelled with [EuroCar.noDataLatency], not with
//    SimCar.silent (a real ELM327 always ends a request with a prompt).
//  • On CAN several emission-related ECUs (ECM 7E8 + TCM 7E9) answer
//    functional requests; the ELM327 prints one line per ECU in arrival
//    order. ECM-first is modelled as the usual case.
//  • K-line (ISO 14230-4) mode 03/07 replies are fixed 6-data-byte messages
//    padded with 00; mode 09 VIN is five "49 02 0N" messages. CAN replies
//    carry a DTC-count byte and ISO-TP multi-frame for longer payloads.
//  • VIN check digit (position 9) is only mandatory in North America. NA-built
//    VINs here (BMW 5UX…) and the JLR VIN carry a valid check digit; ECE VINs
//    (VW/Audi "ZZZ", Mercedes, Dacia, Renault) keep their manufacturer filler.
//  • ISO 15031-5 resets the freeze frame and readiness on mode 04, so the
//    stateful [EuroCar] does the same after a successful clear.

// fake_async ships with flutter_test (see test/helpers/elm327_sim.dart).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/vin_decoder.dart';

import '../helpers/elm327_sim.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _h(int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase();

/// Mode 01 "PIDs supported [base+1 … base+0x20]" reply built from [pids].
String supportBitmap(int base, Set<int> pids) {
  final bytes = [0, 0, 0, 0];
  for (final p in pids) {
    final i = p - base - 1;
    if (i < 0 || i >= 32) continue;
    bytes[i ~/ 8] |= 0x80 >> (i % 8);
  }
  return '41 ${_h(base)} ${bytes.map(_h).join(' ')}';
}

/// Bytes after "41 PP" in the first line that carries that header, or null.
List<int>? firstEcuBytes(String? reply, String request) {
  if (reply == null) return null;
  final hdr = '4${request.substring(1, 2)} ${request.substring(2, 4)}';
  for (final line in reply.split('\n')) {
    if (line.startsWith(hdr)) {
      return line
          .substring(hdr.length)
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => int.parse(s, radix: 16))
          .toList();
    }
  }
  return null;
}

/// "014 / 0: / 1: / 2:" CAN ISO-TP reply carrying [vin] (49 02 01 + 17 chars).
String canVin(String vin) {
  final c = vin.codeUnits.map(_h).toList();
  return '014\n'
      '0: 49 02 01 ${c.sublist(0, 3).join(' ')}\n'
      '1: ${c.sublist(3, 10).join(' ')}\n'
      '2: ${c.sublist(10, 17).join(' ')}';
}

/// ISO 9141-2 / ISO 14230-4 VIN: five "49 02 0N" messages, the first padded
/// with three 00 bytes (ISO 15031-5).
String kLineVin(String vin) {
  final c = vin.codeUnits.map(_h).toList();
  return [
    '49 02 01 00 00 00 ${c[0]}',
    for (var n = 0; n < 4; n++)
      '49 02 0${n + 2} ${c.sublist(1 + 4 * n, 5 + 4 * n).join(' ')}',
  ].join('\n');
}

const _busInit = 'BUS INIT: ...OK\n';

/// "PIDs supported" replies for an ECM (and optionally a TCM that also
/// answers 0100) consistent with [ecm].
Map<String, String> supportReplies(
  Set<int> ecm, {
  Set<int>? tcm,
  String prefix = '',
}) => {
  '0100':
      '$prefix${supportBitmap(0, ecm)}'
      '${tcm == null ? '' : '\n${supportBitmap(0, tcm)}'}',
  if (ecm.contains(0x20)) '0120': supportBitmap(0x20, ecm),
  if (ecm.contains(0x40)) '0140': supportBitmap(0x40, ecm),
};

/// The 18 PIDs one live-data poll reads, in the order the adapter sends them.
const polledPids = [
  '010C',
  '010D',
  '0105',
  '0111',
  '012F',
  '0104',
  '0142',
  '015C',
  '0106',
  '0107',
  '0108',
  '0109',
  '0114',
  '0115',
  '0118',
  '010F',
  '010B',
  '010E',
];

/// Extra live PIDs, sent after [polledPids] and only when a readable bitmap
/// sets their bit: upstream wide-band O2 (0124, else 0134 — and only when
/// there is no narrow-band 0114), diesel / GDI rail pressure, pedal D.
const extraPids = ['0124', '0134', '0123', '0149'];

/// Independent SAE J1979 decoding of each polled PID (reference values).
double? j1979(String pid, List<int>? b) {
  if (b == null || b.isEmpty) return null;
  switch (pid) {
    case '010C':
      return (256 * b[0] + b[1]) / 4;
    case '010D':
    case '010B':
      return b[0].toDouble();
    case '0105':
    case '015C':
    case '010F':
      return b[0] - 40.0;
    case '0111':
    case '012F':
    case '0104':
      return b[0] * 100 / 255;
    case '0142':
      return (256 * b[0] + b[1]) / 1000;
    case '0106':
    case '0107':
    case '0108':
    case '0109':
      return (b[0] - 128) * 100 / 128;
    case '0114':
    case '0115':
    case '0118':
      return b[0] * 0.005;
    case '010E':
      return b[0] / 2 - 64;
    case '0124':
    case '0134':
      return (256 * b[0] + b[1]) / 32768; // equivalence ratio λ
    case '0123':
      return (256 * b[0] + b[1]) * 10.0; // kPa
    case '0149':
      return b[0] * 100 / 255;
  }
  throw ArgumentError(pid);
}

final _field = <String, double? Function(OBDLiveData)>{
  '010C': (d) => d.rpm,
  '010D': (d) => d.speedKmh,
  '0105': (d) => d.coolantTempC,
  '0111': (d) => d.throttlePct,
  '012F': (d) => d.fuelLevelPct,
  '0104': (d) => d.engineLoad,
  '0142': (d) => d.batteryVoltage,
  '015C': (d) => d.oilTempC,
  '0106': (d) => d.fuelTrimShortPct,
  '0107': (d) => d.fuelTrimLongPct,
  '0108': (d) => d.fuelTrimShortB2,
  '0109': (d) => d.fuelTrimLongB2,
  '0114': (d) => d.o2B1S1Voltage,
  '0115': (d) => d.o2B1S2Voltage,
  '0118': (d) => d.o2B2S1Voltage,
  '010F': (d) => d.intakeAirTempC,
  '010B': (d) => d.mapKpa,
  '010E': (d) => d.timingAdvanceDeg,
  '0124': (d) => d.lambdaB1S1,
  '0134': (d) => d.lambdaB1S1,
  '0123': (d) => d.fuelRailPressureKpa,
  '0149': (d) => d.acceleratorPedalPct,
};

// ── Stateful vehicle model ────────────────────────────────────────────────────

/// [SimCar] with protocol-realistic NO DATA timing and a mode 04 that
/// actually clears the ECU state (DTCs, freeze frame, readiness).
class EuroCar extends SimCar {
  EuroCar({
    required String super.protocol,
    required super.responses,
    required super.autoSearchTime,
    super.wrongProtocolReply,
    super.wrongProtocolDelay,
    super.ecuLatency,
    this.noDataLatency = const Duration(milliseconds: 200),
    this.clearReply = '44',
    this.afterClear = const {},
  });

  /// Time until the ELM327 prints NO DATA when no ECU answers.
  final Duration noDataLatency;

  /// Reply to mode 04 (one line per ECU). Contains "7F 04" when the ECM
  /// rejects the clear (NRC 0x22 conditionsNotCorrect, e.g. engine running).
  final String clearReply;

  /// Replies that replace [responses] once the codes are cleared.
  final Map<String, String> afterClear;

  bool cleared = false;

  bool get clearAccepted => !clearReply.contains('7F 04');

  String _peek(String cmd) {
    if (cmd == '04') return clearReply;
    if (cleared) {
      final r = afterClear[cmd];
      if (r != null) return r;
      if (cmd.startsWith('02')) return 'NO DATA'; // freeze frame erased
    }
    return super.answer(cmd);
  }

  @override
  String answer(String cmd) {
    if (cmd == '04' && clearAccepted) cleared = true;
    return _peek(cmd);
  }

  @override
  Duration latency(String cmd) =>
      _peek(cmd) == 'NO DATA' ? noDataLatency : ecuLatency;

  /// True when the ECM answers mode 01 [pid] with data.
  bool answers(String pid) => firstEcuBytes(responses[pid], pid) != null;

  /// True when the ECM's 0100/0120/0140 bitmap advertises [pid] (e.g. 0x0C).
  bool advertises(int pid) {
    final base = ((pid - 1) ~/ 0x20) * 0x20;
    final req = '01${_h(base)}';
    final b = firstEcuBytes(responses[req], req);
    if (b == null || b.length < 4) return false;
    final i = pid - base - 1;
    return (b[i ~/ 8] >> (7 - i % 8)) & 1 == 1;
  }
}

// ── Vehicle descriptor ────────────────────────────────────────────────────────

const ok = MonitorStatus.ready;
const inc = MonitorStatus.notReady;
const na = MonitorStatus.notApplicable;

class Vehicle {
  Vehicle({
    required this.name,
    required this.protocol,
    required this.build,
    required this.connectMin,
    required this.connectMax,
    required this.dtcs,
    required this.dtcsAfterClear,
    required this.vin,
    this.manufacturer,
    this.country,
    this.year,
    required this.milOn,
    required this.dtcCount,
    required this.diesel,
    required this.monitors,
    required this.freezeFrame,
    this.skip = const {},
  });

  final String name;

  /// ELM327 protocol number expected after connect (ATDPN digit).
  final String protocol;
  final EuroCar Function() build;
  final Duration connectMin;
  final Duration connectMax;
  final List<String> dtcs;
  final List<String> dtcsAfterClear;

  /// Expected getVin() result (null = car has no mode 09 PID 02).
  final String? vin;
  final String? manufacturer;
  final String? country;
  final Matcher? year;

  final bool milOn;
  final int dtcCount;
  final bool diesel;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freezeFrame;

  /// Test key → skip reason ("BUG: …").
  final Map<String, String> skip;
}

Map<String, MonitorStatus> spark({
  MonitorStatus misfire = ok,
  MonitorStatus fuel = ok,
  MonitorStatus components = ok,
  MonitorStatus catalyst = na,
  MonitorStatus heatedCatalyst = na,
  MonitorStatus evap = na,
  MonitorStatus secondaryAir = na,
  MonitorStatus ac = na,
  MonitorStatus o2 = na,
  MonitorStatus o2Heater = na,
  MonitorStatus egr = na,
}) => {
  'Misfire': misfire,
  'Fuel System': fuel,
  'Components': components,
  'Catalyst': catalyst,
  'Heated Catalyst': heatedCatalyst,
  'Evap System': evap,
  'Secondary Air': secondaryAir,
  'A/C System': ac,
  'O2 Sensor': o2,
  'O2 Sensor Heater': o2Heater,
  'EGR / VVT': egr,
};

Map<String, MonitorStatus> compression({
  MonitorStatus nmhc = na,
  MonitorStatus noxScr = na,
  MonitorStatus boost = na,
  MonitorStatus exhaustSensor = na,
  MonitorStatus pmFilter = na,
  MonitorStatus egr = na,
}) => {
  'Misfire': ok,
  'Fuel System': ok,
  'Components': ok,
  'NMHC Catalyst': nmhc,
  'NOx / SCR': noxScr,
  'Boost Pressure': boost,
  'Exhaust Gas Sensor': exhaustSensor,
  'PM Filter': pmFilter,
  'EGR / VVT': egr,
};

// ── Vehicle profiles ──────────────────────────────────────────────────────────

/// VW Golf IV 1.6 (2004), EOBD petrol. ISO 14230-4 KWP2000 with 5-baud init
/// (ELM protocol 4) — the protocol commonly reported by ELM327 users for
/// Mk4 VAG ME7/Marelli ECUs (unverified for this exact engine code).
/// No CAN on pins 6/14 → ATSP6 gives CAN ERROR. 5-baud init alone is 2 s
/// (address byte at 5 baud) + sync/keybytes; the ELM walks J1850 first, so
/// ~8 s total auto search. Pre-2005 EOBD ECUs typically do not support
/// mode 09 VIN → NO DATA. Inline-4: no bank-2 PIDs; no 0120 range at all.
final golf2004 = Vehicle(
  name: 'VW Golf IV 1.6 2004',
  protocol: '4',
  build: () => EuroCar(
    protocol: '4',
    autoSearchTime: const Duration(seconds: 8),
    wrongProtocolReply: 'CAN ERROR',
    // K-line round trip at 10.4 kbaud incl. P2 and the ELM's wait for
    // further responders ≈ 130 ms; NO DATA ≈ 300 ms.
    ecuLatency: const Duration(milliseconds: 130),
    noDataLatency: const Duration(milliseconds: 300),
    responses: {
      ...supportReplies(const {
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, //
        0x11, 0x13, 0x14, 0x15, 0x1C,
      }, prefix: _busInit),
      // Warm idle, lean (consistent with the stored P0171 / P1136).
      '010C': '41 0C 0C 1C', // 775 rpm
      '010D': '41 0D 00', // 0 km/h
      '0105': '41 05 7B', // 83 °C
      '0111': '41 11 26', // 14.9 %
      '0104': '41 04 4D', // 30.2 %
      '0106': '41 06 85', // +3.9 %
      '0107': '41 07 94', // +15.6 %
      '0114': '41 14 5A 85', // 0.45 V (narrow-band upstream)
      '0115': '41 15 A0 FF', // 0.80 V
      '010F': '41 0F 41', // 25 °C
      '010B': '41 0B 21', // 33 kPa (1.6 MPI uses a MAP sensor; unverified)
      '010E': '41 0E 94', // +10°
      // A=83: MIL, 3 codes. B=07: continuous supported+complete.
      // C=61: catalyst, O2, O2 heater (EU OBD needs no evap leak monitor).
      // D=21: catalyst + O2 incomplete.
      '0101': '41 01 83 07 61 21',
      // KWP: 3 codes per 6-byte message, no count byte.
      '03': '43 01 71 04 20 11 36', // P0171, P0420, P1136 (VAG lean add.)
      '07': '47 03 00 00 00 00 00', // P0300 pending
      '020C00': '42 0C 00 0C 1C',
      '020D00': '42 0D 00 00',
      '020500': '42 05 00 7B',
      '020400': '42 04 00 4D',
      '020F00': '42 0F 00 41',
      '021100': '42 11 00 26',
      '020600': '42 06 00 9A',
      '020B00': '42 0B 00 21',
      // 0902 absent → NO DATA.
    },
    afterClear: const {
      '03': '43 00 00 00 00 00 00',
      '07': '47 00 00 00 00 00 00',
      '0101': '41 01 00 07 61 61',
    },
  ),
  connectMin: const Duration(seconds: 8),
  connectMax: const Duration(seconds: 12),
  dtcs: const ['P0171', 'P0420', 'P1136', '~P0300'],
  dtcsAfterClear: const [],
  vin: null,
  milOn: true,
  dtcCount: 3,
  diesel: false,
  monitors: spark(catalyst: inc, o2: inc, o2Heater: ok),
  freezeFrame: const {
    'RPM': '775 rpm',
    'Speed': '0 km/h',
    'Coolant': '83°C',
    'Engine Load': '30.2%',
    'Air Temp': '25°C',
    'Throttle': '14.9%',
    'Fuel Trim': '20.3%',
    'MAP': '33 kPa',
  },
);

/// Dacia Logan 1.6 MPI (2010, Romania-built, WMI UU1), Euro 4 petrol.
/// ISO 14230-4 KWP2000 fast init (ELM protocol 5): commonly reported for
/// Renault-group K-line ECUs (unverified for this exact ECU). The ELM tries
/// the 5-baud init first, so auto search ≈ 9 s. Mode 09 VIN support on this
/// ECU is unverified; it is modelled as supported to exercise the KWP
/// five-message VIN path.
const loganVin = 'UU1LSDAAH43612345';
final logan2010 = Vehicle(
  name: 'Dacia Logan 1.6 2010',
  protocol: '5',
  build: () => EuroCar(
    protocol: '5',
    autoSearchTime: const Duration(seconds: 9),
    wrongProtocolReply: 'CAN ERROR',
    ecuLatency: const Duration(milliseconds: 110),
    noDataLatency: const Duration(milliseconds: 300),
    responses: {
      ...supportReplies(const {
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, //
        0x11, 0x13, 0x14, 0x15, 0x1C, 0x20, 0x21,
      }, prefix: _busInit),
      // Cruising at 60 km/h.
      '010C': '41 0C 22 60', // 2200 rpm
      '010D': '41 0D 3C', // 60 km/h
      '0105': '41 05 7E', // 86 °C
      '0111': '41 11 2E', // 18.0 %
      '0104': '41 04 59', // 34.9 %
      '0106': '41 06 7E', // -1.6 %
      '0107': '41 07 83', // +2.3 %
      '0114': '41 14 14 7E', // 0.10 V (faulty upstream sensor, P0130)
      '0115': '41 15 96 FF', // 0.75 V
      '010F': '41 0F 50', // 40 °C
      '010B': '41 0B 2D', // 45 kPa
      '010E': '41 0E 9C', // +14°
      '0121': '41 21 00 2A', // 42 km driven with MIL on
      '0101': '41 01 81 07 61 20', // MIL, 1 code; O2 monitor incomplete
      '03': '43 01 30 00 00 00 00', // P0130
      '07': '47 00 00 00 00 00 00',
      '020C00': '42 0C 00 22 60',
      '020D00': '42 0D 00 3C',
      '020500': '42 05 00 7E',
      '020400': '42 04 00 59',
      '020F00': '42 0F 00 50',
      '0902': kLineVin(loganVin),
    },
    afterClear: const {
      '03': '43 00 00 00 00 00 00',
      '07': '47 00 00 00 00 00 00',
      '0101': '41 01 00 07 61 61',
    },
  ),
  connectMin: const Duration(seconds: 9),
  connectMax: const Duration(seconds: 13),
  dtcs: const ['P0130'],
  dtcsAfterClear: const [],
  vin: loganVin,
  manufacturer: 'Dacia',
  country: 'Romania',
  // Renault-group ECE VINs carry no model-year code at position 10, so the
  // only correct answer is "Unknown" (pos 10 '4' would wrongly read as 2004).
  year: equals('Unknown'),
  milOn: true,
  dtcCount: 1,
  diesel: false,
  monitors: spark(catalyst: ok, o2: inc, o2Heater: ok),
  freezeFrame: const {
    'RPM': '2200 rpm',
    'Speed': '60 km/h',
    'Coolant': '86°C',
    'Engine Load': '34.9%',
    'Air Temp': '40°C',
  },
);

/// VW Golf VII 1.4 TSI DSG (2018). ISO 15765-4 CAN 11-bit 500k (protocol 6).
/// ECM (7E8) + DSG TCM (7E9) both answer functional requests. Wide-band
/// upstream lambda → 0114 unsupported (data is in 0124); narrow-band 0115
/// downstream. Fuel level 012F support on MED17 is commonly reported
/// (unverified). Oil temp 015C not reported via generic OBD (unverified).
const golf2018Vin = 'WVWZZZAUZJW123456';
final golf2018 = Vehicle(
  name: 'VW Golf VII 1.4 TSI 2018',
  protocol: '6',
  build: () => EuroCar(
    protocol: '6',
    autoSearchTime: const Duration(seconds: 7),
    // Two responders: the ELM waits for further replies before printing.
    ecuLatency: const Duration(milliseconds: 90),
    responses: {
      ...supportReplies(
        const {
          0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, //
          0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20, 0x21, 0x24, 0x2E, 0x2F, //
          0x30, 0x31, 0x33, 0x3C, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, //
          0x47, 0x49, 0x4A, 0x4C,
        },
        tcm: const {0x01, 0x1C},
      ),
      '010C': '41 0C 1B 58', // 1750 rpm
      '010D': '41 0D 32', // 50 km/h
      '0105': '41 05 7F', // 87 °C
      '0111': '41 11 2B', // 16.9 %
      '012F': '41 2F 99', // 60.0 %
      '0104': '41 04 52', // 32.2 %
      '0142': '41 42 37 3C', // 14.14 V
      '0124': '41 24 80 52 66 66', // λ 1.0025, 3.2 V (wide-band B1S1)
      '0149': '41 49 2E', // pedal 18.0 %
      '0106': '41 06 81', // +0.8 %
      '0107': '41 07 7A', // -4.7 %
      '0115': '41 15 A5 FF', // 0.825 V
      '010F': '41 0F 4B', // 35 °C
      '010B': '41 0B 5A', // 90 kPa
      '010E': '41 0E 8A', // +5°
      // ECM: MIL, 1 code. TCM: MIL request, 1 code (components only).
      '0101': '41 01 81 07 61 00\n41 01 81 04 00 00',
      '03': '43 01 02 99\n43 01 07 30', // ECM P0299, TCM P0730
      '07': '47 01 03 01\n47 00', // ECM P0301 pending
      '020C00': '42 0C 00 2B C0',
      '020D00': '42 0D 00 50',
      '020500': '42 05 00 80',
      '020400': '42 04 00 C7',
      '020F00': '42 0F 00 47',
      '021100': '42 11 00 99',
      '020600': '42 06 00 7E',
      '020B00': '42 0B 00 87',
      '0902': canVin(golf2018Vin),
    },
    clearReply: '44\n44',
    afterClear: const {
      '03': '43 00\n43 00',
      '07': '47 00\n47 00',
      '0101': '41 01 00 07 61 61\n41 01 00 04 00 00',
    },
  ),
  connectMin: Duration.zero,
  connectMax: const Duration(seconds: 1),
  dtcs: const ['P0299', 'P0730', '~P0301'],
  dtcsAfterClear: const [],
  vin: golf2018Vin,
  manufacturer: 'Volkswagen',
  country: 'Germany',
  year: equals('2018'),
  milOn: true,
  dtcCount: 2,
  diesel: false,
  monitors: spark(catalyst: ok, o2: ok, o2Heater: ok),
  freezeFrame: const {
    'RPM': '2800 rpm',
    'Speed': '80 km/h',
    'Coolant': '88°C',
    'Engine Load': '78.0%',
    'Air Temp': '31°C',
    'Throttle': '60.0%',
    'Fuel Trim': '-1.6%',
    'MAP': '135 kPa',
  },
);

/// Audi A6 C7 3.0 TFSI (2012). CAN 11-bit 500k. Supercharged V6: bank-2
/// trims 0108/0109 and B2S2 (0119) supported; both upstream sensors are
/// wide-band (0124/0128), so 0114 and 0118 are unsupported. The TCM line
/// arrives first for mode 03 here, and the ECM's 3 codes need ISO-TP
/// multi-frame with 0xAA padding in the consecutive frame.
const a6Vin = 'WAUZZZ4GZCN123456';
final a62012 = Vehicle(
  name: 'Audi A6 C7 3.0 TFSI 2012',
  protocol: '6',
  build: () => EuroCar(
    protocol: '6',
    autoSearchTime: const Duration(seconds: 7),
    ecuLatency: const Duration(milliseconds: 90),
    responses: {
      ...supportReplies(
        const {
          0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, //
          0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x19, 0x1C, 0x1F, 0x20, 0x21, //
          0x24, 0x28, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x3C, 0x3E, 0x40, 0x41, //
          0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x49, 0x4A, 0x4C,
        },
        tcm: const {0x01, 0x1C},
      ),
      '010C': '41 0C 26 AC', // 2475 rpm
      '010D': '41 0D 78', // 120 km/h
      '0105': '41 05 82', // 90 °C
      '0111': '41 11 40', // 25.1 %
      '012F': '41 2F 4D', // 30.2 %
      '0104': '41 04 66', // 40.0 %
      '0142': '41 42 38 0C', // 14.348 V
      '0124': '41 24 7F AE 66 66', // λ 0.9975 (wide-band B1S1)
      '0149': '41 49 33', // pedal 20.0 %
      '0106': '41 06 7F', // -0.8 %
      '0107': '41 07 84', // +3.1 %
      '0108': '41 08 80', // 0 %
      '0109': '41 09 7D', // -2.3 %
      '0115': '41 15 9B FF', // 0.775 V
      '010F': '41 0F 5A', // 50 °C (Gulf summer)
      '010B': '41 0B 64', // 100 kPa
      '010E': '41 0E 98', // +12°
      '0101': '41 01 83 07 61 21\n41 01 00 04 00 00',
      '03':
          '43 00\n'
          '008\n'
          '0: 43 03 04 30 04 20\n'
          '1: 00 11 AA AA AA AA AA', // P0430, P0420, P0011
      '07': '47 01 03 04\n47 00', // P0304 pending
      '020C00': '42 0C 00 0A F0',
      '020D00': '42 0D 00 00',
      '020500': '42 05 00 87',
      '020400': '42 04 00 33',
      '020F00': '42 0F 00 5F',
      '021100': '42 11 00 1A',
      '020600': '42 06 00 80',
      '020B00': '42 0B 00 1E',
      '0902': canVin(a6Vin),
    },
    clearReply: '44\n44',
    afterClear: const {
      '03': '43 00\n43 00',
      '07': '47 00\n47 00',
      '0101': '41 01 00 07 61 61\n41 01 00 04 00 00',
    },
  ),
  connectMin: Duration.zero,
  connectMax: const Duration(seconds: 1),
  dtcs: const ['P0430', 'P0420', 'P0011', '~P0304'],
  dtcsAfterClear: const [],
  vin: a6Vin,
  manufacturer: 'Audi',
  country: 'Germany',
  year: equals('2012'),
  milOn: true,
  dtcCount: 3,
  diesel: false,
  monitors: spark(catalyst: inc, o2: inc, o2Heater: ok),
  freezeFrame: const {
    'RPM': '700 rpm',
    'Speed': '0 km/h',
    'Coolant': '95°C',
    'Engine Load': '20.0%',
    'Air Temp': '55°C',
    'Throttle': '10.2%',
    'Fuel Trim': '0.0%',
    'MAP': '30 kPa',
  },
);

/// BMW X5 E70 xDrive50i (2013), N63 twin-turbo V8, Spartanburg-built
/// (WMI 5UX, as sold in the GCC). D-CAN = ISO 15765-4 11-bit 500k. DME
/// (7E8) + EGS (7E9). Fuel level (012F) and oil temp (015C) are commonly
/// reported as unavailable via generic OBD on BMWs (unverified per DME).
/// Mode 04 with the engine running: ISO 15031-5 allows NRC 0x22
/// (conditionsNotCorrect); modelled here for the DME — whether this DME
/// does so is unverified, but any EOBD ECU may.
const x5Vin = '5UXZV8C57DL123456'; // valid NA check digit '7'
final x52013 = Vehicle(
  name: 'BMW X5 xDrive50i 2013 (GCC)',
  protocol: '6',
  build: () => EuroCar(
    protocol: '6',
    autoSearchTime: const Duration(seconds: 7),
    ecuLatency: const Duration(milliseconds: 90),
    responses: {
      ...supportReplies(
        const {
          0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, //
          0x0E, 0x0F, 0x11, 0x13, 0x15, 0x19, 0x1C, 0x1F, 0x20, 0x21, 0x24, //
          0x28, 0x2E, 0x30, 0x31, 0x33, 0x3C, 0x3E, 0x40, 0x41, 0x42, 0x43, //
          0x44, 0x45, 0x46, 0x47, 0x49, 0x4A, 0x4C,
        },
        tcm: const {0x01, 0x1C},
      ),
      // Hot idle, A/C on, both banks lean (P0171 / P0174).
      '010C': '41 0C 0A 8C', // 675 rpm
      '010D': '41 0D 00', // 0 km/h
      '0105': '41 05 87', // 95 °C
      '0111': '41 11 0E', // 5.5 %
      '0104': '41 04 2E', // 18.0 %
      '0142': '41 42 36 B0', // 14.0 V
      '0124': '41 24 80 00 66 66', // λ 1.000 (wide-band B1S1)
      '0149': '41 49 2B', // pedal 16.9 %
      '0106': '41 06 88', // +6.3 %
      '0107': '41 07 99', // +19.5 %
      '0108': '41 08 8A', // +7.8 %
      '0109': '41 09 9C', // +21.9 %
      '0115': '41 15 28 FF', // 0.20 V
      '010F': '41 0F 55', // 45 °C
      '010B': '41 0B 23', // 35 kPa
      '010E': '41 0E 8E', // +7°
      '0101': '41 01 82 07 61 00\n41 01 00 04 00 00',
      '03': '43 02 01 71 01 74\n43 00', // P0171, P0174
      '07': '47 00\n47 00',
      '020C00': '42 0C 00 0A 8C',
      '020D00': '42 0D 00 00',
      '020500': '42 05 00 87',
      '020400': '42 04 00 2E',
      '020F00': '42 0F 00 55',
      '021100': '42 11 00 0E',
      '020600': '42 06 00 89',
      '020B00': '42 0B 00 23',
      '0902': canVin(x5Vin),
    },
    clearReply: '7F 04 22\n44', // DME refuses, EGS (no codes) acknowledges
  ),
  connectMin: Duration.zero,
  connectMax: const Duration(seconds: 1),
  dtcs: const ['P0171', 'P0174'],
  dtcsAfterClear: const ['P0171', 'P0174'],
  vin: x5Vin,
  manufacturer: 'BMW',
  country: 'United States',
  year: equals('2013'),
  milOn: true,
  dtcCount: 2,
  diesel: false,
  monitors: spark(catalyst: ok, o2: ok, o2Heater: ok),
  freezeFrame: const {
    'RPM': '675 rpm',
    'Speed': '0 km/h',
    'Coolant': '95°C',
    'Engine Load': '18.0%',
    'Air Temp': '45°C',
    'Throttle': '5.5%',
    'Fuel Trim': '7.0%',
    'MAP': '35 kPa',
  },
);

/// Mercedes-Benz C 200 W205 (2015), M274 2.0 turbo, ECE/GCC VIN (WDD…).
/// CAN 11-bit 500k; ECM + 7G-Tronic TCM. Fuel level (012F) is commonly not
/// available from the ECM via generic OBD on Mercedes (unverified). ECE
/// Mercedes VIN: positions 4-9 model code, 10 = '1' (not a model year; to my
/// knowledge a steering/variant code), 11 = plant (F = Bremen).
const c200Vin = 'WDD2050431F123456';
EuroCar Function() _c200({String? mode03}) =>
    () => EuroCar(
      protocol: '6',
      autoSearchTime: const Duration(seconds: 7),
      ecuLatency: const Duration(milliseconds: 90),
      responses: {
        ...supportReplies(
          const {
            0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, //
            0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20, 0x21, 0x24, 0x2E, 0x30, //
            0x31, 0x33, 0x3C, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, //
            0x49, 0x4A, 0x4C,
          },
          tcm: const {0x01, 0x1C},
        ),
        '010C': '41 0C 1F 40', // 2000 rpm
        '010D': '41 0D 64', // 100 km/h
        '0105': '41 05 7D', // 85 °C
        '0111': '41 11 33', // 20.0 %
        '0104': '41 04 4C', // 29.8 %
        '0142': '41 42 37 DC', // 14.3 V
        '0124': '41 24 80 29 66 66', // λ 1.00125 (wide-band B1S1)
        '0149': '41 49 40', // pedal 25.1 %
        '0106': '41 06 80', // 0 %
        '0107': '41 07 82', // +1.6 %
        '0115': '41 15 B4 FF', // 0.90 V
        '010F': '41 0F 4E', // 38 °C
        '010B': '41 0B 6E', // 110 kPa
        '010E': '41 0E 9E', // +15°
        '0101': '41 01 83 07 61 00\n41 01 00 04 00 00',
        '03':
            mode03 ??
            '008\n'
                '0: 43 03 00 16 03 00\n'
                '1: 04 20 55 55 55 55 55\n'
                '43 00', // P0016, P0300, P0420 (ECM), TCM none
        '07': '47 01 01 71\n47 00',
        '020C00': '42 0C 00 1F 40',
        '020D00': '42 0D 00 64',
        '020500': '42 05 00 7D',
        '020400': '42 04 00 4C',
        '020F00': '42 0F 00 4E',
        '021100': '42 11 00 33',
        '020600': '42 06 00 80',
        '020B00': '42 0B 00 6E',
        '0902': canVin(c200Vin),
      },
      clearReply: '44\n44',
      afterClear: const {
        '03': '43 00\n43 00',
        '07': '47 00\n47 00',
        '0101': '41 01 00 07 61 61\n41 01 00 04 00 00',
      },
    );
final c2002015 = Vehicle(
  name: 'Mercedes C 200 W205 2015',
  protocol: '6',
  build: _c200(),
  connectMin: Duration.zero,
  connectMax: const Duration(seconds: 1),
  dtcs: const ['P0016', 'P0300', 'P0420', '~P0171'],
  dtcsAfterClear: const [],
  vin: c200Vin,
  manufacturer: 'Mercedes',
  country: 'Germany',
  // ECE Mercedes: pos 10 is not a year ('1' would read as 2001).
  year: equals('Unknown'),
  milOn: true,
  dtcCount: 3,
  diesel: false,
  monitors: spark(catalyst: ok, o2: ok, o2Heater: ok),
  freezeFrame: const {
    'RPM': '2000 rpm',
    'Speed': '100 km/h',
    'Coolant': '85°C',
    'Engine Load': '29.8%',
    'Air Temp': '38°C',
    'Throttle': '20.0%',
    'Fuel Trim': '0.0%',
    'MAP': '110 kPa',
  },
);

/// Mercedes-Benz Sprinter 316 CDI (906, 2014), OM651 Euro 5 diesel, N1 EOBD.
/// CAN 11-bit 500k, single responding ECU (manual gearbox). Diesel: no fuel
/// trims, no narrow-band O2, no ignition timing → those PIDs are NO DATA.
/// 0111 is the intake throttle flap (support unverified). Readiness: byte B
/// bit 3 = compression ignition; C = NMHC cat, boost, exhaust gas sensor,
/// DPF, EGR (no SCR on Euro 5).
const sprinterVin = 'WDB9066331S123456';
final sprinter2014 = Vehicle(
  name: 'Mercedes Sprinter 316 CDI 2014 (diesel)',
  protocol: '6',
  build: () => EuroCar(
    protocol: '6',
    autoSearchTime: const Duration(seconds: 7),
    ecuLatency: const Duration(milliseconds: 60),
    responses: {
      ...supportReplies(const {
        0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x1C, 0x1F, //
        0x20, 0x21, 0x23, 0x2C, 0x2D, 0x30, 0x31, 0x33, 0x40, 0x41, 0x42, //
        0x49,
      }),
      '010C': '41 0C 0C 80', // 800 rpm
      '010D': '41 0D 00', // 0 km/h
      '0105': '41 05 73', // 75 °C
      '0111': '41 11 E6', // 90.2 % (flap open)
      '0104': '41 04 26', // 14.9 %
      '0142': '41 42 37 14', // 14.1 V
      '0123': '41 23 0A 8C', // rail 27 MPa (common-rail idle)
      '0149': '41 49 26', // pedal 14.9 % (at rest)
      '010F': '41 0F 46', // 30 °C
      '010B': '41 0B 66', // 102 kPa
      '0101': '41 01 81 0F E9 40', // MIL, 1 code, diesel, DPF incomplete
      '03': '43 01 24 63', // P2463 DPF soot accumulation
      '07': '47 01 04 01', // P0401 EGR flow insufficient (pending)
      '020C00': '42 0C 00 1F 40',
      '020D00': '42 0D 00 5A',
      '020500': '42 05 00 7D',
      '020400': '42 04 00 99',
      '020F00': '42 0F 00 50',
      '021100': '42 11 00 E6',
      '020B00': '42 0B 00 B4',
      '0902': canVin(sprinterVin),
    },
    afterClear: const {
      '03': '43 00',
      '07': '47 00',
      '0101': '41 01 00 0F E9 E9',
    },
  ),
  connectMin: Duration.zero,
  connectMax: const Duration(seconds: 1),
  dtcs: const ['P2463', '~P0401'],
  dtcsAfterClear: const [],
  vin: sprinterVin,
  manufacturer: 'Mercedes',
  country: 'Germany',
  year: equals('Unknown'), // ECE Mercedes, see C 200
  milOn: true,
  dtcCount: 1,
  diesel: true,
  monitors: compression(
    nmhc: ok,
    boost: ok,
    exhaustSensor: ok,
    pmFilter: inc,
    egr: ok,
  ),
  freezeFrame: const {
    'RPM': '2000 rpm',
    'Speed': '90 km/h',
    'Coolant': '85°C',
    'Engine Load': '60.0%',
    'Air Temp': '40°C',
    'Throttle': '90.2%',
    'MAP': '180 kPa',
  },
);

/// Range Rover L405 5.0 V8 Supercharged (2016). CAN 11-bit 500k; ECM + ZF
/// 8HP TCM. JLR VINs use the NA layout worldwide (pos 10 = model year
/// G = 2016, pos 11 A = Solihull); check digit computed. Oil temp 015C and
/// fuel level 012F support are unverified (modelled as supported so one
/// vehicle exercises both). TCM holds U0401 (invalid data from ECM).
const rrVin = 'SALGA2EF7GA123456';
final rangeRover2016 = Vehicle(
  name: 'Range Rover 5.0 V8 SC 2016',
  protocol: '6',
  build: () => EuroCar(
    protocol: '6',
    autoSearchTime: const Duration(seconds: 7),
    ecuLatency: const Duration(milliseconds: 90),
    responses: {
      ...supportReplies(
        const {
          0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, //
          0x0E, 0x0F, 0x10, 0x11, 0x13, 0x15, 0x19, 0x1C, 0x1F, 0x20, 0x21, //
          0x24, 0x28, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x3C, 0x3E, 0x40, 0x41, //
          0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x49, 0x4A, 0x4C, 0x5C,
        },
        tcm: const {0x01, 0x1C},
      ),
      // Desert highway, 140 km/h.
      '010C': '41 0C 2E E0', // 3000 rpm
      '010D': '41 0D 8C', // 140 km/h
      '0105': '41 05 8A', // 98 °C
      '0111': '41 11 4D', // 30.2 %
      '012F': '41 2F CC', // 80.0 %
      '0104': '41 04 73', // 45.1 %
      '0142': '41 42 38 A4', // 14.5 V
      '0124': '41 24 7F D7 66 66', // λ 0.99875 (wide-band B1S1)
      '0149': '41 49 59', // pedal 34.9 %
      '015C': '41 5C 96', // 110 °C
      '0106': '41 06 7C', // -3.1 %
      '0107': '41 07 86', // +4.7 %
      '0108': '41 08 82', // +1.6 %
      '0109': '41 09 88', // +6.3 %
      '0115': '41 15 A0 FF', // 0.80 V
      '010F': '41 0F 5F', // 55 °C
      '010B': '41 0B 78', // 120 kPa (boost)
      '010E': '41 0E 90', // +8°
      '0101': '41 01 81 07 61 00\n41 01 81 04 00 00',
      '03': '43 01 03 02\n43 01 C4 01', // ECM P0302, TCM U0401
      '07': '47 01 00 11\n47 00', // ECM P0011 pending
      '020C00': '42 0C 00 0C 80',
      '020D00': '42 0D 00 00',
      '020500': '42 05 00 69',
      '020400': '42 04 00 40',
      '020F00': '42 0F 00 3C',
      '021100': '42 11 00 1F',
      '020600': '42 06 00 79',
      '020B00': '42 0B 00 2A',
      '0902': canVin(rrVin),
    },
    clearReply: '44\n44',
    afterClear: const {
      '03': '43 00\n43 00',
      '07': '47 00\n47 00',
      '0101': '41 01 00 07 61 61\n41 01 00 04 00 00',
    },
  ),
  connectMin: Duration.zero,
  connectMax: const Duration(seconds: 1),
  dtcs: const ['P0302', 'U0401', '~P0011'],
  dtcsAfterClear: const [],
  vin: rrVin,
  manufacturer: 'Land Rover',
  country: 'United Kingdom',
  year: equals('2016'),
  milOn: true,
  dtcCount: 2,
  diesel: false,
  monitors: spark(catalyst: ok, o2: ok, o2Heater: ok),
  freezeFrame: const {
    'RPM': '800 rpm',
    'Speed': '0 km/h',
    'Coolant': '65°C',
    'Engine Load': '25.1%',
    'Air Temp': '20°C',
    'Throttle': '12.2%',
    'Fuel Trim': '-5.5%',
    'MAP': '42 kPa',
  },
);

/// GENERIC 29-bit CAN EOBD vehicle (ISO 15765-4 29-bit 500k, ELM protocol 7).
/// I know of no European passenger car that answers EOBD on 29-bit IDs with
/// confidence; Euro VI heavy-duty vehicles use 29-bit but speak WWH-OBD
/// (ISO 27145 / UDS) or J1939, which would not answer mode 01 at all. This
/// profile is a modelled Euro 6 diesel light-commercial (SCR + DPF) that
/// speaks J1979 over 29-bit, to exercise the ATSP6 → NO DATA → ATSP0 path.
/// 11-bit 7DF on a 29-bit 500k bus is ACKed but unanswered → NO DATA.
/// The WMI (VF1 = Renault) is chosen only for decoder coverage.
const generic29Vin = 'VF1MA000864512345';
final generic29 = Vehicle(
  name: 'Generic 29-bit CAN EOBD diesel (modelled)',
  protocol: '7',
  build: () => EuroCar(
    protocol: '7',
    autoSearchTime: const Duration(seconds: 6),
    wrongProtocolReply: 'NO DATA',
    wrongProtocolDelay: const Duration(milliseconds: 200),
    ecuLatency: const Duration(milliseconds: 60),
    responses: {
      ...supportReplies(const {
        0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x11, 0x1C, 0x1F, //
        0x20, 0x21, 0x23, 0x2C, 0x2D, 0x30, 0x31, 0x33, 0x40, 0x41, 0x42, //
        0x49, 0x5C,
      }),
      '010C': '41 0C 0D 48', // 850 rpm
      '010D': '41 0D 00',
      '0105': '41 05 78', // 80 °C
      '0111': '41 11 CC', // 80.0 %
      '0104': '41 04 21', // 12.9 %
      '0142': '41 42 36 4C', // 13.9 V
      '0123': '41 23 0F A0', // rail 40 MPa
      '0149': '41 49 1A', // pedal 10.2 %
      '015C': '41 5C 82', // 90 °C
      '010F': '41 0F 3C', // 20 °C
      '010B': '41 0B 65', // 101 kPa
      // No MIL, diesel; C=EB: NMHC, NOx/SCR, boost, EGS, DPF, EGR;
      // D=02: SCR incomplete.
      '0101': '41 01 00 0F EB 02',
      '03': '43 00',
      '07': '47 01 20 EE', // P20EE SCR efficiency (pending)
      '0902': canVin(generic29Vin),
    },
    afterClear: const {'07': '47 00', '0101': '41 01 00 0F EB EB'},
  ),
  connectMin: const Duration(seconds: 6),
  connectMax: const Duration(seconds: 9),
  dtcs: const ['~P20EE'],
  dtcsAfterClear: const [],
  vin: generic29Vin,
  manufacturer: 'Renault',
  country: 'France',
  milOn: false,
  dtcCount: 0,
  diesel: true,
  monitors: compression(
    nmhc: ok,
    noxScr: inc,
    boost: ok,
    exhaustSensor: ok,
    pmFilter: ok,
    egr: ok,
  ),
  freezeFrame: const {},
);

final vehicles = [
  golf2004,
  logan2010,
  golf2018,
  a62012,
  x52013,
  c2002015,
  sprinter2014,
  rangeRover2016,
  generic29,
];

// ── Measurement helpers ───────────────────────────────────────────────────────

/// Runs one live-data poll and returns the decoded frame, how long the poll
/// took (from the 3 s tick that started it to the emitted frame) and the
/// commands it sent.
(OBDLiveData, Duration, List<String>) pollOnce(Rig rig) =>
    pollWith(rig.async, rig.adapter, rig.elm);

/// [pollOnce] for an [adapter] that may have been reconnected to [elm]
/// (a different simulated car than the rig it was created with).
(OBDLiveData, Duration, List<String>) pollWith(
  FakeAsync async,
  OBDAdapter adapter,
  FakeElm327 elm,
) {
  final skip = elm.commands.length;
  OBDLiveData? data;
  Duration? at;
  final sub = adapter.liveDataStream.listen((d) {
    data ??= d;
    at ??= async.elapsed;
  });
  adapter.startLiveData();
  async.elapse(const Duration(seconds: 3)); // first tick fires the poll
  final started = async.elapsed;
  final deadline = started + const Duration(seconds: 40);
  while (data == null && async.elapsed < deadline) {
    async.elapse(const Duration(milliseconds: 10));
  }
  adapter.stopLiveData();
  sub.cancel();
  if (data == null) fail('no live-data frame within 40 s');
  return (data!, at! - started, elm.commands.sublist(skip));
}

/// Support bitmap of every ECU line for range [base] in [car]'s reply to
/// "01BB", ORed (J1979: a PID is available if any ECU supports it).
int _orBitmap(SimCar car, int base) {
  final req = '01${_h(base)}';
  final hdr = '41 ${_h(base)} ';
  var mask = 0;
  for (final line in (car.responses[req] ?? '').split('\n')) {
    if (!line.startsWith(hdr)) continue;
    final b = line
        .substring(hdr.length)
        .split(' ')
        .where((x) => x.isNotEmpty)
        .map((x) => int.parse(x, radix: 16))
        .toList();
    if (b.length < 4) continue;
    mask |= (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }
  return mask;
}

bool _bit(int mask, int base, int pid) =>
    (mask >> (0x20 - (pid - base))) & 1 == 1;

/// The ORed 0100 / 0120 / 0140 bitmaps of [car], following the J1979 chain
/// (a range is only read when the previous bitmap's last bit says so).
Map<int, int> _masks(SimCar car) {
  final m00 = _orBitmap(car, 0x00);
  final m20 = _bit(m00, 0x00, 0x20) ? _orBitmap(car, 0x20) : 0;
  final m40 = _bit(m20, 0x20, 0x40) ? _orBitmap(car, 0x40) : 0;
  return {0x00: m00, 0x20: m20, 0x40: m40};
}

/// The [extraPids] a poll of [car] requests (see [extraPids]).
List<String> polledExtras(SimCar car) {
  final m = _masks(car);
  bool adv(int pid) => _advertised(m, pid);
  return [
    if (!adv(0x14) && adv(0x24)) '0124',
    if (!adv(0x14) && !adv(0x24) && adv(0x34)) '0134',
    if (adv(0x23)) '0123',
    if (adv(0x49)) '0149',
  ];
}

/// One poll's requests after the bitmaps: the [regular] PIDs in poll order,
/// ATRV in the 0142 slot when 0142 isn't among them (the sim answers '?',
/// so only on the first two polls of a connection), then [extras].
List<String> pollSequence(
  Iterable<String> regular, {
  List<String> extras = const [],
  int poll = 1,
}) => [
  for (final p in polledPids)
    if (p == '0142' && !regular.contains(p)) ...[
      if (poll <= 2) 'ATRV',
    ] else if (regular.contains(p))
      p,
  ...extras,
];

/// What one J1979-conformant first poll of [car] must send: the 0120 / 0140
/// bitmap requests the chain calls for (0120 only if some ECU's 0100 sets
/// bit 0x20, 0140 only if some 0120 sets bit 0x40), then exactly the
/// [polledPids] some ECU advertises, in poll order (see [pollSequence]).
List<String> expectedFirstPoll(SimCar car) {
  final masks = _masks(car);
  return [
    if (_bit(masks[0x00]!, 0x00, 0x20)) '0120',
    if (_bit(masks[0x20]!, 0x20, 0x40)) '0140',
    ...pollSequence([
      for (final p in polledPids)
        if (_advertised(masks, int.parse(p.substring(2), radix: 16))) p,
    ], extras: polledExtras(car)),
  ];
}

bool _advertised(Map<int, int> masks, int pid) {
  final base = ((pid - 1) ~/ 0x20) * 0x20;
  return _bit(masks[base] ?? 0, base, pid);
}

final _matrix = <String, Map<String, String>>{};
void _record(Vehicle v, String key, String value) =>
    (_matrix[v.name] ??= {})[key] = value;

String _secs(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

const _handshake = ['ATE0', 'ATL0', 'ATS0', 'ATH0'];

// ── Variants for the regression group ─────────────────────────────────────────

/// [base] with replies patched (a null value removes the reply → NO DATA),
/// an optional other mode 04 reply / clear outcome / post-clear state, and
/// requests that hang once (no reply, no prompt) like some clones do.
class _Variant extends EuroCar {
  _Variant(
    EuroCar base, {
    Map<String, String?> patch = const {},
    String? clearReply,
    Map<String, String>? afterClear,
    this.accepts,
    Set<String> hangsOnce = const {},
  }) : _hangsOnce = hangsOnce,
       super(
         protocol: base.protocol!,
         responses: _patched(base.responses, patch),
         autoSearchTime: base.autoSearchTime,
         wrongProtocolReply: base.wrongProtocolReply,
         wrongProtocolDelay: base.wrongProtocolDelay,
         ecuLatency: base.ecuLatency,
         noDataLatency: base.noDataLatency,
         clearReply: clearReply ?? base.clearReply,
         afterClear: afterClear ?? base.afterClear,
       );

  /// Whether the ECUs really cleared (overrides the "no 7F 04" heuristic,
  /// e.g. for "7F 04 78" responsePending followed by "44").
  final bool? accepts;
  final Set<String> _hangsOnce;

  @override
  Set<String> get hangsOnce => _hangsOnce;

  @override
  bool get clearAccepted => accepts ?? super.clearAccepted;

  static Map<String, String> _patched(
    Map<String, String> r,
    Map<String, String?> p,
  ) => {
    for (final e in r.entries)
      if (!p.containsKey(e.key)) e.key: e.value,
    for (final e in p.entries)
      if (e.value != null) e.key: e.value!,
  };
}

/// Every [polledPids] field of [d] equals the J1979 decode of the first
/// ECU line [car] answers (null when the car answers NO DATA); extras as in
/// [expectExtras].
void expectDecoded(EuroCar car, OBDLiveData d, {bool extras = true}) {
  for (final p in polledPids) {
    final exp = j1979(p, firstEcuBytes(car.responses[p], p));
    final got = _field[p]!(d);
    if (exp == null) {
      expect(got, isNull, reason: '$p → NO DATA → null');
    } else {
      expect(got, closeTo(exp, 1e-9), reason: p);
    }
  }
  expectExtras(car, d, polled: extras);
}

/// The wide-band λ / rail pressure / pedal fields of [d] decode the PIDs
/// [polledExtras] picks and are null otherwise (all null when [polled] is
/// false, i.e. the adapter never got a readable bitmap).
void expectExtras(EuroCar car, OBDLiveData d, {bool polled = true}) {
  final sent = polled ? polledExtras(car) : const <String>[];
  double? want(String p) =>
      sent.contains(p) ? j1979(p, firstEcuBytes(car.responses[p], p)) : null;
  void check(double? got, double? exp, String what) => exp == null
      ? expect(got, isNull, reason: '$what not polled → null')
      : expect(got, closeTo(exp, 1e-9), reason: what);
  check(d.lambdaB1S1, want('0124') ?? want('0134'), 'λ (0124/0134)');
  check(d.fuelRailPressureKpa, want('0123'), '0123');
  check(d.acceleratorPedalPct, want('0149'), '0149');
}

int _pid(String cmd) => int.parse(cmd.substring(2), radix: 16);

const _bitmapRequests = {'0120', '0140'};

/// Golf VII ECM support set (same as [golf2018]).
const _golf7Ecm = {
  0x01, 0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, //
  0x10, 0x11, 0x13, 0x15, 0x1C, 0x1F, 0x20, 0x21, 0x24, 0x2E, 0x2F, //
  0x30, 0x31, 0x33, 0x3C, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, //
  0x47, 0x49, 0x4A, 0x4C,
};

const _x5Cleared = {
  '03': '43 00\n43 00',
  '07': '47 00\n47 00',
  '0101': '41 01 00 07 61 61\n41 01 00 04 00 00',
};

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDownAll(() {
    for (final e in _matrix.entries) {
      // ignore: avoid_print
      print('MATRIX ${e.key}: ${e.value}');
    }
  });

  for (final v in vehicles) {
    group(v.name, () {
      test('profile sanity: 0100/0120/0140 bitmaps match the PIDs the ECM '
          'answers', () {
        final car = v.build();
        for (final p in polledPids) {
          final pid = int.parse(p.substring(2), radix: 16);
          expect(car.answers(p), car.advertises(pid), reason: p);
        }
        // Extras the adapter will ask for are answered too.
        for (final p in polledExtras(car)) {
          expect(car.answers(p), isTrue, reason: '$p advertised, no reply');
        }
        expect(car.responses.containsKey('0120'), car.advertises(0x20));
        expect(car.responses.containsKey('0140'), car.advertises(0x40));
        // Every mode 01 reply in the profile is advertised.
        for (final k in car.responses.keys) {
          if (k.length == 4 &&
              k.startsWith('01') &&
              !k.endsWith('00') &&
              k != '0120' &&
              k != '0140') {
            expect(
              car.advertises(int.parse(k.substring(2), radix: 16)),
              isTrue,
              reason: '$k answered but not advertised',
            );
          }
        }
        // NA-region VINs must carry a valid check digit.
        if (v.vin != null && '12345'.contains(v.vin![0])) {
          expect(_checkDigit(v.vin!), v.vin![8]);
        }
      });

      test('connect', () {
        sim(v.build(), (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();
          final took = rig.async.elapsed - t0;
          _record(v, 'connect', '${_secs(took)} s');

          expect(rig.adapter.isConnected, isTrue);
          expect(rig.elm.activeProtocol, v.protocol);
          expect(
            rig.elm.commands,
            v.protocol == '6'
                ? [..._handshake, 'ATSP6', '0100']
                : [..._handshake, 'ATSP6', '0100', 'ATSP0', '0100'],
          );
          expect(took, greaterThanOrEqualTo(v.connectMin));
          expect(took, lessThan(v.connectMax));
        }, connect: false);
      }, skip: v.skip['connect']);

      test('live data: one poll decodes every supported PID', () {
        sim(v.build(), (rig) {
          final car = rig.elm.car as EuroCar;
          final (data, took, sent) = pollOnce(rig);
          final supported = polledPids.where(car.answers).length;
          _record(v, 'poll', '${_secs(took)} s ($supported/18 PIDs supported)');

          // Fix #1: only the advertised PIDs are polled (plus the 0120/0140
          // bitmap requests on the first poll); every one still decodes.
          final expected = expectedFirstPoll(car);
          expect(
            sent.where((c) => c != '0120' && c != '0140').toList(),
            expected.where((c) => c != '0120' && c != '0140').toList(),
          );
          expect(sent, expected);
          for (final p in polledPids) {
            final exp = j1979(p, firstEcuBytes(car.responses[p], p));
            final got = _field[p]!(data);
            if (exp == null) {
              expect(got, isNull, reason: '$p unsupported → null');
            } else {
              expect(got, closeTo(exp, 1e-9), reason: p);
            }
          }
          expectExtras(car, data);
        });
      }, skip: v.skip['live']);

      test('DTCs: confirmed (03) + pending (07)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
        });
      }, skip: v.skip['dtcs']);

      test('clear DTCs: ECU state after mode 04', () {
        sim(v.build(), (rig) {
          final car = rig.elm.car as EuroCar;
          rig.drive(rig.adapter.clearDtcs());
          expect(rig.elm.commands.last, '04');
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcsAfterClear);
          if (car.clearAccepted) {
            final r = rig.drive(rig.adapter.getReadinessMonitors());
            expect(r.milOn, isFalse);
            expect(r.dtcCount, 0);
            expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
          }
        });
      }, skip: v.skip['clear']);

      test(
        'clear DTCs: clearDtcs() result reflects the ECU reply',
        () {
          sim(v.build(), (rig) {
            final car = rig.elm.car as EuroCar;
            expect(rig.drive(rig.adapter.clearDtcs()), car.clearAccepted);
          });
        },
        skip: v.skip['clearResult'],
      );

      test('VIN: getVin() (mode 09 PID 02)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getVin()), v.vin);
        });
      }, skip: v.skip['vin']);

      if (v.vin != null) {
        test(
          'VIN: VinDecoder.decode() → manufacturer + country',
          () {
            final d = VinDecoder.decode(v.vin!, now: DateTime(2026, 11, 3));
            _record(
              v,
              'decode',
              '${d['manufacturer']} / ${d['country']} / ${d['year']}',
            );
            expect(d['manufacturer'], v.manufacturer);
            expect(d['country'], v.country);
          },
          skip: v.skip['vinMfr'],
        );

        if (v.year != null) {
          test('VIN: VinDecoder.decode() → model year', () {
            final d = VinDecoder.decode(v.vin!, now: DateTime(2026, 11, 3));
            expect(d['year'], v.year);
          }, skip: v.skip['vinYear']);
        }
      }

      test('readiness: monitors + spark/diesel', () {
        sim(v.build(), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.compressionIgnition, v.diesel);
          expect({for (final m in r.monitors) m.name: m.status}, v.monitors);
        });
      }, skip: v.skip['readiness']);

      test(
        'readiness: MIL + DTC count over all responding ECUs',
        () {
          sim(v.build(), (rig) {
            final r = rig.drive(rig.adapter.getReadinessMonitors());
            expect(r.milOn, v.milOn);
            expect(r.dtcCount, v.dtcCount);
          });
        },
        skip: v.skip['readinessCombined'],
      );

      test('freeze frame (mode 02, frame 00)', () {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getFreezeFrame()), v.freezeFrame);
        });
      }, skip: v.skip['freeze']);
    });
  }

  // ── Cross-vehicle behaviour ────────────────────────────────────────────────

  group('cross-vehicle', () {
    test('Mercedes C 200: ECM multi-frame mode 03 with the TCM single frame '
        'arriving between the first and consecutive frame (headers off) '
        'keeps all three codes', () {
      final car = _c200(
        mode03:
            '008\n'
            '0: 43 03 00 16 03 00\n'
            '43 00\n'
            '1: 04 20 55 55 55 55 55',
      )();
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), [
          'P0016',
          'P0300',
          'P0420',
          '~P0171',
        ]);
      });
    });

    for (final v in [golf2004, sprinter2014]) {
      test('${v.name}: live poll only requests PIDs advertised in '
          '0100/0120/0140', () {
        sim(v.build(), (rig) {
          final car = rig.elm.car as EuroCar;
          final (_, _, sent) = pollOnce(rig);
          final unadvertised = sent
              .where((p) => !p.startsWith('AT')) // adapter-local (ATRV)
              .where(
                (p) => !car.advertises(int.parse(p.substring(2), radix: 16)),
              )
              .toList();
          expect(unadvertised, isEmpty);
        });
      });
    }
  });
  // ── Adversarial checks of the adapter / decoder fixes ───────────────────────

  group('regression', () {
    // ── #1 support bitmaps ───────────────────────────────────────────────────

    // NO DATA is ambiguous (timeout, busy ECU) → poll the range anyway.
    // A negative response (7F 01 12, ISO 15031-5 "request out of range") is
    // the ECU saying the range doesn't exist → nothing above 0x20 is polled.
    for (final (label, reply, negative) in [
      ('NO DATA', null, false),
      ('7F 01 12 (negative response)', '7F 01 12', true),
    ]) {
      test('Dacia Logan KWP: 0100 sets bit 0x20 but 0120 answers $label → '
          '${negative ? 'range 0x21–0x60 treated as unsupported' : 'range '
              '0x21–0x60 falls back to "poll all"'}, 0140 never asked, values '
          'right, poll < 3 s', () {
        final car = _Variant(logan2010.build(), patch: {'0120': reply});
        sim(car, (rig) {
          final (d, took, sent) = pollOnce(rig);
          final pids = [
            for (final p in polledPids)
              if (car.advertises(_pid(p)) || (!negative && _pid(p) > 0x20)) p,
          ];
          expect(sent, ['0120', ...pollSequence(pids)]);
          expectDecoded(car, d);
          expect(took, lessThan(const Duration(seconds: 3)));

          final (d2, took2, sent2) = pollOnce(rig);
          expect(
            sent2,
            pollSequence(pids, poll: 2),
            reason: 'support is read once per connection',
          );
          expectDecoded(car, d2);
          expect(took2, lessThan(const Duration(seconds: 3)));
        });
      });
    }

    // ── Wide-band O2 / diesel extras ─────────────────────────────────────────

    test('VW Golf VII (wide-band upstream, no 0114): λ from 0124 and pedal '
        'from 0149, after the regular PIDs', () {
      sim(golf2018.build(), (rig) {
        final (d, took, sent) = pollOnce(rig);
        expect(sent.sublist(sent.length - 2), ['0124', '0149']);
        expect(sent, isNot(contains('0114')));
        expect(d.o2B1S1Voltage, isNull);
        expect(d.lambdaB1S1, closeTo(1.0025, 1e-4)); // 0x8052 / 32768
        expect(d.acceleratorPedalPct, closeTo(18.04, 0.01)); // 0x2E
        expect(d.fuelRailPressureKpa, isNull);
        expect(took, lessThan(const Duration(seconds: 3)));
      });
    });

    test('Mercedes Sprinter CDI (diesel): rail pressure from 0123, pedal '
        'from 0149; no wide-band request', () {
      sim(sprinter2014.build(), (rig) {
        final (d, _, sent) = pollOnce(rig);
        expect(sent.sublist(sent.length - 2), ['0123', '0149']);
        expect(d.fuelRailPressureKpa, 27000); // 0x0A8C × 10 kPa
        expect(d.acceleratorPedalPct, closeTo(14.90, 0.01));
        expect(d.lambdaB1S1, isNull);
      });
    });

    test('VW Golf IV KWP: 0100 without bit 0x20 → neither 0120 nor 0140 is '
        'sent, only the 12 advertised PIDs', () {
      sim(golf2004.build(), (rig) {
        final car = rig.elm.car as EuroCar;
        final (d, _, sent) = pollOnce(rig);
        // No 0142 on this ECU → the adapter's ATRV takes its slot.
        expect(
          sent,
          pollSequence(polledPids.where((p) => car.advertises(_pid(p)))),
        );
        expect(sent.where((c) => c != 'ATRV'), hasLength(12));
        expectDecoded(car, d);
      });
    });

    test('VW Golf VII: 012F advertised but answered NO DATA → fuel null, '
        'every other PID decoded, poll < 3 s', () {
      final car = _Variant(golf2018.build(), patch: {'012F': null});
      sim(car, (rig) {
        final (d, took, sent) = pollOnce(rig);
        expect(sent, expectedFirstPoll(car));
        expect(sent, contains('012F'));
        expect(d.fuelLevelPct, isNull);
        expectDecoded(car, d);
        expect(took, lessThan(const Duration(seconds: 3)));

        final (d2, _, sent2) = pollOnce(rig);
        expect(sent2.toSet().intersection(_bitmapRequests), isEmpty);
        expect(
          sent2.every(
            (p) => _advertised({
              for (final b in [0, 0x20, 0x40]) b: _orBitmap(car, b),
            }, _pid(p)),
          ),
          isTrue,
        );
        expectDecoded(car, d2);
      });
    });

    test('VW Golf VII ECM + DSG TCM with different bitmaps (TCM line first): '
        'the union is polled and the TCM-only 0142 decodes', () {
      final ecm = {..._golf7Ecm}..remove(0x42);
      const tcm = {0x01, 0x0D, 0x1C, 0x20, 0x40, 0x42};
      final car = _Variant(
        golf2018.build(),
        patch: {
          '0100': '${supportBitmap(0, tcm)}\n${supportBitmap(0, ecm)}',
          '0120': '${supportBitmap(0x20, ecm)}\n${supportBitmap(0x20, tcm)}',
          '0140': '${supportBitmap(0x40, tcm)}\n${supportBitmap(0x40, ecm)}',
          '0142': '41 42 37 3C', // TCM only: 14.14 V
          '010D': '41 0D 32\n41 0D 32',
        },
      );
      sim(car, (rig) {
        final (d, _, sent) = pollOnce(rig);
        expect(sent, expectedFirstPoll(car));
        expect(sent, containsAll(['0120', '0140', '0142', '012F']));
        expect(d.batteryVoltage, closeTo(14.14, 1e-9));
        expectDecoded(car, d);
      });
    });

    test('ECM 0100 without bit 0x20, only the TCM chains to 0120/0140 → both '
        'bitmaps read (OR over ECUs) and 0142 polled', () {
      final ecm = _golf7Ecm.where((p) => p < 0x20).toSet();
      const tcm = {0x01, 0x1C, 0x20, 0x40, 0x42};
      final car = _Variant(
        golf2018.build(),
        patch: {
          '0100': '${supportBitmap(0, ecm)}\n${supportBitmap(0, tcm)}',
          '0120': supportBitmap(0x20, tcm),
          '0140': supportBitmap(0x40, tcm),
          '012F': null,
        },
      );
      sim(car, (rig) {
        final (d, _, sent) = pollOnce(rig);
        expect(sent, expectedFirstPoll(car));
        expect(sent, containsAll(['0120', '0140', '0142']));
        expect(sent, isNot(contains('012F')));
        expectDecoded(car, d);
      });
    });

    test('reconnect K-line Golf IV → Range Rover on the same adapter: the '
        'support bitmaps are re-read for the new car', () {
      sim(golf2004.build(), (rig) {
        pollOnce(rig);
        final elmB = FakeElm327(rangeRover2016.build());
        final rigB = Rig.fff0(rig.async, elmB);
        rig.drive(rig.adapter.disconnect());
        rig.drive(rig.adapter.connect(rigB.device));
        final (d, _, sent) = pollWith(rig.async, rig.adapter, elmB);
        expect(sent, expectedFirstPoll(elmB.car));
        // Values of the PIDs the Range Rover answers (the others: see the
        // skipped stale-value test below).
        final rr = elmB.car as EuroCar;
        for (final p in polledPids.where(rr.answers)) {
          expect(
            _field[p]!(d),
            closeTo(j1979(p, firstEcuBytes(rr.responses[p], p))!, 1e-9),
            reason: p,
          );
        }
        expectExtras(rr, d);
      });
    });

    test(
      'reconnect Range Rover → K-line Golf IV: only Golf IV PIDs polled',
      () {
        sim(rangeRover2016.build(), (rig) {
          pollOnce(rig);
          final elmB = FakeElm327(golf2004.build());
          final rigB = Rig.fff0(rig.async, elmB);
          rig.drive(rig.adapter.disconnect());
          rig.drive(rig.adapter.connect(rigB.device));
          final (_, took, sent) = pollWith(rig.async, rig.adapter, elmB);
          expect(sent, expectedFirstPoll(elmB.car));
          expect(took, lessThan(const Duration(seconds: 3)));
        });
      },
    );

    test('reconnect to a different car: PIDs the new car lacks are null, '
        'not the previous car\'s values (RR → Golf IV and Golf IV → RR)', () {
      for (final (a, b) in [
        (rangeRover2016, golf2004),
        (golf2004, rangeRover2016),
      ]) {
        sim(a.build(), (rig) {
          pollOnce(rig);
          final elmB = FakeElm327(b.build());
          final rigB = Rig.fff0(rig.async, elmB);
          rig.drive(rig.adapter.disconnect());
          rig.drive(rig.adapter.connect(rigB.device));
          final (d, _, _) = pollWith(rig.async, rig.adapter, elmB);
          expectDecoded(elmB.car as EuroCar, d);
        });
      }
    });

    test('29-bit CAN (protocol 7): bitmaps chain 0100 → 0120 → 0140, poll '
        'only asks advertised PIDs, < 3 s, second poll reuses support', () {
      sim(generic29.build(), (rig) {
        final car = rig.elm.car as EuroCar;
        expect(rig.elm.activeProtocol, '7');
        final (d, took, sent) = pollOnce(rig);
        expect(sent, expectedFirstPoll(car));
        expect(sent.take(2), ['0120', '0140']);
        expectDecoded(car, d);
        expect(took, lessThan(const Duration(seconds: 3)));
        final (_, _, sent2) = pollOnce(rig);
        expect(sent2, sent.skip(2));
      });
    });

    for (final v in vehicles) {
      test('${v.name}: first and second poll both finish within the 3 s '
          'interval', () {
        sim(v.build(), (rig) {
          final car = rig.elm.car as EuroCar;
          final (_, t1, s1) = pollOnce(rig);
          final (d2, t2, s2) = pollOnce(rig);
          _record(v, 'poll2', '${_secs(t2)} s');
          expect(t1, lessThan(const Duration(seconds: 3)));
          expect(t2, lessThan(const Duration(seconds: 3)));
          expect(s2, s1.where((c) => !_bitmapRequests.contains(c)));
          expectDecoded(car, d2);
        });
      });
    }

    // ── #9 recovery after a hung command ─────────────────────────────────────

    for (final (v, hung) in [
      (rangeRover2016, '0105'),
      (golf2004, '010D'),
      (logan2010, '010C'),
    ]) {
      test('${v.name}: $hung hangs once (no reply, no prompt) → the next '
          'PID still gets its own answer, next poll recovers $hung', () {
        final car = _Variant(v.build(), hangsOnce: {hung});
        sim(car, (rig) {
          final (d, _, _) = pollOnce(rig);
          for (final p in polledPids) {
            final exp = j1979(p, firstEcuBytes(car.responses[p], p));
            final got = _field[p]!(d);
            if (p == hung || exp == null) {
              expect(got, isNull, reason: p);
            } else {
              expect(got, closeTo(exp, 1e-9), reason: p);
            }
          }
          final (d2, _, _) = pollOnce(rig);
          expectDecoded(car, d2);
        });
      });
    }

    test('VW Golf VII: the 0120 bitmap request hangs once → that range is '
        'polled anyway (fallback) and every PID decodes', () {
      final car = _Variant(golf2018.build(), hangsOnce: {'0120'});
      sim(car, (rig) {
        final (d, _, sent) = pollOnce(rig);
        expect(sent.first, '0120');
        expect(sent, isNot(contains('0140')));
        expect(sent, containsAll(['012F', '0142', '015C']));
        // The extras need a bitmap that was actually read.
        expect(sent, isNot(contains('0124')));
        expect(sent, isNot(contains('0149')));
        expectDecoded(car, d, extras: false);
      });
    });

    // ── #2 clearDtcs() result ────────────────────────────────────────────────

    for (final (reply, ok, why) in [
      ('7F 04 22', false, 'DME alone refuses (conditionsNotCorrect)'),
      ('7F 04 22\n44', false, 'DME refuses, EGS acknowledges'),
      ('44\n7F 04 22', false, 'DME acknowledges, EGS refuses'),
      ('7F 04 11', false, 'serviceNotSupported'),
      ('NO DATA', false, 'no ECU answered'),
      ('7F 04 78\n44', true, 'responsePending, then positive'),
      ('7F 04 78\n44\n44', true, 'responsePending, then both ECUs positive'),
      ('7F 04 78\n7F 04 22', false, 'responsePending, then refused'),
      ('44\n44', true, 'both ECUs positive'),
    ]) {
      test('BMW X5 mode 04 "${reply.replaceAll('\n', ' / ')}" ($why) → '
          'clearDtcs() == $ok, codes ${ok ? 'gone' : 'kept'}', () {
        final car = _Variant(
          x52013.build(),
          clearReply: reply,
          afterClear: _x5Cleared,
          accepts: ok,
        );
        sim(car, (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), ok);
          expect(
            rig.drive(rig.adapter.getDtcs()),
            ok ? isEmpty : ['P0171', 'P0174'],
          );
        });
      });
    }

    test('K-line Golf IV: mode 04 "44" → true, readiness reset', () {
      sim(golf2004.build(), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isFalse);
        expect(r.dtcCount, 0);
      });
    });

    // ── #3 readiness over several ECUs ───────────────────────────────────────

    test('VW Golf VII: TCM 41 01 line first → same MIL/count/monitors', () {
      final car = _Variant(
        golf2018.build(),
        patch: {'0101': '41 01 81 04 00 00\n41 01 81 07 61 00'},
      );
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 2);
        expect(r.compressionIgnition, isFalse);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, golf2018.monitors);
      });
    });

    test('VW Golf VII: only the DSG TCM answers 0101 → its MIL + count, '
        'components only, spark labels', () {
      final car = _Variant(
        golf2018.build(),
        patch: {'0101': '41 01 81 04 00 00'},
      );
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 1);
        expect(r.compressionIgnition, isFalse);
        expect({
          for (final m in r.monitors) m.name: m.status,
        }, spark(misfire: na, fuel: na));
      });
    });

    for (final (label, lines) in [
      ('TCM after ECM', '41 01 81 0F E9 40\n41 01 00 04 00 00'),
      ('TCM first', '41 01 00 04 00 00\n41 01 81 0F E9 40'),
      ('TCM first with its own code', '41 01 81 04 00 00\n41 01 81 0F E9 40'),
    ]) {
      test('Sprinter diesel + 7G-Tronic TCM (bit 3 clear, spark-looking), '
          '$label → diesel labels from the ECM', () {
        final car = _Variant(sprinter2014.build(), patch: {'0101': lines});
        sim(car, (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.compressionIgnition, isTrue);
          expect(r.milOn, isTrue);
          expect(r.dtcCount, lines.contains('81 04') ? 2 : 1);
          expect({
            for (final m in r.monitors) m.name: m.status,
          }, sprinter2014.monitors);
        });
      });
    }

    test('Range Rover: no MIL on the ECM, TCM requests MIL → MIL on', () {
      final car = _Variant(
        rangeRover2016.build(),
        patch: {'0101': '41 01 00 07 61 00\n41 01 81 04 00 00'},
      );
      sim(car, (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isTrue);
        expect(r.dtcCount, 1);
      });
    });

    // ── #4 headers-off ISO-TP reassembly ─────────────────────────────────────

    const ecmFf = '008\n0: 43 03 00 16 03 00';
    const ecmCf = '1: 04 20 55 55 55 55 55';
    const ecmCodes = ['P0016', 'P0300', 'P0420'];
    for (final (label, mode03, codes) in [
      ('TCM "43 00" first', '43 00\n$ecmFf\n$ecmCf', ecmCodes),
      ('TCM "43 00" last', '$ecmFf\n$ecmCf\n43 00', ecmCodes),
      (
        'TCM P0730 between FF and CF',
        '$ecmFf\n43 01 07 30\n$ecmCf',
        [...ecmCodes, 'P0730'],
      ),
      (
        'TCM P0730 first',
        '43 01 07 30\n$ecmFf\n$ecmCf',
        ['P0730', ...ecmCodes],
      ),
      (
        'TCM multi-frame after the ECM\'s',
        '$ecmFf\n$ecmCf\n008\n0: 43 03 07 30 07 31\n1: 07 32 55 55 55 55 55',
        [...ecmCodes, 'P0730', 'P0731', 'P0732'],
      ),
      (
        'two multi-frame replies interleaved (FF, FF, CF, CF)',
        '$ecmFf\n008\n0: 43 03 07 30 07 31\n$ecmCf\n1: 07 32 55 55 55 55 55',
        [...ecmCodes, 'P0730', 'P0731', 'P0732'],
      ),
    ]) {
      test('Mercedes C 200 mode 03: $label', () {
        sim(_c200(mode03: mode03)(), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), [...codes, '~P0171']);
        });
      });
    }

    test('Audi A6: TCM single frame between the ECM\'s FF and 0xAA-padded '
        'CF keeps P0011', () {
      final car = _Variant(
        a62012.build(),
        patch: {
          '03': '008\n0: 43 03 04 30 04 20\n43 00\n1: 00 11 AA AA AA AA AA',
        },
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), a62012.dtcs);
      });
    });

    // ── #5 VIN parsing ───────────────────────────────────────────────────────

    test('Golf VII: ECM and TCM both answer 0902, frames interleaved', () {
      final c = golf2018Vin.codeUnits.map(_h).toList();
      final ff = '014\n0: 49 02 01 ${c.sublist(0, 3).join(' ')}';
      final cf1 = '1: ${c.sublist(3, 10).join(' ')}';
      final cf2 = '2: ${c.sublist(10, 17).join(' ')}';
      final car = _Variant(
        golf2018.build(),
        patch: {'0902': '$ff\n$ff\n$cf1\n$cf1\n$cf2\n$cf2'},
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), golf2018Vin);
      });
    });

    test('Mercedes C 200: TCM answers 0902 with an all-zero VIN first, ECM '
        'second → the ECM\'s valid VIN', () {
      final car = _Variant(
        c2002015.build(),
        patch: {'0902': '${canVin('\x00' * 17)}\n${canVin(c200Vin)}'},
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), c200Vin);
      });
    });

    test('Dacia Logan KWP: 0902 answered with FF filler → null', () {
      final car = _Variant(
        logan2010.build(),
        patch: {
          '0902': [
            '49 02 01 00 00 00 FF',
            for (var n = 2; n <= 5; n++) '49 02 0$n FF FF FF FF',
          ].join('\n'),
        },
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
      });
    });

    test('Dacia Logan KWP: five-message VIN with an "O" (corrupt) → null', () {
      final car = _Variant(
        logan2010.build(),
        patch: {'0902': kLineVin('UU1LSDAAH4361234O')},
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
      });
    });

    test('BMW X5 5UX VIN with a wrong NA check digit → null', () {
      const bad = '5UXZV8C57DL123457';
      expect(_checkDigit(bad), isNot(bad[8]));
      final car = _Variant(x52013.build(), patch: {'0902': canVin(bad)});
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
      });
    });

    test('ECE VINs keep their filler check digit (VW "Z", Mercedes "1")', () {
      for (final v in [golf2018, a62012, c2002015, sprinter2014]) {
        sim(v.build(), (rig) {
          expect(rig.drive(rig.adapter.getVin()), v.vin, reason: v.name);
        });
      }
    });

    // ── #6–8 VinDecoder ──────────────────────────────────────────────────────

    for (final (vin, mfr, country, year) in [
      ('WDD2050431F123456', 'Mercedes', 'Germany', equals('Unknown')),
      ('W1K2130421A123456', 'Mercedes', 'Germany', equals('Unknown')),
      ('WDB9066331S123456', 'Mercedes', 'Germany', equals('Unknown')),
      ('WVWZZZAUZJW123456', 'Volkswagen', 'Germany', equals('2018')),
      ('WVWZZZ1JZ4W123456', 'Volkswagen', 'Germany', equals('2004')),
      ('WAUZZZ4GZCN123456', 'Audi', 'Germany', equals('2012')),
      ('SALGA2EF7GA123456', 'Land Rover', 'United Kingdom', equals('2016')),
      ('TMBJJ7NE5L0123456', 'Škoda', 'Czech Republic', equals('2020')),
      ('VSSZZZKJZLR123456', 'SEAT', 'Spain', equals('2020')),
      ('5UXZV8C57DL123456', 'BMW', 'United States', equals('2013')),
      ('5UXFE43579L123456', 'BMW', 'United States', equals('2009')),
      ('UU1LSDAAH43612345', 'Dacia', 'Romania', equals('Unknown')),
      ('VF1MA000864512345', 'Renault', 'France', equals('Unknown')),
      ('VF3LCYHZPJS123456', 'Peugeot', 'France', equals('Unknown')),
      ('ZFA31200000123456', 'Fiat', 'Italy', equals('Unknown')),
      ('WBA8E9C51GK123456', 'BMW', 'Germany', anyOf('2016', 'Unknown')),
    ]) {
      test('VinDecoder $vin → $mfr / $country', () {
        final d = VinDecoder.decode(vin, now: DateTime(2026, 11, 3));
        expect(d['manufacturer'], mfr);
        expect(d['country'], country);
        expect(d['year'], year);
      });
    }

    test('VinDecoder: Gulf-common European-brand WMIs are known', () {
      for (final (vin, mfr, country) in [
        ('4JGDA5HB7GA123456', 'Mercedes', 'United States'), // GLE, Alabama
        ('WDF44781313123456', 'Mercedes', 'Germany'), // Vito / V-Class
        ('SCA664S54GU123456', 'Rolls-Royce', 'United Kingdom'),
        ('ZAMYS57A5H1123456', 'Maserati', 'Italy'),
      ]) {
        final d = VinDecoder.decode(vin, now: DateTime(2026, 11, 3));
        expect(d['manufacturer'], mfr, reason: vin);
        expect(d['country'], country, reason: vin);
      }
    });
  });
}

String _checkDigit(String vin) {
  const t = {
    'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8, //
    'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9, 'S': 2, //
    'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9,
  };
  const w = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    final c = vin[i];
    sum += (int.tryParse(c) ?? t[c]!) * w[i];
  }
  final r = sum % 11;
  return r == 10 ? 'X' : '$r';
}
