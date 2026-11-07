// Unit tests for [ProductionOBDAdapter] driven by a simulated BLE ELM327.
//
// Nothing here touches a real Bluetooth stack: flutter_blue_plus classes are
// replaced by hand-written fakes, and the adapter firmware + vehicle ECU are
// modelled by [FakeElm327] / [SimCar]. Every test runs inside [fakeAsync] so
// multi-second protocol searches and timeouts elapse instantly.

import 'dart:async';

// fake_async ships with flutter_test (pinned by the SDK), so it is always
// resolvable even though it is not a direct dev_dependency.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';

import 'helpers/elm327_sim.dart';

// ── Vehicle fixtures ──────────────────────────────────────────────────────────

/// 2022 Ford Taurus: ISO 15765-4 CAN 11-bit 500 kbaud (ELM protocol 6).
const fordTaurus2022 = SimCar(
  protocol: '6',
  // Real ELM327 clones walk J1850 → ISO 9141 → KWP before reaching CAN.
  autoSearchTime: Duration(seconds: 9),
  wrongProtocolReply: 'NO DATA',
  responses: {
    // Support bitmaps advertise exactly the polled PIDs answered below
    // (plus 03 / 10 / 13 / 1C / 1F, which are never polled).
    '0100': '41 00 BF BF B9 13',
    '0120': '41 20 00 02 00 01', // 2F + next range
    '0140': '41 40 40 00 00 10', // 42, 5C
    '010C': '41 0C 1A F8', // 1726 rpm
    '010D': '41 0D 32', // 50 km/h
    '0105': '41 05 5A', // 50 °C
    '0111': '41 11 33', // 20 %
    '012F': '41 2F 80', // 50.2 %
    '0104': '41 04 40', // 25.1 %
    '0142': '41 42 38 40', // 14.4 V
    '015C': '41 5C 64', // 60 °C
    '0106': '41 06 80', // 0 %
    '0107': '41 07 85', // +3.9 %
    '0108': '41 08 7C', // -3.1 %
    '0109': '41 09 80', // 0 %
    '0114': '41 14 5A FF', // 0.45 V
    '0115': '41 15 8C FF', // 0.70 V
    '0118': '41 18 3C FF', // 0.30 V
    '010F': '41 0F 46', // 30 °C
    '010B': '41 0B 21', // 33 kPa
    '010E': '41 0E 94', // +10°
  },
);

const noCodesCan = {'03': '43 00', '07': '47 00'};

SimCar ford({Map<String, String> extra = const {}}) => SimCar(
  protocol: fordTaurus2022.protocol,
  autoSearchTime: fordTaurus2022.autoSearchTime,
  responses: {...fordTaurus2022.responses, ...extra},
);

/// 2004-era K-line car: ISO 9141-2 (protocol 3). Protocol 6 has no CAN bus
/// to talk to, so the ELM reports CAN ERROR; auto search takes ~6 s.
SimCar isoCar({Map<String, String> extra = const {}}) => SimCar(
  protocol: '3',
  wrongProtocolReply: 'CAN ERROR',
  autoSearchTime: const Duration(seconds: 6),
  ecuLatency: const Duration(milliseconds: 150),
  responses: {
    '0100': 'BUS INIT: ...OK\n41 00 BE 1F B8 10',
    '010C': '41 0C 0B B8',
    ...extra,
  },
);

const _handshake = ['ATE0', 'ATL0', 'ATS0', 'ATH0'];

