// Chinese-car profiles and plumbing for test/screens/chinese_cars_ui_test.dart.
//
// The profiles describe what each car's OBD-II side hands the UI once the
// adapter layer has done its job (live PIDs, DTC list incl. '~' pending
// codes, VIN from 09 02, readiness / compression-ignition bit, ATI/ATDP).
// VINs are built with a valid ISO 3779 / GB 16735 check digit (position 9)
// and the SAE model-year character in position 10 (A = 2010 … N = 2022,
// P = 2023, R = 2024, S = 2025).
//
// Per-model PID sets are not published by the OEMs; the values below are
// realistic idle / light-cruise readings, not captures from a specific car.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_service.dart';

import '../../helpers/fake_obd_adapter.dart';

// ── VIN check digit ───────────────────────────────────────────────────────────

const _translit = {
  'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8, //
  'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9,
  'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9,
};
const _weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];

/// ISO 3779 check digit of a 17-char VIN (position 9 is ignored).
String vinCheckDigit(String vin) {
  var sum = 0;
  for (var i = 0; i < 17; i++) {
    sum += (int.tryParse(vin[i]) ?? _translit[vin[i]]!) * _weights[i];
  }
  final r = sum % 11;
  return r == 10 ? 'X' : '$r';
}

/// Fills position 9 ('?') of [template] with the correct check digit.
String vinFrom(String template) {
  assert(template.length == 17 && template[8] == '?', template);
  final v = template.replaceRange(8, 9, '0');
  return v.replaceRange(8, 9, vinCheckDigit(v));
}

// ── Car profiles ──────────────────────────────────────────────────────────────

class ChineseCar {
  const ChineseCar({
    required this.name,
    required this.vinTemplate,
    required this.maker,
    required this.year,
    required this.live,
    required this.dtcs,
    this.diesel = false,
    this.ev = false,
    this.protocol = 'ISO 15765-4 (CAN 11/500)',
  });

  final String name;
  final String vinTemplate;

  /// What the VIN card should show as the maker (correct behaviour).
  final String maker;
  final String year;
  final OBDLiveData live;

  /// As returned by the adapter: '~' prefix = mode 07 pending.
  final List<String> dtcs;
  final bool diesel;
  final bool ev;
  final String protocol;

  String get vin => vinFrom(vinTemplate);

  /// The same car returning [codes] instead of its own DTC list.
  ChineseCar withDtcs(List<String> codes) => ChineseCar(
    name: name,
    vinTemplate: vinTemplate,
    maker: maker,
    year: year,
    live: live,
    dtcs: codes,
    diesel: diesel,
    ev: ev,
    protocol: protocol,
  );
}

// Changan CS75 Plus 2022, 1.5T Blue Core GDI petrol.
const changanCs75Plus = ChineseCar(
  name: 'Changan CS75 Plus 2022',
  vinTemplate: 'LS5A3DDE?NA123456',
  maker: 'Changan',
  year: '2022',
  live: OBDLiveData(
    rpm: 760,
    speedKmh: 0,
    coolantTempC: 89,
    throttlePct: 14.5,
    fuelLevelPct: 62,
    engineLoad: 23.9,
    batteryVoltage: 14.2,
    oilTempC: 86,
    intakeAirTempC: 34,
    mapKpa: 36,
    timingAdvanceDeg: 9.5,
    fuelTrimShortPct: 1.6,
    fuelTrimLongPct: -2.3,
    o2B1S1Voltage: 0.72,
    o2B1S2Voltage: 0.66,
    fuelRailPressureKpa: 5200,
  ),
  dtcs: ['P0300', 'P1336', 'U1012', '~P0171'],
);

// Ford Taurus 2022 built by Changan Ford (WMI LVS), 2.0T EcoBoost.
const fordTaurusChina = ChineseCar(
  name: 'Ford Taurus 2022 (Changan Ford)',
  vinTemplate: 'LVSHJCAC?NF543210',
  maker: 'Ford (Changan)',
  year: '2022',
  live: OBDLiveData(
    rpm: 1850,
    speedKmh: 72,
    coolantTempC: 92,
    throttlePct: 18.4,
    fuelLevelPct: 48,
    engineLoad: 31.4,
    batteryVoltage: 14.4,
    intakeAirTempC: 31,
    mapKpa: 58,
    timingAdvanceDeg: 21,
    fuelTrimShortPct: -0.8,
    fuelTrimLongPct: 3.1,
    o2B1S1Voltage: 0.61,
    o2B1S2Voltage: 0.70,
  ),
  dtcs: ['P0420', '~P0456'],
);

