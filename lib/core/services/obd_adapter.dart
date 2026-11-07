import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'obd_log.dart';

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
  final double? mapKpa;             // PID 010B — manifold absolute pressure (kPa)
  final double? timingAdvanceDeg;   // PID 010E — ignition timing advance (°)
  /// Wide-band upstream sensor (PID 0124, else 0134) — equivalence ratio λ.
  /// Only read when the narrow-band 0114 is not advertised.
  final double? lambdaB1S1;
  final double? fuelRailPressureKpa; // PID 0123 — fuel rail gauge pressure (kPa) — diesel / GDI
  final double? acceleratorPedalPct; // PID 0149 — accelerator pedal position D (%)

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
    this.mapKpa,
    this.timingAdvanceDeg,
    this.lambdaB1S1,
    this.fuelRailPressureKpa,
    this.acceleratorPedalPct,
  });
}

// ── Readiness monitor result ──────────────────────────────────────────────────

enum MonitorStatus { ready, notReady, notApplicable }

class ReadinessMonitor {
  final String name;
  final MonitorStatus status;

  const ReadinessMonitor({required this.name, required this.status});

  bool get isReady       => status == MonitorStatus.ready;
  bool get isNotReady    => status == MonitorStatus.notReady;
  bool get isApplicable  => status != MonitorStatus.notApplicable;
}

/// Summary returned by [OBDAdapter.getReadinessMonitors].
class ReadinessResult {
  final bool milOn;         // MIL (check engine) lamp status
  final int  dtcCount;      // number of confirmed DTCs stored
  final List<ReadinessMonitor> monitors;
  /// True for diesel (compression ignition) engines: PID 0101 byte B bit 3.
  final bool compressionIgnition;

  const ReadinessResult({
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
    this.compressionIgnition = false,
  });
}

// ── Connection state / failures ───────────────────────────────────────────────

enum OBDConnectionState {
  disconnected,
  connecting,
  connected,

  /// The last [OBDAdapter.connect] attempt failed (see [OBDConnectException]).
  failed,

  /// The BLE link dropped mid-session, without [OBDAdapter.disconnect].
  lost,
}

/// Why [OBDAdapter.connect] failed, so the UI can say what to do about it.
enum OBDFailureReason {
  /// The BLE link (connect / service discovery / notify) could not be set up.
  bleConnectFailed,

  /// The BLE connect attempt timed out (adapter unpowered, out of range, or
  /// held by another app).
  bleTimeout,

  /// The device has no writable + notifiable characteristic pair: not a BLE
  /// ELM327 (e.g. a Bluetooth Classic adapter, which this app can't use).
  noElmCharacteristic,

  /// The link is up but nothing answered the ELM327 AT commands.
  adapterNotResponding,

  /// The adapter works but no ECU answered 0100 on any protocol (ignition
  /// off, or a protocol the adapter can't speak).
  ecuNotResponding,

  /// No ECU answered 0100, but there is evidence the car is ON: the vehicle
  /// bus is awake (0100 got "NO DATA", not "CAN ERROR" / "BUS INIT: ERROR")
  /// and either the auto search also ended on NO DATA or the adapter reads a
  /// charging voltage. Typical of electric vehicles that only expose
  /// manufacturer (mode 22) data. A heuristic — see
  /// [ProductionOBDAdapter.classifySilentEcu].
  noStandardObdData,

  unknown,
}

/// Thrown by [OBDAdapter.connect]. Extends [StateError] (what connect threw
/// before failures were typed) and implements [Exception], so existing
/// `on StateError` / `on Exception` handlers keep matching.
class OBDConnectException extends StateError implements Exception {
  OBDConnectException(this.reason, super.message, {this.adapterVersion, this.cause});

  final OBDFailureReason reason;

  /// `ATI` reply, when it could be read before giving up.
  final String? adapterVersion;

  /// Underlying error (e.g. the flutter_blue_plus exception).
  final Object? cause;

  /// Auto search failed on an adapter whose version is typical of clones,
  /// many of which lack the J1850 hardware pre-2008 Ford / GM cars need.
  bool get suggestsCloneAdapter =>
      reason == OBDFailureReason.ecuNotResponding &&
      OBDAdapterInfo.isCloneVersion(adapterVersion);

  @override
  String toString() => 'OBDConnectException(${reason.name}): $message';
}

/// What the adapter says about itself after a successful connect.
class OBDAdapterInfo {
  const OBDAdapterInfo({this.version, this.protocol});

  /// `ATI`, e.g. "ELM327 v1.5".
  final String? version;

  /// `ATDP`, e.g. "AUTO, ISO 15765-4 (CAN 11/500)".
  final String? protocol;

  bool get looksLikeClone => isCloneVersion(version);

  /// Elm Electronics never shipped a v1.5, and nearly every "v2.1" sold is
  /// a clone of it; genuine chips and STN-based adapters report other
  /// versions (v1.4b, v2.2, v2.3 …).
  static bool isCloneVersion(String? v) =>
      v != null &&
      RegExp(r'v\s*(1\.5|2\.1)(?![0-9])', caseSensitive: false).hasMatch(v);
}

// ── Abstract contract (testable) ──────────────────────────────────────────────

abstract class OBDAdapter {
  bool get isConnected;
  String? get connectedDeviceName;
  Stream<OBDLiveData> get liveDataStream;

  /// Current link state; [connectionStateStream] emits every change.
  OBDConnectionState get connectionState;
  Stream<OBDConnectionState> get connectionStateStream;

  /// Throws [OBDConnectException] on failure.
  Future<void> connect(BluetoothDevice device);
  Future<void> disconnect();

  /// Reads `ATI` / `ATDP` once connected. Fields the adapter doesn't answer
  /// are null.
  Future<OBDAdapterInfo> readAdapterInfo();

  void startLiveData();
  void stopLiveData();

  Future<List<String>> getDtcs();
  Future<bool> clearDtcs();

  /// Snapshot of sensor values captured by the ECU when a fault occurred.
  Future<Map<String, String>> getFreezeFrame();

  /// Emission-system readiness monitors from PID 0101.
  Future<ReadinessResult> getReadinessMonitors();

