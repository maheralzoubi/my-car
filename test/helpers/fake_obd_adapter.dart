import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mockito/mockito.dart';
import 'package:mycar/core/services/dtc_repository.dart';
import 'package:mycar/core/services/obd_adapter.dart';

/// Reusable mock for [BluetoothDevice].
/// [FakeOBDAdapter] ignores the device object, so this only needs to satisfy
/// the type system.
class MockBluetoothDevice extends Mock implements BluetoothDevice {}

/// A fully controllable in-memory [OBDAdapter] for use in tests.
///
/// Usage:
/// ```dart
/// final fake = FakeOBDAdapter();
/// OBDService.setTestAdapter(fake);
/// ```
class FakeOBDAdapter implements OBDAdapter {
  // ── Configuration knobs (set before the test) ────────────────────────────

  /// When true, [connect] throws so the service reports init failure.
  bool shouldFailConnect = false;

  /// When set, [connect] throws an [OBDConnectException] with this reason
  /// (takes precedence over [shouldFailConnect]).
  OBDFailureReason? failReason;

  /// `ATI` reply attached to a [failReason] failure.
  String? failAdapterVersion;

  /// Returned by [readAdapterInfo].
  OBDAdapterInfo adapterInfo = const OBDAdapterInfo();

  /// DTCs returned by [getDtcs].
  List<String> dtcsToReturn = [];

  /// When true, [clearDtcs] returns false.
  bool clearShouldFail = false;

  // ── Observation flags (check after the test) ─────────────────────────────

  bool connectCalled = false;
  bool disconnectCalled = false;
  bool startLiveDataCalled = false;
  bool stopLiveDataCalled = false;
  bool getDtcsCalled = false;
  bool clearDtcsCalled = false;

  // ── Internal state ────────────────────────────────────────────────────────

  bool _connected = false;
  final StreamController<OBDLiveData> _dataController =
      StreamController<OBDLiveData>.broadcast();
  final StreamController<OBDConnectionState> _stateController =
      StreamController<OBDConnectionState>.broadcast();
  OBDConnectionState _state = OBDConnectionState.disconnected;

  void _setState(OBDConnectionState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // ── OBDAdapter contract ───────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

  @override
  String? get connectedDeviceName => _connected ? 'FakeAdapter' : null;

  @override
  Stream<OBDLiveData> get liveDataStream => _dataController.stream;

  @override
  OBDConnectionState get connectionState => _state;

  @override
  Stream<OBDConnectionState> get connectionStateStream =>
      _stateController.stream;

  @override
  Future<void> connect(BluetoothDevice device) async {
    connectCalled = true;
    _setState(OBDConnectionState.connecting);
    if (failReason != null) {
      _setState(OBDConnectionState.failed);
      throw OBDConnectException(
        failReason!,
        'FakeOBDAdapter: simulated ${failReason!.name}',
        adapterVersion: failAdapterVersion,
      );
    }
    if (shouldFailConnect) {
      _setState(OBDConnectionState.failed);
      throw Exception('FakeOBDAdapter: simulated connection failure');
    }
    _connected = true;
    _setState(OBDConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _connected = false;
    _setState(OBDConnectionState.disconnected);
  }

  @override
  Future<OBDAdapterInfo> readAdapterInfo() async => adapterInfo;

  @override
  void startLiveData() {
    startLiveDataCalled = true;
  }

  @override
  void stopLiveData() {
    stopLiveDataCalled = true;
  }

  @override
  Future<List<String>> getDtcs() async {
    getDtcsCalled = true;
    return List<String>.from(dtcsToReturn);
  }

  @override
  Future<bool> clearDtcs() async {
    clearDtcsCalled = true;
    if (clearShouldFail) return false;
    // Like a real ECU, a successful clear erases the stored codes, so the
    // next getDtcs() returns none.
    dtcsToReturn = [];
    return true;
  }

  @override
  Future<String?> getVin() async => null;

  @override
  Future<Map<String, String>> getFreezeFrame() async => {};

  @override
  Future<ReadinessResult> getReadinessMonitors() async =>
      const ReadinessResult(milOn: false, dtcCount: 0, monitors: []);

  // ── Test helpers ──────────────────────────────────────────────────────────

  /// Push a [OBDLiveData] snapshot to listeners of [liveDataStream].
  void emitLiveData(OBDLiveData data) => _dataController.add(data);

  /// Simulates the BLE link dropping mid-session (adapter unplugged, out of
  /// range…), like [ProductionOBDAdapter] reporting [OBDConnectionState.lost].
  void simulateDrop() {
    _connected = false;
    _setState(OBDConnectionState.lost);
  }

  /// Dispose the internal stream controllers (call in tearDown).
  void dispose() {
    _dataController.close();
    _stateController.close();
  }
}

// ── FakeDtcRepository ─────────────────────────────────────────────────────────

/// A [DtcRepository] subclass that returns descriptions synchronously,
/// avoiding any rootBundle / network I/O that would hang widget tests.
class FakeDtcRepository extends DtcRepository {
  @override
  Future<String?> getDtcDescription(
    String code, {
    String languageCode = 'en',
  }) async =>
      'Description for $code';
}
