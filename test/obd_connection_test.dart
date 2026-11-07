// Connection reliability of [ProductionOBDAdapter]: typed connect failures,
// adapter info (ATI / ATDP), mid-session BLE drops and the raw-traffic log.
// Driven through the simulated ELM327 in helpers/elm327_sim.dart.

import 'dart:async';
import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';
import 'package:mycar/core/services/obd_log.dart';

import 'helpers/elm327_sim.dart';

// Ford Taurus 2022: ISO 15765-4 CAN 11-bit 500k.
const _taurus = SimCar(
  protocol: '6',
  responses: {'0100': '41 00 BE 3F A8 13', '010C': '41 0C 0F A0'},
);

// Ignition off: nothing answers on any protocol.
const _off = SimCar(protocol: null, autoSearchTime: Duration(seconds: 3));

/// FFF0 device wired to [elm], except that the informational commands in
/// [info] (e.g. ATI / ATDP, which the simulator doesn't implement) are
/// answered here. [infoSent] records them.
class _InfoDevice {
  _InfoDevice(this.elm, {this.info = const {}}) {
    elm.notifications.listen(_out.add);
    device = FakeDevice([
      FakeService('fff0', [
        FakeCharacteristic(
          'fff1',
          properties: simNotifyProps,
          notifications: _out.stream,
        ),
        FakeCharacteristic('fff2', properties: simWriteProps, onWrite: _onWrite),
      ]),
    ]);
  }

  final FakeElm327 elm;
  final Map<String, String> info;
  final _out = StreamController<List<int>>.broadcast();
  final infoSent = <String>[];
  late final FakeDevice device;

  void _onWrite(List<int> bytes) {
    final cmd = utf8.decode(bytes).trim().toUpperCase();
    final reply = info[cmd];
    if (reply == null) return elm.receive(bytes);
    infoSent.add(cmd);
    Timer(const Duration(milliseconds: 20), () {
      _out.add(utf8.encode('$reply\r\r>'));
    });
  }
}

/// Runs [body] on the fake clock with an adapter of its own (so tests can
/// pick [identifyOnFailure] and a private log), then tears down.
void _run(
  SimCar car,
  void Function(Rig rig, ProductionOBDAdapter adapter, OBDLog log,
          _InfoDevice dev)
      body, {
  Map<String, String> info = const {},
  bool identifyOnFailure = false,
}) {
  fakeAsync((async) {
    final elm = FakeElm327(car);
    final dev = _InfoDevice(elm, info: info);
    final rig = Rig(async, elm, dev.device);
    final log = OBDLog();
    final adapter =
        ProductionOBDAdapter(identifyOnFailure: identifyOnFailure, log: log);
    body(rig, adapter, log, dev);
    rig.drive(adapter.disconnect());
    rig.tearDown();
  });
}

OBDConnectException _connectError(Rig rig, OBDAdapter adapter,
    [BluetoothDevice? device]) {
  try {
    rig.drive(adapter.connect(device ?? rig.device));
  } on OBDConnectException catch (e) {
    return e;
  }
  fail('connect() did not throw OBDConnectException');
}

