import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'obd_adapter.dart';
import 'obd_log.dart';

export 'obd_adapter.dart'
    show
        OBDLiveData,
        ReadinessMonitor,
        ReadinessResult,
        MonitorStatus,
        OBDConnectionState,
        OBDFailureReason,
        OBDConnectException,
        OBDAdapterInfo;
export 'obd_log.dart' show OBDLog;

/// Singleton facade over [OBDAdapter].
///
/// Screens call [OBDService.instance] directly.
/// Tests replace the backing adapter via [OBDService.setTestAdapter].
class OBDService {
  OBDService._(this._adapter) {
    _adapter.connectionStateStream.listen(_onAdapterState);
  }

  // ── Singleton ──────────────────────────────────────────────────────────────

  static OBDService _instance =
      OBDService._(ProductionOBDAdapter(identifyOnFailure: true));

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

  // Whether a screen wants live polling (startPolling until stopPolling).
  // Diagnostic requests pause the adapter's timer and only resume it if this
  // is still true when they finish — so a request outliving the dashboard
  // (which calls stopPolling in dispose) can't restart polling.
  bool _pollingWanted = false;

  // Diagnostic requests currently holding polling paused. Polling resumes
  // only when the last one finishes, so overlapping requests (the dashboard
  // fetches DTCs and the VIN together) don't interleave with poll commands.
  int _pausedRequests = 0;

  final _stateController = StreamController<OBDConnectionState>.broadcast();
  OBDConnectionState _state = OBDConnectionState.disconnected;
  OBDConnectException? _lastError;
  OBDAdapterInfo? _adapterInfo;
  BluetoothDevice? _lastDevice;

  void _setState(OBDConnectionState s) {
    if (s == _state) return;
    _state = s;
    _stateController.add(s);
  }

