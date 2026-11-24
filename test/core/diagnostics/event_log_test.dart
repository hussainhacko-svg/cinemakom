import 'dart:io';

import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('event-log'));
  tearDown(() => dir.deleteSync(recursive: true));

  EventLog make({
    Duration flushEvery = const Duration(milliseconds: 30),
    int maxFileBytes = 2 * 1024 * 1024,
    int capacity = 2000,
  }) {
    final log = EventLog(
      echo: false,
      flushEvery: flushEvery,
      maxFileBytes: maxFileBytes,
      capacity: capacity,
      clock: () => DateTime(2026, 11, 24, 3, 12, 45, 123),
    );
    addTearDown(log.close);
    return log;
  }

  File current() => File('${dir.path}/${EventLog.currentName}');
  File previous() => File('${dir.path}/${EventLog.previousName}');

  test('an entry: time to the millisecond, its tag, its text; a stack '
      'trace indented', () {
    final log = make();
    log.record('player', 'phase loading -> ready');
    log.record('error', 'Bad state\n#0 main\n#1 run');
    expect(
      log.recent.first.format(),
      '2026-11-24 03:12:45.123 player    phase loading -> ready',
    );
    expect(
      log.recent.last.format(),
      endsWith('Bad state\n    #0 main\n    #1 run'),
    );
  });

  test('the last session becomes the previous one; a header opens the '
      'new one, then what came before it', () async {
    current().writeAsStringSync('last session\n');
    final log = make();
    log.record('app', 'before the files');
    await log.attach(dir, header: 'Cinemakom 1.2.3 on Linux');
    expect(previous().readAsStringSync(), 'last session\n');
    final text = current().readAsStringSync();
    expect(text, startsWith('Cinemakom 1.2.3 on Linux\n'));
    expect(text, contains('app       before the files'));
    expect(await log.read(previous: true), 'last session\n');
  });

  test('two sessions back is gone', () async {
    previous().writeAsStringSync('two sessions back\n');
    current().writeAsStringSync('last session\n');
    await make().attach(dir);
    expect(previous().readAsStringSync(), 'last session\n');
  });

  test('written within flushEvery; an urgent entry at once', () async {
    final log = make(flushEvery: const Duration(seconds: 30));
    await log.attach(dir);
    log.record('player', 'calm');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(current().readAsStringSync(), isNot(contains('calm')));
    log.record('error', 'boom', urgent: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final text = current().readAsStringSync();
    expect(text, contains('calm'));
    expect(text, contains('boom'));

    final quick = make();
    final other = Directory('${dir.path}/b');
    await quick.attach(other);
    quick.record('net', 'soon');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(
      File('${other.path}/${EventLog.currentName}').readAsStringSync(),
      contains('soon'),
    );
  });

  test('thousands of entries from everywhere land in order', () async {
    final log = make(flushEvery: const Duration(milliseconds: 1));
    await log.attach(dir);
    for (var i = 0; i < 5000; i++) {
      log.record('x', 'entry $i', urgent: i % 97 == 0);
      if (i % 500 == 0) await Future<void>.delayed(Duration.zero);
    }
    await log.flush();
    final numbers = [
      for (final m in RegExp(
        r'entry (\d+)',
      ).allMatches(current().readAsStringSync()))
        int.parse(m[1]!),
    ];
    expect(numbers, List.generate(5000, (i) => i));
  });

  test('a burst the disk can\'t keep up with says what it dropped', () async {
    final log = make(capacity: 10, flushEvery: const Duration(seconds: 30));
    await log.attach(dir);
    for (var i = 0; i < 250; i++) {
      log.record('x', 'entry $i');
    }
    await log.flush();
    final text = current().readAsStringSync();
    expect(text, contains('… 150 entries dropped (the disk fell behind)'));
    expect(text, isNot(contains('entry 149\n')));
    expect(text, contains('entry 150\n'));
    expect(text, contains('entry 249\n'));
  });

  test('memory keeps the newest [capacity]', () {
    final log = make(capacity: 10);
    for (var i = 0; i < 25; i++) {
      log.record('x', '$i');
    }
    expect(log.recent.map((e) => e.message), [
      for (var i = 15; i < 25; i++) '$i',
    ]);
  });

  test('a huge message is cut', () {
    final log = make();
    log.record('error', 'a' * 10000);
    final m = log.recent.single.message;
    expect(m.length, lessThan(4100));
    expect(m, endsWith('(6000 more characters)'));
  });

  test('the file stays under its cap, keeping the newest lines', () async {
    final log = make(maxFileBytes: 20000);
    await log.attach(dir, header: 'header');
    for (var i = 0; i < 2000; i++) {
      log.record('x', 'line $i ${'·' * 20}');
      if (i % 100 == 0) await log.flush();
    }
    await log.flush();
    final text = current().readAsStringSync();
    expect(current().lengthSync(), lessThanOrEqualTo(20000));
    expect(text, startsWith('… older entries of this session dropped'));
    expect(text, contains('line 1999 '));
    expect(text, isNot(contains('line 0 ')));
    // Every kept line is whole.
    for (final line in text.trimRight().split('\n').skip(1)) {
      expect(line, matches(RegExp(r'^2026-11-24 .* x +line \d+ ·+$')));
    }
  });

  test(
    'a folder it can\'t write to: no error, the log stays in memory',
    () async {
      final blocker = File('${dir.path}/not-a-folder')..writeAsStringSync('');
      final log = make();
      await expectLater(log.attach(Directory(blocker.path)), completes);
      log.record('player', 'still recorded');
      await expectLater(log.flush(), completes);
      expect(log.recent.map((e) => e.message), contains('still recorded'));
      expect(await log.read(), contains('still recorded'));
    },
  );

  test('the folder removed while recording: no error', () async {
    final sub = Directory('${dir.path}/logs');
    final log = make();
    await log.attach(sub);
    sub.deleteSync(recursive: true);
    log.record('x', 'after');
    await expectLater(log.flush(), completes);
    expect(log.recent.last.message, 'after');
  });

  test('export: both sessions in one file, the newest last', () async {
    current().writeAsStringSync('old line\n');
    final log = make();
    await log.attach(dir, header: 'header');
    log.record('player', 'new line');
    final file = await log.export(Directory('${dir.path}/out'));
    expect(file.path, endsWith('cinemakom-log-20261124-031245.txt'));
    final text = file.readAsStringSync();
    expect(
      text.indexOf('previous session'),
      lessThan(text.indexOf('old line')),
    );
    expect(text.indexOf('old line'), lessThan(text.indexOf('this session')));
    expect(text.indexOf('this session'), lessThan(text.indexOf('new line')));
  });

  test('clear empties both sessions', () async {
    current().writeAsStringSync('old\n');
    final log = make();
    await log.attach(dir);
    log.record('x', 'now');
    await log.clear();
    expect(log.recent, isEmpty);
    expect(await log.read(), isEmpty);
    expect(await log.read(previous: true), isEmpty);
  });

  test('changes fire on every entry', () async {
    final log = make();
    var fired = 0;
    final sub = log.changes.listen((_) => fired++);
    log
      ..record('a', '1')
      ..record('a', '2');
    await Future<void>.delayed(Duration.zero);
    expect(fired, 2);
    await sub.cancel();
  });

  test('closed: recording does nothing', () async {
    final log = make();
    await log.attach(dir);
    await log.close();
    log.record('x', 'late');
    expect(log.recent, isEmpty);
    expect(current().readAsStringSync(), isNot(contains('late')));
  });
}