void main() {
  // ── 1. Connection: protocol establishment ──────────────────────────────────

  group('connect()', () {
    test(
      'Ford Taurus 2022 (CAN 11-bit 500k): ATSP6 answers → connected fast',
      () {
        sim(fordTaurus2022, (rig) {
          final t0 = rig.async.elapsed;
          rig.connect();

          expect(rig.adapter.isConnected, isTrue);
          expect(rig.adapter.connectedDeviceName, 'OBDII');
          expect(rig.elm.commands, [..._handshake, 'ATSP6', '0100']);
          expect(rig.elm.activeProtocol, '6');
          // No 7–20 s auto search: just the 500 ms settle + a few round trips.
          expect(rig.async.elapsed - t0, lessThan(const Duration(seconds: 2)));
        }, connect: false);
      },
    );

    test('K-line car: ATSP6 → CAN ERROR, ATSP0 auto search after ~6 s → '
        'connected', () {
      sim(isoCar(), (rig) {
        final t0 = rig.async.elapsed;
        rig.connect();

        expect(rig.adapter.isConnected, isTrue);
        expect(rig.elm.commands, [
          ..._handshake,
          'ATSP6',
          '0100',
          'ATSP0',
          '0100',
        ]);
        expect(rig.elm.activeProtocol, '3');
        expect(
          rig.async.elapsed - t0,
          greaterThanOrEqualTo(const Duration(seconds: 6)),
        );

        // The search must not have been interrupted by another command.
        expect(rig.elm.commands.last, '0100');
      }, connect: false);
    });

    test('auto search that takes 18 s still succeeds (within 20 s window)', () {
      final slow = SimCar(
        protocol: '3',
        wrongProtocolReply: 'CAN ERROR',
        autoSearchTime: const Duration(seconds: 18),
        responses: isoCar().responses,
      );
      sim(slow, (rig) {
        rig.connect();
        expect(rig.adapter.isConnected, isTrue);
      }, connect: false);
    });

    test(
      'ignition off: every 0100 fails → throws StateError, BLE released',
      () {
        const off = SimCar(
          protocol: null,
          wrongProtocolReply: 'NO DATA',
          ignitionOffReply: 'UNABLE TO CONNECT',
          autoSearchTime: Duration(seconds: 12),
        );
        sim(off, (rig) {
          expect(
            () => rig.connect(),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('ignition'),
              ),
            ),
          );
          expect(rig.elm.commands, [
            ..._handshake,
            'ATSP6',
            '0100',
            'ATSP0',
            '0100',
            // NO DATA on protocol 6 (bus awake?) → battery voltage asked to
            // confirm the car is on; this clone answers "?" → not confirmed.
            'ATRV',
          ]);
          expect(rig.device.disconnectCalls, 1);
          expect(rig.adapter.isConnected, isFalse);
          expect(rig.adapter.connectedDeviceName, isNull);
        }, connect: false);
      },
    );

    // ── Car ON but silent on standard OBD-II (EVs) vs ignition off ──────────
    //   See ProductionOBDAdapter.classifySilentEcu for the rule.

    OBDConnectException failedConnect(Rig rig) {
      try {
        rig.connect();
      } on OBDConnectException catch (e) {
        return e;
      }
      fail('connect() did not throw');
    }

    test('EV that is ON, silent on mode 01 (NO DATA on protocol 6 and in the '
        'auto search) → noStandardObdData, no ignition advice, BLE released',
        () {
      const ev = SimCar(
        protocol: null,
        wrongProtocolReply: 'NO DATA',
        ignitionOffReply: 'NO DATA',
        autoSearchTime: Duration(seconds: 9),
      );
      sim(ev, (rig) {
        final e = failedConnect(rig);
        expect(e.reason, OBDFailureReason.noStandardObdData);
        expect(e.message, contains('OBD-II'));
        expect(e.message, isNot(contains('ignition')));
        expect(e.suggestsCloneAdapter, isFalse);
        // Two NO DATA replies are enough: no voltage probe needed.
        expect(rig.elm.commands,
            [..._handshake, 'ATSP6', '0100', 'ATSP0', '0100']);
        expect(rig.device.disconnectCalls, 1);
        expect(rig.adapter.connectionState, OBDConnectionState.failed);
      }, connect: false);
    });

    test('EV in READY: NO DATA on protocol 6, UNABLE TO CONNECT after the '
        'search, ATRV 13.9 V (DC-DC charging) → noStandardObdData', () {
      const ev = SimCar(
        protocol: null,
        wrongProtocolReply: 'NO DATA',
        ignitionOffReply: 'UNABLE TO CONNECT',
        autoSearchTime: Duration(seconds: 9),
        adapterVoltage: '13.9V',
      );
      sim(ev, (rig) {
        expect(failedConnect(rig).reason, OBDFailureReason.noStandardObdData);
        expect(rig.elm.commands.last, 'ATRV');
      }, connect: false);
    });

    test('ignition off, gateway ACKs (NO DATA / UNABLE TO CONNECT) but the '
        'battery rests at 12.4 V → still ecuNotResponding', () {
      const off = SimCar(
        protocol: null,
        wrongProtocolReply: 'NO DATA',
        ignitionOffReply: 'UNABLE TO CONNECT',
        adapterVoltage: '12.4V',
      );
      sim(off, (rig) {
        final e = failedConnect(rig);
        expect(e.reason, OBDFailureReason.ecuNotResponding);
        expect(e.message, contains('ignition'));
        expect(e.message, contains('READY'));
      }, connect: false);
    });

    test('ignition-off CAN car (CAN ERROR / UNABLE TO CONNECT) → '
        'ecuNotResponding, no voltage probe', () {
      const off = SimCar(
        protocol: null,
        wrongProtocolReply: 'CAN ERROR',
        ignitionOffReply: 'UNABLE TO CONNECT',
        adapterVoltage: '14.0V', // ignored: the bus is asleep
      );
      sim(off, (rig) {
        expect(failedConnect(rig).reason, OBDFailureReason.ecuNotResponding);
        expect(rig.elm.commands,
            [..._handshake, 'ATSP6', '0100', 'ATSP0', '0100']);
      }, connect: false);
    });

    test('K-line car with the ignition off (CAN ERROR / BUS INIT: ...ERROR) '
        '→ ecuNotResponding', () {
      const off = SimCar(
        protocol: null,
        wrongProtocolReply: 'CAN ERROR',
        ignitionOffReply: 'BUS INIT: ...ERROR',
        autoSearchTime: Duration(seconds: 6),
      );
      sim(off, (rig) {
        expect(failedConnect(rig).reason, OBDFailureReason.ecuNotResponding);
      }, connect: false);
    });

    test('a bus error outweighs NO DATA and a charging voltage '
        '(NO DATA / BUS INIT: ERROR / 13.9 V) → ecuNotResponding', () {
      const off = SimCar(
        protocol: null,
        wrongProtocolReply: 'NO DATA',
        ignitionOffReply: 'BUS INIT: ...ERROR',
        adapterVoltage: '13.9V',
      );
      sim(off, (rig) {
        expect(failedConnect(rig).reason, OBDFailureReason.ecuNotResponding);
        expect(rig.elm.commands, isNot(contains('ATRV')));
      }, connect: false);
    });

    group('classifySilentEcu', () {
      Future<OBDFailureReason> classify(String can, String auto,
          {double? volts}) {
        var asked = false;
        return ProductionOBDAdapter.classifySilentEcu(can, auto,
            readVoltage: () async {
          expect(asked, isFalse);
          asked = true;
          return volts;
        });
      }

      const ecu = OBDFailureReason.ecuNotResponding;
      const ev = OBDFailureReason.noStandardObdData;

      test('bus errors → ecuNotResponding whatever else is seen', () async {
        expect(await classify('CAN ERROR', 'NO DATA', volts: 14), ecu);
        expect(await classify('NO DATA', 'CANERROR', volts: 14), ecu);
        expect(await classify('NO DATA', 'BUS ERROR', volts: 14), ecu);
        expect(await classify('NO DATA', 'SEARCHING...\rBUS INIT: ...ERROR',
            volts: 14), ecu);
        expect(await classify('NO DATA', 'BUSINIT:ERROR', volts: 14), ecu);
      });

      test('no NO DATA anywhere → ecuNotResponding', () async {
        expect(await classify('', '', volts: 14), ecu); // timeouts
        expect(await classify('?', 'SEARCHING...\rUNABLE TO CONNECT',
            volts: 14), ecu);
      });

      test('NO DATA in the auto search → noStandardObdData', () async {
        expect(await classify('', 'SEARCHING...\rNO DATA'), ev);
        expect(await classify('NODATA', 'NO DATA'), ev);
        // "BUS INIT: ...OK" then silence: a K-line ECU woke up.
        expect(await classify('', 'BUS INIT: ...OK\rNO DATA'), ev);
      });

      test('NO DATA on protocol 6 only → decided by the battery voltage',
          () async {
        const auto = 'SEARCHING...\rUNABLE TO CONNECT';
        expect(await classify('NO DATA', auto, volts: 13.9), ev);
        expect(await classify('NO DATA', auto, volts: 13.0), ev);
        expect(await classify('no data', auto, volts: 12.9), ecu);
        expect(await classify('NO DATA', auto, volts: 12.4), ecu);
        expect(await classify('NO DATA', auto), ecu); // ATRV unsupported
      });
    });

    test('ignition off with CAN ERROR on protocol 6 → throws, disconnects', () {
      const off = SimCar(
        protocol: null,
        wrongProtocolReply: 'CAN ERROR',
        autoSearchTime: Duration(seconds: 3),
      );
      sim(off, (rig) {
        expect(() => rig.connect(), throwsStateError);
        expect(rig.device.disconnectCalls, 1);
        expect(rig.adapter.isConnected, isFalse);
      }, connect: false);
    });

    test(
      'ECU never answers 0100 at all → both timeouts elapse, then throws',
      () {
        const dead = SimCar(protocol: null, silent: {'0100'});
        sim(dead, (rig) {
          final t0 = rig.async.elapsed;
          expect(() => rig.connect(), throwsStateError);
          // 5 s (protocol 6) + 20 s (auto) windows were both honoured.
          expect(
            rig.async.elapsed - t0,
            greaterThanOrEqualTo(const Duration(seconds: 25)),
          );
          expect(rig.device.disconnectCalls, 1);
          expect(rig.adapter.isConnected, isFalse);
        }, connect: false);
      },
    );

    test('a failed attempt leaves the adapter reusable for a retry', () {
      fakeAsync((async) {
        // First attempt: ignition off.
        final offElm = FakeElm327(const SimCar(protocol: null));
        final first = Rig.fff0(async, offElm);
        expect(() => first.connect(), throwsStateError);
        expect(first.device.disconnectCalls, 1);

        // Ignition turned on; retry with the same adapter instance.
        final elm = FakeElm327(fordTaurus2022);
        final second = Rig.fff0(async, elm);
        second.drive(first.adapter.connect(second.device));
        expect(first.adapter.isConnected, isTrue);

        second.drive(first.adapter.disconnect());
        async.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('no writable/notifiable characteristic → throws and disconnects', () {
      fakeAsync((async) {
        final elm = FakeElm327(fordTaurus2022);
        final device = FakeDevice([
          FakeService('1800', [
            FakeCharacteristic(
              '2a00',
              properties: const CharacteristicProperties(read: true),
            ),
          ]),
          // Only a notify characteristic: no way to send commands.
          FakeService('180f', [
            FakeCharacteristic('2a19', properties: simNotifyProps),
          ]),
        ]);
        final rig = Rig(async, elm, device);
        expect(() => rig.connect(), throwsStateError);
        expect(device.disconnectCalls, 1);
        expect(rig.adapter.isConnected, isFalse);
        expect(elm.commands, isEmpty);
      });
    });

    test('BLE connect failure is rethrown and the device is released', () {
      fakeAsync((async) {
        final elm = FakeElm327(fordTaurus2022);
        final device = FakeDevice([], connectError: Exception('gatt 133'));
        final rig = Rig(async, elm, device);
        expect(() => rig.connect(), throwsException);
        expect(device.disconnectCalls, 1);
        expect(rig.adapter.isConnected, isFalse);
      });
    });

    test('FFE0 single-characteristic adapter (FFE1 write+notify)', () {
      fakeAsync((async) {
        final elm = FakeElm327(fordTaurus2022);
        final c = FakeCharacteristic(
          'ffe1',
          properties: const CharacteristicProperties(
            writeWithoutResponse: true,
            notify: true,
          ),
          onWrite: elm.receive,
          notifications: elm.notifications,
        );
        final rig = Rig(
          async,
          elm,
          FakeDevice([
            FakeService('ffe0', [c]),
          ]),
        );
        rig.connect();
        expect(rig.adapter.isConnected, isTrue);
        expect(c.notifying, isTrue);
        expect(c.writes.first, 'ATE0\r');
        rig.tearDown();
      });
    });

    test('unknown UUIDs fall back to first writable + first notifiable', () {
      fakeAsync((async) {
        final elm = FakeElm327(fordTaurus2022);
        final notify = FakeCharacteristic(
          '49535343-1e4d-4bd9-ba61-23c647249616',
          properties: simNotifyProps,
          notifications: elm.notifications,
        );
        final write = FakeCharacteristic(
          '49535343-8841-43f4-a8d4-ecbe34729bb3',
          properties: simWriteProps,
          onWrite: elm.receive,
        );
        final rig = Rig(
          async,
          elm,
          FakeDevice([
            FakeService('49535343-fe7d-4ae5-8fa9-9fafd205e455', [
              notify,
              write,
            ]),
          ]),
        );
        rig.connect();
        expect(rig.adapter.isConnected, isTrue);
        expect(write.writes, isNotEmpty);
        rig.tearDown();
      });
    });

    test('BLE drop after init clears isConnected', () {
      sim(fordTaurus2022, (rig) {
        expect(rig.adapter.isConnected, isTrue);
        rig.device.dropLink();
        rig.async.flushMicrotasks();
        expect(rig.adapter.isConnected, isFalse);
      });
    });

    test('commands are written as "<cmd>\\r"', () {
      sim(fordTaurus2022, (rig) {
        final write =
            rig.device.gattServices[1].characteristics[1] as FakeCharacteristic;
        expect(write.writes.take(6), [
          'ATE0\r',
          'ATL0\r',
          'ATS0\r',
          'ATH0\r',
          'ATSP6\r',
          '0100\r',
        ]);
      }, writeProps: simWriteNoRespProps);
    });

    test('protocol-6 0100 that times out (slow clone) does not poison the '
        'auto-search fallback with its late STOPPED/OK replies', () {
      // The ELM is still busy on protocol 6 when the 5 s window closes; the
      // ATSP0 write interrupts it ("STOPPED >"). Without stale-prompt
      // handling that STOPPED answers ATSP0, ATSP0's "OK" answers the
      // auto-search 0100 and connect wrongly fails.
      final slowCan = SimCar(
        protocol: '3',
        wrongProtocolReply: 'CAN ERROR',
        wrongProtocolDelay: const Duration(seconds: 8),
        autoSearchTime: const Duration(seconds: 6),
        responses: isoCar().responses,
      );
      sim(slowCan, (rig) {
        rig.connect();
        expect(rig.adapter.isConnected, isTrue);
        expect(rig.elm.activeProtocol, '3');
      }, connect: false);
    });

    test(
      'clone that swallows the interrupting character: the timed-out '
      '0100 is interrupted with a bare CR, so ATSP0 still arrives intact',
      () {
        // Without the CR the clone would execute "TSP0" ("?"), stay on
        // protocol 6, and the fallback 0100 would fail with CAN ERROR.
        final slowCan = SimCar(
          protocol: '3',
          wrongProtocolReply: 'CAN ERROR',
          wrongProtocolDelay: const Duration(seconds: 8),
          autoSearchTime: const Duration(seconds: 6),
          responses: isoCar().responses,
        );
        sim(
          slowCan,
          (rig) {
            rig.connect();
            expect(rig.adapter.isConnected, isTrue);
            expect(rig.elm.activeProtocol, '3');
            expect(rig.elm.commands, [
              ..._handshake,
              'ATSP6',
              '0100',
              '',
              'ATSP0',
              '0100',
            ]);
          },
          connect: false,
          dropsInterruptChar: true,
        );
      },
    );

    test('no extra CR is sent when nothing timed out', () {
      sim(
        isoCar(),
        (rig) {
          rig.connect();
          expect(rig.elm.commands, isNot(contains('')));
        },
        connect: false,
        dropsInterruptChar: true,
      );
    });
  });

  // ── 2. Transport robustness ────────────────────────────────────────────────

  group('BLE transport', () {
    test('reply split into 1-byte packets', () {
      sim(
        fordTaurus2022,
        (rig) {
          rig.connect();
          expect(rig.adapter.isConnected, isTrue);
          expect(rig.drive(rig.adapter.getVin()), isNull); // NO DATA
        },
        connect: false,
        packetSize: 1,
      );
    });

    test('reply split into 7-byte packets arriving 30 ms apart, with '
        'SEARCHING..., spaces kept (ATS0 ignored) and CR LF line endings', () {
      sim(
        isoCar(extra: noCodesCan),
        (rig) {
          rig.connect();
          expect(rig.adapter.isConnected, isTrue);
          expect(rig.elm.spaces, isTrue);
          expect(rig.drive(rig.adapter.getDtcs()), isEmpty);
        },
        connect: false,
        packetSize: 7,
        packetGap: const Duration(milliseconds: 30),
        honoursSpacesOff: false,
        forceLinefeeds: true,
      );
    });

    test('ACK of write-with-response arriving after the reply notification', () {
      // flutter_blue_plus resolves write() on the GATT write callback; the
      // ELM's reply can be delivered before that. The reply must still be
      // matched to the command.
      sim(
        ford(extra: {'03': '43 01 01 33', '07': '47 00'}),
        (rig) {
          rig.connect();
          expect(rig.adapter.isConnected, isTrue);
          // Protocol 6 must succeed directly — a lost 0100 reply would only be
          // masked by the slow ATSP0 fallback.
          expect(rig.elm.commands, [..._handshake, 'ATSP6', '0100']);
          expect(rig.drive(rig.adapter.getDtcs()), ['P0133']);
        },
        connect: false,
        writeAckDelay: const Duration(milliseconds: 80),
      );
    });

    test('concurrent requests are serialised (VIN + DTCs at once)', () {
      sim(ford(extra: {'0902': _canVin, '03': '43 01 01 33', '07': '47 00'}), (
        rig,
      ) {
        final vin = rig.adapter.getVin();
        final dtcs = rig.adapter.getDtcs();
        expect(rig.drive(vin), '1FAHP2D87GG123456');
        expect(rig.drive(dtcs), ['P0133']);
        // Each command went out only after the previous reply.
        expect(rig.elm.commands.skip(6), ['0902', '03', '07']);
        expect(rig.elm.commands, isNot(contains('STOPPED')));
      });
    });
  });

  // ── 3. Live data ───────────────────────────────────────────────────────────

  group('live data', () {
    test('decodes every PID of a poll', () {
      sim(fordTaurus2022, (rig) {
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        rig.async.elapse(const Duration(seconds: 5));
        rig.adapter.stopLiveData();
        rig.async.elapse(const Duration(seconds: 5));
        sub.cancel();

        expect(frames, hasLength(1));
        final d = frames.single;
        expect(d.rpm, 1726);
        expect(d.speedKmh, 50);
        expect(d.coolantTempC, 50);
        expect(d.throttlePct, closeTo(20.0, 0.01));
        expect(d.fuelLevelPct, closeTo(50.2, 0.01));
        expect(d.engineLoad, closeTo(25.1, 0.01));
        expect(d.batteryVoltage, 14.4);
        expect(d.oilTempC, 60);
        expect(d.fuelTrimShortPct, 0);
        expect(d.fuelTrimLongPct, closeTo(3.91, 0.01));
        expect(d.fuelTrimShortB2, closeTo(-3.13, 0.01));
        expect(d.fuelTrimLongB2, 0);
        expect(d.o2B1S1Voltage, 0.45);
        expect(d.o2B1S2Voltage, 0.70);
        expect(d.o2B2S1Voltage, 0.30);
        expect(d.intakeAirTempC, 30);
        expect(d.mapKpa, 33);
        expect(d.timingAdvanceDeg, 10);
      });
    });

    test('unsupported PIDs (NO DATA) are null; last good value is kept', () {
      // Inline-4 without bank 2 / oil temp sensors.
      final car = SimCar(
        protocol: '6',
        responses: {
          '0100': '41 00 BE 3F A8 13',
          '010C': '41 0C 0B B8',
          '010D': '41 0D 00',
        },
      );
      sim(car, (rig) {
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        rig.async.elapse(const Duration(seconds: 5));
        expect(frames, hasLength(1));
        expect(frames[0].rpm, 750);
        expect(frames[0].speedKmh, 0);
        expect(frames[0].oilTempC, isNull);
        expect(frames[0].fuelTrimShortB2, isNull);

        rig.adapter.stopLiveData();
        rig.async.elapse(const Duration(seconds: 5));
        sub.cancel();
      });
    });

    test('a PID slower than its timeout does not shift replies onto the '
        'following PIDs', () {
      final car = SimCar(
        protocol: '6',
        responses: fordTaurus2022.responses,
        // 010C answers after 2.5 s but the adapter only waits 2 s.
        latencyOverrides: const {'010C': Duration(milliseconds: 2500)},
      );
      sim(car, (rig) {
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        rig.async.elapse(const Duration(seconds: 6));
        rig.adapter.stopLiveData();
        rig.async.elapse(const Duration(seconds: 5));
        sub.cancel();

        expect(frames, isNotEmpty);
        final d = frames.first;
        expect(d.rpm, isNull);
        expect(d.speedKmh, 50, reason: '010D got 010C\'s late STOPPED reply');
        expect(d.coolantTempC, 50);
        expect(d.timingAdvanceDeg, 10);
      });
    });

    test('PID after a timeout is still read on a clone that swallows the '
        'interrupting character', () {
      final car = SimCar(
        protocol: '6',
        responses: fordTaurus2022.responses,
        latencyOverrides: const {'010C': Duration(milliseconds: 2500)},
      );
      sim(car, (rig) {
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        rig.async.elapse(const Duration(seconds: 6));
        rig.adapter.stopLiveData();
        rig.async.elapse(const Duration(seconds: 5));
        sub.cancel();

        expect(frames, isNotEmpty);
        final d = frames.first;
        expect(d.rpm, isNull);
        expect(d.speedKmh, 50, reason: '"010D" must not arrive as "10D"');
        expect(rig.elm.commands, isNot(contains('10D')));
      }, dropsInterruptChar: true);
    });

    test('no polling before connect / during init', () {
      fakeAsync((async) {
        final adapter = ProductionOBDAdapter();
        final frames = <OBDLiveData>[];
        adapter.liveDataStream.listen(frames.add);
        adapter.startLiveData();
        async.elapse(const Duration(seconds: 10));
        adapter.stopLiveData();
        expect(frames, isEmpty);
      });
    });
  });

  // ── 4. DTCs ────────────────────────────────────────────────────────────────

  group('getDtcs()', () {
    List<String> dtcs(SimCar car) {
      late List<String> out;
      sim(car, (rig) => out = rig.drive(rig.adapter.getDtcs()));
      return out;
    }

    test('returns [] when not connected', () {
      fakeAsync((async) {
        final adapter = ProductionOBDAdapter();
        late List<String> r;
        adapter.getDtcs().then((v) => r = v);
        async.flushMicrotasks();
        expect(r, isEmpty);
      });
    });

    test('CAN, no codes ("43 00" / "47 00")', () {
      expect(dtcs(ford(extra: noCodesCan)), isEmpty);
    });

    test('NO DATA for both modes', () {
      expect(dtcs(ford()), isEmpty);
    });

    test('CAN: count byte + codes, pending prefixed with "~"', () {
      expect(
        dtcs(ford(extra: {'03': '43 02 01 33 03 00', '07': '47 01 01 71'})),
        ['P0133', 'P0300', '~P0171'],
      );
    });

    test('CAN: count byte is not mistaken for a code (single P0133)', () {
      expect(dtcs(ford(extra: {'03': '43 01 01 33'})), ['P0133']);
    });

    test('CAN: line without count byte still parses (lenient ECUs)', () {
      expect(dtcs(ford(extra: {'03': '43 01 33 03 00'})), ['P0133', 'P0300']);
    });

    test('CAN: P/C/B/U letters', () {
      expect(dtcs(ford(extra: {'03': '43 04 C1 23 41 00 92 34 00 01'})), [
        'U0123',
        'C0100',
        'B1234',
        'P0001',
      ]);
    });

    test('CAN multi-frame ISO-TP reply ("00A" + "0:"/"1:" lines)', () {
      expect(
        dtcs(
          ford(
            extra: {
              '03': '00A\n0: 43 04 01 33 03 00\n1: 04 20 01 71 00 00 00',
              '07': '47 00',
            },
          ),
        ),
        ['P0133', 'P0300', 'P0420', 'P0171'],
      );
    });

    test('CAN: two ECUs answer (TCM with no codes first)', () {
      expect(dtcs(ford(extra: {'03': '43 00\n43 01 01 33', '07': '47 00'})), [
        'P0133',
      ]);
    });

    test('CAN: pending code already confirmed is not duplicated', () {
      expect(
        dtcs(ford(extra: {'03': '43 01 01 33', '07': '47 02 01 33 01 71'})),
        ['P0133', '~P0171'],
      );
    });

    test('ISO 9141: single P0133 padded with zeros', () {
      expect(dtcs(isoCar(extra: {'03': '43 01 33 00 00 00 00'})), ['P0133']);
    });

    test('ISO 9141: P0101 / P0171 (first byte 01) are not read as a count', () {
      expect(dtcs(isoCar(extra: {'03': '43 01 01 01 71 00 00'})), [
        'P0101',
        'P0171',
      ]);
    });

    test('ISO 9141: several 7-byte messages, pending mode 07', () {
      expect(
        dtcs(
          isoCar(
            extra: {
              '03': '43 01 33 03 00 04 20\n43 01 71 00 00 00 00',
              '07': '47 03 02 00 00 00 00',
            },
          ),
        ),
        ['P0133', 'P0300', 'P0420', 'P0171', '~P0302'],
      );
    });

    test('ISO 9141 / KWP: no codes', () {
      expect(
        dtcs(
          isoCar(
            extra: {'03': '43 00 00 00 00 00 00', '07': '47 00 00 00 00 00 00'},
          ),
        ),
        isEmpty,
      );
    });

    test('error tokens yield [] ("CAN ERROR", "STOPPED")', () {
      expect(dtcs(ford(extra: {'03': 'CAN ERROR', '07': 'STOPPED'})), isEmpty);
    });

    test('clearDtcs sends mode 04', () {
      sim(ford(extra: {'04': '44'}), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isTrue);
        expect(rig.elm.commands.last, '04');
      });
    });
  });

  // ── 5. VIN ─────────────────────────────────────────────────────────────────

  group('getVin()', () {
    String? vin(SimCar car) {
      String? out;
      sim(car, (rig) => out = rig.drive(rig.adapter.getVin()));
      return out;
    }

    test('CAN multi-frame (014 / 0: / 1: / 2:)', () {
      expect(vin(ford(extra: {'0902': _canVin})), '1FAHP2D87GG123456');
    });

    test('CAN multi-frame without spaces', () {
      expect(
        vin(
          ford(
            extra: {
              '0902': '014\n0:490201314641\n1:48503244383747\n2:47313233343536',
            },
          ),
        ),
        '1FAHP2D87GG123456',
      );
    });

    test('ISO 9141 / KWP: five "49 02 0N" messages', () {
      expect(
        vin(
          isoCar(
            extra: {
              '0902':
                  '49 02 01 00 00 00 31\n'
                  '49 02 02 46 41 48 50\n'
                  '49 02 03 32 44 38 37\n'
                  '49 02 04 47 47 31 32\n'
                  '49 02 05 33 34 35 36',
            },
          ),
        ),
        '1FAHP2D87GG123456',
      );
    });

    test('NO DATA → null', () {
      expect(vin(ford()), isNull);
    });

    test('truncated reply → null', () {
      expect(vin(ford(extra: {'0902': '014\n0: 49 02 01 31 46 41'})), isNull);
    });
  });

  // ── 6. Readiness monitors ──────────────────────────────────────────────────

  group('getReadinessMonitors()', () {
    ReadinessResult readiness(SimCar car) {
      late ReadinessResult out;
      sim(car, (rig) => out = rig.drive(rig.adapter.getReadinessMonitors()));
      return out;
    }

    Map<String, MonitorStatus> byName(ReadinessResult r) => {
      for (final m in r.monitors) m.name: m.status,
    };

    test('decodes SAE J1979 PID 01 (spark ignition)', () {
      // A = 0x81 → MIL on, 1 DTC
      // B = 0x27 → misfire/fuel/components supported (bits 0-2),
      //            fuel system incomplete (bit 5)
      // C = 0x65 → catalyst, evap, O2 sensor, O2 heater supported
      // D = 0x04 → evap incomplete
      final r = readiness(ford(extra: {'0101': '41 01 81 27 65 04'}));
      expect(r.milOn, isTrue);
      expect(r.dtcCount, 1);
      expect(byName(r), {
        'Misfire': MonitorStatus.ready,
        'Fuel System': MonitorStatus.notReady,
        'Components': MonitorStatus.ready,
        'Catalyst': MonitorStatus.ready,
        'Heated Catalyst': MonitorStatus.notApplicable,
        'Evap System': MonitorStatus.notReady,
        'Secondary Air': MonitorStatus.notApplicable,
        'A/C System': MonitorStatus.notApplicable,
        'O2 Sensor': MonitorStatus.ready,
        'O2 Sensor Heater': MonitorStatus.ready,
        'EGR / VVT': MonitorStatus.notApplicable,
      });
      expect(r.compressionIgnition, isFalse);
    });

    test('diesel (byte B bit 3): bytes C/D use compression-ignition monitor '
        'names, reserved bits 2 and 4 are skipped', () {
      // B = 0x0F → misfire/fuel/components supported, compression ignition
      // C = 0xFF → every bit set, including reserved bits 2 and 4
      // D = 0x42 → NOx/SCR (bit 1) and PM filter (bit 6) incomplete
      final r = readiness(ford(extra: {'0101': '41 01 00 0F FF 42'}));
      expect(r.compressionIgnition, isTrue);
      expect(r.milOn, isFalse);
      expect(byName(r), {
        'Misfire': MonitorStatus.ready,
        'Fuel System': MonitorStatus.ready,
        'Components': MonitorStatus.ready,
        'NMHC Catalyst': MonitorStatus.ready,
        'NOx / SCR': MonitorStatus.notReady,
        'Boost Pressure': MonitorStatus.ready,
        'Exhaust Gas Sensor': MonitorStatus.ready,
        'PM Filter': MonitorStatus.notReady,
        'EGR / VVT': MonitorStatus.ready,
      });
      // Monitor order stays continuous first, then by bit.
      expect(r.monitors.map((m) => m.name).take(4), [
        'Misfire',
        'Fuel System',
        'Components',
        'NMHC Catalyst',
      ]);
    });

    test('diesel without SCR / PM filter → those are N/A', () {
      // C = 0x89 → NMHC catalyst, boost pressure, EGR supported.
      final r = readiness(ford(extra: {'0101': '41 01 00 0F 89 00'}));
      expect(byName(r)['NOx / SCR'], MonitorStatus.notApplicable);
      expect(byName(r)['PM Filter'], MonitorStatus.notApplicable);
      expect(byName(r)['Boost Pressure'], MonitorStatus.ready);
      expect(byName(r).containsKey('Catalyst'), isFalse);
      expect(byName(r).containsKey('Evap System'), isFalse);
    });

    test('all complete, MIL off', () {
      final r = readiness(ford(extra: {'0101': '41 01 00 07 E5 00'}));
      expect(r.milOn, isFalse);
      expect(r.dtcCount, 0);
      expect(r.monitors.where((m) => m.isNotReady), isEmpty);
      expect(byName(r)['EGR / VVT'], MonitorStatus.ready);
    });

    test('NO DATA → empty result', () {
      final r = readiness(ford());
      expect(r.milOn, isFalse);
      expect(r.dtcCount, 0);
      expect(r.monitors, isEmpty);
    });
  });

  // ── 7. Freeze frame ────────────────────────────────────────────────────────

  group('getFreezeFrame()', () {
    test('decodes mode 02 replies (frame byte stripped), skips NO DATA', () {
      final car = ford(
        extra: {
          '020C00': '42 0C 00 1A F8',
          '020D00': '42 0D 00 32',
          '020500': '42 05 00 7B',
          '020400': '42 04 00 FF',
          '020600': '42 06 00 80',
          // 020F / 0211 / 020B → NO DATA
        },
      );
      sim(car, (rig) {
        final ff = rig.drive(rig.adapter.getFreezeFrame());
        expect(ff, {
          'RPM': '1726 rpm',
          'Speed': '50 km/h',
          'Coolant': '83°C',
          'Engine Load': '100.0%',
          'Fuel Trim': '0.0%',
        });
      });
    });

    test('requests carry frame number 00 (J1979 "02 PID FRAME")', () {
      sim(ford(), (rig) {
        final skip = rig.elm.commands.length;
        rig.drive(rig.adapter.getFreezeFrame());
        expect(rig.commandsAfter(skip), [
          '020C00',
          '020D00',
          '020500',
          '020400',
          '020F00',
          '021100',
          '020600',
          '020B00',
        ]);
      });
    });

    test('strict CAN ECU: only the 3-byte form is answered', () {
      final car = ford(
        extra: {
          '020C': 'NO DATA',
          '020D': 'NO DATA',
          '020C00': '42 0C 00 0B B8',
          '020D00': '42 0D 00 00',
        },
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getFreezeFrame()), {
          'RPM': '750 rpm',
          'Speed': '0 km/h',
        });
      });
    });

    test('padded replies: frame byte is stripped even when the length is '
        'longer than the PID needs', () {
      final car = ford(
        extra: {
          '020C00': '42 0C 00 1A F8 00 00',
          '020D00': '42 0D 00 32 00 00 00',
        },
      );
      sim(car, (rig) {
        expect(rig.drive(rig.adapter.getFreezeFrame()), {
          'RPM': '1726 rpm',
          'Speed': '50 km/h',
        });
      });
    });

    test('reply with only the frame byte (no data) is skipped', () {
      sim(ford(extra: {'020D00': '42 0D 00'}), (rig) {
        expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
      });
    });

    test('nothing stored → empty map', () {
      sim(ford(), (rig) {
        expect(rig.drive(rig.adapter.getFreezeFrame()), isEmpty);
      });
    });
  });

  // ── 8. PID support bitmaps (live poll) ─────────────────────────────────────

  group('PID support bitmaps', () {
    test('only advertised PIDs are polled; no 0120 when 0100 bit 0x20 is '
        'clear', () {
      // Inline-4, MAF only: 04 05 06 07 0C 0D 0E 0F 11 15, nothing > 0x20.
      final car = SimCar(
        protocol: '6',
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {4, 5, 6, 7, 0x0C, 0x0D, 0x0E, 0x0F, 0x11,
              0x15}),
        },
      );
      sim(car, (rig) {
        final (frames, cmds, _) = poll(rig);
        // No 0142 → the adapter's own ATRV reading is asked for instead
        // (this SimCar's ELM answers '?', so battery stays null).
        expect(cmds, [
          '010C', '010D', '0105', '0111', '0104', 'ATRV', '0106', '0107',
          '0115', '010F', '010E',
        ]);
        final d = frames.first;
        expect(d.rpm, 1726);
        expect(d.o2B1S2Voltage, 0.70);
        // Answered by the ECU but not advertised → not asked for.
        expect(d.fuelLevelPct, isNull);
        expect(d.batteryVoltage, isNull);
        expect(d.mapKpa, isNull);
        expect(d.fuelTrimShortB2, isNull);
      });
    });

    test('0120 only when 0100 says so, 0140 only when 0120 says so', () {
      final car = SimCar(
        protocol: '6',
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {0x0C, 0x0D, 0x2F}),
          '0120': _bitmap(0x20, {0x2F}), // last bit clear: no 0x41–0x60
        },
      );
      sim(car, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['0120', '010C', '010D', '012F', 'ATRV']);
        expect(frames.first.fuelLevelPct, closeTo(50.2, 0.01));
      });
    });

    test('bitmaps of all answering ECUs are ORed (TCM adds 0D)', () {
      final car = SimCar(
        protocol: '6',
        responses: {
          ...fordTaurus2022.responses,
          '0100':
              '${_bitmap(0x00, {0x05, 0x0C})}\n'
              '${_bitmap(0x00, {0x0D})}',
        },
      );
      sim(car, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['010C', '010D', '0105', 'ATRV']);
        expect(frames.first.speedKmh, 50);
      });
    });

    test('bitmaps are read once per connection, not on every poll', () {
      sim(fordTaurus2022, (rig) {
        final (frames, cmds, _) = poll(rig, n: 3);
        expect(frames.length, greaterThanOrEqualTo(3));
        expect(cmds.where((c) => c == '0120'), hasLength(1));
        expect(cmds.where((c) => c == '0140'), hasLength(1));
        expect(cmds, isNot(contains('0100')));
        expect(cmds.take(2), ['0120', '0140']);
      });
    });

    test('negative response to a bitmap request (KWP "7F 01 12" for 0120) '
        '→ that range and the ones above it are unsupported, not polled', () {
      final car = SimCar(
        protocol: '6',
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {0x0C, 0x2F}),
          '0120': '7F 01 12',
        },
      );
      sim(car, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['0120', '010C', 'ATRV']);
        expect(frames.first.batteryVoltage, isNull);
        expect(frames.first.oilTempC, isNull);
      });
    });

    test('unparseable bitmap (garbage for 0120) → that range and the ones '
        'above it are polled in full', () {
      final car = SimCar(
        protocol: '6',
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {0x0C, 0x2F}),
          '0120': '41 20 ZZ',
        },
      );
      sim(car, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['0120', '010C', '012F', '0142', '015C']);
        expect(frames.first.batteryVoltage, 14.4);
        expect(frames.first.oilTempC, 60);
      });
    });

    test('K-line car (220 ms per request): poll fits in the 3 s period, so '
        'frames arrive every 3 s', () {
      // isoCar's 0100 advertises 11 of the 18 polled PIDs and nothing above
      // 0x20; before the fix all 18 were sent (18 × 220 ms ≈ 4 s → every
      // other tick skipped, 6 s refresh).
      final car = SimCar(
        protocol: '3',
        wrongProtocolReply: 'CAN ERROR',
        autoSearchTime: const Duration(seconds: 6),
        ecuLatency: const Duration(milliseconds: 220),
        responses: isoCar().responses,
        adapterVoltage: '12.3V', // no 0142 → ATRV on every poll
      );
      sim(car, (rig) {
        final (_, cmds, at) = poll(rig, n: 3);
        expect(cmds.take(11), hasLength(11));
        expect(cmds, isNot(contains('012F')));
        expect(cmds, isNot(contains('0142')));
        expect(cmds.where((c) => c == 'ATRV'), hasLength(greaterThanOrEqualTo(3)));
        final took = at[0] - const Duration(seconds: 3);
        expect(took, lessThan(const Duration(seconds: 3)));
        expect(at[1] - at[0], const Duration(seconds: 3));
        expect(at[2] - at[1], const Duration(seconds: 3));
      });
    });

    test('support is re-read after a reconnect', () {
      fakeAsync((async) {
        final elm = FakeElm327(fordTaurus2022);
        final rig = Rig.fff0(async, elm);
        rig.connect();
        poll(rig);
        rig.drive(rig.adapter.disconnect());

        final elm2 = FakeElm327(SimCar(
          protocol: '6',
          responses: {
            ...fordTaurus2022.responses,
            '0100': _bitmap(0x00, {0x0C}),
          },
        ));
        final rig2 = Rig.fff0(async, elm2);
        rig2.drive(rig.adapter.connect(rig2.device));
        final skip = elm2.commands.length;
        rig.adapter.startLiveData();
        async.elapse(const Duration(seconds: 5));
        rig.adapter.stopLiveData();
        expect(elm2.commands.sublist(skip), ['010C', 'ATRV']);
        rig2.drive(rig.adapter.disconnect());
        async.flushTimers(flushPeriodicTimers: false);
      });
    });
  });

  // ── Wide-band O2, battery fallback, diesel PIDs ───────────────────────────

  group('extended live data', () {
    /// CAN car advertising 0C + 42 + [extra]; [replies] answer the extras.
    SimCar car(Set<int> extra, Map<String, String> replies,
        {String? adapterVoltage}) {
      final pids = {0x0C, 0x42, ...extra};
      return SimCar(
        protocol: '6',
        adapterVoltage: adapterVoltage,
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, pids),
          '0120': _bitmap(0x20, pids),
          '0140': _bitmap(0x40, pids),
          ...replies,
        },
      );
    }

    test('wide-band B1S1 on 0124 (no 0114): λ = (A*256+B)/32768', () {
      sim(car({0x24}, {'0124': '41 24 7A E1 66 66'}), (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['0120', '0140', '010C', '0142', '0124']);
        final d = frames.first;
        expect(d.lambdaB1S1, closeTo(0.96, 0.001)); // 0x7AE1 = 31457
        expect(d.o2B1S1Voltage, isNull);
      });
    });

    test('wide-band B1S1 on 0134 (current type) when 0124 is absent', () {
      sim(car({0x34}, {'0134': '41 34 80 00 80 00'}), (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['0120', '0140', '010C', '0142', '0134']);
        expect(frames.first.lambdaB1S1, 1.0);
      });
    });

    test('0124 is preferred when both 0124 and 0134 are advertised', () {
      final c = car({0x24, 0x34},
          {'0124': '41 24 88 00 66 66', '0134': '41 34 70 00 80 00'});
      sim(c, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, contains('0124'));
        expect(cmds, isNot(contains('0134')));
        expect(frames.first.lambdaB1S1, closeTo(1.0625, 1e-9));
      });
    });

    test('narrow-band 0114 advertised → wide-band PIDs are not polled', () {
      sim(car({0x14, 0x24}, {'0124': '41 24 80 00 66 66'}), (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, contains('0114'));
        expect(cmds, isNot(contains('0124')));
        expect(frames.first.o2B1S1Voltage, 0.45);
        expect(frames.first.lambdaB1S1, isNull);
      });
    });

    test('extras answered but not advertised → never asked for', () {
      final c = car({}, {
        '0124': '41 24 80 00 66 66',
        '0123': '41 23 0B B8',
        '0149': '41 49 26',
      });
      sim(c, (rig) {
        final (frames, cmds, _) = poll(rig);
        for (final p in ['0124', '0134', '0123', '0149']) {
          expect(cmds, isNot(contains(p)));
        }
        expect(frames.first.lambdaB1S1, isNull);
        expect(frames.first.fuelRailPressureKpa, isNull);
        expect(frames.first.acceleratorPedalPct, isNull);
      });
    });

    test('unparseable 0120 bitmap → the range\'s regular PIDs are polled but '
        'not the extras (they need an explicit bit)', () {
      final c = SimCar(
        protocol: '6',
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {0x0C, 0x2F}),
          '0120': '41 20 ZZ',
          '0124': '41 24 80 00 66 66',
          '0123': '41 23 0B B8',
          '0149': '41 49 26',
        },
      );
      sim(c, (rig) {
        final (_, cmds, _) = poll(rig);
        expect(cmds, ['0120', '010C', '012F', '0142', '015C']);
      });
    });

    test('diesel: 0123 rail pressure = (A*256+B)*10 kPa, 0149 pedal = '
        'A*100/255 %', () {
      // Common-rail diesel at idle: no throttle plate, no O2 / timing PIDs.
      final c = car({0x05, 0x0D, 0x23, 0x49},
          {'0123': '41 23 0B B8', '0149': '41 49 26'});
      sim(c, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, [
          '0120', '0140', '010C', '010D', '0105', '0142', '0123', '0149',
        ]);
        final d = frames.first;
        expect(d.fuelRailPressureKpa, 30000); // 0x0BB8 = 3000 → 30 MPa
        expect(d.acceleratorPedalPct, closeTo(14.90, 0.01)); // 0x26 = 38
        expect(d.throttlePct, isNull);
        expect(d.timingAdvanceDeg, isNull);
      });
    });

    test('battery: 0142 unsupported → adapter ATRV reading ("12.4V")', () {
      final c = SimCar(
        protocol: '6',
        adapterVoltage: '12.4V',
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {0x0C, 0x0D}),
        },
      );
      sim(c, (rig) {
        final (frames, cmds, _) = poll(rig);
        expect(cmds, ['010C', '010D', 'ATRV']);
        expect(frames.first.batteryVoltage, 12.4);
      });
    });

    for (final (reply, volts) in [
      ('11.8V', 11.8),
      ('12.6 V', 12.6),
      ('14,2V', 14.2), // clones with a decimal comma
      ('13V', 13.0),
    ]) {
      test('ATRV "$reply" → $volts V', () {
        final c = SimCar(
          protocol: '6',
          adapterVoltage: reply,
          responses: {'0100': _bitmap(0x00, {0x0C}), '010C': '41 0C 0B B8'},
        );
        sim(c, (rig) {
          final (frames, _, _) = poll(rig);
          expect(frames.first.batteryVoltage, closeTo(volts, 1e-9));
        });
      });
    }

    test('0142 advertised → ATRV is never sent', () {
      sim(fordTaurus2022, (rig) {
        final (frames, cmds, _) = poll(rig, n: 2);
        expect(cmds, isNot(contains('ATRV')));
        expect(frames.first.batteryVoltage, 14.4);
      });
    });

    test('clone without ATRV ("?") → null, and not asked again after two '
        'tries', () {
      final c = SimCar(
        protocol: '6',
        responses: {'0100': _bitmap(0x00, {0x0C}), '010C': '41 0C 0B B8'},
      );
      sim(c, (rig) {
        final (frames, cmds, _) = poll(rig, n: 4);
        expect(cmds.where((c) => c == 'ATRV'), hasLength(2));
        expect(frames.every((f) => f.batteryVoltage == null), isTrue);
      });
    });

    test('0142 advertised but never answered → ATRV after two timeouts', () {
      final c = SimCar(
        protocol: '6',
        adapterVoltage: '12.7V',
        silent: const {'0142'},
        responses: {
          ...fordTaurus2022.responses,
          '0100': _bitmap(0x00, {0x0C, 0x42}),
          '0120': _bitmap(0x20, {0x42}),
          '0140': _bitmap(0x40, {0x42}),
        },
      );
      sim(c, (rig) {
        final (frames, cmds, _) = poll(rig, n: 3);
        expect(frames[0].batteryVoltage, isNull);
        expect(frames[1].batteryVoltage, isNull);
        expect(frames[2].batteryVoltage, 12.7);
        expect(cmds.where((c) => c == '0142'), hasLength(2));
      });
    });

    test('ATRV fallback on a K-line car with every extra advertised still '
        'refreshes every 3 s', () {
      // 220 ms per ECU request; 7 regular PIDs + 0124 + 0123 + 0149, no
      // 0142 → ATRV (adapter-local, 15 ms). The first poll also reads the
      // 0120 / 0140 bitmaps.
      final pids = {0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x11, 0x23, 0x24,
          0x49};
      final c = SimCar(
        protocol: '3',
        wrongProtocolReply: 'CAN ERROR',
        autoSearchTime: const Duration(seconds: 6),
        ecuLatency: const Duration(milliseconds: 220),
        adapterVoltage: '12.2V',
        responses: {
          ...fordTaurus2022.responses,
          '0100': 'BUS INIT: ...OK\n${_bitmap(0x00, pids)}',
          '0120': _bitmap(0x20, pids),
          '0140': _bitmap(0x40, pids),
          '0124': '41 24 80 00 66 66',
          '0123': '41 23 0B B8',
          '0149': '41 49 26',
        },
      );
      sim(c, (rig) {
        final (frames, _, at) = poll(rig, n: 3);
        expect(at[0] - const Duration(seconds: 3),
            lessThan(const Duration(seconds: 3)));
        expect(at[2] - at[1], const Duration(seconds: 3));
        expect(frames.last.batteryVoltage, 12.2);
        expect(frames.last.lambdaB1S1, 1.0);
        expect(frames.last.fuelRailPressureKpa, 30000);
        expect(frames.last.acceleratorPedalPct, closeTo(14.90, 0.01));
      });
    });
  });

  // ── 9. clearDtcs() result ──────────────────────────────────────────────────

  group('clearDtcs() result', () {
    bool clear(String? reply) {
      late bool out;
      sim(ford(extra: {'04': ?reply}), (rig) {
        out = rig.drive(rig.adapter.clearDtcs());
        expect(rig.elm.commands.last, '04');
      });
      return out;
    }

    test('"44" → true', () => expect(clear('44'), isTrue));
    test('every ECU "44" → true', () => expect(clear('44\n44'), isTrue));
    test('NO DATA → false', () => expect(clear(null), isFalse));
    test('refusal "7F 04 22" (engine running) → false',
        () => expect(clear('7F 04 22'), isFalse));
    test('one ECU refuses, the other accepts → false',
        () => expect(clear('7F 04 22\n44'), isFalse));
    test('"7F 04 78" (response pending) then "44" → true',
        () => expect(clear('7F 04 78\n44'), isTrue));
    test('refusal without spaces (ATS0) → false',
        () => expect(clear('7F0422'), isFalse));

    test('ECU never answers (timeout) → false', () {
      sim(SimCar(protocol: '6', responses: fordTaurus2022.responses,
          silent: const {'04'}), (rig) {
        expect(rig.drive(rig.adapter.clearDtcs()), isFalse);
      });
    });

    test('not connected → false, nothing sent', () {
      fakeAsync((async) {
        late bool r;
        ProductionOBDAdapter().clearDtcs().then((v) => r = v);
        async.flushMicrotasks();
        expect(r, isFalse);
      });
    });
  });

  // ── 10. Readiness across several ECUs ──────────────────────────────────────

  group('getReadinessMonitors() with several ECUs', () {
    ReadinessResult readiness(String reply) {
      late ReadinessResult out;
      sim(ford(extra: {'0101': reply}),
          (rig) => out = rig.drive(rig.adapter.getReadinessMonitors()));
      return out;
    }

    Map<String, MonitorStatus> byName(ReadinessResult r) => {
      for (final m in r.monitors) m.name: m.status,
    };

    const ecm = '41 01 81 27 65 04'; // MIL, 1 DTC, fuel + evap incomplete
    const tcm = '41 01 00 04 00 00'; // components only

    test('TCM answers first → monitors, MIL and count still from the ECM', () {
      final first = readiness('$tcm\n$ecm');
      final alone = readiness(ecm);
      expect(first.milOn, isTrue);
      expect(first.dtcCount, 1);
      expect(first.compressionIgnition, isFalse);
      expect(byName(first), byName(alone));
    });

    test('MIL = OR, DTC count = sum over ECUs', () {
      // TCM: MIL requested, 2 DTCs, components supported + incomplete.
      final r = readiness('41 01 01 07 65 00\n41 01 82 44 00 00');
      expect(r.milOn, isTrue);
      expect(r.dtcCount, 3);
      expect(byName(r)['Components'], MonitorStatus.notReady);
      expect(byName(r)['Misfire'], MonitorStatus.ready);
    });

    test('supported if any ECU supports it; incomplete only when a '
        'supporting ECU says so', () {
      // ECU 1: catalyst supported + complete. ECU 2: catalyst NOT
      // supported but its "incomplete" bit set (meaningless) → ignored;
      // ECU 2 adds Secondary Air (bit 3) incomplete.
      final r = readiness('41 01 00 07 01 00\n41 01 00 00 08 09');
      expect(byName(r)['Catalyst'], MonitorStatus.ready);
      expect(byName(r)['Secondary Air'], MonitorStatus.notReady);
      expect(byName(r)['Evap System'], MonitorStatus.notApplicable);
    });

    test('diesel ECM after a TCM without bit 3 → compression ignition', () {
      final r = readiness('$tcm\n41 01 00 0F 89 00');
      expect(r.compressionIgnition, isTrue);
      expect(byName(r).containsKey('NMHC Catalyst'), isTrue);
      expect(byName(r).containsKey('Catalyst'), isFalse);
      expect(byName(r)['Boost Pressure'], MonitorStatus.ready);
    });

    test('lines without spaces / CR LF line endings', () {
      final r = readiness('410100040000\r\n410181276504');
      expect(r.milOn, isTrue);
      expect(r.dtcCount, 1);
      expect(byName(r)['Evap System'], MonitorStatus.notReady);
    });
  });

  // ── 11. DTC replies from several ECUs, interleaved ─────────────────────────

  group('getDtcs() interleaved ECU replies (headers off)', () {
    List<String> dtcs(String r03, [String r07 = '47 00']) {
      late List<String> out;
      sim(ford(extra: {'03': r03, '07': r07}),
          (rig) => out = rig.drive(rig.adapter.getDtcs()));
      return out;
    }

    test('single frame from the TCM between the ECM\'s First and '
        'Consecutive Frame → no code lost', () {
      expect(
        dtcs('008\n0: 43 03 00 16 03 00\n43 01 08 42\n'
            '1: 04 20 55 55 55 55 55'),
        ['P0016', 'P0300', 'P0420', 'P0842'],
      );
    });

    test('two multi-frame replies interleaved frame by frame', () {
      expect(
        dtcs('008\n0: 43 03 01 33 03 00\n00A\n0: 43 04 01 71 01 74\n'
            '1: 04 20 00 00 00 00 00\n1: 03 01 03 02 00 00 00'),
        ['P0133', 'P0300', 'P0420', 'P0171', 'P0174', 'P0301', 'P0302'],
      );
    });

    test('single frame before the multi-frame message keeps its order', () {
      expect(
        dtcs('43 01 07 41\n008\n0: 43 03 00 11 01 28\n'
            '1: 04 56 AA AA AA AA AA'),
        ['P0741', 'P0011', 'P0128', 'P0456'],
      );
    });

    test('pending mode 07 interleaved the same way', () {
      expect(
        dtcs('43 00',
            '008\n0: 47 03 01 71 01 74\n47 00\n1: 03 00 00 00 00 00 00'),
        ['~P0171', '~P0174', '~P0300'],
      );
    });
  });

  // ── 12. VIN from several ECUs + validation ─────────────────────────────────

  group('getVin() robustness', () {
    String? vin(String reply) {
      String? out;
      sim(ford(extra: {'0902': reply}),
          (rig) => out = rig.drive(rig.adapter.getVin()));
      return out;
    }

    const silverado = '1GCUYDED8LZ158342';

    test('two ECUs, ISO-TP frames interleaved (both First Frames, then the '
        'Consecutive Frames pairwise) → the VIN, not "1GCC5UDTCUDTCS3CS"', () {
      expect(vin(_interleaved(_vinFrames(silverado), _vinFrames(silverado))),
          silverado);
    });

    test('two ECUs answering one after the other', () {
      expect(vin([..._vinFrames(silverado), ..._vinFrames(silverado)]
          .join('\n')), silverado);
    });

    test('first ECU\'s VIN fails the check digit → second ECU\'s is used', () {
      const bad = '1GCUYDED0LZ158342';
      expect(vin(_interleaved(_vinFrames(bad), _vinFrames(silverado))),
          silverado);
    });

    test('wrong ISO 3779 check digit on a North-American VIN → null', () {
      expect(vin(_vinFrames('1GCUYDED0LZ158342').join('\n')), isNull);
    });

    test('check digit "X" is accepted', () {
      // 1M8GDM9AXKP042788: textbook example with check digit X.
      expect(vin(_vinFrames('1M8GDM9AXKP042788').join('\n')),
          '1M8GDM9AXKP042788');
    });

    test('non-North-American VIN: no check digit required', () {
      expect(vin(_vinFrames('WVWZZZ1KZ8W123456').join('\n')),
          'WVWZZZ1KZ8W123456');
    });

    test('I / O / Q are not VIN characters → null', () {
      expect(vin(_vinFrames('WVWZZZ1KZ8WO23456').join('\n')), isNull);
    });

    test('non-printable bytes → null, not a shortened VIN', () {
      expect(
        vin('014\n0: 49 02 01 31 47 43\n1: 55 59 44 FF 44 38 4C\n'
            '2: 5A 31 35 38 33 34 32'),
        isNull,
      );
    });

    test('K-line: two ECUs\' five-message replies interleaved', () {
      final a = _kLineVin(silverado);
      final b = _kLineVin(silverado);
      expect(
        vin([for (var i = 0; i < 5; i++) ...[a[i], b[i]]].join('\n')),
        silverado,
      );
    });
  });

  // ── 13. Recovery after a command that never gets a prompt ──────────────────

  group('recovery after a hung command', () {
    // 015C advertised by the bitmap but the clone never answers it — no
    // data and no '>' prompt.
    SimCar hangingClone({Set<String> silent = const {},
        Set<String> hangsOnce = const {},
        Map<String, Duration> latency = const {}}) => SimCar(
      protocol: '6',
      responses: fordTaurus2022.responses,
      silent: silent,
      hangsOnce: hangsOnce,
      latencyOverrides: latency,
    );

    OBDLiveData firstFrame(Rig rig) {
      final frames = <OBDLiveData>[];
      final sub = rig.adapter.liveDataStream.listen(frames.add);
      rig.adapter.startLiveData();
      final t0 = rig.async.elapsed;
      while (frames.isEmpty &&
          rig.async.elapsed - t0 < const Duration(seconds: 60)) {
        rig.async.elapse(const Duration(milliseconds: 10));
      }
      rig.adapter.stopLiveData();
      rig.async.elapse(const Duration(seconds: 30));
      sub.cancel();
      expect(frames, isNotEmpty);
      return frames.first;
    }

    test('CR that gets no prompt ends recovery: the next PID\'s real answer '
        'is kept (MG ZS: STFT after a hung 015C)', () {
      sim(hangingClone(silent: {'015C'}), (rig) {
        final skip = rig.elm.commands.length;
        final d = firstFrame(rig);
        expect(d.oilTempC, isNull);
        expect(d.fuelTrimShortPct, 0, reason: '0106 reply was discarded');
        expect(d.fuelTrimLongPct, closeTo(3.91, 0.01));
        expect(d.timingAdvanceDeg, 10);
        // One CR after the hung PID, none afterwards.
        final cmds = rig.commandsAfter(skip);
        final i = cmds.indexOf('015C');
        expect(cmds.sublist(i, i + 3), ['015C', '', '0106']);
        expect(cmds.where((c) => c.isEmpty), hasLength(1));
      });
    });

    test('a PID that never answers is dropped after two timeouts in a row, '
        'and asked again after a reconnect', () {
      sim(hangingClone(silent: {'015C'}), (rig) {
        final skip = rig.elm.commands.length;
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        while (frames.length < 4) {
          rig.async.elapse(const Duration(milliseconds: 10));
        }
        rig.adapter.stopLiveData();
        rig.async.elapse(const Duration(seconds: 30));
        sub.cancel();

        final cmds = rig.commandsAfter(skip);
        expect(cmds.where((c) => c == '015C'), hasLength(2));
        expect(frames.last.oilTempC, isNull);
        expect(frames.last.fuelTrimShortPct, 0);

        rig.drive(rig.adapter.disconnect());
        rig.connect();
        final again = rig.elm.commands.length;
        firstFrame(rig);
        expect(rig.commandsAfter(again), contains('015C'));
      });
    });

    test('a PID that times out once but then answers is kept', () {
      sim(hangingClone(hangsOnce: {'015C'}), (rig) {
        final skip = rig.elm.commands.length;
        final frames = <OBDLiveData>[];
        final sub = rig.adapter.liveDataStream.listen(frames.add);
        rig.adapter.startLiveData();
        while (frames.length < 3) {
          rig.async.elapse(const Duration(milliseconds: 10));
        }
        rig.adapter.stopLiveData();
        rig.async.elapse(const Duration(seconds: 30));
        sub.cancel();
        expect(rig.commandsAfter(skip).where((c) => c == '015C').length,
            greaterThanOrEqualTo(3));
        expect(frames.last.oilTempC, 60);
      });
    });

    test('later commands keep working too (DTCs after the poll)', () {
      sim(hangingClone(silent: {'015C'}), (rig) {
        firstFrame(rig);
        expect(rig.drive(rig.adapter.getVin()), isNull); // NO DATA, no shift
      });
    });

    test('CR repeats the hung command and it is still running when the '
        'next PID is sent → its STOPPED prompt is skipped, not taken as '
        'the answer', () {
      sim(
        hangingClone(
          hangsOnce: {'015C'},
          latency: {'015C': const Duration(milliseconds: 1500)},
        ),
        (rig) {
          final d = firstFrame(rig);
          expect(d.fuelTrimShortPct, 0);
          expect(d.fuelTrimLongPct, closeTo(3.91, 0.01));
        },
      );
    });

    test('same on a clone that swallows the interrupting character', () {
      sim(hangingClone(silent: {'015C'}), (rig) {
        final d = firstFrame(rig);
        expect(d.fuelTrimShortPct, 0);
        expect(rig.elm.commands, isNot(contains('106')));
      }, dropsInterruptChar: true);
    });

    test('notifications coalesced into large packets (STOPPED prompt and '
        'the real reply in one packet) → each prompt handled on its own', () {
      fakeAsync((async) {
        final elm = FakeElm327(hangingClone(
          hangsOnce: {'015C'},
          latency: {'015C': const Duration(milliseconds: 1500)},
        ));
        // Deliver everything the ELM sends within 150 ms as one packet.
        final coalesced = StreamController<List<int>>.broadcast();
        final pending = <int>[];
        Timer? flush;
        elm.notifications.listen((p) {
          pending.addAll(p);
          flush ??= Timer(const Duration(milliseconds: 150), () {
            coalesced.add(List.of(pending));
            pending.clear();
            flush = null;
          });
        });
        final rig = Rig(
          async,
          elm,
          FakeDevice([
            FakeService('fff0', [
              FakeCharacteristic('fff1',
                  properties: simNotifyProps,
                  notifications: coalesced.stream),
              FakeCharacteristic('fff2',
                  properties: simWriteProps, onWrite: elm.receive),
            ]),
          ]),
        );
        rig.connect();
        final d = firstFrame(rig);
        expect(d.fuelTrimShortPct, 0);
        expect(d.fuelTrimLongPct, closeTo(3.91, 0.01));
        expect(d.timingAdvanceDeg, 10);
        rig.tearDown();
      });
    });
  });
}

