// Compatibility matrix: Japanese vehicles (incl. Gulf / Middle-East market
// models) against [ProductionOBDAdapter] + [VinDecoder], driven by the ELM327
// simulator in test/helpers/elm327_sim.dart.
//
// Each vehicle profile models what a real ELM327 prints for that car with
// ATE0 / ATL0 / ATS0 / ATH0 (headers OFF — the app never turns them on):
//   • ELM protocol number (3 = ISO 9141-2, 4 = ISO 14230-4 KWP 5-baud init,
//     5 = ISO 14230-4 KWP fast init, 6 = ISO 15765-4 CAN 11-bit 500k);
//   • ATSP0 auto-search time (5-baud K-line init alone is ~2–3 s; BLE clones
//     walk J1850 PWM/VPW first, CAN last);
//   • PID-support bitmaps 0100 / 0120 / 0140 *computed* from the set of PIDs
//     that actually answer, so bitmap and replies can never disagree;
//   • unsupported PIDs: on CAN and ISO 9141 the ECU simply does not answer, so
//     the ELM prints NO DATA after its AT ST timeout (default 0x32 × 4 ms ≈
//     200 ms); some KWP2000 ECUs instead answer a negative response
//     "7F 01 12" (service 01, NRC 0x12 subFunctionNotSupported) quickly;
//   • a second CAN ECU (TCM, 7E9) where typical — with headers off its lines
//     are indistinguishable from the ECM's;
//   • DTC replies: CAN = count byte + 2 bytes/code (ISO-TP multi-frame beyond
//     2 codes); K-line = 3 codes per message, zero-padded, no count byte;
//   • VIN (0902): CAN = one ISO-TP message "014 / 0: / 1: / 2:"; K-line = five
//     "49 02 0N" messages, the first padded with three 00 bytes;
//   • readiness (0101) and freeze frame (02 PID 00).
//
// Latencies and search times are engineering estimates for a typical BLE
// ELM327 v1.5 clone, not measurements of a specific car — see per-car notes.
//
// Where the app misbehaves, the test asserts the CORRECT behaviour and is
// skipped with 'REGRESSION: …'. The former 'BUG: …' tests (K-line poll
// overrun, unknown WMIs, multi-ECU readiness, unchecked mode 04, unfiltered
// PIDs) now pass and always run.

// ignore_for_file: avoid_print

// fake_async ships with flutter_test (see test/helpers/elm327_sim.dart).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/vin_decoder.dart';

import '../helpers/elm327_sim.dart';

// ── Timing constants ──────────────────────────────────────────────────────────

/// ELM327 default AT ST (0x32 × 4.096 ms) — wait before printing NO DATA.
const _noDataTimeout = Duration(milliseconds: 200);

/// CAN 500k request/response incl. BLE round trip on a clone.
const _canLatency = Duration(milliseconds: 50);

/// ISO 9141-2 / ISO 14230-4 at 10.4 kbaud: P2 (25–50 ms) + ~13 bytes on the
/// wire + the ELM's wait for further responders. ~4–6 requests/s is what
/// K-line cars typically achieve over an ELM327.
const _kLineLatency = Duration(milliseconds: 180);
const _kLineNoData = Duration(milliseconds: 250);

