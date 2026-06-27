import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class OBDLiveData {
  final double? rpm;
  final double? speedKmh;
  final double? coolantTempC;
  final double? throttlePct;
  final double? fuelLevelPct;
  final double? engineLoad;
  final double? batteryVoltage;  // PID 0142 — control module voltage (V)
  final double? oilTempC;        // PID 015C — engine oil temperature (°C)
  final double? fuelTrimShortPct;  // PID 0106 — STFT bank 1 (%)
  final double? fuelTrimLongPct;   // PID 0107 — LTFT bank 1 (%)
  final double? fuelTrimShortB2;   // PID 0108 — STFT bank 2 (%)  — V6/V8 only
  final double? fuelTrimLongB2;    // PID 0109 — LTFT bank 2 (%)  — V6/V8 only
  final double? o2B1S1Voltage;     // PID 0114 — O2 sensor bank 1 sensor 1 upstream (V)
  final double? o2B1S2Voltage;     // PID 0115 — O2 sensor bank 1 sensor 2 downstream (V)
  final double? o2B2S1Voltage;      // PID 0118 — O2 sensor bank 2 sensor 1 (V) — V6/V8
  final double? intakeAirTempC;     // PID 010F — intake air temperature (°C)

  const OBDLiveData({
    this.rpm,
    this.speedKmh,
    this.coolantTempC,
    this.throttlePct,
    this.fuelLevelPct,
    this.engineLoad,
    this.batteryVoltage,
    this.oilTempC,
    this.fuelTrimShortPct,
    this.fuelTrimLongPct,
    this.fuelTrimShortB2,
    this.fuelTrimLongB2,
    this.o2B1S1Voltage,
    this.o2B1S2Voltage,
    this.o2B2S1Voltage,
    this.intakeAirTempC,
  });
}

// ── Readiness monitor result ──────────────────────────────────────────────────

class ReadinessMonitor {
  final String name;
  final bool complete; // true = test passed/ready, false = not yet complete

  const ReadinessMonitor({required this.name, required this.complete});
}

// ── Abstract contract (testable) ──────────────────────────────────────────────

abstract class OBDAdapter {
  bool get isConnected;
  String? get connectedDeviceName;
  Stream<OBDLiveData> get liveDataStream;

  Future<void> connect(BluetoothDevice device);
  Future<void> disconnect();

  void startLiveData();
  void stopLiveData();

  Future<List<String>> getDtcs();
  Future<bool> clearDtcs();

  /// Snapshot of sensor values captured by the ECU when a fault occurred.
  Future<Map<String, String>> getFreezeFrame();

  /// Emission-system readiness monitors from PID 0101.
  Future<List<ReadinessMonitor>> getReadinessMonitors();
}

// ── Production implementation ─────────────────────────────────────────────────
//
// Implements the full BLE + ELM327 handshake directly so we can:
//   • Skip ATZ (which causes a brief BLE disconnect on many adapters and
//     makes the obd2 package's built-in onDisconnected handler tear down
//     the connection before init is complete).
//   • Ignore transient disconnects during the init phase.
// ─────────────────────────────────────────────────────────────────────────────

class ProductionOBDAdapter implements OBDAdapter {
  // ── BLE objects ────────────────────────────────────────────────────────────

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  // While true, transient disconnects (e.g. from adapter power-cycling during
  // protocol setup) do NOT trigger a full teardown.
  bool _initPhase = true;
  bool _connected = false;

  // ── AT response handling ───────────────────────────────────────────────────

  final _buf = StringBuffer();
  Completer<String>? _pending;

  // ── Live data ──────────────────────────────────────────────────────────────

  final _dataController = StreamController<OBDLiveData>.broadcast();
  Timer? _pollingTimer;
  bool _polling = false;          // guard against overlapping polls
  OBDLiveData _lastData = const OBDLiveData(); // last known good values

  // ── OBDAdapter API ─────────────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedDeviceName => _device?.platformName;