/// "1FAHP2D87GG123456" as a CAN ISO-TP reply: 0x14 = 20 bytes
/// (49 02 01 + 17 ASCII chars) over three frames.
const _canVin =
    '014\n'
    '0: 49 02 01 31 46 41\n'
    '1: 48 50 32 44 38 37 47\n'
    '2: 47 31 32 33 34 35 36';

/// Starts polling and collects [n] frames; returns them with the
/// commands sent and the time each frame arrived (from startLiveData).
(List<OBDLiveData>, List<String>, List<Duration>) poll(Rig rig,
    {int n = 1}) {
  final frames = <OBDLiveData>[];
  final at = <Duration>[];
  final skip = rig.elm.commands.length;
  final t0 = rig.async.elapsed;
  final sub = rig.adapter.liveDataStream.listen((d) {
    frames.add(d);
    at.add(rig.async.elapsed - t0);
  });
  rig.adapter.startLiveData();
  while (frames.length < n &&
      rig.async.elapsed - t0 < const Duration(seconds: 60)) {
    rig.async.elapse(const Duration(milliseconds: 10));
  }
  rig.adapter.stopLiveData();
  rig.async.elapse(const Duration(seconds: 30));
  sub.cancel();
  expect(frames, hasLength(greaterThanOrEqualTo(n)));
  return (frames, rig.commandsAfter(skip), at);
}