  /// Vehicle Identification Number from mode 09 PID 02. Returns null when
  /// unsupported or when the response cannot be parsed to 17 chars.
  Future<String?> getVin();
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
  /// [identifyOnFailure]: when no ECU answers, send `ATI` before giving up
  /// so [OBDConnectException.adapterVersion] can flag clone adapters. Off by
  /// default to keep the failed handshake's command sequence minimal;
  /// [OBDService] turns it on.
  ProductionOBDAdapter({this.identifyOnFailure = false, OBDLog? log})
      : _log = log ?? OBDLog.instance;

  final bool identifyOnFailure;
  final OBDLog _log;

  // ── Connection state ───────────────────────────────────────────────────────

  final _stateController = StreamController<OBDConnectionState>.broadcast();
  OBDConnectionState _state = OBDConnectionState.disconnected;

  void _setState(OBDConnectionState s) {
    if (s == _state) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

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

  // Tail of the command queue. The ELM327 handles one command at a time, so
  // callers (live-data poll, DTC / VIN / readiness screens) are serialised
  // instead of overwriting each other's [_pending] completer.
  Future<void> _queue = Future.value();

  // Set when a command timed out. The ELM327 still ends that command with a
  // '>' prompt later (its late answer, or "STOPPED" when the next command
  // interrupts it); that prompt must not be taken as the next command's reply.
  bool _stalePrompt = false;
  Completer<void>? _staleDone; // completed when that stale prompt arrives

  // ── Live data ──────────────────────────────────────────────────────────────

  final _dataController = StreamController<OBDLiveData>.broadcast();
  Timer? _pollingTimer;
  bool _polling = false;          // guard against overlapping polls
  OBDLiveData _lastData = const OBDLiveData(); // last known good values

  // The 0100 reply that established the protocol — reused as the 0x01–0x20
  // support bitmap so the first poll doesn't have to ask for it again.
  String _protocolReply = '';

  // Mode 01 support bitmaps by range base (0x00 / 0x20 / 0x40), merged over
  // every ECU that answered: bit 31 = PID base+1 … bit 0 = base+0x20. A null
  // value means the reply could not be parsed, so every PID of that range
  // is polled. null map = not read yet (done once, on the first poll).
  Map<int, int?>? _pidSupport;

  // ── OBDAdapter API ─────────────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedDeviceName => _device?.platformName;

  @override
  Stream<OBDLiveData> get liveDataStream => _dataController.stream;

  @override
  OBDConnectionState get connectionState => _state;

  @override
  Stream<OBDConnectionState> get connectionStateStream =>
      _stateController.stream;

  @override
  Future<void> connect(BluetoothDevice device) async {
    _setState(OBDConnectionState.connecting);
    _log.event('Connecting to "${device.platformName}"');
    final clock = Stopwatch()..start();
    _device = device;
    _connected = false;
    _initPhase = true;
    _buf.clear();
    _stalePrompt = false;
    _protocolReply = '';
    _pidSupport = null;
    _pidTimeouts.clear();
    // A different car may be on the other end now: never let the previous
    // car's values stand in for PIDs this one doesn't support.
    _lastData = const OBDLiveData();

    try {
      await _connectAndInit(device);
    } catch (e) {
      _log.error('Connect failed after ${clock.elapsedMilliseconds} ms: $e');
      // Leave no half-open BLE link behind, otherwise the next attempt on the
      // same adapter fails too.
      await _release(OBDConnectionState.failed);
      if (e is OBDConnectException) rethrow;
      throw OBDConnectException(OBDFailureReason.unknown, '$e', cause: e);
    }
    _log.event('Connected in ${clock.elapsedMilliseconds} ms');
    _setState(OBDConnectionState.connected);
  }

  Future<void> _connectAndInit(BluetoothDevice device) async {
    // ── 1. BLE connect ────────────────────────────────────────────────────
    try {
      await device.connect(
        license: License.free,
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      final timedOut = e is TimeoutException ||
          (e is FlutterBluePlusException &&
              e.code == FbpErrorCode.timeout.index);
      throw OBDConnectException(
        timedOut ? OBDFailureReason.bleTimeout : OBDFailureReason.bleConnectFailed,
        'BLE connect failed: $e',
        cause: e,
      );
    }
    _connected = true;
    _log.event('BLE link up');

    // ── 2. Watch for disconnections (but ignore them during init) ─────────
    _connStateSub?.cancel();
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && !_initPhase) {
        _onLinkLost();
      }
    });

    // ── 3. Discover GATT services ─────────────────────────────────────────
    try {
      final services = await device.discoverServices();
      _resolveCharacteristics(services);
    } catch (e) {
      throw OBDConnectException(
        OBDFailureReason.bleConnectFailed,
        'GATT service discovery failed: $e',
        cause: e,
      );
    }

    if (_writeChar == null || _notifyChar == null) {
      throw OBDConnectException(
        OBDFailureReason.noElmCharacteristic,
        'No writable + notifiable characteristic pair found on this device. '
        'Ensure it is a BLE ELM327 adapter.',
      );
    }
    _log.event('Write ${_writeChar!.uuid.str}, notify ${_notifyChar!.uuid.str}');

    // ── 4. Subscribe to incoming data ─────────────────────────────────────
    try {
      await _notifyChar!.setNotifyValue(true);
    } catch (e) {
      throw OBDConnectException(
        OBDFailureReason.bleConnectFailed,
        'Enabling notifications failed: $e',
        cause: e,
      );
    }
    _notifySub?.cancel();
    _notifySub = _notifyChar!.lastValueStream.listen(_onNotify);

    // ── 5. ELM327 init — we intentionally skip ATZ ────────────────────────
    //   ATZ resets the adapter which causes a brief BLE disconnect on many
    //   cheap ELM327 clones.  That disconnect fires the connection-state
    //   listener and tears down the session before we finish init.
    //   Skipping ATZ is safe: the adapter is already in a usable state the
    //   moment the BLE connection is established.
    await Future.delayed(const Duration(milliseconds: 500));
    final handshake = [
      await _sendAT('ATE0', timeout: 2000), // echo off
      await _sendAT('ATL0'),               // linefeeds off
      await _sendAT('ATS0'),               // spaces off
      await _sendAT('ATH0'),               // headers off
    ];
    // Not one reply: whatever is on the other end of this characteristic
    // pair isn't an ELM327 (or it's wedged). Don't sit through 25 s of
    // protocol timeouts to then blame the car.
    if (handshake.every((r) => r.isEmpty)) {
      throw OBDConnectException(
        OBDFailureReason.adapterNotResponding,
        'The adapter did not answer any ELM327 AT command.',
      );
    }