// Geely Coolray (SX11) 2021, 1.5T 3-cyl: wide-band upstream sensor only,
// battery voltage from ATRV (no PID 0142).
const geelyCoolray = ChineseCar(
  name: 'Geely Coolray 2021',
  vinTemplate: 'L6T7824Z?MN123456',
  maker: 'Geely',
  year: '2021',
  live: OBDLiveData(
    rpm: 820,
    speedKmh: 0,
    coolantTempC: 91,
    throttlePct: 12.2,
    fuelLevelPct: 35,
    engineLoad: 27.1,
    batteryVoltage: 13.9,
    intakeAirTempC: 38,
    mapKpa: 33,
    timingAdvanceDeg: 6,
    fuelTrimShortPct: 0.8,
    fuelTrimLongPct: 1.6,
    lambdaB1S1: 0.99,
    o2B1S2Voltage: 0.68,
  ),
  dtcs: ['P0016', 'B1000', 'C1000'],
);

// Chery Tiggo 8 Pro 2022, 1.6 TGDI.
const cheryTiggo8Pro = ChineseCar(
  name: 'Chery Tiggo 8 Pro 2022',
  vinTemplate: 'LVVDB21B?NC012345',
  maker: 'Chery',
  year: '2022',
  live: OBDLiveData(
    rpm: 790,
    speedKmh: 0,
    coolantTempC: 88,
    throttlePct: 13.7,
    fuelLevelPct: 71,
    engineLoad: 22.4,
    batteryVoltage: 14.1,
    intakeAirTempC: 36,
    mapKpa: 34,
    timingAdvanceDeg: 8,
    fuelTrimShortPct: -1.6,
    fuelTrimLongPct: 2.3,
    o2B1S1Voltage: 0.58,
    o2B1S2Voltage: 0.69,
  ),
  dtcs: ['P1607', 'C1201', '~P0128'],
);

// Haval Jolion 2023, 1.5T.
const havalJolion = ChineseCar(
  name: 'Haval Jolion 2023',
  vinTemplate: 'LGWEF6A5?PH123456',
  maker: 'Great Wall Motor (GWM)',
  year: '2023',
  live: OBDLiveData(
    rpm: 2100,
    speedKmh: 96,
    coolantTempC: 93,
    throttlePct: 21.6,
    fuelLevelPct: 54,
    engineLoad: 38.0,
    batteryVoltage: 14.3,
    oilTempC: 95,
    intakeAirTempC: 33,
    mapKpa: 75,
    timingAdvanceDeg: 18,
    fuelTrimShortPct: 2.3,
    fuelTrimLongPct: -0.8,
    o2B1S1Voltage: 0.77,
    o2B1S2Voltage: 0.71,
  ),
  dtcs: ['P0301', 'U0140'],
);

// MG5 2023 (SAIC), 1.5 NA.
const mg5 = ChineseCar(
  name: 'MG5 2023',
  vinTemplate: 'LSJW74U9?PZ123456',
  maker: 'SAIC MG',
  year: '2023',
  live: OBDLiveData(
    rpm: 740,
    speedKmh: 0,
    coolantTempC: 90,
    throttlePct: 11.8,
    fuelLevelPct: 80,
    engineLoad: 19.6,
    batteryVoltage: 14.0,
    intakeAirTempC: 35,
    mapKpa: 31,
    timingAdvanceDeg: 10,
    fuelTrimShortPct: 0,
    fuelTrimLongPct: 4.7,
    o2B1S1Voltage: 0.31,
    o2B1S2Voltage: 0.64,
  ),
  dtcs: ['P0420', '~P0171', 'U0140'],
);

// GWM Poer 2022, 2.0T GW4D20M common-rail diesel.
const gwmPoerDiesel = ChineseCar(
  name: 'GWM Poer 2.0T diesel 2022',
  vinTemplate: 'LGWDBE17?NG123456',
  maker: 'Great Wall Motor (GWM)',
  year: '2022',
  diesel: true,
  live: OBDLiveData(
    rpm: 760,
    speedKmh: 0,
    coolantTempC: 84,
    fuelLevelPct: 66,
    engineLoad: 18.0,
    batteryVoltage: 14.1,
    oilTempC: 82,
    intakeAirTempC: 30,
    mapKpa: 104,
    acceleratorPedalPct: 12.5,
    fuelRailPressureKpa: 32000,
  ),
  dtcs: ['P2002', 'P0087', '~P0401'],
);

