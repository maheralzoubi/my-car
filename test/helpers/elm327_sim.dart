// Simulated BLE ELM327 adapter + vehicle ECU for driving [ProductionOBDAdapter]
// in tests without real Bluetooth. Shared by test/obd_adapter_test.dart and
// the per-vehicle suites under test/vehicles/.
//
// [SimCar] models what the car's ECU(s) answer; [FakeElm327] models the
// adapter firmware (echo, ATS0/ATL0 formatting, protocol search, STOPPED on
// interrupt, packet splitting); [sim] wires both to a [ProductionOBDAdapter]
// inside [fakeAsync] so multi-second searches elapse instantly.

import 'dart:async';
import 'dart:convert';

// fake_async ships with flutter_test (pinned by the SDK), so it is always
// resolvable even though it is not a direct dev_dependency.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycar/core/services/obd_adapter.dart';

// ── Simulated vehicle ─────────────────────────────────────────────────────────

/// What the car's ECU(s) do. Responses are written the way an ELM327 prints
/// them by default (spaces between bytes, one ECU message per line, '\n'
/// separating lines); the simulator applies ATS0 / ATL0 formatting itself.
class SimCar {
  const SimCar({
    this.protocol,
    this.responses = const {},
    this.ecuLatency = const Duration(milliseconds: 60),
    this.latencyOverrides = const {},
    this.autoSearchTime = const Duration(seconds: 7),
    this.wrongProtocolReply = 'NO DATA',
    this.wrongProtocolDelay = const Duration(milliseconds: 300),
    this.ignitionOffReply = 'UNABLE TO CONNECT',
    this.silent = const {},
    this.hangsOnce = const {},
    this.adapterVoltage,
  });

  /// ELM327 protocol number the ECU talks (e.g. '6' = ISO 15765-4 CAN
  /// 11-bit 500k, '3' = ISO 9141-2). null → ignition off / ECU silent.
  final String? protocol;

  /// OBD request (e.g. '010C') → ECU reply. Missing → 'NO DATA'.
  final Map<String, String> responses;

  final Duration ecuLatency;
  final Map<String, Duration> latencyOverrides;

  /// How long ATSP0 auto-detect walks the protocol list before answering.
  final Duration autoSearchTime;

  /// Printed when an OBD request is sent on a protocol the car doesn't use.
  final String wrongProtocolReply;
  final Duration wrongProtocolDelay;

  /// Printed at the end of a failed auto search.
  final String ignitionOffReply;

  /// Requests the adapter never answers at all (forces adapter timeouts).
  final Set<String> silent;

  /// Requests that hang (no reply, no prompt) the first time they are
  /// received and are answered normally after that — e.g. when an idle
  /// ELM327 repeats them on a bare CR.
  final Set<String> hangsOnce;

  /// What the adapter prints for ATRV (its own pin-16 voltage reading, e.g.
  /// '12.4V'). null → '?', like clones that don't implement ATRV.
  final String? adapterVoltage;

  String answer(String cmd) => responses[cmd] ?? 'NO DATA';
  Duration latency(String cmd) => latencyOverrides[cmd] ?? ecuLatency;
}

// ── Simulated ELM327 firmware ─────────────────────────────────────────────────

class FakeElm327 {
  FakeElm327(
    this.car, {
    this.packetSize = 20,
    this.packetGap = Duration.zero,
    this.honoursSpacesOff = true,
    this.forceLinefeeds = false,
    this.dropsInterruptChar = false,
  });

  final SimCar car;

  /// BLE notification payload size (20 = default ATT MTU of 23 - 3).
  final int packetSize;

  /// Delay between consecutive notification packets of one reply.
  final Duration packetGap;

  /// Some clones ignore ATS0 and keep printing spaces.
  final bool honoursSpacesOff;

  /// Some clones ignore ATL0 and keep sending CR LF.
  final bool forceLinefeeds;

  /// Some clones discard the character that interrupts a busy command, so
  /// "ATSP0" sent to a busy adapter is executed as "TSP0".
  final bool dropsInterruptChar;

  static const _atDelay = Duration(milliseconds: 15);

  bool echo = true;
  bool spaces = true;
  bool linefeeds = true;
  String selectedProtocol = '0';
  String? activeProtocol;

  /// Every command received, in order, without the trailing CR (a bare CR
  /// is recorded as '').
  final commands = <String>[];
  String? _last;

  final _out = StreamController<List<int>>.broadcast();
  Stream<List<int>> get notifications => _out.stream;

  Timer? _busy;
  final _hung = <String>{};

  String get _eol => (linefeeds || forceLinefeeds) ? '\r\n' : '\r';

