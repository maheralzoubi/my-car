import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:mycar/core/services/obd_service.dart';

import 'helpers/fake_obd_adapter.dart';

// A minimal BluetoothDevice mock — we only need the object to exist.
class _MockDevice extends Mock implements BluetoothDevice {}

void main() {
  late FakeOBDAdapter fake;
  late _MockDevice device;

  setUp(() {
    fake = FakeOBDAdapter();
    device = _MockDevice();
    OBDService.setTestAdapter(fake);
  });

  tearDown(() {
    fake.dispose();
  });

  // ── initialize ─────────────────────────────────────────────────────────────

  group('initialize', () {
    test('returns true and sets isInitialized on success', () async {
      final ok = await OBDService.instance.initialize(device);

      expect(ok, isTrue);
      expect(OBDService.instance.isInitialized, isTrue);
      expect(fake.connectCalled, isTrue);
    });

    test('returns false and keeps isInitialized=false when adapter throws',
        () async {
      fake.shouldFailConnect = true;

      final ok = await OBDService.instance.initialize(device);

      expect(ok, isFalse);
      expect(OBDService.instance.isInitialized, isFalse);
    });
  });

  // ── startPolling / stopPolling ─────────────────────────────────────────────

  group('startPolling', () {
    test('calls adapter.startLiveData only when initialized', () async {
      // Not initialized → should not call startLiveData
      OBDService.instance.startPolling();
      expect(fake.startLiveDataCalled, isFalse);

      // Initialize first
      await OBDService.instance.initialize(device);
      OBDService.instance.startPolling();
      expect(fake.startLiveDataCalled, isTrue);
    });

    test('stopPolling calls adapter.stopLiveData', () async {
      await OBDService.instance.initialize(device);
      OBDService.instance.startPolling();
      OBDService.instance.stopPolling();
      expect(fake.stopLiveDataCalled, isTrue);
    });
  });

  // ── liveDataStream ─────────────────────────────────────────────────────────

  group('liveDataStream', () {
    test('forwards events emitted by the adapter', () async {
      await OBDService.instance.initialize(device);

      const snapshot = OBDLiveData(rpm: 2500, speedKmh: 80);
      final events = <OBDLiveData>[];
      final sub = OBDService.instance.liveDataStream.listen(events.add);

      fake.emitLiveData(snapshot);
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.rpm, 2500);
      expect(events.first.speedKmh, 80);

      await sub.cancel();
    });
  });

  // ── getDtcs ────────────────────────────────────────────────────────────────

  group('getDtcs', () {
    test('returns empty list when not initialized', () async {
      final codes = await OBDService.instance.getDtcs();
      expect(codes, isEmpty);
      expect(fake.getDtcsCalled, isFalse);
    });

    test('returns codes from adapter when initialized', () async {
      fake.dtcsToReturn = ['P0420', 'P0171', 'C1201'];
      await OBDService.instance.initialize(device);

      final codes = await OBDService.instance.getDtcs();

      expect(codes, containsAll(['P0420', 'P0171', 'C1201']));
      expect(fake.getDtcsCalled, isTrue);
    });

    test('returns empty list when adapter throws', () async {
      await OBDService.instance.initialize(device);
      // Override getDtcs to throw by creating a fresh adapter sub-class
      final throwingFake = _ThrowingGetDtcsAdapter();
      OBDService.setTestAdapter(throwingFake);
      // Re-initialize so isInitialized = true with the new adapter
      await OBDService.instance.initialize(device);

      final codes = await OBDService.instance.getDtcs();
      expect(codes, isEmpty);
      throwingFake.dispose();
    });
  });

  // ── clearDtcs ──────────────────────────────────────────────────────────────

  group('clearDtcs', () {
    test('returns false when not initialized', () async {
      final ok = await OBDService.instance.clearDtcs();
      expect(ok, isFalse);
      expect(fake.clearDtcsCalled, isFalse);
    });

    test('returns true on success', () async {
      await OBDService.instance.initialize(device);
      final ok = await OBDService.instance.clearDtcs();
      expect(ok, isTrue);
      expect(fake.clearDtcsCalled, isTrue);
    });

    test('returns false when adapter reports failure', () async {
      fake.clearShouldFail = true;
      await OBDService.instance.initialize(device);
      final ok = await OBDService.instance.clearDtcs();
      expect(ok, isFalse);
    });
  });

  // ── Polling around diagnostic requests ────────────────────────────────────
  // Each request pauses live polling. It must resume only if a screen still
  // wants it — e.g. not after the dashboard was disposed mid-request.

  group('polling around diagnostic requests', () {
    late _GatedAdapter gated;

    setUp(() async {
      gated = _GatedAdapter();
      OBDService.setTestAdapter(gated);
      await OBDService.instance.initialize(device);
    });

    tearDown(() => gated.dispose());

    final requests = <String, Future<Object?> Function()>{
      'getDtcs': () => OBDService.instance.getDtcs(),
      'clearDtcs': () => OBDService.instance.clearDtcs(),
      'getVin': () => OBDService.instance.getVin(),
      'getFreezeFrame': () => OBDService.instance.getFreezeFrame(),
      'getReadinessMonitors': () =>
          OBDService.instance.getReadinessMonitors(),
    };

    for (final entry in requests.entries) {
      test('${entry.key}: stopPolling mid-request keeps polling stopped',
          () async {
        OBDService.instance.startPolling();
        final pending = entry.value();
        await gated.untilPending(1);
        expect(gated.polling, isFalse); // paused for the request

        OBDService.instance.stopPolling(); // e.g. dashboard disposed
        final startsBefore = gated.startCount;
        gated.releaseAll();
        await pending;

        expect(gated.polling, isFalse);
        expect(gated.startCount, startsBefore);
      });

      test('${entry.key}: resumes polling that was active before', () async {
        OBDService.instance.startPolling();
        final pending = entry.value();
        await gated.untilPending(1);
        gated.releaseAll();
        await pending;
        expect(gated.polling, isTrue);
      });
    }

    test('does not start polling that was never started', () async {
      final pending = OBDService.instance.getDtcs();
      await gated.untilPending(1);
      gated.releaseAll();
      await pending;
      expect(gated.polling, isFalse);
      expect(gated.startCount, 0);
    });

    test('does not resume when the request fails after stopPolling',
        () async {
      gated.failRequests = true;
      OBDService.instance.startPolling();
      final pending = OBDService.instance.getVin();
      await gated.untilPending(1);
      OBDService.instance.stopPolling();
      gated.releaseAll();
      expect(await pending, isNull);
      expect(gated.polling, isFalse);
    });

    test('overlapping requests resume polling once, after the last one',
        () async {
      OBDService.instance.startPolling();
      final dtcs = OBDService.instance.getDtcs();
      final vin = OBDService.instance.getVin();
      await gated.untilPending(2);
      final startsBefore = gated.startCount;

      gated.release(0);
      await dtcs;
      expect(gated.polling, isFalse); // VIN request still on the bus

      gated.release(1);
      await vin;
      expect(gated.polling, isTrue);
      expect(gated.startCount, startsBefore + 1);
    });

    test('startPolling during a request is deferred until it finishes',
        () async {
      final pending = OBDService.instance.getDtcs();
      await gated.untilPending(1);
      OBDService.instance.startPolling();
      expect(gated.polling, isFalse);

      gated.releaseAll();
      await pending;
      expect(gated.polling, isTrue);
    });

    test('disconnect mid-request keeps polling stopped', () async {
      OBDService.instance.startPolling();
      final pending = OBDService.instance.getDtcs();
      await gated.untilPending(1);
      await OBDService.instance.disconnect();
      gated.releaseAll();
      await pending;
      expect(gated.polling, isFalse);
    });
  });

  // ── disconnect ─────────────────────────────────────────────────────────────

  group('disconnect', () {
    test('resets isInitialized and calls adapter.disconnect', () async {
      await OBDService.instance.initialize(device);
      expect(OBDService.instance.isInitialized, isTrue);

      await OBDService.instance.disconnect();

      expect(OBDService.instance.isInitialized, isFalse);
      expect(fake.disconnectCalled, isTrue);
      expect(fake.stopLiveDataCalled, isTrue);
    });

    test('reports disconnected and forgets the adapter info', () async {
      fake.adapterInfo = const OBDAdapterInfo(version: 'ELM327 v1.5');
      await OBDService.instance.initialize(device);
      await OBDService.instance.disconnect();
      expect(OBDService.instance.connectionState,
          OBDConnectionState.disconnected);
      expect(OBDService.instance.adapterInfo, isNull);
    });
  });

  // ── Connection state, failure reasons, adapter info ───────────────────────

  group('connection state', () {
    test('success: connecting → connected, adapter info read', () async {
      fake.adapterInfo = const OBDAdapterInfo(
        version: 'ELM327 v1.5',
        protocol: 'ISO 15765-4 (CAN 11/500)',
      );
      final states = <OBDConnectionState>[];
      final sub = OBDService.instance.connectionStateStream.listen(states.add);

      await OBDService.instance.initialize(device);
      await Future<void>.delayed(Duration.zero);

      expect(states,
          [OBDConnectionState.connecting, OBDConnectionState.connected]);
      expect(OBDService.instance.adapterInfo?.version, 'ELM327 v1.5');
      expect(OBDService.instance.adapterInfo?.protocol,
          'ISO 15765-4 (CAN 11/500)');
      expect(OBDService.instance.lastError, isNull);
      expect(OBDService.instance.lastDevice, same(device));
      await sub.cancel();
    });

    for (final reason in OBDFailureReason.values) {
      test('failure ${reason.name} is kept in lastError', () async {
        fake.failReason = reason;
        final ok = await OBDService.instance.initialize(device);
        expect(ok, isFalse);
        expect(OBDService.instance.connectionState, OBDConnectionState.failed);
        expect(OBDService.instance.lastError?.reason, reason);
      });
    }

    test('an untyped adapter error becomes reason unknown', () async {
      fake.shouldFailConnect = true;
      await OBDService.instance.initialize(device);
      expect(OBDService.instance.lastError?.reason, OBDFailureReason.unknown);
      expect(OBDService.instance.lastError?.message,
          contains('simulated connection failure'));
    });

    test('a success clears the previous error', () async {
      fake.failReason = OBDFailureReason.ecuNotResponding;
      await OBDService.instance.initialize(device);
      fake.failReason = null;
      await OBDService.instance.initialize(device);
      expect(OBDService.instance.lastError, isNull);
      expect(OBDService.instance.connectionState,
          OBDConnectionState.connected);
    });

    test('clone hint when auto search failed on a clone version', () async {
      fake
        ..failReason = OBDFailureReason.ecuNotResponding
        ..failAdapterVersion = 'ELM327 v2.1';
      await OBDService.instance.initialize(device);
      expect(OBDService.instance.lastError!.suggestsCloneAdapter, isTrue);
    });
  });

  group('mid-session drop', () {
    test('stops polling, clears isInitialized and stale data, reports lost',
        () async {
      await OBDService.instance.initialize(device);
      OBDService.instance.startPolling();
      final live = OBDService.instance.liveDataStream.listen((_) {});
      fake.emitLiveData(const OBDLiveData(rpm: 900));
      await Future<void>.delayed(Duration.zero);
      expect(OBDService.instance.currentData.rpm, 900);

      final states = <OBDConnectionState>[];
      final sub = OBDService.instance.connectionStateStream.listen(states.add);
      fake.stopLiveDataCalled = false;
      fake.simulateDrop();
      await Future<void>.delayed(Duration.zero);

      expect(states, [OBDConnectionState.lost]);
      expect(OBDService.instance.connectionState, OBDConnectionState.lost);
      expect(OBDService.instance.isInitialized, isFalse);
      expect(fake.stopLiveDataCalled, isTrue);
      expect(OBDService.instance.currentData.rpm, isNull);
      // Requests no longer reach the dead link.
      expect(await OBDService.instance.getDtcs(), isEmpty);
      expect(fake.getDtcsCalled, isFalse);
      await sub.cancel();
      await live.cancel();
    });

    test('reconnect() reuses the last device and resumes wanted polling',
        () async {
      await OBDService.instance.initialize(device);
      OBDService.instance.startPolling();
      fake.simulateDrop();
      await Future<void>.delayed(Duration.zero);

      fake
        ..connectCalled = false
        ..startLiveDataCalled = false;
      expect(await OBDService.instance.reconnect(), isTrue);
      expect(fake.connectCalled, isTrue);
      expect(OBDService.instance.isInitialized, isTrue);
      expect(fake.startLiveDataCalled, isTrue);
    });

    test('reconnect() does not start polling nobody asked for', () async {
      await OBDService.instance.initialize(device);
      fake.simulateDrop();
      await Future<void>.delayed(Duration.zero);
      expect(await OBDService.instance.reconnect(), isTrue);
      expect(fake.startLiveDataCalled, isFalse);
    });

    test('reconnect() without a previous device → false', () async {
      expect(await OBDService.instance.reconnect(), isFalse);
      expect(fake.connectCalled, isFalse);
    });

    test('a drop while not initialized is ignored', () async {
      fake.simulateDrop();
      await Future<void>.delayed(Duration.zero);
      expect(OBDService.instance.connectionState,
          OBDConnectionState.disconnected);
    });
  });

  group('diagnosticReport', () {
    test('header with state, adapter and error, then the raw log', () async {
      OBDLog.instance.clear();
      OBDLog.instance.tx('ATE0');
      fake
        ..failReason = OBDFailureReason.ecuNotResponding
        ..failAdapterVersion = 'ELM327 v1.5';
      await OBDService.instance.initialize(device);

      final report = OBDService.instance.diagnosticReport();
      expect(report, contains('State: failed'));
      expect(report, contains('ecuNotResponding'));
      expect(report, contains('Adapter (at failure): ELM327 v1.5'));
      expect(report, contains('TX ATE0'));
    });
  });
}

