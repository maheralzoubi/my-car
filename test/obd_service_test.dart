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
  });
}

// ── Helper: adapter whose getDtcs always throws ────────────────────────────────

class _ThrowingGetDtcsAdapter extends FakeOBDAdapter {
  @override
  Future<List<String>> getDtcs() async =>
      throw Exception('simulated getDtcs error');
}