/// "41 BB AA BB CC DD" support bitmap for [base] advertising [pids]; the
/// last bit is set when any PID above the range is listed.
String _bitmap(int base, Set<int> pids) {
  final b = [0, 0, 0, 0];
  for (var i = 0; i < 32; i++) {
    final p = base + 1 + i;
    final on = i == 31 ? pids.any((q) => q > p) : pids.contains(p);
    if (on) b[i ~/ 8] |= 0x80 >> (i % 8);
  }
  String h(int x) => x.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '41 ${h(base)} ${b.map(h).join(' ')}';
}

String _hexOf(Iterable<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// [vin] as the four lines of a CAN ISO-TP 0902 reply (headers off).
List<String> _vinFrames(String vin) {
  final p = [0x49, 0x02, 0x01, ...vin.codeUnits];
  return [
    '014',
    '0: ${_hexOf(p.sublist(0, 6))}',
    '1: ${_hexOf(p.sublist(6, 13))}',
    '2: ${_hexOf(p.sublist(13, 20))}',
  ];
}

/// Two ECUs' ISO-TP replies as the ELM327 prints them when they overlap:
/// both First Frames (with their byte-count lines), then the Consecutive
/// Frames pairwise.
String _interleaved(List<String> a, List<String> b) => [
  a[0], a[1], b[0], b[1],
  for (var i = 2; i < a.length; i++) ...[a[i], b[i]],
].join('\n');

/// [vin] as five ISO 9141 / KWP "49 02 0N" messages.
List<String> _kLineVin(String vin) {
  final c = [0, 0, 0, ...vin.codeUnits];
  return [
    for (var n = 0; n < 5; n++)
      '49 02 0${n + 1} ${_hexOf(c.sublist(n * 4, n * 4 + 4))}',
  ];
}