// ── Helper: adapter whose getDtcs always throws ────────────────────────────────

class _ThrowingGetDtcsAdapter extends FakeOBDAdapter {
  @override
  Future<List<String>> getDtcs() async =>
      throw Exception('simulated getDtcs error');
}

// ── Helper: adapter whose diagnostic requests block until released ────────────

class _GatedAdapter extends FakeOBDAdapter {
  /// Mirrors the adapter's live-data timer: on after startLiveData, off after
  /// stopLiveData.
  bool polling = false;
  int startCount = 0;

  /// When true, released requests throw instead of returning.
  bool failRequests = false;

  /// One completer per diagnostic request that reached the adapter.
  final List<Completer<void>> pending = [];

  @override
  void startLiveData() {
    super.startLiveData();
    polling = true;
    startCount++;
  }

  @override
  void stopLiveData() {
    super.stopLiveData();
    polling = false;
  }

  /// Waits (real time — OBDService sleeps 300 ms before each request) until
  /// [n] requests are blocked inside the adapter.
  Future<void> untilPending(int n) async {
    while (pending.length < n) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void release(int i) => pending[i].complete();

  void releaseAll() {
    for (final c in pending) {
      if (!c.isCompleted) c.complete();
    }
  }

  Future<T> _held<T>(Future<T> Function() body) async {
    final gate = Completer<void>();
    pending.add(gate);
    await gate.future;
    if (failRequests) throw Exception('simulated adapter error');
    return body();
  }

  @override
  Future<List<String>> getDtcs() => _held(() => super.getDtcs());

  @override
  Future<bool> clearDtcs() => _held(() => super.clearDtcs());

  @override
  Future<String?> getVin() => _held(() => super.getVin());

  @override
  Future<Map<String, String>> getFreezeFrame() =>
      _held(() => super.getFreezeFrame());

  @override
  Future<ReadinessResult> getReadinessMonitors() =>
      _held(() => super.getReadinessMonitors());
}
