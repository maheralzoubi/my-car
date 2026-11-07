import 'dart:collection';

/// What an [OBDLogEntry] records.
enum OBDLogKind {
  /// Command written to the adapter.
  tx,

  /// Raw '>'-terminated reply from the adapter.
  rx,

  /// Connection lifecycle / informational note.
  event,

  /// Timeout, write failure, failed connect, link drop.
  error,
}

class OBDLogEntry {
  const OBDLogEntry(this.time, this.kind, this.text);

  final DateTime time;
  final OBDLogKind kind;
  final String text;

  static const _tags = {
    OBDLogKind.tx: 'TX ',
    OBDLogKind.rx: 'RX ',
    OBDLogKind.event: '-- ',
    OBDLogKind.error: '!! ',
  };

  @override
  String toString() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t =
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    return '$t ${_tags[kind]}$text';
  }
}

/// Ring buffer of raw ELM327 traffic (commands, raw replies, timings,
/// errors) so a failure on a real car can be copied from the connection
/// screen and diagnosed later. Oldest entries are dropped past [capacity].
class OBDLog {
  OBDLog({this.capacity = 800});

  /// Shared log written by the production adapter.
  static final OBDLog instance = OBDLog();

  final int capacity;
  final _entries = ListQueue<OBDLogEntry>();

  List<OBDLogEntry> get entries => List.unmodifiable(_entries);

  void tx(String command) => _add(OBDLogKind.tx, escape(command));

  /// [raw] reply (control characters made visible) and how long it took.
  void rx(String raw, {Duration? took}) => _add(
    OBDLogKind.rx,
    took == null ? escape(raw) : '${escape(raw)}  (${took.inMilliseconds} ms)',
  );

  void event(String message) => _add(OBDLogKind.event, message);

  void error(String message) => _add(OBDLogKind.error, message);

  void clear() => _entries.clear();

  /// Plain-text dump, oldest first, optionally preceded by [header] lines.
  String dump({List<String> header = const []}) {
    final b = StringBuffer();
    for (final h in header) {
      b.writeln(h);
    }
    if (header.isNotEmpty) b.writeln();
    if (_entries.isEmpty) b.writeln('(no adapter traffic recorded)');
    for (final e in _entries) {
      b.writeln(e);
    }
    return b.toString();
  }

  void _add(OBDLogKind kind, String text) {
    _entries.addLast(OBDLogEntry(DateTime.now(), kind, text));
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  /// [s] with CR / LF / other control characters spelled out, so the exact
  /// bytes the adapter sent survive copy-paste.
  static String escape(String s) {
    final b = StringBuffer();
    for (final c in s.codeUnits) {
      if (c == 0x0D) {
        b.write(r'\r');
      } else if (c == 0x0A) {
        b.write(r'\n');
      } else if (c < 0x20 || c == 0x7F) {
        b.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
      } else {
        b.writeCharCode(c);
      }
    }
    return b.toString();
  }
}