/// The 18 PIDs [ProductionOBDAdapter] reads per live-data poll, in order.
const _pollPids = [
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

/// Extra live PIDs, sent after [_pollPids] only when a bitmap sets their
/// bit: upstream wide-band O2 (0124, else 0134 — only without a narrow-band
/// 0114), diesel / GDI fuel rail pressure, accelerator pedal D.
const _extraPids = ['0124', '0134', '0123', '0149'];

/// Every live PID whose decoded value a test can check. 0134 is left out:
/// it fills the same field as 0124, so expectations key λ by '0124' or
/// '0134' and [_lambdaWant] picks whichever the car's profile uses.
const _checkedPids = [..._pollPids, '0124', '0123', '0149'];

double? _lambdaWant(Map<String, double> live) =>
    live['0124'] ?? live['0134'];

final _fields = <String, double? Function(OBDLiveData)>{
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

final _now = DateTime(2026, 11, 3);

// ── Reply builders (exact ELM327 print formats) ───────────────────────────────

String _h(int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase();
String _pid(int p) => '01${_h(p)}';

/// "41 00 AA BB CC DD": bit 7 of A = PID base+1 … bit 0 of D = base+0x20
/// (set when any higher PID is supported).
String supportBitmap(int base, Set<int> pids) {
  final bytes = [0, 0, 0, 0];
  for (var i = 0; i < 32; i++) {
    final p = base + 1 + i;
    final on = p == base + 0x20 ? pids.any((x) => x > p) : pids.contains(p);
    if (on) bytes[i ~/ 8] |= 0x80 >> (i % 8);
  }
  return '41 ${_h(base)} ${bytes.map(_h).join(' ')}';
}

/// VIN as one CAN ISO-TP message: 0x014 bytes = 49 02 01 + 17 chars.
String canVinReply(String vin) {
  final b = ['49', '02', '01', ...vin.codeUnits.map(_h)];
  return '014\n'
      '0: ${b.sublist(0, 6).join(' ')}\n'
      '1: ${b.sublist(6, 13).join(' ')}\n'
      '2: ${b.sublist(13, 20).join(' ')}';
}

/// VIN as five ISO 9141-2 / ISO 14230-4 messages "49 02 0N + 4 bytes"
/// (SAE J1979 non-CAN: first message = 00 00 00 + char 1).
String kLineVinReply(String vin) {
  final c = [0, 0, 0, ...vin.codeUnits];
  return [
    for (var n = 0; n < 5; n++)
      '49 02 0${n + 1} ${c.sublist(n * 4, n * 4 + 4).map(_h).join(' ')}',
  ].join('\n');
}

/// ISO 3779 / 49 CFR 565 check digit (position 9).
bool vinCheckDigitValid(String vin) {
  const values = {
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
  const weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    final ch = vin[i];
    sum += (int.tryParse(ch) ?? values[ch]!) * weights[i];
  }
  final r = sum % 11;
  return vin[8] == (r == 10 ? 'X' : '$r');
}

/// Plausible replies for supported PIDs the app never polls, so every bit in
/// a support bitmap is backed by an answering PID.
const _filler = {
  0x03: '41 03 02 00', // fuel system 1 closed loop
  0x10: '41 10 01 F4', // MAF 5.00 g/s
  0x13: '41 13 33', // O2 sensors present: B1S1, B1S2, B2S1, B2S2
  0x19: '41 19 A0 FF', // B2S2 0.80 V
  0x1C: '41 1C 01', // OBD-II as defined by CARB
  0x1F: '41 1F 01 2C', // 300 s since start
  0x21: '41 21 00 00', // 0 km with MIL on
  0x23: '41 23 0F A0', // fuel rail pressure (diesel)
  0x24: '41 24 80 00 66 66', // wide-range A/F B1S1 λ≈1.0
  0x28: '41 28 80 00 66 66', // wide-range A/F B2S1 λ≈1.0
  0x2C: '41 2C 33', // commanded EGR 20 %
  0x2E: '41 2E 00', // commanded evap purge 0 %
  0x2F: '41 2F 80', // fuel level 50.2 %
  0x30: '41 30 FF', // warm-ups since clear
  0x31: '41 31 13 88', // 5000 km since clear
  0x33: '41 33 64', // baro 100 kPa
  0x3C: '41 3C 13 88', // cat temp B1S1 460 °C
  0x41: '41 41 00 07 E5 00', // monitors this drive cycle
  0x43: '41 43 00 30', // absolute load 18.8 %
  0x44: '41 44 80 00', // commanded λ 1.0
  0x45: '41 45 0A', // relative throttle 3.9 %
  0x46: '41 46 46', // ambient 30 °C
  0x47: '41 47 30', // abs throttle B 18.8 %
  0x49: '41 49 26', // accelerator pedal D 14.9 %
  0x4A: '41 4A 13', // accelerator pedal E 7.5 %
  0x4C: '41 4C 1A', // commanded throttle actuator 10.2 %
};

// ── ECU model with state (mode 04) and NO DATA latency ────────────────────────

class JapaneseCar extends SimCar {
  JapaneseCar({
    required super.protocol,
    required super.responses,
    required super.ecuLatency,
    required this.noDataLatency,
    required super.autoSearchTime,
    required super.wrongProtocolReply,
    required this.afterClear,
    this.clearReply = '44',
    super.latencyOverrides,
    super.silent,
    super.hangsOnce,
  });

  final Duration noDataLatency;

  /// Replies that replace [responses] once mode 04 has been accepted.
  final Map<String, String> afterClear;

  /// "44" = accepted; "7F 04 22" = conditionsNotCorrect (e.g. engine running);
  /// "7F 04 78\n44" = responsePending, then accepted. With several ECUs each
  /// prints its own line; the codes count as cleared once any ECU said 44.
  final String clearReply;

  bool cleared = false;

  @override
  String answer(String cmd) {
    if (cmd == '04') {
      if (clearReply.split('\n').any((l) => l.startsWith('44'))) {
        cleared = true;
      }
      return clearReply;
    }
    if (cleared && afterClear.containsKey(cmd)) return afterClear[cmd]!;
    return super.answer(cmd);
  }

  @override
  Duration latency(String cmd) =>
      latencyOverrides[cmd] ??
      (responses.containsKey(cmd) || cmd == '04' ? ecuLatency : noDataLatency);
}

// ── Vehicle profile + expectations ────────────────────────────────────────────

const _r = MonitorStatus.ready;
const _nr = MonitorStatus.notReady;
const _na = MonitorStatus.notApplicable;

class Vehicle {
  const Vehicle({
    required this.name,
    required this.protocol,
    required this.protocolName,
    required this.pids,
    required this.replies,
    required this.notes,
    this.tcmPids,
    this.tcmReplies = const {},
    this.unsupportedReply = 'NO DATA',
    this.busInit,
    required this.latency,
    required this.noData,
    this.autoSearch = const Duration(seconds: 7),
    required this.live,
    required this.dtcs,
    required this.vin,
    required this.decoded,
    required this.milOn,
    required this.dtcCount,
    required this.diesel,
    required this.monitors,
    required this.freeze,
    this.skip = const {},
  });

  final String name;
  final String protocol;
  final String protocolName;
  final String notes;

  /// Mode 01 PIDs the ECM answers (bitmap PIDs 00/20/40 are derived).
  final Set<int> pids;

  /// ECM replies (mode 01 polled PIDs, 0101, 03, 07, 02xx00, 0902 …).
  final Map<String, String> replies;

  /// Second CAN ECU (TCM 7E9): supported PIDs and replies, printed after
  /// the ECM's line(s).
  final Set<int>? tcmPids;
  final Map<String, String> tcmReplies;

  final String unsupportedReply;
  final String? busInit;
  final Duration latency;
  final Duration noData;
  final Duration autoSearch;

  // Expectations.
  final Map<String, double> live; // polled PID → decoded value; absent = null
  final List<String> dtcs;
  final String? vin;
  final Map<String, String>? decoded; // manufacturer / country / year
  final bool milOn;
  final int dtcCount;
  final bool diesel;
  final Map<String, MonitorStatus> monitors;
  final Map<String, String> freeze;

  /// Test key → skip reason ('REGRESSION: …').
  final Map<String, String> skip;

  bool get isCan => protocol == '6';

  Map<String, String> _bitmaps(Set<int> p) => {
    '0100': supportBitmap(0x00, p),
    if (p.any((x) => x > 0x20)) '0120': supportBitmap(0x20, p),
    if (p.any((x) => x > 0x40)) '0140': supportBitmap(0x40, p),
  };

  JapaneseCar build({
    Map<String, String> override = const {},
    bool tcmFirst = false,
    String clearReply = '44',
    Map<String, Duration> latencyOverrides = const {},
    Set<String> silent = const {},
    Set<String> hangsOnce = const {},
  }) {
    final ecm = <String, String>{
      ..._bitmaps(pids),
      for (final p in pids)
        if (_filler.containsKey(p)) _pid(p): _filler[p]!,
      ...replies,
    };
    // KWP ECUs that answer a negative response for unsupported PIDs.
    if (unsupportedReply != 'NO DATA') {
      for (var p = 0x01; p <= 0x60; p++) {
        if (!pids.contains(p) && p % 0x20 != 0) {
          ecm.putIfAbsent(_pid(p), () => unsupportedReply);
        }
      }
      for (final b in ['0120', '0140']) {
        ecm.putIfAbsent(b, () => unsupportedReply);
      }
    }

    final merged = <String, String>{...ecm};
    if (tcmPids != null) {
      final tcm = {..._bitmaps(tcmPids!), ...tcmReplies};
      for (final e in tcm.entries) {
        final mine = ecm[e.key];
        merged[e.key] = mine == null
            ? e.value
            : tcmFirst
            ? '${e.value}\n$mine'
            : '$mine\n${e.value}';
      }
    }
    if (busInit != null) merged['0100'] = '$busInit\n${merged['0100']}';
    merged.addAll(override);

    // After an accepted mode 04: no codes, MIL off, non-continuous monitors
    // all incomplete again (J1979).
    final noCodes = isCan
        ? ['43 00', '47 00']
        : ['43 00 00 00 00 00 00', '47 00 00 00 00 00 00'];
    final rb = replies['0101']!.split(' ').skip(2).toList();
    final ecmCleared = '41 01 00 ${rb[1]} ${rb[2]} ${rb[2]}';
    String withTcm(String ecmLine, String? tcmLine) =>
        tcmLine == null ? ecmLine : '$ecmLine\n$tcmLine';
    final afterClear = {
      '03': withTcm(noCodes[0], tcmPids == null ? null : noCodes[0]),
      '07': withTcm(noCodes[1], tcmPids == null ? null : noCodes[1]),
      '0101': withTcm(ecmCleared, tcmReplies['0101']),
    };

    return JapaneseCar(
      protocol: protocol,
      responses: merged,
      ecuLatency: latency,
      noDataLatency: noData,
      autoSearchTime: autoSearch,
      wrongProtocolReply: isCan ? 'NO DATA' : 'CAN ERROR',
      afterClear: afterClear,
      clearReply: clearReply,
      latencyOverrides: latencyOverrides,
      silent: silent,
      hangsOnce: hangsOnce,
    );
  }

  /// Every PID any ECU advertises (ECM ∪ TCM).
  Set<int> get allPids => {...pids, ...?tcmPids};

  /// Bitmap requests the first poll must make: 0120 when the 0100 reply's
  /// last bit (PID 0x20) is set, 0140 when 0120's last bit (0x40) is set —
  /// [supportBitmap] sets those bits exactly when a higher PID exists.
  List<String> get bitmapRequests => [
    if (allPids.any((x) => x > 0x20)) '0120',
    if (allPids.any((x) => x > 0x40)) '0140',
  ];

  /// The [_extraPids] the app asks for (see [_extraPids]).
  List<String> get polledExtras => [
    if (!allPids.contains(0x14) && allPids.contains(0x24)) '0124',
    if (!allPids.contains(0x14) &&
        !allPids.contains(0x24) &&
        allPids.contains(0x34))
      '0134',
    if (allPids.contains(0x23)) '0123',
    if (allPids.contains(0x49)) '0149',
  ];

  /// The live-data requests of poll [poll] (after any bitmap requests):
  /// the advertised PIDs in poll order, ATRV in the 0142 slot when 0142
  /// isn't advertised (the sim answers '?', so only on the first two polls
  /// of a connection), then [polledExtras].
  List<String> pollRequests({int poll = 1}) => [
    for (final c in _pollPids)
      if (c == '0142' && !allPids.contains(0x42)) ...[
        if (poll <= 2) 'ATRV',
      ] else if (allPids.contains(int.parse(c.substring(2), radix: 16)))
        c,
    ...polledExtras,
  ];

  /// [pollRequests] of the first poll of a connection.
  List<String> get supportedPollPids => pollRequests();
}

// ── Vehicle profiles ──────────────────────────────────────────────────────────

/// Toyota Camry 2004 (XV30 ACV30, 2AZ-FE 2.4 I4), Japan-built export car.
const camry2004 = Vehicle(
  name: 'Toyota Camry 2004',
  protocol: '3',
  protocolName: 'ISO 9141-2',
  notes:
      'Toyota used ISO 9141-2 on most 1996–2004 models and moved to ISO '
      '14230-4 KWP and then CAN between ~2004 and 2008; which one a given '
      '2004 Camry uses depends on market/build date (UNSURE: modelled as '
      '9141-2). 2AZ-FE is a MAF engine (no 010B), upstream sensor is a '
      'wide-band A/F sensor reported as 0124, not 0114. No 0140 range on a '
      '2004 ECU, so no 0142 voltage.',
  busInit: 'BUS INIT: ...OK',
  latency: _kLineLatency,
  noData: _kLineNoData,
  autoSearch: Duration(seconds: 6),
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x13,
    0x15,
    0x1C,
    0x21,
    0x24,
  },
  replies: {
    '0124': '41 24 80 29 66 66', // A/F sensor λ 1.00125
    '010C': '41 0C 0A F0',
    '010D': '41 0D 00',
    '0105': '41 05 80',
    '0111': '41 11 26',
    '0104': '41 04 4D',
    '0106': '41 06 82',
    '0107': '41 07 7B',
    '0115': '41 15 9A FF',
    '010F': '41 0F 46',
    '010E': '41 0E 8E',
    '0101': '41 01 82 07 65 04',
    '03': '43 01 71 04 20 00 00', // P0171, P0420
    '07': '47 03 00 00 00 00 00', // pending P0300
    '020C00': '42 0C 00 1C 20',
    '020D00': '42 0D 00 3C',
    '020500': '42 05 00 7E',
    '020400': '42 04 00 33',
    '020F00': '42 0F 00 41',
    '021100': '42 11 00 2E',
    '020600': '42 06 00 9A',
  },
  live: {
    '0124': 1.00125,
    '010C': 700,
    '010D': 0,
    '0105': 88,
    '0111': 14.902,
    '0104': 30.196,
    '0106': 1.5625,
    '0107': -3.90625,
    '0115': 0.77,
    '010F': 30,
    '010E': 7,
  },
  dtcs: ['P0171', 'P0420', '~P0300'],
  vin: 'JTDBE32K940123456',
  decoded: {'manufacturer': 'Toyota', 'country': 'Japan', 'year': '2004'},
  milOn: true,
  dtcCount: 2,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _r,
    'Heated Catalyst': _na,
    'Evap System': _nr,
    'Secondary Air': _na,
    'A/C System': _na,
    'O2 Sensor': _r,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _na,
  },
  freeze: {
    'RPM': '1800 rpm',
    'Speed': '60 km/h',
    'Coolant': '86°C',
    'Engine Load': '20.0%',
    'Air Temp': '25°C',
    'Throttle': '18.0%',
    'Fuel Trim': '20.3%',
  },
);

/// Honda Accord 2003 (CM5, K24A 2.4 I4).
const accord2003 = Vehicle(
  name: 'Honda Accord 2003',
  protocol: '3',
  protocolName: 'ISO 9141-2',
  notes:
      'Honda used ISO 9141-2 through ~2005 before CAN. Mode 09 was optional '
      'before MY2005 and many pre-2005 Honda ECUs answer 0902 with NO DATA '
      '— modelled that way. K24 is speed-density (MAP 010B supported). '
      'Upstream sensor is Honda\'s wide-band LAF, so 0114 is not reported '
      '(UNSURE whether some trims expose it).',
  busInit: 'BUS INIT: ...OK',
  latency: _kLineLatency,
  noData: _kLineNoData,
  autoSearch: Duration(seconds: 6),
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x11,
    0x13,
    0x15,
    0x1C,
  },
  replies: {
    '010C': '41 0C 0C E4',
    '010D': '41 0D 00',
    '0105': '41 05 82',
    '0111': '41 11 1F',
    '0104': '41 04 40',
    '0106': '41 06 80',
    '0107': '41 07 7D',
    '0115': '41 15 A0 FF',
    '010F': '41 0F 44',
    '010B': '41 0B 1F',
    '010E': '41 0E 8A',
    '0101': '41 01 81 07 E5 04',
    '03': '43 14 57 00 00 00 00', // P1457 (Honda EVAP canister, P1xxx)
    '07': '47 00 00 00 00 00 00',
    '020C00': '42 0C 00 0A A0',
    '020D00': '42 0D 00 00',
    '020500': '42 05 00 85',
    '020400': '42 04 00 4D',
    '020F00': '42 0F 00 3C',
    '021100': '42 11 00 1F',
    '020600': '42 06 00 7D',
    '020B00': '42 0B 00 22',
    // 0902 absent → NO DATA (mode 09 unsupported).
  },
  live: {
    '010C': 825,
    '010D': 0,
    '0105': 90,
    '0111': 12.157,
    '0104': 25.098,
    '0106': 0,
    '0107': -2.34375,
    '0115': 0.8,
    '010F': 28,
    '010B': 31,
    '010E': 5,
  },
  dtcs: ['P1457'],
  vin: null, // ECU doesn't report it; label VIN would be JHMCM56373C123456
  decoded: null,
  milOn: true,
  dtcCount: 1,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _r,
    'Heated Catalyst': _na,
    'Evap System': _nr,
    'Secondary Air': _na,
    'A/C System': _na,
    'O2 Sensor': _r,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _r,
  },
  freeze: {
    'RPM': '680 rpm',
    'Speed': '0 km/h',
    'Coolant': '93°C',
    'Engine Load': '30.2%',
    'Air Temp': '20°C',
    'Throttle': '12.2%',
    'Fuel Trim': '-2.3%',
    'MAP': '34 kPa',
  },
);

