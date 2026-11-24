// MediaKitEngine (mpv: Linux and Windows) on the real libmpv, with two
// short MP4 files ffmpeg makes first (so it runs offline, in a minute; it
// needs `ffmpeg` on the PATH; media_kit's libmpv doesn't play mpv's own
// `av://lavfi:` sources). The
// races: a new file, or the player closing, while a file is still opening.
// Each is swept over many delays so the second call lands at every step of
// the first one's setup.
//
//   fvm flutter test integration_test/media_kit_engine_test.dart -d linux
import 'dart:io';

import 'package:cinemakom/core/player/media_kit_engine.dart';
import 'package:cinemakom/core/player/player_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

/// 4 s at 4:3, and 9 s at 16:9: told apart by length and shape.
late EngineSource short;
late EngineSource long;

/// An MP4 of [seconds] at [size], with sound, made by ffmpeg in [dir].
Future<EngineSource> clip(
  Directory dir,
  String name,
  int seconds,
  String size,
) async {
  final path = '${dir.path}/$name.mp4';
  final r = await Process.run('ffmpeg', [
    '-loglevel',
    'error',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=duration=$seconds:size=$size:rate=25',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=$seconds',
    '-shortest',
    '-c:v',
    'libx264',
    '-preset',
    'ultrafast',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    path,
  ]);
  if (r.exitCode != 0) fail('ffmpeg failed: ${r.stderr}');
  return EngineSource(path);
}

/// Delays (ms) between the first call and the second: from before the
/// first await to after the file plays.
const sweep = [0, 1, 2, 3, 5, 8, 12, 20, 35, 60, 100, 200];

/// [future], or a failure naming [what] if it hasn't ended in 5 s (an
/// engine call that never returns is a bug: the player screen would hang).
Future<T> within<T>(Future<T> future, String what) => future.timeout(
  const Duration(seconds: 5),
  onTimeout: () => fail('$what never returned'),
);

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Waits until [done], up to [seconds].
Future<void> until(
  String what,
  bool Function() done, {
  int seconds = 10,
}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
    await wait(20);
  }
}

/// A new engine, closed after the test whatever happens: a native player
/// still open after that is one the engine lost track of.
MediaKitEngine engineFor({bool perFile = false}) {
  final engine = MediaKitEngine(recreatePerFile: perFile);
  addTearDown(engine.dispose);
  return engine;
}