// BYD Song Plus DM-i 2023 (plug-in hybrid, engine off in EV mode). BYD's
// passenger-car WMI is LGX.
const bydSongPlusDmi = ChineseCar(
  name: 'BYD Song Plus DM-i 2023',
  vinTemplate: 'LGXC74C4?P0123456',
  maker: 'BYD',
  year: '2023',
  live: OBDLiveData(
    rpm: 0,
    speedKmh: 38,
    coolantTempC: 46,
    fuelLevelPct: 70,
    engineLoad: 0,
    batteryVoltage: 13.8,
    intakeAirTempC: 29,
  ),
  dtcs: ['P0A80', 'P0AA6', '~P0A7F', 'P1A00'],
);

// BYD Atto 3 (Yuan Plus) 2023 EV: no engine ECU; the VCU answers a handful
// of mode 01 PIDs. WMI LC0 (BYD Auto export).
const bydAtto3 = ChineseCar(
  name: 'BYD Atto 3 EV 2023',
  vinTemplate: 'LC0CE4CB?P0123456',
  maker: 'BYD',
  year: '2023',
  ev: true,
  live: OBDLiveData(speedKmh: 42, batteryVoltage: 13.9),
  dtcs: ['P0AFA', 'U0100', 'P1A10'],
);

const allChineseCars = [
  changanCs75Plus,
  fordTaurusChina,
  geelyCoolray,
  cheryTiggo8Pro,
  havalJolion,
  mg5,
  gwmPoerDiesel,
  bydSongPlusDmi,
  bydAtto3,
];

// ── Adapter ───────────────────────────────────────────────────────────────────

/// [FakeOBDAdapter] answering VIN and readiness for [car].
class ChineseCarAdapter extends FakeOBDAdapter {
  ChineseCarAdapter(this.car) {
    dtcsToReturn = List.of(car.dtcs);
    adapterInfo = OBDAdapterInfo(
      version: 'ELM327 v2.1',
      protocol: car.protocol,
    );
  }

  final ChineseCar car;

  @override
  Future<String?> getVin() async => car.vin;

  @override
  Future<ReadinessResult> getReadinessMonitors() async => ReadinessResult(
    milOn: dtcsToReturn.any((c) => !c.startsWith('~')),
    dtcCount: dtcsToReturn.where((c) => !c.startsWith('~')).length,
    monitors: const [],
    compressionIgnition: car.diesel,
  );
}

// ── Platform channels ─────────────────────────────────────────────────────────

const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

/// Connectivity reports "offline", so DtcRepository only uses bundled data.
void mockOffline() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivity, (call) async {
        if (call.method == 'check') return ['none'];
        return null;
      });
}

void clearOfflineMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivity, null);
}

/// Records share-sheet calls (any method) for the rest of the test.
List<MethodCall> captureShares(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    shareChannel,
    (c) async {
      calls.add(c);
      return 'dev.fluttercommunity.plus/share/unavailable';
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      null,
    ),
  );
  return calls;
}

/// Loads the bundled DTC JSON (EN and AR) for [codes] outside fake-async —
/// the large asset loads never complete under FakeAsync. The parsed maps are
/// cached statically, so the screen's own lookups are then synchronous-ish.
Future<Map<String, String?>> warmDtcs(
  WidgetTester tester,
  DtcRepository repo,
  Iterable<String> codes, {
  String lang = 'en',
}) async {
  final out = <String, String?>{};
  await tester.runAsync(() async {
    for (final raw in codes) {
      final code = raw.startsWith('~') ? raw.substring(1) : raw;
      out[code] = await repo.getDtcDescription(code, languageCode: lang);
    }
  });
  return out;
}

// ── Overflow collection ───────────────────────────────────────────────────────

FlutterExceptionHandler? _onErrorBeforeCollecting;
bool _collecting = false;

/// Collects RenderFlex overflow reports instead of failing the test (other
/// errors still fail it). Returns the live list of report texts.
///
/// Call [stopCollectingOverflows] before `expect`ing on the list: a failing
/// expect while FlutterError.onError is still overridden trips the test
/// binding's "test overrode FlutterError.onError" assertion, which hides the
/// real failure and can wedge the rest of the file.
List<String> collectOverflows() {
  final reports = <String>[];
  if (!_collecting) _onErrorBeforeCollecting = FlutterError.onError;
  _collecting = true;
  final original = _onErrorBeforeCollecting;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (details.exceptionAsString().contains('overflowed')) {
      reports.add(text);
      return;
    }
    original?.call(details);
  };
  addTearDown(stopCollectingOverflows);
  return reports;
}

/// Restores the FlutterError.onError that [collectOverflows] replaced.
void stopCollectingOverflows() {
  if (!_collecting) return;
  FlutterError.onError = _onErrorBeforeCollecting;
  _collecting = false;
}