  /// A mid-session BLE drop: stop polling and drop the now-stale snapshot
  /// so screens show "disconnected" rather than frozen values. Polling
  /// resumes on a successful [reconnect] if a screen still wants it.
  void _onAdapterState(OBDConnectionState s) {
    if (s != OBDConnectionState.lost || !_initialized) return;
    _initialized = false;
    _adapter.stopLiveData();
    _currentData = const OBDLiveData();
    _setState(OBDConnectionState.lost);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get isInitialized => _initialized;

  /// Link state as the UI should show it; [connectionStateStream] emits
  /// every change (including [OBDConnectionState.lost] on a BLE drop).
  OBDConnectionState get connectionState => _state;
  Stream<OBDConnectionState> get connectionStateStream =>
      _stateController.stream;

  /// Why the last [initialize] failed (null after a success).
  OBDConnectException? get lastError => _lastError;

  /// `ATI` / `ATDP` of the connected adapter (null until connected).
  OBDAdapterInfo? get adapterInfo => _adapterInfo;

  /// Device of the last [initialize] call, for [reconnect].
  BluetoothDevice? get lastDevice => _lastDevice;

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
  /// Returns `true` on success, `false` on any failure (no throw); the
  /// reason is then in [lastError].
  Future<bool> initialize(BluetoothDevice device) async {
    _initialized = false;
    _lastDevice = device;
    _lastError = null;
    _adapterInfo = null;
    _currentData = const OBDLiveData();
    _setState(OBDConnectionState.connecting);
    try {
      await _adapter.connect(device);
    } catch (e) {
      _lastError = e is OBDConnectException
          ? e
          : OBDConnectException(OBDFailureReason.unknown, '$e', cause: e);
      _setState(OBDConnectionState.failed);
      return false;
    }
    try {
      _adapterInfo = await _adapter.readAdapterInfo();
    } catch (_) {
      _adapterInfo = const OBDAdapterInfo();
    }
    _initialized = true;
    _setState(OBDConnectionState.connected);
    // Back after a drop with a screen still showing live data.
    if (_pollingWanted && _pausedRequests == 0) _adapter.startLiveData();
    return true;
  }

  /// Retries [initialize] on [lastDevice] (e.g. after a mid-session drop).
  Future<bool> reconnect() async {
    final device = _lastDevice;
    if (device == null) return false;
    return initialize(device);
  }

  /// Plain-text report for support: link state, adapter info, last error
  /// and the raw ELM327 traffic from [OBDLog.instance].
  String diagnosticReport() {
    final info = _adapterInfo;
    String? device;
    try {
      device = _lastDevice?.platformName;
    } catch (_) {} // test doubles may not implement it
    return OBDLog.instance.dump(header: [
      'MyCar OBD diagnostic log — ${DateTime.now().toIso8601String()}',
      'State: ${_state.name}',
      if (device != null) 'Device: "$device"',
      if (info?.version != null) 'Adapter: ${info!.version}',
      if (info?.protocol != null) 'Protocol: ${info!.protocol}',
      if (_lastError != null) 'Last error: $_lastError',
      if (_lastError?.adapterVersion != null)
        'Adapter (at failure): ${_lastError!.adapterVersion}',
    ]);
  }

  /// Starts background telemetry polling.
  ///
  /// If a diagnostic request is in flight, polling starts once it finishes.
  void startPolling() {
    if (!_initialized) return;
    _pollingWanted = true;
    if (_pausedRequests == 0) _adapter.startLiveData();
  }

  /// Stops background telemetry polling. In-flight diagnostic requests will
  /// not restart it.
  void stopPolling() {
    _pollingWanted = false;
    _adapter.stopLiveData();
  }

  /// Runs [request] with live polling paused, returning [fallback] on error.
  /// Polling resumes afterwards only if it is still wanted.
  Future<T> _withPollingPaused<T>(
    Future<T> Function() request,
    T fallback,
  ) async {
    _pausedRequests++;
    // Stop the live-data timer so its pending _sendAT calls don't
    // overwrite the Completer that the request is about to create.
    _adapter.stopLiveData();
    try {
      // Brief pause to let any in-flight poll command fully complete.
      await Future.delayed(const Duration(milliseconds: 300));
      return await request();
    } catch (_) {
      return fallback;
    } finally {
      _pausedRequests--;
      if (_pausedRequests == 0 && _pollingWanted && _initialized) {
        _adapter.startLiveData();
      }
    }
  }

  /// Returns stored DTC codes (e.g. `["P0420", "P0171"]`).
  ///
  /// Returns `[]` when not connected or on error.
  Future<List<String>> getDtcs() async {
    if (!_initialized) return [];
    return _withPollingPaused(_adapter.getDtcs, <String>[]);
  }

  /// Clears stored DTCs and resets the MIL. Returns `false` on error.
  Future<bool> clearDtcs() async {
    if (!_initialized) return false;
    return _withPollingPaused(_adapter.clearDtcs, false);
  }

  /// Sensor values captured by the ECU at the moment a fault occurred.
  Future<Map<String, String>> getFreezeFrame() async {
    if (!_initialized) return {};
    return _withPollingPaused(_adapter.getFreezeFrame, <String, String>{});
  }

  /// Emission-system readiness monitors.
  Future<ReadinessResult> getReadinessMonitors() async {
    const empty = ReadinessResult(milOn: false, dtcCount: 0, monitors: []);
    if (!_initialized) return empty;
    return _withPollingPaused(_adapter.getReadinessMonitors, empty);
  }

  /// Vehicle Identification Number (mode 09 PID 02).
  Future<String?> getVin() async {
    if (!_initialized) return null;
    return _withPollingPaused<String?>(_adapter.getVin, null);
  }

  /// Disconnects from the adapter and resets state.
  Future<void> disconnect() async {
    _pollingWanted = false;
    _adapter.stopLiveData();
    await _adapter.disconnect();
    _initialized = false;
    _adapterInfo = null;
    _setState(OBDConnectionState.disconnected);
  }
}