    // ── 6. Establish the vehicle protocol before declaring success ────────
    //   ATSP0 alone only arms auto-detect; the actual search runs on the
    //   first OBD request and can take 5–10 s on clone adapters (they walk
    //   J1850 / ISO 9141 / KWP before reaching CAN). Sending live-data PIDs
    //   with short timeouts interrupts that search ("STOPPED") so it never
    //   completes. Try CAN 11-bit 500k first (every 2008+ car, incl. Ford),
    //   then fall back to a full auto search with a long timeout.
    final can = await _tryProtocol('6', timeout: 5000);
    if (!can.ok) {
      final auto = await _tryProtocol('0', timeout: 20000);
      if (!auto.ok) await _throwEcuSilent(can.reply, auto.reply);
    }

    _initPhase = false;
  }

  /// Neither protocol 6 nor the auto search got a 0100 answer: work out why
  /// from their replies ([classifySilentEcu]) and throw.
  Future<Never> _throwEcuSilent(String canReply, String autoReply) async {
    final version = identifyOnFailure
        ? _atReply('ATI', await _sendAT('ATI', timeout: 1500))
        : null;
    final reason = await classifySilentEcu(
      canReply,
      autoReply,
      readVoltage: _adapterVoltage,
    );
    if (reason == OBDFailureReason.noStandardObdData) {
      throw OBDConnectException(
        reason,
        'The vehicle bus is awake but no ECU answered standard OBD-II '
        '(mode 01) requests. Common on electric vehicles, which only share '
        'manufacturer-specific data.',
        adapterVersion: version,
      );
    }
    throw OBDConnectException(
      OBDFailureReason.ecuNotResponding,
      'Adapter connected but the vehicle ECU did not respond. '
      'Make sure the ignition is ON (electric/hybrid: switch to READY).',
      adapterVersion: version,
    );
  }

  /// A 12 V battery being charged — by the alternator, or by an EV's DC-DC
  /// converter in READY — reads at least this much on OBD pin 16; a resting
  /// one (car off) reads ~12.0–12.8 V.
  static const chargingVolts = 13.0;

  /// Why no ECU answered 0100, neither on protocol 6 ([canReply]) nor in the
  /// auto search ([autoReply]). The ELM327 can't tell "car off" from "car on
  /// but silent on standard OBD-II" outright, so this is a heuristic:
  ///
  ///  1. A bus-level error on either attempt — "CAN ERROR" / "BUS ERROR"
  ///     (nothing acknowledged the CAN frame) or "BUS INIT: ...ERROR" (no
  ///     K-line ECU woke up) — means no bus activity: ignition off, or a
  ///     wiring / adapter problem → [OBDFailureReason.ecuNotResponding].
  ///  2. No "NO DATA" on either attempt (timeouts, "UNABLE TO CONNECT", "?")
  ///     is no evidence either way → ecuNotResponding.
  ///  3. "NO DATA" means the frame was acknowledged — something on the bus
  ///     is awake — but nothing answered mode 01. That alone is weak: some
  ///     gateways wake up and ACK with the ignition off, and the ELM327
  ///     reports NO DATA then too. So it needs confirmation: the auto search
  ///     also ended on NO DATA, or [readVoltage] (ATRV, only asked here)
  ///     reads ≥ [chargingVolts], i.e. the car is ON / READY.
  ///     Confirmed → [OBDFailureReason.noStandardObdData] (typical of EVs,
  ///     whose data is only on manufacturer mode 22); unconfirmed (resting
  ///     battery voltage, or a clone without ATRV) → ecuNotResponding.
  ///
  /// The noStandardObdData advice still tells petrol / diesel drivers to
  /// check the ignition, so a misclassified combustion car isn't misled.
  static Future<OBDFailureReason> classifySilentEcu(
    String canReply,
    String autoReply, {
    required Future<double?> Function() readVoltage,
  }) async {
    String flat(String r) => r.toUpperCase().replaceAll(RegExp(r'\s'), '');
    final can = flat(canReply);
    final auto = flat(autoReply);
    final busInitError = RegExp(r'BUSINIT:?\.*ERROR');
    bool busError(String r) =>
        r.contains('CANERROR') ||
        r.contains('BUSERROR') ||
        busInitError.hasMatch(r);

    if (busError(can) || busError(auto)) {
      return OBDFailureReason.ecuNotResponding;
    }
    final autoNoData = auto.contains('NODATA');
    if (!autoNoData && !can.contains('NODATA')) {
      return OBDFailureReason.ecuNotResponding;
    }
    if (autoNoData) return OBDFailureReason.noStandardObdData;
    final volts = await readVoltage();
    return volts != null && volts >= chargingVolts
        ? OBDFailureReason.noStandardObdData
        : OBDFailureReason.ecuNotResponding;
  }

  @override
  Future<OBDAdapterInfo> readAdapterInfo() async {
    if (!_connected) return const OBDAdapterInfo();
    final info = OBDAdapterInfo(
      version: _atReply('ATI', await _sendAT('ATI', timeout: 1500)),
      protocol: _atReply('ATDP', await _sendAT('ATDP', timeout: 1500)),
    );
    _log.event('Adapter "${info.version ?? '?'}", '
        'protocol "${info.protocol ?? '?'}"');
    return info;
  }

  /// Text of an informational AT reply ([cmd] echo and blank lines dropped),
  /// or null when the adapter didn't answer or rejected it ("?").
  static String? _atReply(String cmd, String response) {
    final lines = [
      for (final l in response.split(RegExp(r'[\r\n]+')))
        if (l.trim().isNotEmpty && l.trim().toUpperCase() != cmd) l.trim(),
    ];
    if (lines.isEmpty || lines.last == '?') return null;
    return lines.last;
  }

  /// Selects ELM327 protocol [p] and checks the ECU answers PID 0100. The
  /// raw [reply] is kept: on failure it is the evidence for
  /// [classifySilentEcu] ("NO DATA" vs "CAN ERROR" …).
  Future<({bool ok, String reply})> _tryProtocol(
    String p, {
    required int timeout,
  }) async {
    await _sendAT('ATSP$p', timeout: 2000);
    final r = await _sendAT('0100', timeout: timeout);
    if (_bytes(r, '4100').length < 4) return (ok: false, reply: r);
    _protocolReply = r;
    return (ok: true, reply: r);
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
    // One packet may carry more than one prompt (e.g. "STOPPED >" followed
    // by the next reply): handle each '>'-terminated response on its own.
    var text = _buf.toString();
    var end = text.indexOf('>');
    if (end == -1) return;
    while (end != -1) {
      _onResponse(text.substring(0, end).trim());
      text = text.substring(end + 1);
      end = text.indexOf('>');
    }
    _buf
      ..clear()
      ..write(text);
  }

  void _onResponse(String response) {
    if (_stalePrompt) {
      _log.rx('$response  [late reply, discarded]');
      _stalePrompt = false; // reply to a command we already gave up on
      _staleDone?.complete();
      _staleDone = null;
      return;
    }
    // A bare "STOPPED" is never the answer to the command now pending: it
    // is the ELM327 ending a command we already gave up on, interrupted by
    // our write (see [_resync]). The real answer follows with its own '>'.
    if (response == 'STOPPED') {
      _log.rx('STOPPED  [discarded]');
      return;
    }
    if (!(_pending?.isCompleted ?? true)) {
      _pending!.complete(response);
      _pending = null;
    } else {
      _log.rx('$response  [unsolicited]');
    }
  }

  Future<String> _sendAT(String cmd, {int timeout = 1500}) {
    final reply = _queue.then((_) => _sendNow(cmd, timeout));
    _queue = reply; // _sendNow never throws
    return reply;
  }

  Future<String> _sendNow(String cmd, int timeout) async {
    if (_writeChar == null) return '';
    if (_stalePrompt) await _resync();
    _buf.clear();
    // Keep a local reference: the reply notification can arrive (and clear
    // [_pending]) before a write-with-response future resolves.
    final pending = _pending = Completer<String>();

    final clock = Stopwatch()..start();
    _log.tx(cmd);
    try {
      await _write('$cmd\r');
      final r = await pending.future.timeout(Duration(milliseconds: timeout));
      _log.rx(r, took: clock.elapsed);
      return r;
    } on TimeoutException {
      _log.error('$cmd: no reply within $timeout ms');
      _stalePrompt = true;
      return '';
    } catch (e) {
      _log.error('$cmd: $e');
      return '';
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<void> _write(String text) async {
    final bytes = utf8.encode(text);
    if (_writeChar!.properties.writeWithoutResponse) {
      await _writeChar!.write(bytes, withoutResponse: true);
    } else {
      await _writeChar!.write(bytes);
    }
  }

  /// The previous command timed out, so the ELM327 may still be busy with it.
  /// Interrupt it with a bare CR and wait for its prompt before sending the
  /// next real command: some clones swallow the character that interrupts a
  /// busy command, turning e.g. "ATSP0" into "TSP0" ("?").
  ///
  /// If the CR gets no prompt within its window the ELM327 is idle: the
  /// timed-out command ended without ever printing '>' (hanging clones do
  /// this for PIDs the ECU ignores), and on an idle ELM a bare CR just
  /// repeats that command, which hangs again. Recovery ends there — keeping
  /// [_stalePrompt] set would throw away the next command's real answer.
  /// Should the repeated command still be running, the next write interrupts
  /// it and its "STOPPED" prompt is skipped in [_onNotify].
  Future<void> _resync() async {
    final done = _staleDone = Completer<void>();
    _log.tx(r'\r  [resync after timeout]');
    try {
      await _write('\r');
      await done.future.timeout(const Duration(milliseconds: 1000));
    } catch (_) {
      _stalePrompt = false; // idle: nothing stale left to wait for
    } finally {
      if (identical(_staleDone, done)) _staleDone = null;
    }
  }

  // ── OBD PIDs ───────────────────────────────────────────────────────────────

  /// Live-data request; PIDs the support bitmaps rule out are not sent at
  /// all (each would cost a full NO DATA timeout, ~0.2–0.3 s on K-line).
  Future<String> _query(String pid, {int timeout = 2000}) async {
    if (!_pidSupported(int.parse(pid.substring(2), radix: 16))) return '';
    // Some clones never answer certain PIDs at all (no NO DATA, no prompt).
    // Each attempt costs the timeout plus a resync, so after two misses in
    // a row stop asking for the rest of this connection.
    if ((_pidTimeouts[pid] ?? 0) >= 2) return '';
    final r = await _sendAT(pid, timeout: timeout);
    _pidTimeouts[pid] = r.isEmpty ? (_pidTimeouts[pid] ?? 0) + 1 : 0;
    return r;
  }

  /// Consecutive timeouts per live-data PID (reset on any reply).
  final _pidTimeouts = <String, int>{};

  // ── PID support bitmaps (0100 / 0120 / 0140) ──────────────────────────────

  bool _pidSupported(int pid) {
    final support = _pidSupport;
    if (support == null) return true; // not read yet → poll everything
    final base = (pid - 1) ~/ 0x20 * 0x20;
    if (!support.containsKey(base)) return true;
    final mask = support[base];
    if (mask == null) return true; // range unparseable → poll it anyway
    return (mask >> (0x1F - (pid - 1 - base))) & 1 == 1;
  }

  /// Stricter than [_pidSupported]: true only when a parsed bitmap sets the
  /// PID's bit. Used for the optional extras (wide-band O2, diesel PIDs) so
  /// an unreadable bitmap doesn't add four more requests to every poll.
  bool _pidAdvertised(int pid) {
    final base = (pid - 1) ~/ 0x20 * 0x20;
    final mask = _pidSupport?[base];
    return mask != null && (mask >> (0x1F - (pid - 1 - base))) & 1 == 1;
  }

  /// Reads the support bitmaps once per connection. 0100 comes from the
  /// protocol handshake; 0120 / 0140 are only requested when the previous
  /// bitmap's last bit (PID 0x20 / 0x40) says that range exists, as J1979
  /// requires. Bitmaps of every answering ECU are ORed together.
  Future<Map<int, int?>> _readPidSupport() async {
    final support = <int, int?>{0x00: _bitmapOf(_protocolReply, 0x00)};
    for (final base in const [0x20, 0x40]) {
      final prev = support[base - 0x20];
      if (prev == null) {
        support[base] = null; // previous range unknown → can't rule it out
      } else if (prev & 1 == 0) {
        support[base] = 0; // range not advertised → nothing there
      } else {
        final hdr = base.toRadixString(16).padLeft(2, '0').toUpperCase();
        support[base] = _bitmapOf(await _sendAT('01$hdr', timeout: 2000), base);
      }
    }
    return support;
  }

  /// "41 BB AA BB CC DD" lines for range [base] ORed into one 32-bit mask,
  /// or null when no line could be parsed.
  int? _bitmapOf(String response, int base) {
    int? mask;
    final hdr = '41${base.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    for (final b in _replyLines(response, hdr, 4)) {
      mask = (mask ?? 0) | (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
    }
    // A negative response ("7F 01 xx") is the ECU explicitly saying it has
    // nothing in this range — not an unreadable reply. Polling the range
    // anyway costs a request per PID every cycle (enough to push K-line
    // cars past the 3 s refresh).
    if (mask == null &&
        response.replaceAll(' ', '').toUpperCase().contains('7F01')) {
      return 0;
    }
    return mask;
  }

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
    // Older (mostly K-line) ECUs have no 0142: fall back to the adapter's own
    // reading of OBD pin 16 (ATRV), i.e. battery voltage minus wiring drop.
    if (!_pidSupported(0x42) || (_pidTimeouts['0142'] ?? 0) >= 2) {
      return _adapterVoltage();
    }
    // PID 0142 = Control module voltage. Formula: (A*256 + B) / 1000 → volts.
    final b = _bytes(await _query('0142', timeout: 1000), '4142');
    return b.length >= 2 ? (b[0] * 256 + b[1]) / 1000.0 : null;
  }

  /// ELM327 "ATRV" → "12.4V". Clones that don't implement it answer "?";
  /// after two such replies (or timeouts) it is not asked again this
  /// connection ([_pidTimeouts] is cleared on connect).
  Future<double?> _adapterVoltage() async {
    if ((_pidTimeouts['ATRV'] ?? 0) >= 2) return null;
    final r = await _sendAT('ATRV', timeout: 1000);
    final m = RegExp(r'(\d{1,2}(?:[.,]\d+)?)\s*V\b', caseSensitive: false)
        .firstMatch(r);
    final v = m == null ? null : double.tryParse(m[1]!.replaceAll(',', '.'));
    final ok = v != null && v > 0 && v < 30;
    _pidTimeouts['ATRV'] = ok ? 0 : (_pidTimeouts['ATRV'] ?? 0) + 1;
    return ok ? v : null;
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
    final b = _bytes(await _query('010F', timeout: 800), '410F');
    return b.isNotEmpty ? (b[0] - 40).toDouble() : null;
  }

  Future<double?> _map() async {
    // PID 010B = Manifold Absolute Pressure. Formula: A (kPa), range 0–255.
    // At idle on naturally-aspirated engine: ~30–45 kPa (vacuum).
    // At wide-open throttle: close to barometric (~100 kPa).
    // On turbocharged engines: can exceed 100 kPa (boost).
    final b = _bytes(await _query('010B', timeout: 800), '410B');
    return b.isNotEmpty ? b[0].toDouble() : null;
  }

  Future<double?> _timingAdvance() async {
    // PID 010E = Timing advance. Formula: (A - 128) / 2 (degrees BTDC).
    // Negative = retarded (ECU pulling timing due to knock detection).
    // Healthy idle: typically +5 to +15°. Knock retard pulls it toward 0 or negative.
    final b = _bytes(await _query('010E', timeout: 800), '410E');
    return b.isNotEmpty ? (b[0] - 128) / 2.0 : null;
  }

  Future<double?> _lambdaB1S1() async {
    // Modern turbo / GDI engines use a wide-band (air-fuel ratio) upstream
    // sensor and report B1S1 on PID 0124 (ratio + voltage) or 0134 (ratio +
    // current) instead of 0114. Bytes A,B = equivalence ratio:
    // (A*256 + B) / 32768 → λ 0–2 (1.00 = stoichiometric, < 1 rich, > 1 lean).
    if (_pidAdvertised(0x14)) return null; // narrow-band sensor covers it
    final pid = _pidAdvertised(0x24)
        ? '0124'
        : _pidAdvertised(0x34) ? '0134' : null;
    if (pid == null) return null;
    final b = _bytes(await _query(pid, timeout: 800), '41${pid.substring(2)}');
    return b.length >= 2 ? (b[0] * 256 + b[1]) / 32768.0 : null;
  }

  Future<double?> _fuelRailPressure() async {
    // PID 0123 = Fuel rail gauge pressure (diesel common rail / GDI).
    // Formula: (A*256 + B) * 10 → kPa. Diesel idle ~25–35 MPa.
    if (!_pidAdvertised(0x23)) return null;
    final b = _bytes(await _query('0123', timeout: 800), '4123');
    return b.length >= 2 ? (b[0] * 256 + b[1]) * 10.0 : null;
  }

  Future<double?> _acceleratorPedal() async {
    // PID 0149 = Accelerator pedal position D. Formula: A*100/255 (%).
    // Diesels often have no throttle plate (no 0111), so this is their
    // driver-demand signal. Raw sensor value: rarely reads 0 % at rest.
    if (!_pidAdvertised(0x49)) return null;
    final b = _bytes(await _query('0149', timeout: 800), '4149');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  // ── Live data ──────────────────────────────────────────────────────────────

  @override
  void startLiveData() {
    _pollingTimer?.cancel();
    // A poll reads up to 21 PIDs (+ ATRV when 0142 is missing) — only those
    // the ECU advertises (see [_readPidSupport]; the wide-band O2 / diesel
    // extras need an explicit bit): ~1 s on CAN, ~2–3 s on K-line, but up
    // to ~20 s if every PID times out. Ticks that fire while a poll is still
    // running are skipped (see [_polling]).
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
      _pidSupport ??= await _readPidSupport();
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
        mapKpa:           (await _map())               ?? _lastData.mapKpa,
        timingAdvanceDeg: (await _timingAdvance())     ?? _lastData.timingAdvanceDeg,
        lambdaB1S1:       (await _lambdaB1S1())        ?? _lastData.lambdaB1S1,
        fuelRailPressureKpa: (await _fuelRailPressure()) ?? _lastData.fuelRailPressureKpa,
        acceleratorPedalPct: (await _acceleratorPedal()) ?? _lastData.acceleratorPedalPct,
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
    final r = await _sendAT('04', timeout: 5000);
    return _clearAccepted(r);
  }

  /// Mode 04 succeeded only if an ECU answered "44" and none refused with a
  /// negative response "7F 04 NN" (typically NN = 22 conditionsNotCorrect:
  /// engine running). NO DATA / empty / timeout → false. NN = 78
  /// (responsePending) is not a refusal: the final answer follows it.
  bool _clearAccepted(String response) {
    var accepted = false;
    for (final line in _lines(response)) {
      if (RegExp(r'^7F04[0-9A-F]{2}').hasMatch(line) &&
          !line.startsWith('7F0478')) {
        return false;
      }
      if (line.startsWith('44')) accepted = true;
    }
    return accepted;
  }

  // ── VIN (mode 09 PID 02) ─────────────────────────────────────────────────

  @override
  Future<String?> getVin() async {
    if (!_connected) return null;
    final r = await _sendAT('0902', timeout: 6000);
    return _parseVin(r);
  }

  /// Several ECUs may answer 0902 (e.g. GM ECM + TCM), and with headers off
  /// their replies can interleave. Each ECU's reply is reassembled on its
  /// own and the first one that decodes to a valid VIN wins:
  ///   • CAN: one ISO-TP message "014 / 0: / 1: / 2:" = 49 02 01 + 17 chars
  ///     (grouped by [_messages]);
  ///   • ISO 9141 / KWP / J1850: five messages "49 02 0N" + 4 bytes, the
  ///     first padded with 00 00 00. Each message N joins the first group
  ///     still missing N.
  /// Returns null rather than a garbled VIN.
  String? _parseVin(String response) {
    final candidates = <List<int>>[];
    final kLine = <Map<int, List<int>>>[];
    for (final (hex, multiFrame) in _messages(response)) {
      if (!hex.startsWith('4902')) continue;
      final b = _hexBytes(hex.substring(4));
      if (b.isEmpty) continue;
      if (!multiFrame && b.length == 5 && b[0] >= 1 && b[0] <= 5) {
        final n = b[0];
        var group = kLine.where((g) => !g.containsKey(n)).firstOrNull;
        if (group == null) kLine.add(group = {});
        group[n] = b.sublist(1);
        continue;
      }
      // CAN: drop the item-count byte (01) that precedes the 17 chars.
      candidates.add(b[0] == 0x01 && b.length > 17 ? b.sublist(1) : b);
    }
    for (final g in kLine) {
      candidates.add([for (var n = 1; n <= 5; n++) ...?g[n]]);
    }

    for (final c in candidates) {
      var start = 0;
      while (start < c.length && c[start] == 0) {
        start++; // leading 00 padding
      }
      if (c.length - start < 17) continue;
      final vin = String.fromCharCodes(c.sublist(start, start + 17));
      if (_isValidVin(vin)) return vin;
    }
    return null;
  }

  static final _vinAlphabet = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static const _vinValues = {
    'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8,
    'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9,
    'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9,
  };
  static const _vinWeights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];

  /// 17 characters of the VIN alphabet (no I, O, Q). Where the position-9
  /// check digit is mandatory, it must also be correct:
  ///  * North America (WMI starting 1–5): 49 CFR 565.15.
  ///  * China (ISO 3780 rows L and H): GB 16735 makes position 9 a check
  ///    digit computed exactly as in 49 CFR 565.
  /// Elsewhere it is optional and not checked: Europe (ECE) leaves it free,
  /// and Korean domestic-market VINs use position 9 for a market / drive-side
  /// letter (D, P, R) rather than a check digit, so 'K' is not checked.
  static bool _isValidVin(String vin) {
    if (!_vinAlphabet.hasMatch(vin)) return false;
    // Region '0' is unassigned in ISO 3780, and a VIN of one repeated
    // character is ECU filler (e.g. all '0'), not a real VIN.
    if (vin[0] == '0' || vin.split('').toSet().length == 1) return false;
    if (!'12345LH'.contains(vin[0])) return true;
    var sum = 0;
    for (var i = 0; i < 17; i++) {
      sum += (int.tryParse(vin[i]) ?? _vinValues[vin[i]]!) * _vinWeights[i];
    }
    final r = sum % 11;
    return vin[8] == (r == 10 ? 'X' : '$r');
  }

  // ── Freeze frame (mode 02) ────────────────────────────────────────────────

  @override
  Future<Map<String, String>> getFreezeFrame() async {
    if (!_connected) return {};
    final data = <String, String>{};

    // (request, response header, label, expected data bytes, converter).
    // J1979 mode 02 requests carry a frame number after the PID ("00" = the
    // frame stored with the first confirmed DTC); strict CAN ECUs answer a
    // bare "020C" with NO DATA.
    final queries = <(String, String, String, int, String Function(List<int>))>[
      ('020C00', '420C', 'RPM',         2, (b) => '${((b[0]*256+b[1])/4).toStringAsFixed(0)} rpm'),
      ('020D00', '420D', 'Speed',        1, (b) => '${b[0]} km/h'),
      ('020500', '4205', 'Coolant',      1, (b) => '${b[0]-40}°C'),
      ('020400', '4204', 'Engine Load',  1, (b) => '${(b[0]*100/255).toStringAsFixed(1)}%'),
      ('020F00', '420F', 'Air Temp',     1, (b) => '${b[0]-40}°C'),
      ('021100', '4211', 'Throttle',     1, (b) => '${(b[0]*100/255).toStringAsFixed(1)}%'),
      ('020600', '4206', 'Fuel Trim',    1, (b) => '${((b[0]/1.28)-100).toStringAsFixed(1)}%'),
      ('020B00', '420B', 'MAP',          1, (b) => '${b[0]} kPa'),
    ];

    for (final q in queries) {
      final r = await _sendAT(q.$1, timeout: 1200);
      final raw = _bytes(r, q.$2);
      // Reply is "42 PID FRAME data…": always drop the echoed frame byte
      // (some ECUs pad the data, so the length alone can't tell).
      if (raw.isEmpty) continue;
      final b = raw.sublist(1);
      if (b.length >= q.$4) {
        data[q.$3] = q.$5(b);
      }
    }
    return data;
  }

  // ── Readiness monitors (PID 0101) ─────────────────────────────────────────

  @override
  Future<ReadinessResult> getReadinessMonitors() async {
    if (!_connected) {
      return const ReadinessResult(milOn: false, dtcCount: 0, monitors: []);
    }
    final r = await _sendAT('0101', timeout: 3000);
    // With headers off every ECU that answers (ECM, TCM, …) prints its own
    // "41 01 A B C D" line, in no guaranteed order.
    final ecus = _replyLines(r, '4101', 4);
    if (ecus.isEmpty) {
      return const ReadinessResult(milOn: false, dtcCount: 0, monitors: []);
    }

    // SAE J1979 PID 01 layout:
    //   A: bit 7 = MIL on, bits 6-0 = confirmed DTC count
    //   B: bits 0-2 = continuous monitor supported, bits 4-6 = incomplete,
    //      bit 3 = compression ignition (diesel)
    //   C: non-continuous monitor supported (bit per monitor)
    //   D: non-continuous monitor incomplete (same bit order as C)
    //
    // Merged across ECUs per J1979: MIL = OR, DTC count = sum, a monitor is
    // supported if any ECU supports it and incomplete if any ECU supporting
    // it reports it incomplete.
    //
    // Spark vs compression ignition comes from the engine ECU, taken to be
    // the one reporting the most supported monitors (B bits 0-2 + C; the
    // first line wins a tie): a TCM typically reports "components" only and
    // its bit 3 says nothing about the engine. Because C/D bits name
    // different monitors on spark and diesel engines, only ECUs of the same
    // ignition type are merged into C/D.
    int supportedCount(List<int> e) =>
        _popCount(e[1] & 0x07) + _popCount(e[2]);
    var engine = ecus.first;
    for (final e in ecus) {
      if (supportedCount(e) > supportedCount(engine)) engine = e;
    }
    final diesel = (engine[1] >> 3) & 1 == 1;

    var milOn = false;
    var dtcCount = 0;
    var contSup = 0, contInc = 0, ncSup = 0, ncInc = 0;
    for (final e in ecus) {
      milOn |= (e[0] >> 7) & 1 == 1;
      dtcCount += e[0] & 0x7F;
      contSup |= e[1] & 0x07;
      contInc |= e[1] & 0x07 & (e[1] >> 4); // incomplete only if supported
      if (((e[1] >> 3) & 1 == 1) == diesel) {
        ncSup |= e[2];
        ncInc |= e[2] & e[3];
      }
    }

    final monitors = <ReadinessMonitor>[];

    void add(String name, int supByte, int supBit, int incByte, int incBit) {
      final sup = (supByte >> supBit) & 1 == 1;
      monitors.add(ReadinessMonitor(
        name: name,
        status: !sup
            ? MonitorStatus.notApplicable
            : (incByte >> incBit) & 1 == 1
                ? MonitorStatus.notReady
                : MonitorStatus.ready,
      ));
    }

    // Continuous monitors — byte B.
    add('Misfire',          contSup, 0, contInc, 0);
    add('Fuel System',      contSup, 1, contInc, 1);
    add('Components',       contSup, 2, contInc, 2);
    // Non-continuous monitors — bytes C / D. The bits mean different
    // monitors on spark- and compression-ignition engines; null = reserved.
    const spark = [
      'Catalyst', 'Heated Catalyst', 'Evap System', 'Secondary Air',
      'A/C System', 'O2 Sensor', 'O2 Sensor Heater', 'EGR / VVT',
    ];
    const compression = [
      'NMHC Catalyst', 'NOx / SCR', null, 'Boost Pressure',
      null, 'Exhaust Gas Sensor', 'PM Filter', 'EGR / VVT',
    ];
    final names = diesel ? compression : spark;
    for (var bit = 0; bit < 8; bit++) {
      final name = names[bit];
      if (name != null) add(name, ncSup, bit, ncInc, bit);
    }

    return ReadinessResult(
      milOn: milOn,
      dtcCount: dtcCount,
      monitors: monitors,
      compressionIgnition: diesel,
    );
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  @override
  Future<void> disconnect() async {
    if (_device != null) _log.event('Disconnect requested');
    await _release(OBDConnectionState.disconnected);
  }

  /// Unexpected BLE drop after init: stop polling, fail the command in
  /// flight fast instead of letting it time out, and report [lost]. BLE
  /// objects stay until the next [connect] / [disconnect] releases them.
  void _onLinkLost() {
    if (!_connected) return;
    _log.error('BLE link lost');
    _connected = false;
    stopLiveData();
    _stalePrompt = false;
    if (!(_pending?.isCompleted ?? true)) _pending!.complete('');
    _pending = null;
    _setState(OBDConnectionState.lost);
  }

  /// Tears the session down and ends in state [end].
  Future<void> _release(OBDConnectionState end) async {
    stopLiveData();
    _notifySub?.cancel();
    _notifySub = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _initPhase = false;
    _connected = false;
    _buf.clear();
    _stalePrompt = false;
    _staleDone = null;
    _pidSupport = null;
    _pidTimeouts.clear();
    _lastData = const OBDLiveData();
    try {
      _pending?.completeError('Disconnected');
    } catch (_) {}
    _pending = null;
    try {
      await _device?.disconnect();
    } catch (e) {
      _log.error('BLE disconnect failed: $e');
    }
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _setState(end);
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

  /// [response] split into lines, spaces removed, upper-cased, empty lines
  /// dropped.
  static List<String> _lines(String response) => [
    for (final l in response.toUpperCase().split(RegExp(r'[\r\n]+')))
      if (l.replaceAll(' ', '').isNotEmpty) l.replaceAll(' ', ''),
  ];

  /// Data bytes after [header] on every line that carries at least [n] of
  /// them — one entry per answering ECU (headers off, single-frame replies
  /// such as "41 01 …"). The header must start the line or follow non-hex
  /// text ("BUS INIT: ...OK", "SEARCHING...") so it is never matched inside
  /// another reply's data.
  static List<List<int>> _replyLines(String response, String header, int n) {
    final re = RegExp('(?:^|[^0-9A-F])$header((?:[0-9A-F]{2}){$n})');
    return [
      for (final line in _lines(response))
        if (re.firstMatch(line) case final m?) _hexBytes(m.group(1)!),
    ];
  }

  static List<int> _hexBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final n = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (n == null) break;
      out.add(n);
    }
    return out;
  }

  static int _popCount(int x) {
    var n = 0;
    for (var v = x; v != 0; v &= v - 1) {
      n++;
    }
    return n;
  }

  /// Splits a headers-off reply into one hex string per ECU message, in the
  /// order the messages started. Each line is a message, except CAN ISO-TP
  /// multi-frame replies, which the ELM327 prints as a byte-count line
  /// followed by "0:", "1:", … frames that belong together:
  ///   00A
  ///   0: 43 04 01 33 03 00
  ///   1: 04 20 01 71 00 00 00
  /// Other ECUs' lines can arrive between those frames — a single frame, or
  /// a second ECU's whole ISO-TP message frame by frame. So a group stays
  /// open until its declared byte count is collected; each byte-count line
  /// opens a new group, each "N:" frame joins the oldest open group whose
  /// next frame index is N (indices wrap after F), and every other hex line
  /// is a message of its own.
  static List<(String, bool)> _messages(String response) {
    final entries = <Object>[]; // String (single line) or _IsoTpGroup
    final open = <_IsoTpGroup>[];
    final frameRe = RegExp(r'^([0-9A-F]):([0-9A-F]*)$');
    for (final line in _lines(response)) {
      final frame = frameRe.firstMatch(line);
      if (frame != null) {
        final index = int.parse(frame.group(1)!, radix: 16);
        final data = frame.group(2)!;
        // Two ECUs' frames with the same index can overtake each other.
        // Prefer the oldest group the frame fits (anything past that group's
        // declared length is only padding); a shorter group would otherwise
        // swallow and truncate another ECU's codes.
        final candidates = open.where((g) => g.frames % 16 == index);
        var group = candidates.where((g) => g.fits(data)).firstOrNull ??
            candidates.firstOrNull;
        if (group == null) {
          if (index != 0) continue; // orphan consecutive frame
          // First frame without a byte-count line: length unknown.
          group = _IsoTpGroup(0);
          open.add(group);
          entries.add(group);
        }
        group.add(data);
        if (group.complete) open.remove(group);
      } else if (RegExp(r'^[0-9A-F]{3}$').hasMatch(line)) {
        final group = _IsoTpGroup(int.parse(line, radix: 16));
        open.add(group);
        entries.add(group);
      } else if (RegExp(r'^(?:[0-9A-F]{2})+$').hasMatch(line)) {
        entries.add(line);
      }
    }
    return [
      for (final e in entries)
        if (e is _IsoTpGroup) (e.hex, true) else (e as String, false),
    ];
  }

  List<String> _parseDtcs(String response, {String header = '43'}) {
    // Ignore ELM327 error responses.
    final flat = response.replaceAll(RegExp(r'\s'), '').toUpperCase();
    const errorTokens = ['NODATA', 'UNABLETOCONNECT', 'CANERROR', 'STOPPED', 'ERROR'];
    if (errorTokens.any(flat.contains)) return [];

    final hdr = header.toUpperCase();
    final messages = _messages(response);

    final dtcs = <String>[];
    for (final (hex, multiFrame) in messages) {
      if (!hex.startsWith(hdr)) continue;
      var data = hex.substring(hdr.length);
      if (data.length < 2) continue; // e.g. "43" with nothing after it

      // CAN (ISO 15765-4) puts a DTC-count byte after the mode byte:
      //   43 02 01 33 03 00   → 2 codes
      // ISO 9141 / KWP / J1850 don't; they send fixed 6-byte payloads padded
      // with 00:
      //   43 01 33 00 00 00 00
      // A CAN payload is 1 + 2n bytes (odd), a legacy one 2n bytes (even),
      // so the length tells the two apart without knowing the protocol.
      if (multiFrame || (data.length ~/ 2).isOdd) {
        final count = int.tryParse(data.substring(0, 2), radix: 16) ?? 0;
        final end = (2 + count * 4).clamp(2, data.length);
        data = data.substring(2, end);
      }

      for (var i = 0; i + 4 <= data.length; i += 4) {
        final b1 = int.tryParse(data.substring(i, i + 2), radix: 16) ?? 0;
        final b2 = int.tryParse(data.substring(i + 2, i + 4), radix: 16) ?? 0;
        if (b1 == 0 && b2 == 0) continue;

        final prefix = ['P', 'C', 'B', 'U'][(b1 >> 6) & 3];
        // Use hex formatting: P0300 → "0300", not decimal 768 → "0768".
        final num = (b1 & 0x3F).toRadixString(16).padLeft(2, '0').toUpperCase() +
                    b2.toRadixString(16).padLeft(2, '0').toUpperCase();
        final code = '$prefix$num';
        if (!dtcs.contains(code)) dtcs.add(code);
      }
    }
    return dtcs;
  }
}

