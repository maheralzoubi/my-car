import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'obd_adapter.dart';

export 'obd_adapter.dart' show OBDLiveData;

/// Singleton facade over [OBDAdapter].
///
/// Screens call [OBDService.instance] directly.
/// Tests replace the backing adapter via [OBDService.setTestAdapter].
class OBDService {
  OBDService._(this._adapter);

  // ── Singleton ──────────────────────────────────────────────────────────────

  static OBDService _instance = OBDService._(ProductionOBDAdapter());

  static OBDService get instance => _instance;

  /// Replaces the singleton's adapter with a test double.
  ///
  /// Call this in [setUp] / [tearDown] when writing widget/unit tests so
  /// screens never touch real Bluetooth.
  @visibleForTesting
  static void setTestAdapter(OBDAdapter adapter) {
    _instance = OBDService._(adapter);
  }

  // ── Internal state ─────────────────────────────────────────────────────────

  final OBDAdapter _adapter;
  bool _initialized = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isInitialized => _initialized;

  String? get connectedDeviceName => _adapter.connectedDeviceName;

  /// Most-recent telemetry snapshot (used as StreamBuilder initialData).
  OBDLiveData _currentData = const OBDLiveData();
  OBDLiveData get currentData => _currentData;

  /// Live telemetry stream. Emits [OBDLiveData] each time the adapter polls.
  /// Also keeps [currentData] up to date.
  Stream<OBDLiveData> get liveDataStream => _adapter.liveDataStream.map((d) {
        _currentData = d;
        return d;
      });

  /// Connects to [device] and runs the ELM327 handshake.
  ///
  /// Returns `true` on success, `false` on any failure (no throw).
  Future<bool> initialize(BluetoothDevice device) async {
    _initialized = false;
    try {
      await _adapter.connect(device);
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Starts background telemetry polling.
  void startPolling() {
    if (!_initialized) return;
    _adapter.startLiveData();
  }

  /// Stops background telemetry polling.
  void stopPolling() => _adapter.stopLiveData();

  /// Returns stored DTC codes (e.g. `["P0420", "P0171"]`).
  ///
  /// Returns `[]` when not connected or on error.
  Future<List<String>> getDtcs() async {
    if (!_initialized) return [];
    try {
      return await _adapter.getDtcs();
    } catch (_) {
      return [];
    }
  }

  /// Clears stored DTCs and resets the MIL. Returns `false` on error.
  Future<bool> clearDtcs() async {
    if (!_initialized) return false;
    try {
      return await _adapter.clearDtcs();
    } catch (_) {
      return false;
    }
  }

  /// Disconnects from the adapter and resets state.
  Future<void> disconnect() async {
    _adapter.stopLiveData();
    await _adapter.disconnect();
    _initialized = false;
  }
}