/// Mitsubishi Pajero 2006 (Gen 3 V75/V77, 6G75 3.8 V6), Gulf market.
const pajero2006 = Vehicle(
  name: 'Mitsubishi Pajero 2006',
  protocol: '5',
  protocolName: 'ISO 14230-4 KWP fast',
  notes:
      'Mitsubishi used ISO 14230-4 KWP (fast init) on mid-2000s ECUs. Gulf '
      'states had no OBD-II/EOBD mandate then, so a GCC-spec car may not '
      'be fully J1979-compliant (UNSURE). Unsupported PIDs are answered '
      'with the KWP negative response 7F 01 12, documented for many '
      'KWP2000 ECUs. MAF engine (no 010B). VIN uses the non-US WMI JMY '
      '(US Montero would be JA4); 0902 support on this ECU is UNSURE.',
  busInit: 'BUS INIT: OK', // fast init: no 5-baud dots (UNSURE of exact text)
  unsupportedReply: '7F 01 12',
  latency: _kLineLatency,
  noData: _kLineNoData,
  // 5-baud init (~3 s) must fail before the ELM tries fast init.
  autoSearch: Duration(seconds: 8),
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x13,
    0x14,
    0x15,
    0x18,
    0x19,
    0x1C,
  },
  replies: {
    '010C': '41 0C 0C 80',
    '010D': '41 0D 00',
    '0105': '41 05 7D',
    '0111': '41 11 21',
    '0104': '41 04 3A',
    '0106': '41 06 7E',
    '0107': '41 07 83',
    '0108': '41 08 80',
    '0109': '41 09 7C',
    '0114': '41 14 32 FF',
    '0115': '41 15 96 FF',
    '0118': '41 18 B4 FF',
    '010F': '41 0F 4B',
    '010E': '41 0E 90',
    '0101': '41 01 81 07 65 00',
    '03': '43 03 04 00 00 00 00', // P0304
    '07': '47 00 00 00 00 00 00',
    '020C00': '42 0C 00 0C 80',
    '020D00': '42 0D 00 00',
    '020500': '42 05 00 87',
    '020400': '42 04 00 40',
    '020F00': '42 0F 00 50',
    '021100': '42 11 00 20',
    '020600': '42 06 00 80',
    '020B00': '7F 02 12',
  },
  live: {
    '010C': 800,
    '010D': 0,
    '0105': 85,
    '0111': 12.941,
    '0104': 22.745,
    '0106': -1.5625,
    '0107': 2.34375,
    '0108': 0,
    '0109': -3.125,
    '0114': 0.25,
    '0115': 0.75,
    '0118': 0.9,
    '010F': 35,
    '010E': 8,
  },
  dtcs: ['P0304'],
  vin: 'JMYLYV7586J123456',
  decoded: {'manufacturer': 'Mitsubishi', 'country': 'Japan', 'year': '2006'},
  milOn: true,
  dtcCount: 1,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _r,
    'Heated Catalyst': _na,
    'Evap System': _r,
    'Secondary Air': _na,
    'A/C System': _na,
    'O2 Sensor': _r,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _na,
  },
  freeze: {
    'RPM': '800 rpm',
    'Speed': '0 km/h',
    'Coolant': '95°C',
    'Engine Load': '25.1%',
    'Air Temp': '40°C',
    'Throttle': '12.5%',
    'Fuel Trim': '0.0%',
  },
);

/// Nissan Sunny 2010 (Gulf market, 1.5 I4).
const sunny2010 = Vehicle(
  name: 'Nissan Sunny 2010',
  protocol: '4',
  protocolName: 'ISO 14230-4 KWP 5-baud',
  notes:
      'Pre-CAN Nissan ECUs used ISO 14230-4 KWP; whether the 2010 Gulf '
      'Sunny ECU uses 5-baud (protocol 4) or fast init (5) is UNSURE — '
      'modelled as 5-baud. Only a pending P0133, so no freeze frame is '
      'stored (all 02xx00 → NO DATA). Japan-built JN1 VIN assumed (UNSURE: '
      'later Gulf Sunnys are built outside Japan).',
  busInit: 'BUS INIT: ...OK',
  latency: _kLineLatency,
  noData: _kLineNoData,
  autoSearch: Duration(seconds: 6),
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x13,
    0x14,
    0x15,
    0x1C,
    0x21,
  },
  replies: {
    '010C': '41 0C 0A 28',
    '010D': '41 0D 00',
    '0105': '41 05 7A',
    '0111': '41 11 0D',
    '0104': '41 04 47',
    '0106': '41 06 84',
    '0107': '41 07 80',
    '0114': '41 14 46 FF',
    '0115': '41 15 8C FF',
    '010F': '41 0F 50',
    '010E': '41 0E 94',
    '0101': '41 01 00 07 65 21',
    '03': '43 00 00 00 00 00 00',
    '07': '47 01 33 00 00 00 00', // pending P0133
  },
  live: {
    '010C': 650,
    '010D': 0,
    '0105': 82,
    '0111': 5.098,
    '0104': 27.843,
    '0106': 3.125,
    '0107': 0,
    '0114': 0.35,
    '0115': 0.7,
    '010F': 40,
    '010E': 10,
  },
  dtcs: ['~P0133'],
  vin: 'JN1FB10AXA0123456',
  decoded: {'manufacturer': 'Nissan', 'country': 'Japan', 'year': '2010'},
  milOn: false,
  dtcCount: 0,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _nr,
    'Heated Catalyst': _na,
    'Evap System': _r,
    'Secondary Air': _na,
    'A/C System': _na,
    'O2 Sensor': _nr,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _na,
  },
  freeze: {},
);