  void receive(List<int> bytes) {
    var text = utf8.decode(bytes);

    // A real ELM327 aborts an in-flight OBD request when any new character
    // arrives, prints STOPPED and a prompt, then handles the new command.
    final wasBusy = _busy?.isActive ?? false;
    if (wasBusy) {
      _busy!.cancel();
      _send('STOPPED$_eol$_eol>');
      if (dropsInterruptChar) text = text.substring(1);
    }
    _busy = null;

    var cmd = text.replaceAll('\r', '').trim().toUpperCase();
    commands.add(cmd);
    if (cmd.isEmpty) {
      // A CR that interrupted a busy command just ends that line; on an idle
      // ELM327 a bare CR repeats the previous command.
      if (wasBusy || _last == null) return;
      cmd = _last!;
    }
    _last = cmd;

    final prefix = echo ? '$cmd$_eol' : '';
    if (cmd.startsWith('AT')) {
      final reply = _at(cmd);
      Timer(_atDelay, () => _send('$prefix$reply$_eol$_eol>'));
      return;
    }
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(cmd)) {
      Timer(_atDelay, () => _send('$prefix?$_eol$_eol>')); // e.g. "TSP0"
      return;
    }
    _obd(cmd, prefix);
  }

  String _at(String cmd) {
    switch (cmd) {
      case 'ATZ':
        return 'ELM327 v1.5';
      case 'ATE0':
        echo = false;
        return 'OK';
      case 'ATE1':
        echo = true;
        return 'OK';
      case 'ATL0':
        linefeeds = false;
        return 'OK';
      case 'ATS0':
        if (honoursSpacesOff) spaces = false;
        return 'OK';
      case 'ATH0':
        return 'OK';
      case 'ATDPN':
        return activeProtocol ?? 'A0';
      case 'ATRV':
        return car.adapterVoltage ?? '?';
    }
    if (cmd.startsWith('ATSP') && cmd.length == 5) {
      selectedProtocol = cmd.substring(4);
      activeProtocol = null;
      return 'OK';
    }
    return '?';
  }

  void _obd(String cmd, String prefix) {
    if (car.silent.contains(cmd) ||
        (car.hangsOnce.contains(cmd) && _hung.add(cmd))) {
      if (prefix.isNotEmpty) _send(prefix);
      return;
    }

    if (activeProtocol != null) {
      _reply(prefix, car.latency(cmd), car.answer(cmd));
      return;
    }

    if (selectedProtocol == '0') {
      // Auto search: "SEARCHING..." straight away, the result much later.
      _send('${prefix}SEARCHING...$_eol');
      _busy = Timer(car.autoSearchTime, () {
        if (car.protocol == null) {
          _send('${_format(car.ignitionOffReply)}$_eol$_eol>');
        } else {
          activeProtocol = car.protocol;
          _send('${_format(car.answer(cmd))}$_eol$_eol>');
        }
      });
      return;
    }

    if (selectedProtocol == car.protocol) {
      _reply(
        prefix,
        car.latency(cmd),
        car.answer(cmd),
        onDone: () => activeProtocol = car.protocol,
      );
    } else {
      _reply(prefix, car.wrongProtocolDelay, car.wrongProtocolReply);
    }
  }

  void _reply(
    String prefix,
    Duration delay,
    String body, {
    void Function()? onDone,
  }) {
    _busy = Timer(delay, () {
      onDone?.call();
      _send('$prefix${_format(body)}$_eol$_eol>');
    });
  }

  String _format(String body) {
    final lines = body
        .split('\n')
        .map((l) => spaces ? l : l.replaceAll(' ', ''));
    return lines.join(_eol);
  }

  /// Splits [text] into BLE-sized notification packets.
  void _send(String text) {
    final bytes = utf8.encode(text);
    final packets = <List<int>>[
      for (var i = 0; i < bytes.length; i += packetSize)
        bytes.sublist(i, (i + packetSize).clamp(0, bytes.length)),
    ];
    if (packetGap == Duration.zero) {
      packets.forEach(_out.add);
      return;
    }
    for (var i = 0; i < packets.length; i++) {
      final p = packets[i];
      Timer(packetGap * i, () => _out.add(p));
    }
  }
}

// ── flutter_blue_plus fakes ───────────────────────────────────────────────────

class FakeCharacteristic implements BluetoothCharacteristic {
  FakeCharacteristic(
    String uuid, {
    this.properties = const CharacteristicProperties(),
    this.onWrite,
    Stream<List<int>>? notifications,
    this.writeAckDelay = Duration.zero,
  }) : _uuid = Guid(uuid),
       _notifications = notifications ?? const Stream.empty();

  final Guid _uuid;
  final Stream<List<int>> _notifications;
  final void Function(List<int>)? onWrite;

  /// Simulates a write-with-response whose ACK reaches Dart only after the
  /// adapter's reply notification has already been delivered.
  final Duration writeAckDelay;

  bool notifying = false;
  final writes = <String>[];

  @override
  final CharacteristicProperties properties;

  @override
  Guid get uuid => _uuid;

  @override
  Stream<List<int>> get lastValueStream => _notifications;

  @override
  Future<bool> setNotifyValue(
    bool notify, {
    int timeout = 15,
    bool forceIndications = false,
  }) async {
    notifying = notify;
    return true;
  }