  @override
  Stream<OBDLiveData> get liveDataStream => _dataController.stream;

  @override
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    _connected = false;
    _initPhase = true;
    _buf.clear();

    // ── 1. BLE connect ────────────────────────────────────────────────────
    await device.connect(
      license: License.free,
      autoConnect: false,
      timeout: const Duration(seconds: 15),
    );
    _connected = true;

    // ── 2. Watch for disconnections (but ignore them during init) ─────────
    _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && !_initPhase) {
        _connected = false;
      }
    });

    // ── 3. Discover GATT services ─────────────────────────────────────────
    final services = await device.discoverServices();
    _resolveCharacteristics(services);

    if (_writeChar == null || _notifyChar == null) {
      throw StateError(
        'No writable + notifiable characteristic pair found on this device. '
        'Ensure it is a BLE ELM327 adapter.',
      );
    }

    // ── 4. Subscribe to incoming data ─────────────────────────────────────
    await _notifyChar!.setNotifyValue(true);
    _notifySub?.cancel();
    _notifySub = _notifyChar!.lastValueStream.listen(_onNotify);

    // ── 5. ELM327 init — we intentionally skip ATZ ────────────────────────
    //   ATZ resets the adapter which causes a brief BLE disconnect on many
    //   cheap ELM327 clones.  That disconnect fires the connection-state
    //   listener and tears down the session before we finish init.
    //   Skipping ATZ is safe: the adapter is already in a usable state the
    //   moment the BLE connection is established.
    await Future.delayed(const Duration(milliseconds: 500));
    await _sendAT('ATE0', timeout: 2000); // echo off
    await _sendAT('ATL0');               // linefeeds off
    await _sendAT('ATS0');               // spaces off
    await _sendAT('ATH0');               // headers off
    await _sendAT('ATSP0', timeout: 3000); // auto-detect OBD protocol

    _initPhase = false;
  }

  // ── Characteristic resolution ──────────────────────────────────────────────
  //
  // Priority order (most specific → least):
  //   FFF0 service  →  FFF2 write  +  FFF1 notify   (most common ELM327 BLE)
  //   FFE0 service  →  FFE1 write+notify (single characteristic adapters)
  //   Any Notify UUID known from popular OBD adapters
  //   Fallback: first writable + first notifiable in any service
  // ──────────────────────────────────────────────────────────────────────────

  static const _knownSvcIds   = ['fff0', 'ffe0', 'e7810a71', 'be781a71'];
  static const _knownWriteIds = ['fff2', 'ffe1', 'bef8d6c9'];
  static const _knownNotifyIds = ['fff1', 'ffe1', 'bef8d6c9'];

  void _resolveCharacteristics(List<BluetoothService> services) {
    _writeChar = null;
    _notifyChar = null;

    for (final svc in services) {
      final sId = svc.uuid.str.toLowerCase();
      final knownSvc = _knownSvcIds.any(sId.contains);

      for (final c in svc.characteristics) {
        final cId = c.uuid.str.toLowerCase();
        final knownWrite  = _knownWriteIds.any(cId.contains);
        final knownNotify = _knownNotifyIds.any(cId.contains);

        if (_writeChar == null &&
            (knownSvc || knownWrite) &&
            (c.properties.write || c.properties.writeWithoutResponse)) {
          _writeChar = c;
        }
        if (_notifyChar == null &&
            (knownSvc || knownNotify) &&
            (c.properties.notify || c.properties.indicate)) {
          _notifyChar = c;
        }
      }
    }

    // Fallback: any writable + any notifiable pair
    if (_writeChar == null || _notifyChar == null) {
      for (final svc in services) {
        for (final c in svc.characteristics) {
          if (_writeChar == null &&
              (c.properties.write || c.properties.writeWithoutResponse)) {
            _writeChar = c;
          }
          if (_notifyChar == null &&
              (c.properties.notify || c.properties.indicate)) {
            _notifyChar = c;
          }
        }
      }
    }
  }

  // ── BLE I/O ────────────────────────────────────────────────────────────────

  void _onNotify(List<int> data) {
    if (data.isEmpty) return;
    _buf.write(utf8.decode(data, allowMalformed: true));
    if (_buf.toString().contains('>')) {
      final response = _buf.toString().replaceAll('>', '').trim();
      _buf.clear();
      if (!(_pending?.isCompleted ?? true)) {
        _pending!.complete(response);
        _pending = null;
      }
    }
  }

  Future<String> _sendAT(String cmd, {int timeout = 1500}) async {
    if (_writeChar == null) return '';
    _buf.clear();
    _pending = Completer<String>();

    final bytes = utf8.encode('$cmd\r');
    try {
      if (_writeChar!.properties.writeWithoutResponse) {
        await _writeChar!.write(bytes, withoutResponse: true);
      } else {
        await _writeChar!.write(bytes);
      }
      return await _pending!.future
          .timeout(Duration(milliseconds: timeout));
    } catch (_) {
      _pending = null;
      return '';
    }
  }

  // ── OBD PIDs ───────────────────────────────────────────────────────────────

  Future<String> _query(String pid, {int timeout = 2000}) =>
      _sendAT(pid, timeout: timeout);

  Future<double?> _rpm() async {
    final b = _bytes(await _query('010C'), '410C');
    return b.length >= 2 ? ((b[0] * 256) + b[1]) / 4.0 : null;
  }

  Future<double?> _speed() async {
    final b = _bytes(await _query('010D'), '410D');
    return b.isNotEmpty ? b[0].toDouble() : null;
  }

  Future<double?> _coolant() async {
    final b = _bytes(await _query('0105'), '4105');
    return b.isNotEmpty ? (b[0] - 40).toDouble() : null;
  }

  Future<double?> _throttle() async {
    final b = _bytes(await _query('0111', timeout: 1000), '4111');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  Future<double?> _fuel() async {
    // PID 012F is optional on many vehicles — use a short timeout to fail fast.
    final b = _bytes(await _query('012F', timeout: 1000), '412F');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  Future<double?> _load() async {
    final b = _bytes(await _query('0104', timeout: 1500), '4104');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  Future<double?> _batteryVoltage() async {
    // PID 0142 = Control module voltage. Formula: (A*256 + B) / 1000 → volts.
    final b = _bytes(await _query('0142', timeout: 1000), '4142');
    return b.length >= 2 ? (b[0] * 256 + b[1]) / 1000.0 : null;
  }

  Future<double?> _oilTemp() async {
    // PID 015C = Engine oil temperature. Formula: A - 40 (°C). Optional on many vehicles.
    final b = _bytes(await _query('015C', timeout: 1000), '415C');
    return b.isNotEmpty ? (b[0] - 40).toDouble() : null;
  }

  Future<double?> _fuelTrimShort() async {
    // PID 0106 = Short-term fuel trim bank 1. Formula: (A/1.28) - 100 (%).
    // Negative = lean (ECU adding fuel), positive = rich (ECU removing fuel).
    final b = _bytes(await _query('0106', timeout: 1000), '4106');
    return b.isNotEmpty ? (b[0] / 1.28) - 100 : null;
  }

  Future<double?> _fuelTrimLong() async {
    final b = _bytes(await _query('0107', timeout: 1000), '4107');
    return b.isNotEmpty ? (b[0] / 1.28) - 100 : null;
  }

  Future<double?> _fuelTrimShortB2() async {
    // PID 0108 = Short-term fuel trim bank 2 (V6/V8 engines only).
    final b = _bytes(await _query('0108', timeout: 800), '4108');
    return b.isNotEmpty ? (b[0] / 1.28) - 100 : null;
  }

  Future<double?> _fuelTrimLongB2() async {
    // PID 0109 = Long-term fuel trim bank 2 (V6/V8 engines only).
    final b = _bytes(await _query('0109', timeout: 800), '4109');
    return b.isNotEmpty ? (b[0] / 1.28) - 100 : null;
  }

  Future<double?> _o2B1S1() async {
    // PID 0114 = O2 sensor bank 1 sensor 1 (upstream before catalyst).
    // Byte A = voltage: A/200 → 0–1.275 V.  Healthy sensor cycles 0.1–0.9 V.
    // Stuck near 0.45 V = dead/lazy sensor.
    final b = _bytes(await _query('0114', timeout: 800), '4114');
    return b.isNotEmpty ? b[0] / 200.0 : null;
  }

  Future<double?> _o2B1S2() async {
    // PID 0115 = O2 sensor bank 1 sensor 2 (downstream after catalyst).
    // Should be relatively stable ~0.6–0.8 V when catalyst is healthy.
    final b = _bytes(await _query('0115', timeout: 800), '4115');
    return b.isNotEmpty ? b[0] / 200.0 : null;
  }

  Future<double?> _o2B2S1() async {
    // PID 0118 = O2 sensor bank 2 sensor 1 (V6/V8 engines only).
    final b = _bytes(await _query('0118', timeout: 800), '4118');
    return b.isNotEmpty ? b[0] / 200.0 : null;
  }

  Future<double?> _intakeAirTemp() async {
    // PID 010F = Intake air temperature. Formula: A - 40 (°C).
    // > 60°C indicates heat soak (common on turbocharged engines) or
    // a failed intercooler — reduces engine power and efficiency.
    final b = _bytes(await _query('010F', timeout: 800), '410F');
    return b.isNotEmpty ? (b[0] - 40).toDouble() : null;
  }

  // ── Live data ──────────────────────────────────────────────────────────────

  @override
  void startLiveData() {
    _pollingTimer?.cancel();
    // 3 s gives each poll room to finish (6 PIDs × up to 2 s worst-case timeout)
    // before the next one fires.
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _poll(),
    );
  }

  @override
  void stopLiveData() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  Future<void> _poll() async {
    if (!_connected || _initPhase) return;
    // Skip this tick if a previous poll is still in progress.
    if (_polling) return;
    _polling = true;
    try {
      // Fall back to the last known good value when a PID returns null
      // (unsupported sensor, transient timeout, etc.) so the UI never
      // flickers back to '--' after a value has been established.
      _lastData = OBDLiveData(
        rpm:              (await _rpm())              ?? _lastData.rpm,
        speedKmh:         (await _speed())            ?? _lastData.speedKmh,
        coolantTempC:     (await _coolant())          ?? _lastData.coolantTempC,
        throttlePct:      (await _throttle())         ?? _lastData.throttlePct,
        fuelLevelPct:     (await _fuel())             ?? _lastData.fuelLevelPct,
        engineLoad:       (await _load())             ?? _lastData.engineLoad,
        batteryVoltage:   (await _batteryVoltage())   ?? _lastData.batteryVoltage,
        oilTempC:         (await _oilTemp())          ?? _lastData.oilTempC,
        fuelTrimShortPct: (await _fuelTrimShort())    ?? _lastData.fuelTrimShortPct,
        fuelTrimLongPct:  (await _fuelTrimLong())     ?? _lastData.fuelTrimLongPct,
        fuelTrimShortB2:  (await _fuelTrimShortB2())  ?? _lastData.fuelTrimShortB2,
        fuelTrimLongB2:   (await _fuelTrimLongB2())   ?? _lastData.fuelTrimLongB2,
        o2B1S1Voltage:    (await _o2B1S1())           ?? _lastData.o2B1S1Voltage,
        o2B1S2Voltage:    (await _o2B1S2())           ?? _lastData.o2B1S2Voltage,
        o2B2S1Voltage:    (await _o2B2S1())            ?? _lastData.o2B2S1Voltage,
        intakeAirTempC:   (await _intakeAirTemp())     ?? _lastData.intakeAirTempC,
      );
      if (!_dataController.isClosed) _dataController.add(_lastData);
    } finally {
      _polling = false;
    }
  }

  // ── DTCs ───────────────────────────────────────────────────────────────────

  @override
  Future<List<String>> getDtcs() async {
    if (!_connected) return [];

    // Mode 03 — confirmed stored codes (MIL is ON for these).
    final r03 = await _sendAT('03', timeout: 10000);
    final confirmed = _parseDtcs(r03, header: '43');

    // Mode 07 — pending codes: detected this drive cycle but not yet confirmed.
    // Real faults (airbag, sensor failures, etc.) often appear here before they
    // become "confirmed". Prefix with '~' so the UI can label them "Pending".
    final r07 = await _sendAT('07', timeout: 5000);
    final pending = _parseDtcs(r07, header: '47')
        .map((c) => '~$c')
        .toList();

    // Merge: confirmed first, then pending codes not already in confirmed list.
    final confirmedSet = confirmed.toSet();
    final uniquePending = pending.where((p) => !confirmedSet.contains(p.substring(1))).toList();
    return [...confirmed, ...uniquePending];
  }

  @override
  Future<bool> clearDtcs() async {
    if (!_connected) return false;
    await _sendAT('04', timeout: 5000);
    return true;
  }

  // ── Freeze frame (mode 02) ────────────────────────────────────────────────

  @override
  Future<Map<String, String>> getFreezeFrame() async {
    if (!_connected) return {};
    final data = <String, String>{};

    // Each key: PID to send.  Value: (label, response header, expected data bytes, converter).
    final queries = <(String, String, String, int, String Function(List<int>))>[
      ('020C', '420C', 'RPM',         2, (b) => '${((b[0]*256+b[1])/4).toStringAsFixed(0)} rpm'),
      ('020D', '420D', 'Speed',        1, (b) => '${b[0]} km/h'),
      ('0205', '4205', 'Coolant',      1, (b) => '${b[0]-40}°C'),
      ('0204', '4204', 'Engine Load',  1, (b) => '${(b[0]*100/255).toStringAsFixed(1)}%'),
      ('020F', '420F', 'Air Temp',     1, (b) => '${b[0]-40}°C'),
      ('0211', '4211', 'Throttle',     1, (b) => '${(b[0]*100/255).toStringAsFixed(1)}%'),
      ('0206', '4206', 'Fuel Trim',    1, (b) => '${((b[0]/1.28)-100).toStringAsFixed(1)}%'),
      ('020B', '420B', 'MAP',          1, (b) => '${b[0]} kPa'),
    ];

    for (final q in queries) {
      final r = await _sendAT(q.$1, timeout: 1200);
      final raw = _bytes(r, q.$2);
      // Mode 02 responses include a frame-number byte (0–3) before the data.
      final b = (raw.length == q.$4 + 1 && raw[0] <= 3) ? raw.sublist(1) : raw;
      if (b.length >= q.$4) {
        data[q.$3] = q.$5(b);
      }
    }
    return data;
  }

  // ── Readiness monitors (PID 0101) ─────────────────────────────────────────

  @override
  Future<List<ReadinessMonitor>> getReadinessMonitors() async {
    if (!_connected) return [];
    final r = await _sendAT('0101', timeout: 3000);
    final b = _bytes(r, '4101');
    if (b.length < 3) return [];

    // Byte B: incomplete flags (1=not done). Byte C: supported flags (1=supported).
    final incomplete = b[1];
    final supported  = b[2];
    // Byte D (optional): more monitors.
    final incD = b.length > 3 ? b[3] : 0;
    final supD = b.length > 4 ? b[4] : 0xFF;

    final monitors = <ReadinessMonitor>[];

    void add(String name, int supByte, int incByte, int bit) {
      if ((supByte >> bit) & 1 == 1) {
        monitors.add(ReadinessMonitor(
          name: name,
          complete: ((incByte >> bit) & 1) == 0,
        ));
      }
    }

    // Byte B monitors (bits 0-7)
    add('Misfire',          supported, incomplete, 0);
    add('Fuel System',      supported, incomplete, 1);
    add('Components',       supported, incomplete, 2);
    add('Catalyst',         supported, incomplete, 4);
    add('Heated Catalyst',  supported, incomplete, 5);
    add('Evap System',      supported, incomplete, 6);
    add('Secondary Air',    supported, incomplete, 7);
    // Byte D monitors
    add('A/C System',       supD, incD, 0);
    add('O2 Sensor',        supD, incD, 1);
    add('O2 Sensor Heater', supD, incD, 2);
    add('EGR / VVT',        supD, incD, 3);

    return monitors;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  Future<void> disconnect() async {
    stopLiveData();
    _notifySub?.cancel();
    _notifySub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _initPhase = false;
    _connected = false;
    _buf.clear();
    try {
      _pending?.completeError('Disconnected');
    } catch (_) {}
    _pending = null;
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    _notifyChar = null;
  }

  // ── Parsing helpers ────────────────────────────────────────────────────────

  List<int> _bytes(String response, String header) {
    final clean = response
        .replaceAll(' ', '')
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .toUpperCase();
    final idx = clean.indexOf(header.toUpperCase());
    if (idx == -1) return [];
    final hex = clean.substring(idx + header.length);
    final result = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final n = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (n == null) break;
      result.add(n);
    }
    return result;
  }

  List<String> _parseDtcs(String response, {String header = '43'}) {
    // Normalise: strip spaces, CR/LF, and ELM327 multi-frame line prefixes (e.g. "0:", "1:").
    final clean = response
        .replaceAll(' ', '')
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .replaceAll(RegExp(r'\d:'), '')
        .toUpperCase();

    // Ignore ELM327 error responses.
    const errorTokens = ['NODATA', 'UNABLETOCONNECT', 'CANERROR', 'STOPPED', 'ERROR'];
    if (errorTokens.any(clean.contains)) return [];

    final dtcs = <String>[];
    final idx = clean.indexOf(header.toUpperCase());
    if (idx == -1) return dtcs;

    String data = clean.substring(idx + header.length);

    // ISO 9141 / KWP2000 vehicles prepend a count byte before the DTC pairs.
    // CAN vehicles (ISO 15765) do not include a count byte.
    // Detection: if first byte is 1–6 AND there are at least count×2 bytes
    // of DTC data following AND the first DTC byte after it is non-zero,
    // treat the first byte as a count and skip it.
    if (data.length >= 6) {
      final possibleCount = int.tryParse(data.substring(0, 2), radix: 16) ?? 0;
      if (possibleCount >= 1 && possibleCount <= 6) {
        final minLen = 2 + possibleCount * 4; // count(2 chars) + DTCs
        if (data.length >= minLen) {
          final firstDtcHi = int.tryParse(data.substring(2, 4), radix: 16) ?? 0;
          final firstDtcLo = int.tryParse(data.substring(4, 6), radix: 16) ?? 0;
          if (firstDtcHi != 0 || firstDtcLo != 0) {
            // Looks like a count byte — extract exactly count DTC pairs.
            data = data.substring(2, 2 + possibleCount * 4);
          }
        }
      }
    }

    for (var i = 0; i + 4 <= data.length; i += 4) {
      final b1 = int.tryParse(data.substring(i, i + 2), radix: 16) ?? 0;
      final b2 = int.tryParse(data.substring(i + 2, i + 4), radix: 16) ?? 0;
      if (b1 == 0 && b2 == 0) continue;

      final prefix = ['P', 'C', 'B', 'U'][(b1 >> 6) & 3];
      // Use hex formatting: P0300 → "0300", not decimal 768 → "0768".
      final num = (b1 & 0x3F).toRadixString(16).padLeft(2, '0').toUpperCase() +
                  b2.toRadixString(16).padLeft(2, '0').toUpperCase();
      dtcs.add('$prefix$num');
    }
    return dtcs;
  }
}

// ── Visible-for-testing factory typedef ───────────────────────────────────────

@visibleForTesting
typedef OBDAdapterFactory = OBDAdapter Function();