/// Toyota Land Cruiser 2021 (LC200, 1UR-FE 4.6 V8), GCC spec.
const landCruiser2021 = Vehicle(
  name: 'Toyota Land Cruiser 2021',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  notes:
      'Toyota CAN, 11-bit, ECM 7E8. A/F sensors upstream (0124/0128) so '
      '0114/0118 are unsupported; 012F fuel level and 015C oil temp are '
      'widely reported as unsupported on Toyota generic OBD (UNSURE for '
      'this exact ECU). LC200 VINs use WMI JTM (Toyota SUV, Japan).',
  latency: _canLatency,
  noData: _noDataTimeout,
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x13,
    0x15,
    0x19,
    0x1C,
    0x1F,
    0x21,
    0x24,
    0x28,
    0x2E,
    0x30,
    0x31,
    0x33,
    0x3C,
    0x41,
    0x42,
    0x43,
    0x44,
    0x45,
    0x46,
    0x47,
    0x49,
    0x4A,
    0x4C,
  },
  replies: {
    '0124': '41 24 7F AE 66 66', // A/F sensor λ 0.9975
    '010C': '41 0C 0A 6C',
    '010D': '41 0D 00',
    '0105': '41 05 7D',
    '0111': '41 11 1A',
    '0104': '41 04 2D',
    '0142': '41 42 37 E6',
    '0106': '41 06 81',
    '0107': '41 07 7E',
    '0108': '41 08 7F',
    '0109': '41 09 84',
    '0115': '41 15 B4 FF',
    '010F': '41 0F 48',
    '010E': '41 0E 8C',
    '0101': '41 01 81 07 E5 04',
    '03': '43 01 04 55', // P0455
    '07': '47 01 04 41', // pending P0441
    '020C00': '42 0C 00 0A 6C',
    '020D00': '42 0D 00 00',
    '020500': '42 05 00 7D',
    '020400': '42 04 00 2D',
    '020F00': '42 0F 00 48',
    '021100': '42 11 00 1A',
    '020600': '42 06 00 81',
  },
  live: {
    '0124': 0.9975,
    '0149': 14.90,
    '010C': 667,
    '010D': 0,
    '0105': 85,
    '0111': 10.196,
    '0104': 17.647,
    '0142': 14.31,
    '0106': 0.78125,
    '0107': -1.5625,
    '0108': -0.78125,
    '0109': 3.125,
    '0115': 0.9,
    '010F': 32,
    '010E': 6,
  },
  dtcs: ['P0455', '~P0441'],
  vin: 'JTMHY7AJ6M4123456',
  decoded: {'manufacturer': 'Toyota', 'country': 'Japan', 'year': '2021'},
  milOn: true,
  dtcCount: 1,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _r,
    'Heated Catalyst': _na,
    'Evap System': _nr,
    'Secondary Air': _na,
    'A/C System': _na,
    'O2 Sensor': _r,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _r,
  },
  freeze: {
    'RPM': '667 rpm',
    'Speed': '0 km/h',
    'Coolant': '85°C',
    'Engine Load': '17.6%',
    'Air Temp': '32°C',
    'Throttle': '10.2%',
    'Fuel Trim': '0.8%',
  },
);

/// Lexus LX 570 2020 (URJ201, 3UR-FE 5.7 V8, 8-speed AT).
const lexusLx2020 = Vehicle(
  name: 'Lexus LX 570 2020',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  notes:
      'Same platform as LC200. 3UR-FE has secondary-air injection (C bit 3). '
      'A transmission ECU answering on 7E9 is modelled (UNSURE whether the '
      'AB80 8AT has a separate OBD-addressable TCM on this model).',
  latency: _canLatency,
  noData: _noDataTimeout,
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x13,
    0x15,
    0x19,
    0x1C,
    0x1F,
    0x21,
    0x24,
    0x28,
    0x2E,
    0x30,
    0x31,
    0x33,
    0x3C,
    0x41,
    0x42,
    0x43,
    0x44,
    0x45,
    0x46,
    0x47,
    0x49,
    0x4A,
    0x4C,
  },
  replies: {
    '010C': '41 0C 0A 50',
    '010D': '41 0D 00',
    '0105': '41 05 7F',
    '0111': '41 11 1C',
    '0104': '41 04 30',
    '0142': '41 42 38 0C',
    '0106': '41 06 80',
    '0107': '41 07 82',
    '0108': '41 08 7E',
    '0109': '41 09 80',
    '0115': '41 15 AA FF',
    '010F': '41 0F 4A',
    '010E': '41 0E 8A',
    '0101': '41 01 81 07 ED 00',
    '03': '43 01 01 71', // P0171
    '07': '47 00',
    '020C00': '42 0C 00 1F 40',
    '020D00': '42 0D 00 64',
    '020500': '42 05 00 7F',
    '020400': '42 04 00 59',
    '020F00': '42 0F 00 50',
    '021100': '42 11 00 33',
    '020600': '42 06 00 A0',
  },
  tcmPids: {0x01, 0x0D, 0x1C},
  tcmReplies: {
    '010D': '41 0D 00',
    '011C': '41 1C 01',
    '0101': '41 01 00 04 00 00',
    '03': '43 00',
    '07': '47 01 07 41', // pending P0741 (torque converter clutch)
  },
  live: {
    '0124': 1.0,
    '0149': 14.90,
    '010C': 660,
    '010D': 0,
    '0105': 87,
    '0111': 10.980,
    '0104': 18.824,
    '0142': 14.348,
    '0106': 0,
    '0107': 1.5625,
    '0108': -1.5625,
    '0109': 0,
    '0115': 0.85,
    '010F': 34,
    '010E': 5,
  },
  dtcs: ['P0171', '~P0741'],
  vin: 'JTJHY7AX6L4123456',
  decoded: {'manufacturer': 'Lexus', 'country': 'Japan', 'year': '2020'},
  milOn: true,
  dtcCount: 1,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _r,
    'Heated Catalyst': _na,
    'Evap System': _r,
    'Secondary Air': _r,
    'A/C System': _na,
    'O2 Sensor': _r,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _r,
  },
  freeze: {
    'RPM': '2000 rpm',
    'Speed': '100 km/h',
    'Coolant': '87°C',
    'Engine Load': '34.9%',
    'Air Temp': '40°C',
    'Throttle': '20.0%',
    'Fuel Trim': '25.0%',
  },
);

/// Toyota Hilux 2019 diesel (AN120/GUN, 2.8 1GD-FTV / 2.4 2GD-FTV),
/// Thailand-built for the GCC.
const hilux2019 = Vehicle(
  name: 'Toyota Hilux 2019 diesel',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  notes:
      'Compression ignition: 0101 byte B bit 3 set; no spark timing, '
      'O2 or fuel-trim PIDs; 0111 replaced by accelerator pedal 0149/014A '
      '(UNSURE: some diesels report 0111 for the intake throttle). DPF '
      '(PM filter) monitor modelled as fitted — GCC-spec Hilux diesels are '
      'sold with and without DPF (UNSURE). VIN WMI MR0 = Toyota Motor '
      'Thailand (ISO 3780: ML–MR Thailand).',
  latency: _canLatency,
  noData: _noDataTimeout,
  pids: {
    0x01,
    0x04,
    0x05,
    0x0B,
    0x0C,
    0x0D,
    0x0F,
    0x10,
    0x1C,
    0x1F,
    0x21,
    0x23,
    0x2C,
    0x30,
    0x31,
    0x33,
    0x41,
    0x42,
    0x46,
    0x49,
    0x4A,
  },
  replies: {
    '0123': '41 23 0C 1C', // common rail 31 MPa at idle
    '010C': '41 0C 0C 80',
    '010D': '41 0D 00',
    '0105': '41 05 82',
    '0104': '41 04 26',
    '0142': '41 42 36 B0',
    '010F': '41 0F 41',
    '010B': '41 0B 65',
    '0101': '41 01 81 0F E9 40',
    '03': '43 01 20 02', // P2002 DPF efficiency below threshold
    '07': '47 01 04 01', // pending P0401 EGR flow insufficient
    '020C00': '42 0C 00 17 70',
    '020D00': '42 0D 00 50',
    '020500': '42 05 00 84',
    '020400': '42 04 00 66',
    '020F00': '42 0F 00 46',
    '020B00': '42 0B 00 A0',
  },
  live: {
    '0123': 31000,
    '0149': 14.90,
    '010C': 800,
    '010D': 0,
    '0105': 90,
    '0104': 14.902,
    '0142': 14.0,
    '010F': 25,
    '010B': 101,
  },
  dtcs: ['P2002', '~P0401'],
  vin: 'MR0HA3CD3K0123456',
  decoded: {'manufacturer': 'Toyota', 'country': 'Thailand', 'year': '2019'},
  milOn: true,
  dtcCount: 1,
  diesel: true,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'NMHC Catalyst': _r,
    'NOx / SCR': _na,
    'Boost Pressure': _r,
    'Exhaust Gas Sensor': _r,
    'PM Filter': _nr,
    'EGR / VVT': _r,
  },
  freeze: {
    'RPM': '1500 rpm',
    'Speed': '80 km/h',
    'Coolant': '92°C',
    'Engine Load': '40.0%',
    'Air Temp': '30°C',
    'MAP': '160 kPa',
  },
);