/// One CAN ISO-TP message being reassembled by [ProductionOBDAdapter._messages].
class _IsoTpGroup {
  _IsoTpGroup(this.length);

  /// Declared byte count (0 = unknown: no byte-count line was printed).
  final int length;
  final _buf = StringBuffer();
  int frames = 0;

  void add(String hex) {
    _buf.write(hex);
    frames++;
  }

  bool get complete => length > 0 && _buf.length >= length * 2;

  static final _padding = RegExp(r'^(?:(?:00)+|(?:AA)+|(?:55)+|(?:CC)+)$');

  /// Whether [hex] can be this message's next frame: everything beyond the
  /// bytes still missing must be ISO-TP filler.
  bool fits(String hex) {
    if (length == 0) return true;
    final remaining = length * 2 - _buf.length;
    if (hex.length <= remaining) return true;
    return _padding.hasMatch(hex.substring(remaining < 0 ? 0 : remaining));
  }

  /// Collected bytes, last-frame padding dropped when the length is known.
  String get hex {
    final h = _buf.toString();
    return length > 0 && h.length > length * 2 ? h.substring(0, length * 2) : h;
  }
}

// ── Visible-for-testing factory typedef ───────────────────────────────────────

@visibleForTesting
typedef OBDAdapterFactory = OBDAdapter Function();
