import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One line of the [EventLog].
@immutable
class LogEntry {
  const LogEntry(this.at, this.tag, this.message);

  final DateTime at;

  /// What it's about: `player`, `downloads`, `net`, `error`, `key`, …
  final String tag;
  final String message;

  /// `2026-11-24 03:12:45.123 player    phase loading -> ready`. Lines
  /// after the first (a stack trace) are indented.
  String format() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = at;
    final time =
        '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')}';
    final body = message.replaceAll('\n', '\n    ');
    return '$time ${tag.padRight(9)} $body';
  }

  @override
  String toString() => format();
}

/// The app's flight recorder: what happened recently, kept on the device so
/// a bug that happens once can still be looked at afterwards (the owner's
/// "Report a problem"). Nothing is ever sent anywhere.
///
/// [record] is cheap, synchronous and never throws, so anything can call
/// it. Entries stay in memory ([recent]) and are appended to `current.log`
/// in [directory] at most [flushEvery] later ([urgent] ones at once). At
/// startup the last session's file becomes `previous.log`, so a crash or a
/// freeze that got the app killed leaves its trail. Each file is kept under
/// [maxFileBytes] by dropping its oldest half.
class EventLog {
  EventLog({
    this.capacity = 2000,
    this.flushEvery = const Duration(seconds: 2),
    this.maxFileBytes = 2 * 1024 * 1024,
    this.maxMessageLength = 4000,
    bool? echo,
    DateTime Function()? clock,
  }) : echo = echo ?? kDebugMode,
       _clock = clock ?? DateTime.now;

  /// The log everything records to. Tests replace it.
  static EventLog instance = EventLog();

  /// Entries kept in memory.
  final int capacity;
  final Duration flushEvery;
  final int maxFileBytes;

  /// Longer messages are cut (a huge error text must not fill the file).
  final int maxMessageLength;

  /// Also print each entry (debug builds), as `debugPrint` did.
  final bool echo;
  final DateTime Function() _clock;

  static const currentName = 'current.log';
  static const previousName = 'previous.log';

  final _recent = <LogEntry>[];
  final _pending = <String>[];

  /// Lines waiting for the disk, at most: a burst the writes can't keep up
  /// with drops its oldest, and says so in the file.
  int get maxPending => capacity * 10;
  int _dropped = 0;
  final _changes = StreamController<void>.broadcast();
  Timer? _flushTimer;
  Future<void> _writing = Future<void>.value();
  File? _file;
  bool _broken = false;
  bool _closed = false;

  /// The folder the files are in, once [attach] ran.
  Directory? get directory => _file?.parent;

  /// The newest last.
  List<LogEntry> get recent => List.unmodifiable(_recent);

  /// Fires after every [record].
  Stream<void> get changes => _changes.stream;

  /// Records [message] under [tag]. [urgent] writes it to the file at once
  /// (errors: the app may be about to die).
  void record(String tag, String message, {bool urgent = false}) {
    if (_closed) return;
    try {
      final text = message.length > maxMessageLength
          ? '${message.substring(0, maxMessageLength)}… '
                '(${message.length - maxMessageLength} more characters)'
          : message;
      final entry = LogEntry(_clock(), tag, text);
      _recent.add(entry);
      if (_recent.length > capacity) {
        _recent.removeRange(0, _recent.length - capacity);
      }
      final line = entry.format();
      if (echo) debugPrint(line);
      _pending.add(line);
      if (_pending.length > maxPending) {
        final over = _pending.length - maxPending;
        _pending.removeRange(0, over);
        _dropped += over;
      }
      if (!_changes.isClosed) _changes.add(null);
      // Before [attach] there's no file: what's pending goes in then.
      if (_file == null) return;
      if (urgent) {
        unawaited(flush());
      } else {
        _flushTimer ??= Timer(flushEvery, () => unawaited(flush()));
      }
    } on Object {
      // The recorder must never be the thing that breaks the app.
    }
  }