/// Nissan Patrol 2015 (Y62, VK56VD 5.6 V8, 7AT), GCC spec.
const patrol2015 = Vehicle(
  name: 'Nissan Patrol 2015',
  protocol: '6',
  protocolName: 'ISO 15765-4 CAN 11/500',
  notes:
      'Nissan CAN: ECM 7E8 + TCM 7E9 both answer functional requests. '
      'VK56VD uses A/F sensors upstream (0114/0118 unsupported) and a MAF '
      '(no 010B). Three confirmed codes → multi-frame ISO-TP mode 03 reply. '
      'VIN with WMI JN8 (Nissan SUV, Japan); GCC Y62 VINs may not encode '
      'model year in position 10 (UNSURE) — modelled NA-style.',
  latency: _canLatency,
  noData: _noDataTimeout,
  pids: {
    0x01,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x10,
    0x11,
    0x13,
    0x15,
    0x19,
    0x1C,
    0x1F,
    0x21,
    0x24,
    0x28,
    0x2E,
    0x2F,
    0x30,
    0x31,
    0x33,
    0x3C,
    0x41,
    0x42,
    0x43,
    0x44,
    0x45,
    0x46,
    0x47,
    0x49,
    0x4A,
    0x4C,
  },
  replies: {
    '010C': '41 0C 0A 8C',
    '010D': '41 0D 00',
    '0105': '41 05 7C',
    '0111': '41 11 18',
    '012F': '41 2F 9E',
    '0104': '41 04 33',
    '0142': '41 42 37 96',
    '0106': '41 06 7F',
    '0107': '41 07 88',
    '0108': '41 08 80',
    '0109': '41 09 8A',
    '0115': '41 15 A5 FF',
    '010F': '41 0F 4D',
    '010E': '41 0E 92',
    '0101': '41 01 83 07 E5 00',
    // P0171, P0174, P0300 — 8 bytes → ISO-TP first + consecutive frame.
    '03': '008\n0: 43 03 01 71 01 74\n1: 03 00 00 00 00 00 00',
    '07': '47 00',
    '020C00': '42 0C 00 0A 8C',
    '020D00': '42 0D 00 00',
    '020500': '42 05 00 7C',
    '020400': '42 04 00 33',
    '020F00': '42 0F 00 4D',
    '021100': '42 11 00 18',
    '020600': '42 06 00 8A',
  },
  tcmPids: {0x01, 0x0D, 0x1C},
  tcmReplies: {
    '010D': '41 0D 00',
    '011C': '41 1C 01',
    '0101': '41 01 00 04 00 00',
    '03': '43 00',
    '07': '47 00',
  },
  live: {
    '0124': 1.0,
    '0149': 14.90,
    '010C': 675,
    '010D': 0,
    '0105': 84,
    '0111': 9.412,
    '012F': 61.961,
    '0104': 20.0,
    '0142': 14.23,
    '0106': -0.78125,
    '0107': 6.25,
    '0108': 0,
    '0109': 7.8125,
    '0115': 0.825,
    '010F': 37,
    '010E': 9,
  },
  dtcs: ['P0171', 'P0174', 'P0300'],
  vin: 'JN8AY2NY9F9123456',
  decoded: {'manufacturer': 'Nissan', 'country': 'Japan', 'year': '2015'},
  milOn: true,
  dtcCount: 3,
  diesel: false,
  monitors: {
    'Misfire': _r,
    'Fuel System': _r,
    'Components': _r,
    'Catalyst': _r,
    'Heated Catalyst': _na,
    'Evap System': _r,
    'Secondary Air': _na,
    'A/C System': _na,
    'O2 Sensor': _r,
    'O2 Sensor Heater': _r,
    'EGR / VVT': _r,
  },
  freeze: {
    'RPM': '675 rpm',
    'Speed': '0 km/h',
    'Coolant': '84°C',
    'Engine Load': '20.0%',
    'Air Temp': '37°C',
    'Throttle': '9.4%',
    'Fuel Trim': '7.8%',
  },
);

/// VIN replies are generated from the VIN (see [carFor]) so the hex can't
/// drift from the expected value.
const vehicles = <Vehicle>[
  camry2004,
  accord2003,
  pajero2006,
  sunny2010,
  landCruiser2021,
  lexusLx2020,
  hilux2019,
  patrol2015,
];

/// Final responses for [v] incl. the VIN in the protocol's format.
JapaneseCar carFor(
  Vehicle v, {
  Map<String, String> override = const {},
  bool tcmFirst = false,
  String clearReply = '44',
  Map<String, Duration> latencyOverrides = const {},
  Set<String> silent = const {},
  Set<String> hangsOnce = const {},
}) {
  final vinReply = v.vin == null
      ? <String, String>{}
      : {'0902': v.isCan ? canVinReply(v.vin!) : kLineVinReply(v.vin!)};
  return v.build(
    override: {...vinReply, ...override},
    tcmFirst: tcmFirst,
    clearReply: clearReply,
    latencyOverrides: latencyOverrides,
    silent: silent,
    hangsOnce: hangsOnce,
  );
}

// ── Measurements collected for the matrix printout ────────────────────────────

final _connectTime = <String, Duration>{};
final _pollTime = <String, Duration>{};
final _polled = <String, List<String>>{};

