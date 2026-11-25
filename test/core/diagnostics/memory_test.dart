// The memory readings and their lines in the flight recorder
// (docs/MEMORY.md §4).
import 'package:cinemakom/core/diagnostics/event_log.dart';
import 'package:cinemakom/core/diagnostics/memory.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// `/proc/self/smaps_rollup` as Linux 7.3 writes it.
const rollup = '''
5562f938c000-7ffce3061000 ---p 00000000 00:00 0                          [rollup]
Rss:              861204 kB
Pss:              845120 kB
Pss_Anon:         712000 kB
Anonymous:        712000 kB
LazyFree:              0 kB
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(MemoryLog.reset);

  List<String> memoryLines() => [
    for (final e in EventLog.instance.recent)
      if (e.tag == 'memory') e.message,
  ];

  test('smaps_rollup sizes are read in bytes, the header skipped', () {
    final sizes = parseSmapsRollup(rollup);
    expect(sizes['Rss'], 861204 * 1024);
    expect(sizes['Anonymous'], 712000 * 1024);
    expect(sizes['LazyFree'], 0);
    expect(sizes.containsKey('rollup'), isFalse);
  });

  test("Android's summary sizes, without the prefix, the rest skipped", () {
    expect(
      parseAndroidMemoryStats({
        'summary.java-heap': '40960',
        'summary.graphics': '204800',
        'summary.total-pss': 'n/a',
        'gc.count': '12',
      }),
      {'java-heap': 40 << 20, 'graphics': 200 << 20},
    );
  });

  test('a sample in whole MB, the parts a platform lacks left out', () {
    final json = const MemorySample(
      rss: 850 << 20,
      maxRss: 900 << 20,
      imageBytes: 40 << 20,
      images: 120,
      liveImages: 30,
    ).toJson();
    expect(json['rss_mb'], 850);
    expect(json['images_mb'], 40);
    expect(json.containsKey('anon_mb'), isFalse);
    expect(json.containsKey('android_mb'), isFalse);
  });

  test('before startDiagnostics, closing writes one line and no timer', () {
    fakeAsync((async) {
      MemoryLog.playerOpened();
      MemoryLog.playerClosed();
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(minutes: 1));
      expect(memoryLines(), [
        startsWith('player open: rss '),
        startsWith('player closed: rss '),
      ]);
    });
  });

  test('once started, a line 30 s after closing; a new video cancels it', () {
    fakeAsync((async) {
      MemoryLog.start();
      MemoryLog.playerClosed();
      async.elapse(const Duration(seconds: 10));
      MemoryLog.playerOpened();
      async.elapse(const Duration(minutes: 1));
      expect(memoryLines(), hasLength(2));

      MemoryLog.playerClosed();
      async.elapse(const Duration(seconds: 31));
      expect(memoryLines().last, startsWith('30 s after the player closed:'));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