  /// Starts writing to [dir]: the last session's `current.log` becomes
  /// `previous.log`, [header] opens the new one, and what was recorded
  /// before this goes in after it.
  Future<void> attach(Directory dir, {String? header}) async {
    if (_closed) return;
    try {
      await dir.create(recursive: true);
      final current = File('${dir.path}/$currentName');
      final previous = File('${dir.path}/$previousName');
      if (await current.exists()) {
        if (await previous.exists()) await previous.delete();
        await current.rename(previous.path);
      }
      await current.writeAsString(
        header == null ? '' : '${header.trimRight()}\n',
        flush: true,
      );
      _file = current;
      _broken = false;
    } on Object catch (e) {
      _broken = true;
      record('log', 'cannot write the log in ${dir.path}: $e');
      return;
    }
    await flush();
  }

  /// Writes what's pending. Writes run one after another.
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    return _writing = _writing.then((_) => _write());
  }

  Future<void> _write() async {
    final file = _file;
    if (file == null || _broken || _pending.isEmpty) return;
    final dropped = _dropped;
    final lines = [
      if (dropped > 0) '… $dropped entries dropped (the disk fell behind)',
      ..._pending,
    ].join('\n');
    _pending.clear();
    _dropped = 0;
    try {
      await file.writeAsString('$lines\n', mode: FileMode.append, flush: true);
      if (await file.length() > maxFileBytes) await _trim(file);
    } on Object {
      // Disk full or the folder gone: keep the in-memory log only.
      _broken = true;
    }
  }

  /// Drops the oldest half of [file], from a line start.
  Future<void> _trim(File file) async {
    final bytes = await file.readAsBytes();
    var from = bytes.length - maxFileBytes ~/ 2;
    while (from < bytes.length && bytes[from] != 0x0A) {
      from++;
    }
    final kept = bytes.sublist(from < bytes.length ? from + 1 : bytes.length);
    final header = utf8.encode(
      '… older entries of this session dropped (over '
      '${maxFileBytes ~/ 1024} KB)\n',
    );
    await file.writeAsBytes([...header, ...kept], flush: true);
  }

  /// The text of this session's file ([previous]: the last session's), or
  /// of [recent] when there's no file.
  Future<String> read({bool previous = false}) async {
    await flush();
    final dir = directory;
    if (dir == null) {
      return previous ? '' : _recent.map((e) => e.format()).join('\n');
    }
    final file = File('${dir.path}/${previous ? previousName : currentName}');
    try {
      return await file.exists() ? await file.readAsString() : '';
    } on Object {
      return '';
    }
  }

  /// One file with both sessions, newest last, in [dir] (for sharing or
  /// saving): `cinemakom-log-20261124-031245.txt`.
  Future<File> export(Directory dir) async {
    final previous = await read(previous: true);
    final current = await read();
    final t = _clock();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'cinemakom-log-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}.txt';
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsString(
      [
        if (previous.isNotEmpty) ...[
          '===== previous session =====',
          previous.trimRight(),
          '',
        ],
        '===== this session =====',
        current.trimRight(),
        '',
      ].join('\n'),
      flush: true,
    );
    return file;
  }

  /// Empties both sessions (the screen's "Clear").
  Future<void> clear() async {
    _recent.clear();
    _pending.clear();
    if (!_changes.isClosed) _changes.add(null);
    final dir = directory;
    if (dir == null) return;
    await _writing;
    try {
      final previous = File('${dir.path}/$previousName');
      if (await previous.exists()) await previous.delete();
      await File('${dir.path}/$currentName').writeAsString('', flush: true);
    } on Object {
      // Nothing to clear.
    }
  }

  /// Writes what's left and stops recording.
  Future<void> close() async {
    await flush();
    _closed = true;
    await _changes.close();
  }
}

/// Records [message] under [tag] in [EventLog.instance].
void logEvent(String tag, String message, {bool urgent = false}) =>
    EventLog.instance.record(tag, message, urgent: urgent);