String _secs(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(2);

/// Runs one live-data poll; returns (frame, poll duration, every command the
/// ELM received during that poll — bitmap requests 0120/0140 included).
(OBDLiveData, Duration, List<String>) _pollOnce(Rig rig) =>
    _pollWith(rig.async, rig.adapter, rig.elm);

(OBDLiveData, Duration, List<String>) _pollWith(
  FakeAsync async,
  ProductionOBDAdapter adapter,
  FakeElm327 elm,
) {
  final frames = <OBDLiveData>[];
  final stamps = <Duration>[];
  var end = -1;
  final sub = adapter.liveDataStream.listen((d) {
    frames.add(d);
    stamps.add(async.elapsed);
    if (end == -1) end = elm.commands.length;
  });
  final skip = elm.commands.length;
  final t0 = async.elapsed;
  adapter.startLiveData();
  while (frames.isEmpty && async.elapsed - t0 < const Duration(seconds: 60)) {
    async.elapse(const Duration(milliseconds: 10));
  }
  adapter.stopLiveData();
  async.elapse(const Duration(seconds: 30)); // drain any in-flight poll
  sub.cancel();
  expect(frames, isNotEmpty, reason: 'no live-data frame within 60 s');
  final cmds = elm.commands.sublist(skip, end);
  // First timer tick fires 3 s after startLiveData().
  return (frames.first, stamps.first - t0 - const Duration(seconds: 3), cmds);
}

bool _isBitmapRequest(String cmd) =>
    const {'0100', '0120', '0140', '0160'}.contains(cmd);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  tearDownAll(() {
    print('\nJapanese-car matrix (simulated seconds)');
    print('Vehicle'.padRight(28) + 'connect'.padLeft(9) + 'poll'.padLeft(9));
    for (final v in vehicles) {
      final c = _connectTime[v.name];
      final p = _pollTime[v.name];
      print(
        v.name.padRight(28) +
            (c == null ? '-' : _secs(c)).padLeft(9) +
            (p == null ? '-' : _secs(p)).padLeft(9),
      );
    }
  });

  for (final v in vehicles) {
    group('${v.name} [${v.protocolName}, ELM ${v.protocol}]', () {
      test('profile sanity: bitmaps match answering PIDs, VIN valid', () {
        final car = carFor(v);
        // Every polled PID decodes iff the ECM claims it in its bitmap.
        for (final cmd in _pollPids) {
          final p = int.parse(cmd.substring(2), radix: 16);
          expect(
            v.live.containsKey(cmd),
            v.pids.contains(p),
            reason: '$cmd expectation vs support bitmap',
          );
          final reply = car.answer(cmd).replaceAll(' ', '');
          expect(
            reply.contains('41${cmd.substring(2)}'),
            v.pids.contains(p),
            reason: '$cmd reply vs support bitmap',
          );
        }
        for (final p in v.pids) {
          expect(
            car.answer(_pid(p)).replaceAll(' ', ''),
            contains('41${_h(p)}'),
            reason: 'bitmap claims PID ${_h(p)} but it does not answer',
          );
        }
        // An extra has an expectation iff the adapter will ask for it.
        for (final cmd in _extraPids) {
          expect(
            v.live.containsKey(cmd),
            v.polledExtras.contains(cmd),
            reason: '$cmd expectation vs support bitmap',
          );
        }
        if (v.vin != null) {
          expect(v.vin, hasLength(17));
          expect(v.vin, isNot(matches(RegExp('[IOQ]'))));
          expect(vinCheckDigitValid(v.vin!), isTrue, reason: 'check digit');
        }
        // Readiness byte B bit 3 must match the engine type.
        final b = int.parse(v.replies['0101']!.split(' ')[3], radix: 16);
        expect((b >> 3) & 1 == 1, v.diesel);
      });

      test('(a) connect', () {
        sim(carFor(v), (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();
          final took = rig.async.elapsed - t0;
          _connectTime[v.name] = took;

          expect(rig.adapter.isConnected, isTrue);
          expect(rig.elm.activeProtocol, v.protocol);
          const hs = ['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100'];
          if (v.isCan) {
            expect(rig.elm.commands, hs);
            expect(took, lessThan(const Duration(seconds: 2)));
          } else {
            expect(rig.elm.commands, [...hs, 'ATSP0', '0100']);
            expect(took, greaterThanOrEqualTo(v.autoSearch));
            expect(took, lessThan(v.autoSearch + const Duration(seconds: 3)));
          }
        }, connect: false);
      });

      test('(b) one live-data poll decodes supported PIDs, null otherwise', () {
        sim(carFor(v), (rig) {
          final (d, took, cmds) = _pollOnce(rig);
          _pollTime[v.name] = took;
          _polled[v.name] = cmds;
          // 0100 is reused from the handshake; 0120 / 0140 are asked once,
          // before the PIDs, only when the previous bitmap advertises them.
          // Then exactly the advertised live-data PIDs, in poll order.
          expect(cmds, [...v.bitmapRequests, ...v.supportedPollPids]);
          for (final cmd in _checkedPids) {
            final value = _fields[cmd]!(d);
            final want = cmd == '0124' ? _lambdaWant(v.live) : v.live[cmd];
            if (want == null) {
              expect(value, isNull, reason: '$cmd should be unsupported');
            } else {
              expect(value, closeTo(want, 0.01), reason: cmd);
            }
          }
        });
      });

      test('(b2) a full poll fits in the 3 s polling period', () {
        sim(carFor(v), (rig) {
          final (_, took, _) = _pollOnce(rig);
          expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
        });
      }, skip: v.skip['poll']);

      test('(c) DTCs confirmed + pending, then clear', () {
        sim(carFor(v), (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
          expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
          expect(rig.elm.commands.last, '04');
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, isFalse);
          expect(r.dtcCount, 0);
        });
      });

      test('(d1) VIN read via getVin()', () {
        sim(carFor(v), (rig) {
          expect(rig.drive(rig.adapter.getVin()), v.vin);
        });
      });

      if (v.decoded != null) {
        test(
          '(d2) VinDecoder: manufacturer, model year, country',
          () {
            final d = VinDecoder.decode(v.vin!, now: _now);
            expect(d['error'], isNull);
            expect(d['manufacturer'], v.decoded!['manufacturer']);
            expect(d['year'], v.decoded!['year']);
            expect(d['country'], v.decoded!['country']);
          },
          skip: v.skip['vin-decode'],
        );
      }

      test('(e) readiness monitors', () {
        sim(carFor(v), (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, v.milOn);
          expect(r.dtcCount, v.dtcCount);
          expect(r.compressionIgnition, v.diesel);
          expect({for (final m in r.monitors) m.name: m.status}, v.monitors);
        });
      });

      test('(f) freeze frame', () {
        sim(carFor(v), (rig) {
          expect(rig.drive(rig.adapter.getFreezeFrame()), v.freeze);
        });
      });
    });
  }

  // ── Vehicle-specific scenarios ──────────────────────────────────────────────

  group('vehicle-specific', () {
    test('Honda Accord 2003: 0902 unsupported → null, no crash, and the '
        'connection stays usable', () {
      sim(carFor(accord2003), (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
        expect(rig.drive(rig.adapter.getDtcs()), ['P1457']);
      });
    });

    test('Mitsubishi Pajero 2006: KWP negative responses (7F 01 12 / '
        '7F 02 12) are treated as unsupported, not as data', () {
      sim(carFor(pajero2006), (rig) {
        final (d, _, _) = _pollOnce(rig);
        expect(d.fuelLevelPct, isNull);
        expect(d.batteryVoltage, isNull);
        expect(d.oilTempC, isNull);
        expect(d.mapKpa, isNull);
        expect(
          rig.drive(rig.adapter.getFreezeFrame()).containsKey('MAP'),
          isFalse,
        );
      });
    });

    test(
      'Lexus LX 2020: TCM (7E9) answers 0101 before the ECM → MIL and DTC '
      'count must still reflect the ECM (J1979: OR the MIL, sum the counts)',
      () {
        sim(carFor(lexusLx2020, tcmFirst: true), (rig) {
          expect(rig.adapter.isConnected, isTrue); // 0100 still fine
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, isTrue);
          expect(r.dtcCount, 1);
          expect({
            for (final m in r.monitors) m.name: m.status,
          }, lexusLx2020.monitors);
        });
      },
    );

    test('Lexus LX 2020: TCM first for DTCs still merges both ECUs', () {
      sim(carFor(lexusLx2020, tcmFirst: true), (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), ['P0171', '~P0741']);
      });
    });

    test('Nissan Patrol 2015: TCM first in front of a multi-frame ECM '
        'mode 03 reply', () {
      sim(carFor(patrol2015, tcmFirst: true), (rig) {
        expect(rig.drive(rig.adapter.getDtcs()), ['P0171', 'P0174', 'P0300']);
      });
    });

    test('Nissan Patrol 2015: ECU refuses mode 04 (7F 04 22, conditions not '
        'correct — e.g. engine running) → clearDtcs() reports failure', () {
      sim(carFor(patrol2015, clearReply: '7F 04 22'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        expect(rig.drive(rig.adapter.getDtcs()), patrol2015.dtcs);
      });
    });

    test('Toyota Hilux 2019 diesel: readiness reports compression ignition '
        'and no spark-only monitors', () {
      sim(carFor(hilux2019), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        final names = r.monitors.map((m) => m.name).toSet();
        expect(r.compressionIgnition, isTrue);
        expect(names, isNot(contains('Catalyst')));
        expect(names, isNot(contains('Evap System')));
        expect(names, contains('PM Filter'));
      });
    });

    test('all vehicles: PIDs the ECU says it does not support (0100/0120/0140 '
        'bitmaps) are not polled', () {
      for (final v in vehicles) {
        sim(carFor(v), (rig) {
          final (_, _, cmds) = _pollOnce(rig);
          // The bitmap requests themselves are not polled PIDs (the old
          // version of this test counted 0120/0140 as such); they may only
          // be sent when the previous range's bit 0x20 / 0x40 says so.
          final bitmaps = cmds.where(_isBitmapRequest).toList();
          expect(bitmaps, v.bitmapRequests, reason: '${v.name} bitmaps');
          for (final cmd in cmds.where(
            (c) => !_isBitmapRequest(c) && !c.startsWith('AT'), // ATRV
          )) {
            final p = int.parse(cmd.substring(2), radix: 16);
            expect(v.allPids, contains(p), reason: '${v.name} polled $cmd');
          }
        });
      }
    });
  });

  // ── Regression: adversarial checks of the obd_adapter / vin_decoder fixes ──

  group('regression', () {
    /// [extras] false: the adapter never read a usable bitmap, so the
    /// extras (which need an explicit bit) were not asked for → null.
    void expectLive(
      OBDLiveData d,
      Map<String, double> want, {
      String? skip,
      bool extras = true,
    }) {
      for (final cmd in _checkedPids) {
        if (cmd == skip) continue;
        final w = !extras && _extraPids.contains(cmd)
            ? null
            : cmd == '0124' ? _lambdaWant(want) : want[cmd];
        final got = _fields[cmd]!(d);
        if (w == null) {
          expect(got, isNull, reason: '$cmd should be null');
        } else {
          expect(got, closeTo(w, 0.01), reason: cmd);
        }
      }
    }

    int pidOf(String cmd) => int.parse(cmd.substring(2), radix: 16);

    // ── #1 support bitmaps ────────────────────────────────────────────────

    for (final v in [camry2004, sunny2010]) {
      test('#1 ${v.name}: 0100 bit 0x20 set but 0120 answers NO DATA (K-line '
          'timeout) → 0x01–0x20 still filtered by 0100, values right, '
          'poll ≤ 3 s', () {
        sim(carFor(v, override: {'0120': 'NO DATA'}), (rig) {
          final (d, took, cmds) = _pollOnce(rig);
          expect(cmds.first, '0120');
          for (final c in cmds.skip(1).where((c) => !c.startsWith('AT'))) {
            if (pidOf(c) <= 0x20) {
              expect(v.pids, contains(pidOf(c)), reason: 'polled $c');
            }
          }
          for (final x in _extraPids) {
            expect(cmds, isNot(contains(x)), reason: 'no readable 0120 bit');
          }
          expectLive(d, v.live, extras: false);
          expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
        });
      });
    }

    test('#1 Mitsubishi Pajero 2006 (KWP): 0100 bit 0x20 set but the ECU '
        'rejects 0120 with "7F 01 12" → nothing above 0x20 is polled and the '
        'poll fits in 3 s', () {
      sim(
        carFor(
          pajero2006,
          override: {
            '0100':
                'BUS INIT: OK\n'
                '${supportBitmap(0x00, {...pajero2006.pids, 0x21})}',
          },
        ),
        (rig) {
          final (d, took, cmds) = _pollOnce(rig);
          expect(cmds, ['0120', ...pajero2006.supportedPollPids]);
          expectLive(d, pajero2006.live);
          expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
        },
      );
    });

    test('#1 Toyota Camry 2004: 0120 itself answers NO DATA → PIDs 0x21+ '
        'fall back to polled, but none of them decodes garbage', () {
      sim(carFor(camry2004, override: {'0120': 'NO DATA'}), (rig) {
        final (d, _, _) = _pollOnce(rig);
        expect(d.fuelLevelPct, isNull);
        expect(d.batteryVoltage, isNull);
        expect(d.oilTempC, isNull);
      });
    });

    for (final (v, pid) in [
      (landCruiser2021, '0142'),
      (camry2004, '0115'),
      (pajero2006, '0118'),
    ]) {
      test('#1 ${v.name}: bitmap advertises $pid but it answers NO DATA → '
          'null, every other value right, next poll still fine', () {
        sim(carFor(v, override: {pid: 'NO DATA'}), (rig) {
          for (var i = 0; i < 2; i++) {
            final (d, took, cmds) = _pollOnce(rig);
            expect(cmds, contains(pid)); // advertised → still asked
            expect(_fields[pid]!(d), isNull);
            expectLive(d, v.live, skip: pid);
            expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
          }
        });
      });
    }

    for (final tcmFirst in [false, true]) {
      test('#1 Lexus LX 2020: ECM and TCM advertise different 0100 bitmaps '
          '(speed only on the TCM, ${tcmFirst ? 'TCM' : 'ECM'} line first) '
          '→ the union is polled, nothing else', () {
        final ecm = supportBitmap(0x00, lexusLx2020.pids.difference({0x0D}));
        final tcm = supportBitmap(0x00, {0x01, 0x0D, 0x1C});
        sim(
          carFor(
            lexusLx2020,
            override: {
              '0100': tcmFirst ? '$tcm\n$ecm' : '$ecm\n$tcm',
              '010D': '41 0D 2A', // TCM output-shaft speed, 42 km/h
            },
          ),
          (rig) {
            final (d, _, cmds) = _pollOnce(rig);
            expect(cmds, [
              ...lexusLx2020.bitmapRequests,
              ...lexusLx2020.supportedPollPids,
            ]);
            expect(d.speedKmh, 42);
            expectLive(d, lexusLx2020.live, skip: '010D');
          },
        );
      });
    }

    test('#1 a K-line TCM-less ECM whose 0100 lacks bit 0x20 is never asked '
        '0120, even though higher PIDs are in _pollPids', () {
      sim(carFor(pajero2006), (rig) {
        final (_, _, cmds) = _pollOnce(rig);
        expect(cmds.where(_isBitmapRequest), isEmpty);
        expect(cmds, isNot(contains('012F')));
        expect(cmds, isNot(contains('0142')));
        expect(cmds, isNot(contains('015C')));
      });
    });

    /// Connects one adapter to [a], polls, disconnects, connects the same
    /// adapter to [b] and polls again; returns b's first frame + commands.
    (OBDLiveData, Duration, List<String>) reconnect(Vehicle a, Vehicle b) {
      late (OBDLiveData, Duration, List<String>) out;
      fakeAsync((async) {
        final elmA = FakeElm327(carFor(a));
        final rigA = Rig.fff0(async, elmA);
        rigA.connect();
        final (_, _, cmdsA) = _pollOnce(rigA);
        expect(cmdsA, [...a.bitmapRequests, ...a.supportedPollPids]);
        rigA.drive(rigA.adapter.disconnect());

        final elmB = FakeElm327(carFor(b));
        final rigB = Rig.fff0(async, elmB);
        rigA.drive(rigA.adapter.connect(rigB.device));
        expect(rigA.adapter.isConnected, isTrue);
        out = _pollWith(async, rigA.adapter, elmB);

        rigA.drive(rigA.adapter.disconnect());
        async.flushTimers(flushPeriodicTimers: false);
      });
      return out;
    }

    const reconnectPairs = [
      (hilux2019, landCruiser2021),
      (landCruiser2021, hilux2019),
      (camry2004, patrol2015),
      (patrol2015, sunny2010),
    ];

    for (final (a, b) in reconnectPairs) {
      test('#1 reconnecting the same adapter from ${a.name} to ${b.name} '
          're-reads the support bitmaps', () {
        final (d, took, cmds) = reconnect(a, b);
        expect(cmds, [...b.bitmapRequests, ...b.supportedPollPids]);
        for (final e in b.live.entries) {
          expect(_fields[e.key]!(d), closeTo(e.value, 0.01), reason: e.key);
        }
        expect(took, lessThanOrEqualTo(const Duration(seconds: 3)));
      });
    }

    test('#1 reconnecting to a different car does not show the previous car\'s '
        'values for PIDs the new car does not support', () {
      for (final (a, b) in reconnectPairs) {
        final (d, _, _) = reconnect(a, b);
        for (final cmd in _checkedPids) {
          if (b.live.containsKey(cmd)) continue;
          if (cmd == '0124' && _lambdaWant(b.live) != null) continue;
          expect(
            _fields[cmd]!(d),
            isNull,
            reason: '${a.name} → ${b.name}: $cmd carried over',
          );
        }
      }
    });

    for (final v in vehicles) {
      test('#1 ${v.name}: steady state refreshes every 3 s — no timer tick '
          'skipped over 4 cycles', () {
        sim(carFor(v), (rig) {
          final stamps = <Duration>[];
          final sub = rig.adapter.liveDataStream.listen(
            (_) => stamps.add(rig.async.elapsed),
          );
          final t0 = rig.async.elapsed;
          rig.adapter.startLiveData();
          rig.async.elapse(const Duration(milliseconds: 14900));
          rig.adapter.stopLiveData();
          rig.async.elapse(const Duration(seconds: 30));
          sub.cancel();
          // Ticks at 3, 6, 9, 12 s → four frames before 14.9 s.
          final inWindow = stamps
              .where((s) => s - t0 < const Duration(milliseconds: 14900))
              .toList();
          expect(inWindow, hasLength(4), reason: 'frames at $stamps');
          for (var i = 1; i < inWindow.length; i++) {
            expect(
              inWindow[i] - inWindow[i - 1],
              lessThanOrEqualTo(const Duration(milliseconds: 3250)),
            );
          }
        });
      });
    }

    // ── #2 clearDtcs ──────────────────────────────────────────────────────

    for (final v in [patrol2015, camry2004]) {
      test('#2 ${v.name}: "7F 04 78" (responsePending) then "44" 2 s later '
          '→ true and the codes are gone', () {
        sim(
          carFor(
            v,
            clearReply: '7F 04 78\n44',
            latencyOverrides: {'04': const Duration(seconds: 2)},
          ),
          (rig) {
            expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
            expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          },
        );
      });

      for (final reply in ['7F 04 78\n7F 04 22', '7F 04 78', 'NO DATA']) {
        test('#2 ${v.name}: clear answered "${reply.replaceAll('\n', ' / ')}"'
            ' → false, codes still there', () {
          sim(carFor(v, clearReply: reply), (rig) {
            expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
            expect(rig.drive(rig.adapter.getDtcs()), v.dtcs);
          });
        });
      }
    }

    for (final reply in ['44\n7F 04 22', '7F 04 22\n44', '44\n7F 04 31']) {
      test('#2 Lexus LX 2020: one ECU accepts mode 04 and the other refuses '
          '(${reply.replaceAll('\n', ' / ')}) → false', () {
        sim(carFor(lexusLx2020, clearReply: reply), (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
        });
      });
    }

    test('#2 Lexus LX 2020: both ECUs answer 44 → true', () {
      sim(carFor(lexusLx2020, clearReply: '44\n44'), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
      });
    });

    test('#2 Toyota Camry 2004: clear takes longer than the 5 s timeout '
        '→ false (not silently "cleared")', () {
      sim(
        carFor(
          camry2004,
          latencyOverrides: {'04': const Duration(milliseconds: 5600)},
        ),
        (rig) {
          expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
          // The late "44" must not be taken as the answer to the next command.
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, isFalse);
        },
      );
    });

    // ── #3 readiness ──────────────────────────────────────────────────────

    test('#3 Lexus LX 2020: only the TCM answers 0101 → its data alone '
        '(MIL off, 0 DTCs, spark, Components only)', () {
      sim(carFor(lexusLx2020, override: {'0101': '41 01 00 04 00 00'}), (rig) {
        final r = rig.drive(rig.adapter.getReadinessMonitors());
        expect(r.milOn, isFalse);
        expect(r.dtcCount, 0);
        expect(r.compressionIgnition, isFalse);
        final m = {for (final x in r.monitors) x.name: x.status};
        expect(m['Components'], _r);
        expect(m['Misfire'], _na);
        expect(m['Fuel System'], _na);
        expect(m.entries.where((e) => e.value != _na).map((e) => e.key), [
          'Components',
        ]);
      });
    });

    for (final tcmFirst in [false, true]) {
      test('#3 Toyota Hilux 2019 diesel ECM + spark-looking TCM '
          '(${tcmFirst ? 'TCM' : 'ECM'} first) → diesel monitors, MIL on, '
          '1 DTC', () {
        const ecm = '41 01 81 0F E9 40';
        const tcm = '41 01 00 04 00 00';
        sim(
          carFor(
            hilux2019,
            override: {'0101': tcmFirst ? '$tcm\n$ecm' : '$ecm\n$tcm'},
          ),
          (rig) {
            final r = rig.drive(rig.adapter.getReadinessMonitors());
            expect(r.compressionIgnition, isTrue);
            expect(r.milOn, isTrue);
            expect(r.dtcCount, 1);
            expect({
              for (final m in r.monitors) m.name: m.status,
            }, hilux2019.monitors);
          },
        );
      });
    }

    test('#3 Nissan Patrol 2015: TCM with its own MIL request and a TCM '
        'monitor incomplete → counts summed, MIL ORed', () {
      sim(
        carFor(
          patrol2015,
          tcmFirst: true,
          override: {'0101': '41 01 81 44 00 00\n41 01 03 07 E5 00'},
        ),
        (rig) {
          final r = rig.drive(rig.adapter.getReadinessMonitors());
          expect(r.milOn, isTrue);
          expect(r.dtcCount, 4);
          expect(r.compressionIgnition, isFalse);
          final m = {for (final x in r.monitors) x.name: x.status};
          expect(m['Components'], _nr); // TCM says incomplete
          expect(m['Catalyst'], _r);
          expect(m['EGR / VVT'], _r);
        },
      );
    });

    // ── #4 headers-off ISO-TP reassembly ──────────────────────────────────

    test('#4 Nissan Patrol 2015: TCM single frame "43 00" between the ECM\'s '
        'first and consecutive frame', () {
      sim(
        carFor(
          patrol2015,
          override: {
            '03': '008\n0: 43 03 01 71 01 74\n43 00\n1: 03 00 00 00 00 00 00',
          },
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), ['P0171', 'P0174', 'P0300']);
        },
      );
    });

    test('#4 Nissan Patrol 2015: ECM and TCM multi-frame mode 03 replies '
        'interleaved frame by frame', () {
      sim(
        carFor(
          patrol2015,
          override: {
            '03':
                '008\n0: 43 03 01 71 01 74\n'
                '00A\n0: 43 04 07 00 07 15\n'
                '1: 03 00 00 00 00 00 00\n'
                '1: 07 20 07 30 00 00 00',
          },
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), [
            'P0171',
            'P0174',
            'P0300',
            'P0700',
            'P0715',
            'P0720',
            'P0730',
          ]);
        },
      );
    });

    test('#4 Toyota Camry 2004 (K-line): 4 confirmed codes in two '
        '3-code messages', () {
      sim(
        carFor(
          camry2004,
          override: {'03': '43 01 71 04 20 03 00\n43 01 33 00 00 00 00'},
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getDtcs()), [
            'P0171',
            'P0420',
            'P0300',
            'P0133',
            // '~P0300' is pending AND confirmed → listed once.
          ]);
        },
      );
    });

    // ── #5 VIN parser ─────────────────────────────────────────────────────

    String kLineShuffled(String vin, List<int> order) {
      final lines = kLineVinReply(vin).split('\n');
      return [for (final n in order) lines[n - 1]].join('\n');
    }

    for (final (v, order) in [
      (camry2004, [3, 1, 5, 2, 4]),
      (pajero2006, [5, 4, 3, 2, 1]),
      (sunny2010, [2, 1, 4, 3, 5]),
    ]) {
      test('#5 ${v.name}: K-line VIN messages arrive out of order '
          '(${order.join(',')}) → reassembled by message number', () {
        sim(carFor(v, override: {'0902': kLineShuffled(v.vin!, order)}), (rig) {
          expect(rig.drive(rig.adapter.getVin()), v.vin);
        });
      });
    }

    test('#5 Toyota Camry 2004: K-line VIN with message 4 missing → null, '
        'not a 13-character fragment', () {
      sim(
        carFor(
          camry2004,
          override: {
            '0902': kLineShuffled(camry2004.vin!, [1, 2, 3, 5]),
          },
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getVin()), isNull);
        },
      );
    });

    test('#5 Toyota Camry 2004: two K-line ECUs answer 0902 interleaved '
        '(1,1,2,2,…) → one clean VIN', () {
      final a = kLineVinReply(camry2004.vin!).split('\n');
      sim(
        carFor(
          camry2004,
          override: {
            '0902': [for (final l in a) '$l\n$l'].join('\n'),
          },
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getVin()), camry2004.vin);
        },
      );
    });

    test('#5 Lexus LX 2020: ECM and TCM CAN VIN replies interleaved frame by '
        'frame', () {
      final e = canVinReply(lexusLx2020.vin!).split('\n');
      sim(
        carFor(
          lexusLx2020,
          override: {
            '0902': [e[0], e[1], e[0], e[1], e[2], e[2], e[3], e[3]].join('\n'),
          },
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getVin()), lexusLx2020.vin);
        },
      );
    });

    test('#5 Toyota Land Cruiser 2021: TCM answers 0902 with "7F 09 12" in '
        'the middle of the ECM\'s ISO-TP VIN', () {
      final e = canVinReply(landCruiser2021.vin!).split('\n');
      sim(
        carFor(
          landCruiser2021,
          override: {
            '0902': [e[0], e[1], '7F 09 12', e[2], e[3]].join('\n'),
          },
        ),
        (rig) {
          expect(rig.drive(rig.adapter.getVin()), landCruiser2021.vin);
        },
      );
    });

    test('#5 Toyota Land Cruiser 2021: a corrupted VIN character (I/O/Q) '
        '→ null instead of garbage', () {
      final bad = landCruiser2021.vin!.replaceRange(11, 12, 'O');
      sim(carFor(landCruiser2021, override: {'0902': canVinReply(bad)}), (rig) {
        expect(rig.drive(rig.adapter.getVin()), isNull);
      });
    });

    // ── #6–8 VinDecoder ───────────────────────────────────────────────────

    for (final (vin, maker, country, year) in [
      ('JTMHY7AJ6M4123456', 'Toyota', 'Japan', '2021'), // LC200 GCC
      ('JTEBU3FJ5AK123456', 'Toyota', 'Japan', '2010'), // Prado 150
      ('MR0HA3CD3K0123456', 'Toyota', 'Thailand', '2019'), // Hilux
      ('JMYLYV7586J123456', 'Mitsubishi', 'Japan', '2006'), // Pajero
      ('JN8AY2NY9F9123456', 'Nissan', 'Japan', '2015'), // Patrol Y62
      ('JTJHY7AX6L4123456', 'Lexus', 'Japan', '2020'), // LX 570
      ('JHMCM56373C123456', 'Honda', 'Japan', '2003'), // Accord CM5
      // Position 10 '0' is not a model-year code → Unknown, not a guess.
      ('JTMHV05J604123456', 'Toyota', 'Japan', 'Unknown'),
    ]) {
      test('#6-8 VinDecoder $vin → $maker / $country / $year', () {
        final d = VinDecoder.decode(vin, now: _now);
        expect(d['error'], isNull);
        expect(d['manufacturer'], maker);
        expect(d['country'], country);
        expect(d['year'], year);
      });
    }

    for (final (vin, country) in [
      ('MA3EWDE1S00123456', 'India'), // Maruti Suzuki
      ('MHFXW42G2A2123456', 'Indonesia'), // Toyota Astra
      ('MMBJNKB40FD123456', 'Thailand'), // Mitsubishi Thailand
      ('MNTVCUD40Z0123456', 'Thailand'), // Nissan Thailand
    ]) {
      test('#8 ISO 3780 second-character country split: $vin → $country', () {
        expect(VinDecoder.decode(vin, now: _now)['country'], country);
      });
    }

    test('#6 VinDecoder: other WMIs of Japanese brands common in the Gulf', () {
      for (final (vin, maker) in [
        ('JS3JB43V0A4123456', 'Suzuki'), // Jimny / Grand Vitara (SUV WMI)
        ('JMBXTGF2WAZ123456', 'Mitsubishi'), // Europe/export Mitsubishi
        ('JT3HN86R0Y0123456', 'Toyota'), // older Land Cruiser / 4Runner
        ('MMBJNKB40FD123456', 'Mitsubishi'), // Thailand: Pajero Sport/L200
        ('MHFXW42G2A2123456', 'Toyota'), // Indonesia: Fortuner/Innova
        ('MNTVCUD40Z0123456', 'Nissan'), // Thailand: Navara
        ('MRHGM2650AP123456', 'Honda'), // Thailand: City/Civic
        ('MPATFS86JAT123456', 'Isuzu'), // Thailand: D-Max
      ]) {
        expect(
          VinDecoder.decode(vin, now: _now)['manufacturer'],
          maker,
          reason: vin,
        );
      }
    });

    // ── #9 recovery after a hung / late command ───────────────────────────

    test('#9 Toyota Camry 2004: 0105 hangs once (no prompt) → only coolant '
        'is lost that cycle, the next answer is not discarded or shifted', () {
      sim(carFor(camry2004, hangsOnce: {'0105'}), (rig) {
        final (d1, _, _) = _pollOnce(rig);
        expect(d1.coolantTempC, isNull);
        expectLive(d1, camry2004.live, skip: '0105');
        final (d2, took2, _) = _pollOnce(rig);
        expectLive(d2, camry2004.live);
        expect(took2, lessThanOrEqualTo(const Duration(seconds: 3)));
      });
    });

    test('#9 Toyota Camry 2004: 0111 answers after its 1 s timeout → the late '
        'reply is not taken as 0104\'s', () {
      sim(
        carFor(
          camry2004,
          latencyOverrides: {'0111': const Duration(milliseconds: 1200)},
        ),
        (rig) {
          final (d, _, _) = _pollOnce(rig);
          expect(d.throttlePct, isNull);
          expectLive(d, camry2004.live, skip: '0111');
        },
      );
    });

    test('#9 Toyota Land Cruiser 2021: clone never answers 0142 at all → '
        'every other PID still right on every cycle', () {
      sim(carFor(landCruiser2021, silent: {'0142'}), (rig) {
        for (var i = 0; i < 2; i++) {
          final (d, _, _) = _pollOnce(rig);
          expect(d.batteryVoltage, isNull);
          expectLive(d, landCruiser2021.live, skip: '0142');
        }
        expect(rig.drive(rig.adapter.getDtcs()), landCruiser2021.dtcs);
      });
    });
  });
}