  @override
  Future<void> write(
    List<int> value, {
    bool withoutResponse = false,
    bool allowLongWrite = false,
    int timeout = 15,
  }) async {
    writes.add(utf8.decode(value));
    onWrite?.call(value);
    if (writeAckDelay > Duration.zero) await Future.delayed(writeAckDelay);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeService implements BluetoothService {
  FakeService(String uuid, this.characteristics) : _uuid = Guid(uuid);

  final Guid _uuid;

  @override
  final List<BluetoothCharacteristic> characteristics;

  @override
  Guid get uuid => _uuid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDevice implements BluetoothDevice {
  FakeDevice(this.gattServices, {this.deviceName = 'OBDII', this.connectError});

  final List<BluetoothService> gattServices;
  final String deviceName;
  final Object? connectError;

  int connectCalls = 0;
  int disconnectCalls = 0;
  final _state = StreamController<BluetoothConnectionState>.broadcast();

  /// Simulates the BLE link dropping (out of range, adapter unplugged…).
  void dropLink() => _state.add(BluetoothConnectionState.disconnected);

  @override
  String get platformName => deviceName;

  /// Every real BLE device has one; screens compare devices by it.
  @override
  DeviceIdentifier get remoteId => DeviceIdentifier('FA:KE:00:00:$deviceName');

  @override
  Stream<BluetoothConnectionState> get connectionState => _state.stream;

  @override
  Future<void> connect({
    required License license,
    Duration timeout = const Duration(seconds: 35),
    int? mtu = 512,
    bool autoConnect = false,
  }) async {
    connectCalls++;
    if (connectError != null) throw connectError!;
    _state.add(BluetoothConnectionState.connected);
  }

  @override
  Future<List<BluetoothService>> discoverServices({
    bool subscribeToServicesChanged = true,
    int timeout = 15,
  }) async => gattServices;

  @override
  Future<void> disconnect({
    int timeout = 35,
    bool queue = true,
    int androidDelay = 2000,
  }) async {
    disconnectCalls++;
    _state.add(BluetoothConnectionState.disconnected);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Rig: adapter + simulated hardware ─────────────────────────────────────────

const simWriteProps = CharacteristicProperties(write: true);
const simWriteNoRespProps = CharacteristicProperties(
  writeWithoutResponse: true,
);
const simNotifyProps = CharacteristicProperties(notify: true);

class Rig {
  Rig(this.async, this.elm, this.device) : adapter = ProductionOBDAdapter();

  /// Typical FFF0 adapter (Vgate / Veepeak / most clones):
  /// FFF1 notify + FFF2 write.
  factory Rig.fff0(
    FakeAsync async,
    FakeElm327 elm, {
    Duration writeAckDelay = Duration.zero,
    CharacteristicProperties writeProps = simWriteProps,
  }) {
    final notify = FakeCharacteristic(
      'fff1',
      properties: simNotifyProps,
      notifications: elm.notifications,
    );
    final write = FakeCharacteristic(
      'fff2',
      properties: writeProps,
      onWrite: elm.receive,
      writeAckDelay: writeAckDelay,
    );
    return Rig(
      async,
      elm,
      FakeDevice([
        FakeService('1800', [FakeCharacteristic('2a00')]),
        FakeService('fff0', [notify, write]),
      ]),
    );
  }

  final FakeAsync async;
  final FakeElm327 elm;
  final FakeDevice device;
  final ProductionOBDAdapter adapter;

  /// Runs [future] to completion on the fake clock, stepping in 10 ms ticks.
  T drive<T>(Future<T> future, {Duration max = const Duration(seconds: 90)}) {
    late T value;
    Object? error;
    StackTrace? trace;
    var done = false;
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        trace = s;
        done = true;
      },
    );
    final deadline = async.elapsed + max;
    while (!done && async.elapsed < deadline) {
      async.elapse(const Duration(milliseconds: 10));
    }
    if (!done) fail('future still pending after $max of simulated time');
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value;
  }

  void connect() => drive(adapter.connect(device));

  /// Commands the ELM saw after init (ATE0…0100 handshake stripped).
  List<String> commandsAfter(int skip) => elm.commands.sublist(skip);

  void tearDown() {
    drive(adapter.disconnect());
    async.flushTimers(flushPeriodicTimers: false);
  }
}

/// Builds a rig, connects (unless [connect] is false), runs [body], tears down.
void sim(
  SimCar car,
  void Function(Rig rig) body, {
  bool connect = true,
  int packetSize = 20,
  Duration packetGap = Duration.zero,
  bool honoursSpacesOff = true,
  bool forceLinefeeds = false,
  bool dropsInterruptChar = false,
  Duration writeAckDelay = Duration.zero,
  CharacteristicProperties writeProps = simWriteProps,
}) {
  fakeAsync((async) {
    final elm = FakeElm327(
      car,
      packetSize: packetSize,
      packetGap: packetGap,
      honoursSpacesOff: honoursSpacesOff,
      forceLinefeeds: forceLinefeeds,
      dropsInterruptChar: dropsInterruptChar,
    );
    final rig = Rig.fff0(
      async,
      elm,
      writeAckDelay: writeAckDelay,
      writeProps: writeProps,
    );
    if (connect) rig.connect();
    body(rig);
    rig.tearDown();
  });
}
