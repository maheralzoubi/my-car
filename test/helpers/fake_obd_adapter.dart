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

  // ── OBDAdapter contract ───────────────────────────────────────────────────

  @override
  bool get isConnected => _connected;

  @override
  Stream<OBDLiveData> get liveDataStream => _dataController.stream;

  @override
  Future<void> connect(BluetoothDevice device) async {
    connectCalled = true;
    if (shouldFailConnect) {
      throw Exception('FakeOBDAdapter: simulated connection failure');
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _connected = false;
  }

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
    return !clearShouldFail;
  }

  // ── Test helpers ──────────────────────────────────────────────────────────

  /// Push a [OBDLiveData] snapshot to listeners of [liveDataStream].
  void emitLiveData(OBDLiveData data) => _dataController.add(data);

  /// Dispose the internal stream controller (call in tearDown).
  void dispose() => _dataController.close();
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