void main() {
  // Live frames: media_kit's open() waits on the frame loop, and never
  // returns in a plain testWidgets() that draws none.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();

  late Directory media;
  setUpAll(() async {
    media = Directory.systemTemp.createTempSync('cinemakom-mpv');
    short = await clip(media, 'short', 4, '320x240');
    long = await clip(media, 'long', 9, '640x360');
  });
  tearDownAll(() => media.deleteSync(recursive: true));

  /// Each test leaves no native player behind.
  late int before;
  setUp(() => before = MediaKitEngine.livePlayers);
  tearDown(() async {
    await until(
      'every native player closed (${MediaKitEngine.livePlayers - before} left)',
      () => MediaKitEngine.livePlayers == before,
    );
  });

  testWidgets('a file plays: its length, its shape, time passing', (
    tester,
  ) async {
    final engine = engineFor();
    final aspects = <double>[];
    final sub = engine.aspectRatio.listen(aspects.add);
    await within(engine.open(short), 'open');
    await until('playing past 1 s', () {
      return engine.currentPosition > const Duration(seconds: 1);
    });
    expect(engine.currentDuration.inSeconds, inInclusiveRange(3, 4));
    expect(aspects.last, closeTo(4 / 3, 0.01));
    await sub.cancel();
    await within(engine.dispose(), 'dispose');
  });

  testWidgets('a file that can\'t open: an error, and open doesn\'t throw', (
    tester,
  ) async {
    final engine = engineFor();
    final errors = <String>[];
    final sub = engine.errors.listen(errors.add);
    await expectLater(
      engine.open(const EngineSource('/nonexistent/cinemakom-test.mp4')),
      completes,
    );
    await until('an error', () => errors.isNotEmpty);
    await sub.cancel();
    await within(engine.dispose(), 'dispose');
  });

  testWidgets('a subtitle file that can\'t load is a subtitle error', (
    tester,
  ) async {
    final engine = engineFor();
    final errors = <String>[];
    final subtitleErrors = <String>[];
    final subs = [
      engine.errors.listen(errors.add),
      engine.subtitleErrors.listen(subtitleErrors.add),
    ];
    await within(engine.open(long), 'open');
    await until('playing', () => engine.currentPosition > Duration.zero);
    await within(
      engine.setSubtitle(
        const EngineSubtitle(uri: '/nonexistent/cinemakom.srt', language: 'en'),
      ),
      'setSubtitle',
    );
    await until('a subtitle error', () => subtitleErrors.isNotEmpty);
    expect(errors, isEmpty);
    for (final s in subs) {
      await s.cancel();
    }
    await within(engine.dispose(), 'dispose');
  });

  for (final perFile in [false, true]) {
    final mode = perFile ? 'a new player per file' : 'one player';

    group(mode, () {
      testWidgets('the speed and volume chosen carry over to the next file', (
        tester,
      ) async {
        final engine = engineFor(perFile: perFile);
        await within(engine.setRate(1.5), 'setRate');
        await within(engine.open(short), 'open');
        await within(engine.setVolume(30), 'setVolume');
        await within(engine.open(long), 'open');
        await until('playing', () {
          return engine.currentPosition > const Duration(milliseconds: 500);
        });
        // At 1.5×, the file runs half again as fast as the clock.
        final at = engine.currentPosition;
        final clock = Stopwatch()..start();
        await wait(2000);
        final ratio =
            (engine.currentPosition - at).inMilliseconds /
            clock.elapsedMilliseconds;
        expect(ratio, inInclusiveRange(1.3, 1.7));
        await within(engine.dispose(), 'dispose');
      });

      for (final ms in sweep) {
        testWidgets(
          'closed $ms ms into opening: nothing thrown, no player left',
          (tester) async {
            final engine = engineFor(perFile: perFile);
            final errors = <Object>[];
            final opening = engine.open(short).catchError(errors.add);
            await wait(ms);
            await within(engine.dispose(), 'dispose');
            await within(opening, 'the open');
            expect(errors, isEmpty);
          },
        );

        testWidgets('closed $ms ms into opening a second file', (tester) async {
          final engine = engineFor(perFile: perFile);
          await within(engine.open(short), 'open');
          await until('playing', () => engine.currentPosition > Duration.zero);
          final errors = <Object>[];
          final opening = engine.open(long).catchError(errors.add);
          await wait(ms);
          await within(engine.dispose(), 'dispose');
          await within(opening, 'the open');
          expect(errors, isEmpty);
        });

        testWidgets(
          'a second file $ms ms into the first: the second plays, one '
          'player',
          (tester) async {
            final engine = engineFor(perFile: perFile);
            final errors = <Object>[];
            final first = engine.open(short).catchError(errors.add);
            await wait(ms);
            final second = engine.open(long).catchError(errors.add);
            await within(Future.wait([first, second]), 'both opens');
            await until(
              'the second file playing',
              () =>
                  engine.currentDuration > const Duration(seconds: 6) &&
                  engine.currentPosition > Duration.zero,
            );
            expect(errors, isEmpty);
            expect(MediaKitEngine.livePlayers - before, 1);
            await within(engine.dispose(), 'dispose');
          },
        );
      }

      for (final ms in sweep) {
        testWidgets('controls $ms ms into closing never throw', (tester) async {
          final engine = engineFor(perFile: perFile);
          await within(engine.open(long), 'open');
          await until('playing', () => engine.currentPosition > Duration.zero);
          final closing = engine.dispose();
          await wait(ms);
          await within(
            Future.wait([
              engine.play(),
              engine.pause(),
              engine.seek(const Duration(seconds: 2)),
              engine.setRate(1.25),
              engine.setVolume(50),
              engine.setSubtitle(
                const EngineSubtitle(uri: '/x.srt', language: 'en'),
              ),
              engine.setSubtitle(null),
              engine.setSubtitleDelay(const Duration(seconds: 1)),
              engine.setSubtitleScale(1.2),
              engine.open(short),
            ]),
            'the controls',
          );
          await within(closing, 'dispose');
        });
      }

      testWidgets('five files in a row: the last plays', (tester) async {
        final engine = engineFor(perFile: perFile);
        await within(
          Future.wait([
            for (var i = 0; i < 4; i++) engine.open(short),
            engine.open(long),
          ]),
          'five opens',
        );
        await until(
          'the last file playing',
          () =>
              engine.currentDuration > const Duration(seconds: 6) &&
              engine.currentPosition > Duration.zero,
        );
        expect(MediaKitEngine.livePlayers - before, 1);
        await within(engine.dispose(), 'dispose');
      });
    });
  }

  testWidgets('once closed, everything is a no-op and nothing throws', (
    tester,
  ) async {
    final engine = engineFor();
    await within(engine.open(short), 'open');
    await within(engine.dispose(), 'dispose');
    await within(engine.open(long), 'open');
    await within(engine.play(), 'play');
    await within(engine.pause(), 'pause');
    await within(engine.seek(const Duration(seconds: 1)), 'seek');
    await within(engine.setRate(2), 'setRate');
    await within(engine.setVolume(10), 'setVolume');
    await within(
      engine.setSubtitle(
        const EngineSubtitle(uri: '/x.ass', language: 'ar', styled: true),
      ),
      'setSubtitle',
    );
    await within(engine.setSubtitle(null), 'setSubtitle');
    await within(
      engine.setSubtitleDelay(const Duration(seconds: 1)),
      'setSubtitleDelay',
    );
    await within(engine.setSubtitleScale(1.2), 'setSubtitleScale');
    await within(engine.dispose(), 'dispose');
    expect(engine.currentPosition, Duration.zero);
  });
}