void main() {
  // ── Typed failures ──────────────────────────────────────────────────────────

  group('connect failure reasons', () {
    test('BLE connect error → bleConnectFailed (still an Exception)', () {
      fakeAsync((async) {
        final rig = Rig(
          async,
          FakeElm327(_taurus),
          FakeDevice([], connectError: Exception('gatt 133')),
        );
        final e = _connectError(rig, rig.adapter);
        expect(e.reason, OBDFailureReason.bleConnectFailed);
        expect(e, isA<Exception>());
        expect(e.cause.toString(), contains('gatt 133'));
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
        expect(rig.device.disconnectCalls, 1);
      });
    });

    test('BLE connect timeout → bleTimeout', () {
      for (final error in <Object>[
        TimeoutException('connect'),
        FlutterBluePlusException(
          ErrorPlatform.fbp,
          'connect',
          FbpErrorCode.timeout.index,
          'Timed out after 15s',
        ),
      ]) {
        fakeAsync((async) {
          final rig = Rig(
            async,
            FakeElm327(_taurus),
            FakeDevice([], connectError: error),
          );
          expect(
            _connectError(rig, rig.adapter).reason,
            OBDFailureReason.bleTimeout,
            reason: '$error',
          );
        });
      }
    });

    test('no writable + notifiable pair (Bluetooth Classic / not an OBD '
        'adapter) → noElmCharacteristic, still a StateError', () {
      fakeAsync((async) {
        final elm = FakeElm327(_taurus);
        final rig = Rig(
          async,
          elm,
          FakeDevice([
            FakeService('180f', [
              FakeCharacteristic('2a19', properties: simNotifyProps),
            ]),
          ]),
        );
        final e = _connectError(rig, rig.adapter);
        expect(e.reason, OBDFailureReason.noElmCharacteristic);
        expect(e, isA<StateError>());
        expect(elm.commands, isEmpty);
      });
    });

    test('device that never answers AT commands → adapterNotResponding '
        'after the handshake, without the 25 s protocol search', () {
      fakeAsync((async) {
        final elm = FakeElm327(_taurus);
        // Writable + notifiable, but nothing behind it answers.
        final rig = Rig(
          async,
          elm,
          FakeDevice([
            FakeService('fff0', [
              FakeCharacteristic('fff1', properties: simNotifyProps),
              FakeCharacteristic('fff2', properties: simWriteProps),
            ]),
          ]),
        );
        final t0 = async.elapsed;
        final e = _connectError(rig, rig.adapter);
        expect(e.reason, OBDFailureReason.adapterNotResponding);
        // Four handshake timeouts (+ resyncs) ≈ 10 s, vs ≈ 36 s before.
        expect(async.elapsed - t0, lessThan(const Duration(seconds: 12)));
        expect(elm.commands, isEmpty);
        expect(rig.device.disconnectCalls, 1);
        expect(rig.adapter.isConnected, isFalse);
      });
    });

    test('ignition off → ecuNotResponding, message mentions the ignition '
        'and READY for electric/hybrid cars', () {
      _run(_off, (rig, adapter, log, dev) {
        final e = _connectError(rig, adapter);
        expect(e.reason, OBDFailureReason.ecuNotResponding);
        expect(e.message, contains('ignition'));
        expect(e.message, contains('electric/hybrid: switch to READY'));
        expect(e.adapterVersion, isNull); // identifyOnFailure is off
        expect(dev.infoSent, isEmpty);
        // NO DATA on protocol 6 → ATRV asked to confirm the car is on; the
        // simulator answers "?" (no reading) → not confirmed.
        expect(rig.elm.commands.sublist(rig.elm.commands.length - 3),
            ['ATSP0', '0100', 'ATRV']);
      });
    });

    test('car ON but silent on mode 01 (charging voltage) → '
        'noStandardObdData, with ATI version, logged in the report', () {
      const ev = SimCar(
        protocol: null,
        autoSearchTime: Duration(seconds: 3),
        adapterVoltage: '14.1V',
      );
      _run(ev, (rig, adapter, log, dev) {
        final e = _connectError(rig, adapter);
        expect(e.reason, OBDFailureReason.noStandardObdData);
        expect(e.message, isNot(contains('ignition')));
        expect(e.adapterVersion, 'ELM327 v1.5');
        expect(e.suggestsCloneAdapter, isFalse); // not an adapter problem
        expect(dev.infoSent, ['ATI']);
        expect(rig.elm.commands.last, 'ATRV');
        expect(log.dump(), contains('noStandardObdData'));
      }, info: {'ATI': 'ELM327 v1.5'}, identifyOnFailure: true);
    });
  });

  // ── Clone hint ──────────────────────────────────────────────────────────────

  group('clone adapter hint', () {
    test('failed auto search on a "v1.5" adapter reads ATI and flags it', () {
      _run(_off, (rig, adapter, log, dev) {
        final e = _connectError(rig, adapter);
        expect(dev.infoSent, ['ATI']);
        expect(e.adapterVersion, 'ELM327 v1.5');
        expect(e.suggestsCloneAdapter, isTrue);
        expect(rig.device.disconnectCalls, 1);
      }, info: {'ATI': 'ELM327 v1.5'}, identifyOnFailure: true);
    });

    test('genuine / STN version → no hint', () {
      _run(_off, (rig, adapter, log, dev) {
        final e = _connectError(rig, adapter);
        expect(e.adapterVersion, 'ELM327 v1.4b');
        expect(e.suggestsCloneAdapter, isFalse);
      }, info: {'ATI': 'ELM327 v1.4b'}, identifyOnFailure: true);
    });

    test('ATI rejected ("?") → version null, no hint', () {
      _run(_off, (rig, adapter, log, dev) {
        final e = _connectError(rig, adapter);
        expect(e.adapterVersion, isNull);
        expect(e.suggestsCloneAdapter, isFalse);
      }, identifyOnFailure: true); // simulator answers ATI with "?"
    });

    test('only an ECU failure gets the hint', () {
      expect(
        OBDConnectException(
          OBDFailureReason.adapterNotResponding,
          'x',
          adapterVersion: 'ELM327 v1.5',
        ).suggestsCloneAdapter,
        isFalse,
      );
    });

    test('isCloneVersion', () {
      expect(OBDAdapterInfo.isCloneVersion('ELM327 v1.5'), isTrue);
      expect(OBDAdapterInfo.isCloneVersion('ELM327 v2.1'), isTrue);
      expect(OBDAdapterInfo.isCloneVersion('elm327 V1.5a'), isTrue);
      expect(OBDAdapterInfo.isCloneVersion('ELM327 v1.4b'), isFalse);
      expect(OBDAdapterInfo.isCloneVersion('ELM327 v2.2'), isFalse);
      expect(OBDAdapterInfo.isCloneVersion('ELM327 v1.55'), isFalse);
      expect(OBDAdapterInfo.isCloneVersion(null), isFalse);
    });
  });

  // ── Adapter info ────────────────────────────────────────────────────────────

  group('readAdapterInfo', () {
    test('reads ATI and ATDP after the protocol is established', () {
      _run(_taurus, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        expect(dev.infoSent, isEmpty); // not part of connect()
        final info = rig.drive(adapter.readAdapterInfo());
        expect(dev.infoSent, ['ATI', 'ATDP']);
        expect(info.version, 'ELM327 v2.1');
        expect(info.protocol, 'ISO 15765-4 (CAN 11/500)');
        expect(info.looksLikeClone, isTrue);
      }, info: {
        'ATI': 'ELM327 v2.1',
        'ATDP': 'ISO 15765-4 (CAN 11/500)',
      });
    });

    test('echoed command and blank lines are stripped', () {
      _run(_taurus, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        final info = rig.drive(adapter.readAdapterInfo());
        expect(info.version, 'OBDII to RS232 Interpreter');
        expect(info.protocol, 'AUTO, ISO 9141-2');
      }, info: {
        'ATI': 'ATI\r\rOBDII to RS232 Interpreter',
        'ATDP': '\rAUTO, ISO 9141-2\r',
      });
    });

    test('unanswered / rejected → null fields', () {
      _run(_taurus, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        final info = rig.drive(adapter.readAdapterInfo());
        expect(info.version, isNull);
        expect(info.protocol, isNull);
      });
    });

    test('not connected → empty info, nothing sent', () {
      _run(_taurus, (rig, adapter, log, dev) {
        final info = rig.drive(adapter.readAdapterInfo());
        expect(info.version, isNull);
        expect(rig.elm.commands, isEmpty);
      });
    });
  });

  // ── Connection state / drops ────────────────────────────────────────────────

  group('connection state', () {
    test('connect → disconnect', () {
      _run(_taurus, (rig, adapter, log, dev) {
        final states = <OBDConnectionState>[];
        adapter.connectionStateStream.listen(states.add);
        expect(adapter.connectionState, OBDConnectionState.disconnected);

        rig.drive(adapter.connect(rig.device));
        rig.drive(adapter.disconnect());
        rig.async.flushMicrotasks();

        expect(states, [
          OBDConnectionState.connecting,
          OBDConnectionState.connected,
          OBDConnectionState.disconnected,
        ]);
      });
    });

    test('failed connect ends in failed (no transient disconnected)', () {
      _run(_off, (rig, adapter, log, dev) {
        final states = <OBDConnectionState>[];
        adapter.connectionStateStream.listen(states.add);
        _connectError(rig, adapter);
        rig.async.flushMicrotasks();
        expect(states, [
          OBDConnectionState.connecting,
          OBDConnectionState.failed,
        ]);
      });
    });

    test('BLE drop mid-session → lost, polling stops', () {
      _run(_taurus, (rig, adapter, log, dev) {
        final states = <OBDConnectionState>[];
        adapter.connectionStateStream.listen(states.add);
        rig.drive(adapter.connect(rig.device));
        adapter.startLiveData();
        rig.async.elapse(const Duration(seconds: 4)); // one poll

        rig.device.dropLink();
        rig.async.flushMicrotasks();
        expect(states.last, OBDConnectionState.lost);
        expect(adapter.isConnected, isFalse);

        // Let the poll that was running drain, then no new ones start.
        rig.async.elapse(const Duration(seconds: 30));
        final sent = rig.elm.commands.length;
        rig.async.elapse(const Duration(seconds: 30));
        expect(rig.elm.commands.length, sent);
      });
    });

    test('a request in flight when the link drops returns at once', () {
      final slow = SimCar(
        protocol: '6',
        responses: _taurus.responses,
        latencyOverrides: const {'03': Duration(seconds: 8)},
      );
      _run(slow, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        final t0 = rig.async.elapsed;
        final dtcs = adapter.getDtcs();
        rig.async.elapse(const Duration(milliseconds: 200));
        rig.device.dropLink();
        expect(rig.drive(dtcs), isEmpty);
        expect(rig.async.elapsed - t0, lessThan(const Duration(seconds: 2)));
      });
    });

    test('disconnects during the handshake are not reported as lost', () {
      _run(_taurus, (rig, adapter, log, dev) {
        final states = <OBDConnectionState>[];
        adapter.connectionStateStream.listen(states.add);
        final pending = adapter.connect(rig.device);
        rig.async.elapse(const Duration(milliseconds: 100));
        rig.device.dropLink(); // e.g. adapter power-cycling during setup
        rig.drive(pending);
        expect(states, isNot(contains(OBDConnectionState.lost)));
        expect(adapter.connectionState, OBDConnectionState.connected);
      });
    });

    test('reconnect after a drop', () {
      _run(_taurus, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        rig.device.dropLink();
        rig.async.flushMicrotasks();
        expect(adapter.connectionState, OBDConnectionState.lost);

        rig.drive(adapter.connect(rig.device));
        expect(adapter.connectionState, OBDConnectionState.connected);
        expect(adapter.isConnected, isTrue);
      });
    });
  });

  // ── Diagnostic log ──────────────────────────────────────────────────────────

  group('diagnostic log', () {
    test('records commands, raw replies with timings, and the outcome', () {
      _run(_taurus, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        final tx = log.entries.where((e) => e.kind == OBDLogKind.tx);
        expect(tx.map((e) => e.text),
            ['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6', '0100']);
        // ATE0 is still echoed: the raw reply keeps the echo and the CRs.
        final rx = log.entries.where((e) => e.kind == OBDLogKind.rx).toList();
        expect(rx.first.text, startsWith(r'ATE0\r\nOK'));
        expect(rx.first.text, matches(RegExp(r'\(\d+ ms\)$')));
        expect(rx.last.text, startsWith('4100BE3FA813')); // ATS0: no spaces
        expect(log.dump(), contains('Connected in'));
      });
    });

    test('a failed connect logs every timeout and the failure', () {
      const dead = SimCar(protocol: null, silent: {'0100'});
      _run(dead, (rig, adapter, log, dev) {
        _connectError(rig, adapter);
        final dump = log.dump();
        expect(
          RegExp(r'0100: no reply within \d+ ms').allMatches(dump).length,
          2,
        );
        expect(dump, contains('Connect failed'));
        expect(dump, contains('ecuNotResponding'));
      });
    });

    test('BLE drop is logged', () {
      _run(_taurus, (rig, adapter, log, dev) {
        rig.drive(adapter.connect(rig.device));
        rig.device.dropLink();
        rig.async.flushMicrotasks();
        expect(
          log.entries.last,
          isA<OBDLogEntry>()
              .having((e) => e.kind, 'kind', OBDLogKind.error)
              .having((e) => e.text, 'text', 'BLE link lost'),
        );
      });
    });

    test('ring buffer keeps only the newest entries', () {
      final log = OBDLog(capacity: 3);
      for (var i = 0; i < 5; i++) {
        log.tx('CMD$i');
      }
      expect(log.entries.map((e) => e.text), ['CMD2', 'CMD3', 'CMD4']);
      log.clear();
      expect(log.dump(), contains('no adapter traffic'));
    });

    test('dump: header first, control characters spelled out', () {
      final log = OBDLog()..rx('OK\r\n\x07', took: const Duration(milliseconds: 42));
      final dump = log.dump(header: ['Device: OBDII']);
      expect(dump, startsWith('Device: OBDII\n\n'));
      expect(dump, contains(r'RX OK\r\n\x07  (42 ms)'));
    });
  });
}
