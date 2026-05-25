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

  const OBDLiveData({
    this.rpm,
    this.speedKmh,
    this.coolantTempC,
    this.throttlePct,
    this.fuelLevelPct,
    this.engineLoad,
  });
}

// ── Abstract contract (testable) ──────────────────────────────────────────────

abstract class OBDAdapter {
  bool get isConnected;
  Stream<OBDLiveData> get liveDataStream;

  Future<void> connect(BluetoothDevice device);
  Future<void> disconnect();

  void startLiveData();
  void stopLiveData();

  Future<List<String>> getDtcs();
  Future<bool> clearDtcs();
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

  // ── OBDAdapter API ─────────────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

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
    final b = _bytes(await _query('0111'), '4111');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  Future<double?> _fuel() async {
    final b = _bytes(await _query('012F'), '412F');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  Future<double?> _load() async {
    final b = _bytes(await _query('0104'), '4104');
    return b.isNotEmpty ? b[0] * 100 / 255 : null;
  }

  // ── Live data ──────────────────────────────────────────────────────────────

  @override
  void startLiveData() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 2),
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
    final snapshot = OBDLiveData(
      rpm:          await _rpm(),
      speedKmh:     await _speed(),
      coolantTempC: await _coolant(),
      throttlePct:  await _throttle(),
      fuelLevelPct: await _fuel(),
      engineLoad:   await _load(),
    );
    if (!_dataController.isClosed) _dataController.add(snapshot);
  }

  // ── DTCs ───────────────────────────────────────────────────────────────────

  @override
  Future<List<String>> getDtcs() async {
    if (!_connected) return [];
    final r = await _sendAT('03', timeout: 10000);
    return _parseDtcs(r);
  }

  @override
  Future<bool> clearDtcs() async {
    if (!_connected) return false;
    await _sendAT('04', timeout: 5000);
    return true;
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

  List<String> _parseDtcs(String response) {
    final clean = response.replaceAll(' ', '').toUpperCase();
    final dtcs = <String>[];
    final idx = clean.indexOf('43');
    if (idx == -1) return dtcs;
    final data = clean.substring(idx + 2);
    for (var i = 0; i + 3 < data.length; i += 4) {
      final b1 = int.tryParse(data.substring(i, i + 2), radix: 16) ?? 0;
      final b2 = int.tryParse(data.substring(i + 2, i + 4), radix: 16) ?? 0;
      if (b1 == 0 && b2 == 0) continue;
      final prefix = ['P', 'C', 'B', 'U'][(b1 >> 6) & 3];
      final num = ((b1 & 0x3F) << 8 | b2).toString().padLeft(4, '0');
      dtcs.add('$prefix$num');
    }
    return dtcs;
  }
}

// ── Visible-for-testing factory typedef ───────────────────────────────────────

@visibleForTesting
typedef OBDAdapterFactory = OBDAdapter Function();
