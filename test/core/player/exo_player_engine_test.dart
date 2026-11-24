// ExoPlayerEngine (Android phones and TVs) against a fake video_player
// platform: what it asks ExoPlayer for, how it reports ExoPlayer's events,
// its races (a new file, or the player closing, while a file is still
// opening) and the subtitle files it parses. Until this test the engine was
// only ever checked by hand on a phone.
import 'dart:async';
import 'dart:math';

import 'package:cinemakom/core/player/exo_player_engine.dart';
import 'package:cinemakom/core/player/player_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fake_video_platform.dart';

/// Everything [engine] reported.
class Seen {
  Seen(PlayerEngine engine) {
    _subs = [
      engine.position.listen(positions.add),
      engine.duration.listen(durations.add),
      engine.aspectRatio.listen(aspects.add),
      engine.buffered.listen(buffered.add),
      engine.playing.listen(playing.add),
      engine.buffering.listen(buffering.add),
      engine.completed.listen(completed.add),
      engine.errors.listen(errors.add),
      engine.subtitleErrors.listen(subtitleErrors.add),
      engine.subtitleText.listen(lines.add),
    ];
  }

  late final List<StreamSubscription<Object?>> _subs;
  final positions = <Duration>[];
  final durations = <Duration>[];
  final aspects = <double>[];
  final buffered = <Duration>[];
  final playing = <bool>[];
  final buffering = <bool>[];
  final completed = <bool>[];
  final errors = <String>[];
  final subtitleErrors = <String>[];
  final lines = <List<String>>[];

  Future<void> cancel() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }
}

/// Lets queued microtasks and platform answers run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const stream = EngineSource(
  'https://cdn.example/v/1080.mp4',
  headers: {'Referer': 'https://cinemana.shabakaty.com/'},
);
const other = EngineSource('https://cdn.example/v/720.mp4');

const srt =
    '1\n'
    '00:00:01,000 --> 00:00:03,000\n'
    '<i>Hello</i>\n'
    '{\\an8}there\n'
    '\n'
    '2\n'
    '00:00:05,000 --> 00:00:06,000\n'
    'Bye\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVideoPlatform platform;
  late ExoPlayerEngine engine;
  late Seen seen;

  /// Subtitle files by URL; a [Completer] holds a load, an [Exception]
  /// fails it.
  late Map<String, Object> files;

  setUp(() {
    platform = FakeVideoPlatform();
    VideoPlayerPlatform.instance = platform;
    files = {};
    engine = ExoPlayerEngine(
      loadText: (url) async {
        final file = files[url];
        if (file is Completer<String>) return file.future;
        if (file is Exception) throw file;
        if (file is String) return file;
        throw Exception('404 $url');
      },
    );
    seen = Seen(engine);
  });

  tearDown(() async {
    await seen.cancel();
    await engine.dispose();
  });

  group('opening', () {
    test('a stream opens with the shared headers, in a texture view, mixed '
        'with other audio (audio focus is AudioFocus\'s)', () async {
      await engine.open(stream);
      final v = platform.last;
      expect(v.source.sourceType, DataSourceType.network);
      expect(v.source.uri, stream.uri);
      expect(v.source.httpHeaders, stream.headers);
      expect(v.options.viewType, VideoViewType.textureView);
      expect(platform.mixWithOthers, isTrue);
    });

    test('a downloaded file plays from disk', () async {
      await engine.open(const EngineSource('file:///data/Movies/A%20B.mp4'));
      expect(platform.last.source.sourceType, DataSourceType.file);
      expect(platform.last.source.uri, endsWith('/data/Movies/A%20B.mp4'));
    });

    test('once open: its length, its shape, playing, at the start asked '
        'for, with the speed and volume chosen before', () async {
      await engine.setRate(1.5);
      await engine.setVolume(40);
      await engine.open(stream, start: const Duration(minutes: 10));
      await settle();
      expect(seen.durations.last, const Duration(minutes: 90));
      expect(seen.aspects.last, closeTo(16 / 9, 1e-9));
      expect(seen.playing.last, isTrue);
      expect(engine.currentDuration, const Duration(minutes: 90));
      expect(engine.currentPosition, const Duration(minutes: 10));
      expect(
        platform.last.calls,
        // video_player sends the speed once playback starts.
        containsAllInOrder(['volume 0.4', 'seek 600', 'play', 'speed 1.5']),
      );
    });

    test('play: false opens it paused', () async {
      await engine.open(stream, play: false);
      await settle();
      expect(platform.last.calls, isNot(contains('play')));
      expect(seen.playing, isNot(contains(true)));
    });

    test(
      'a new open reports buffering and not finished until it plays',
      () async {
        // Before anything is known about the new file.
        platform.autoInitialize = false;
        unawaited(engine.open(stream));
        await settle();
        expect(seen.buffering, [true]);
        expect(seen.completed, [false]);
        expect(seen.playing, [false]);
      },
    );

    test(
      'ExoPlayer\'s events: buffering, what is buffered ahead, the end',
      () async {
        await engine.open(stream);
        await settle();
        await engine.seek(const Duration(minutes: 22));
        final v = platform.last;
        v.send(VideoEventType.bufferingStart);
        await settle();
        expect(seen.buffering.last, isTrue);
        v.send(
          VideoEventType.bufferingUpdate,
          buffered: [
            DurationRange(Duration.zero, const Duration(minutes: 5)),
            DurationRange(
              const Duration(minutes: 20),
              const Duration(minutes: 30),
            ),
            DurationRange(
              const Duration(minutes: 40),
              const Duration(minutes: 50),
            ),
          ],
        );
        v.send(VideoEventType.bufferingEnd);
        await settle();
        expect(seen.buffered.last, const Duration(minutes: 30));
        expect(seen.buffering.last, isFalse);
        v.send(VideoEventType.completed);
        await settle();
        expect(seen.completed.last, isTrue);
      },
    );

    test('a decoder that can\'t play the file is told apart', () {
      for (final e in [
        'MediaCodecVideoRenderer error, index=0, format=Format(1, null, '
            'video/hevc, 3840x2160), format_supported=NO_EXCEEDS_CAPABILITIES',
        'DecoderInitializationException: Decoder init failed: c2.qti.hevc',
      ]) {
        expect(engine.isDecoderError(e), isTrue, reason: e);
      }
      for (final e in ['Source error', 'HttpDataSourceException', '']) {
        expect(engine.isDecoderError(e), isFalse, reason: e);
      }
      expect(engine.errorsStopPlayback, isTrue);
      expect(engine.supportsStyledSubtitles, isFalse);
    });
  });

  group('errors', () {
    test('a file that won\'t open: its error, still "buffering" (the player '
        'recovers), and no native player left', () async {
      platform.autoInitialize = false;
      final opening = engine.open(stream);
      await settle();
      platform.last.fail('Source error');
      await expectLater(opening, completes);
      await settle();
      expect(seen.errors.single, contains('Source error'));
      expect(seen.buffering.last, isTrue);
      expect(platform.alive, isEmpty);
    });

    test('ExoPlayer stopping mid-film: each error once, and the last good '
        'position kept (video_player resets it to 0)', () async {
      await engine.open(stream);
      await settle();
      await engine.seek(const Duration(minutes: 30));
      await settle();
      platform.last.fail('Network down');
      await settle();
      platform.last.fail('Network down');
      await settle();
      expect(seen.errors, ['Network down']);
      expect(engine.currentPosition, const Duration(minutes: 30));
      expect(engine.currentDuration, const Duration(minutes: 90));
      expect(seen.positions.last, const Duration(minutes: 30));
      expect(seen.durations, isNot(contains(Duration.zero)));
      platform.last.fail('Decoder gone');
      await settle();
      expect(seen.errors, ['Network down', 'Decoder gone']);
    });
  });

  group('one file at a time', () {
    test('a new file closes the old one', () async {
      await engine.open(stream);
      await settle();
      final first = platform.last;
      await engine.open(other);
      await settle();
      expect(first.disposed, isTrue);
      expect(platform.alive, [platform.last]);
      expect(platform.last.source.uri, other.uri);
    });

    // A quality or episode switch while the first file still sets up. The
    // overtaken open went on, became the shown player and played, and the
    // next open never closed it: a second ExoPlayer playing behind.
    test('an open overtaken while it sets up is closed, never shown', () async {
      platform.autoDuration = const Duration(minutes: 10);
      final volume = platform.holdVolume = Completer<void>();
      final first = engine.open(stream);
      await settle();
      final overtaken = platform.last;
      platform
        ..holdVolume = null
        ..autoDuration = const Duration(minutes: 20);
      await engine.open(other);
      await settle();
      volume.complete();
      await expectLater(first, completes);
      await settle();

      expect(overtaken.disposed, isTrue);
      expect(overtaken.calls, isNot(contains('play')));
      expect(platform.alive.single.source.uri, other.uri);
      expect(engine.currentDuration, const Duration(minutes: 20));
      overtaken.send(VideoEventType.completed);
      await settle();
      expect(seen.completed.last, isFalse, reason: 'its events are ignored');
    });

    test('many opens in a row leave one player: the last', () async {
      platform.autoInitialize = false;
      final opens = [
        for (var i = 0; i < 5; i++)
          engine.open(EngineSource('https://cdn.example/$i.mp4')),
      ];
      await settle();
      for (final v in [...platform.videos]) {
        v.initialize();
      }
      await Future.wait(opens);
      await settle();
      expect(platform.alive.single.source.uri, 'https://cdn.example/4.mp4');
    });

    // Back pressed just as the next file starts loading: the player closed
    // while the old file was being released, then the open went on and
    // wrote to the closed streams (a StateError).
    test('closing while the old file is released: nothing thrown, nothing '
        'left open', () async {
      await engine.open(stream);
      await settle();
      final release = platform.holdDispose = Completer<void>();
      final next = engine.open(other);
      await settle();
      final closing = engine.dispose();
      await settle();
      platform.holdDispose = null;
      release.complete();
      await expectLater(next, completes);
      await closing;
      await settle();
      expect(platform.alive, isEmpty);
    });

    test('closing while a file opens closes it when it\'s ready', () async {
      platform.autoInitialize = false;
      final opening = engine.open(stream);
      await settle();
      await engine.dispose();
      platform.last.initialize();
      await expectLater(opening, completes);
      await settle();
      expect(platform.alive, isEmpty);
    });

    test('closing while the opened file sets up', () async {
      final volume = platform.holdVolume = Completer<void>();
      final opening = engine.open(stream);
      await settle();
      await engine.dispose();
      volume.complete();
      await expectLater(opening, completes);
      await settle();
      expect(platform.alive, isEmpty);
      expect(platform.last.calls, isNot(contains('play')));
    });

    test('once closed, everything is a no-op and nothing throws', () async {
      await engine.open(stream);
      await settle();
      await engine.dispose();
      final made = platform.videos.length;
      await engine.open(other);
      await engine.play();
      await engine.pause();
      await engine.seek(const Duration(seconds: 5));
      await engine.setRate(2);
      await engine.setVolume(10);
      await engine.setSubtitle(
        const EngineSubtitle(
          uri: 'https://s/a.ass',
          language: 'ar',
          styled: true,
        ),
      );
      files['https://s/a.srt'] = srt;
      await engine.setSubtitle(
        const EngineSubtitle(uri: 'https://s/a.srt', language: 'en'),
      );
      await engine.setSubtitle(null);
      await engine.setSubtitleDelay(const Duration(seconds: 1));
      await engine.setSubtitleScale(1.2);
      await engine.dispose();
      expect(platform.videos, hasLength(made));
      expect(engine.currentPosition, Duration.zero);
    });
  });

  group('plain subtitles', () {
    const en = EngineSubtitle(uri: 'https://s/a.srt', language: 'en');

    Future<List<String>> at(Duration t) async {
      await engine.seek(t);
      await settle();
      return seen.lines.isEmpty ? const [] : seen.lines.last;
    }

    test('SubRip: each line at its time, without markup', () async {
      files[en.uri] = srt;
      await engine.open(stream);
      await settle();
      await engine.setSubtitle(en);
      expect(await at(const Duration(seconds: 2)), ['Hello', 'there']);
      expect(await at(const Duration(seconds: 4)), isEmpty);
      expect(await at(const Duration(milliseconds: 5500)), ['Bye']);
      expect(await at(const Duration(seconds: 6)), isEmpty, reason: 'ends');
    });

    test('a delay shows them later', () async {
      files[en.uri] = srt;
      await engine.open(stream);
      await settle();
      await engine.setSubtitle(en);
      expect(await at(const Duration(milliseconds: 5500)), ['Bye']);
      await engine.setSubtitleDelay(const Duration(seconds: 1));
      await settle();
      expect(seen.lines.last, isEmpty);
      expect(await at(const Duration(milliseconds: 6500)), ['Bye']);
    });

    test('WebVTT, with a byte order mark and Windows line ends', () async {
      files[en.uri] = '﻿WEBVTT\r\n\r\n00:00:01.000 --> 00:00:03.000\r\nHi\r\n';
      await engine.open(stream);
      await settle();
      await engine.setSubtitle(en);
      expect(await at(const Duration(seconds: 2)), ['Hi']);
    });

    test('off clears the lines', () async {
      files[en.uri] = srt;
      await engine.open(stream);
      await settle();
      await engine.setSubtitle(en);
      expect(await at(const Duration(seconds: 2)), isNotEmpty);
      await engine.setSubtitle(null);
      await settle();
      expect(seen.lines.last, isEmpty);
    });

    test('styled tracks are refused: they need libass', () async {
      await engine.open(stream);
      await engine.setSubtitle(
        const EngineSubtitle(
          uri: 'https://s/a.ass',
          language: 'ar',
          styled: true,
        ),
      );
      expect(seen.subtitleErrors.single, contains('libass'));
    });

    test('a file that won\'t load or has no captions is reported, not '
        'thrown', () async {
      await engine.open(stream);
      files[en.uri] = Exception('offline');
      await expectLater(engine.setSubtitle(en), completes);
      files[en.uri] = 'not a subtitle file';
      await expectLater(engine.setSubtitle(en), completes);
      // video_player's parser throws on some files: reported the same way.
      files[en.uri] = 'a\nb\nc';
      await expectLater(engine.setSubtitle(en), completes);
      await settle();
      expect(seen.subtitleErrors, hasLength(3));
      expect(seen.subtitleErrors[1], contains('No captions'));
    });

    test('a slow file overtaken by another track never shows', () async {
      final slow = Completer<String>();
      files['https://s/slow.srt'] = slow;
      files[en.uri] = srt.replaceAll('Hello', 'Fast');
      await engine.open(stream);
      await settle();
      final first = engine.setSubtitle(
        const EngineSubtitle(uri: 'https://s/slow.srt', language: 'ar'),
      );
      await engine.setSubtitle(en);
      slow.complete(srt.replaceAll('Hello', 'Slow'));
      await first;
      expect(await at(const Duration(seconds: 2)), ['Fast', 'there']);
    });

    test('a new file drops the old file\'s subtitles', () async {
      files[en.uri] = srt;
      await engine.open(stream);
      await settle();
      await engine.setSubtitle(en);
      expect(await at(const Duration(seconds: 2)), isNotEmpty);
      await engine.open(other);
      await settle();
      expect(seen.lines.last, isEmpty);
      expect(await at(const Duration(seconds: 2)), isEmpty);
    });

    test('a slow file for the old file never shows on the new one', () async {
      final slow = Completer<String>();
      files[en.uri] = slow;
      await engine.open(stream);
      await settle();
      final loading = engine.setSubtitle(en);
      await engine.open(other);
      await settle();
      slow.complete(srt);
      await loading;
      expect(await at(const Duration(seconds: 2)), isEmpty);
    });

    test('closing while a subtitle file loads', () async {
      final slow = Completer<String>();
      files[en.uri] = slow;
      await engine.open(stream);
      final loading = engine.setSubtitle(en);
      await engine.dispose();
      slow.complete(srt);
      await expectLater(loading, completes);
    });

    test('a film-length file stays quick to follow', () async {
      final cues = StringBuffer();
      for (var i = 0; i < 20000; i++) {
        final s = Duration(milliseconds: i * 400);
        String t(Duration d) =>
            '${d.inHours.toString().padLeft(2, '0')}:'
            '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
            '${(d.inSeconds % 60).toString().padLeft(2, '0')},'
            '${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}';
        cues.write(
          '${i + 1}\n${t(s)} --> ${t(s + const Duration(milliseconds: 300))}\n'
          'Line $i\n\n',
        );
      }
      files[en.uri] = '$cues';
      await engine.open(stream);
      await settle();
      final watch = Stopwatch()..start();
      await engine.setSubtitle(en);
      for (var i = 0; i < 300; i++) {
        await engine.seek(Duration(milliseconds: i * 13337));
      }
      watch.stop();
      expect(await at(const Duration(milliseconds: 4000 * 400 + 100)), [
        'Line 4000',
      ]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  // Subtitle files come from the server and from the user's disk. Whatever
  // is in them, loading one never throws, never hangs, and only ever shows
  // non-empty lines without markup; a file that can't be read is reported.
  group('subtitle files are never trusted', () {
    const track = EngineSubtitle(uri: 'https://s/fuzz.srt', language: 'ar');
    final nasty = [
      '',
      ' ',
      '\u0000',
      '﻿',
      '‏',
      '-->',
      ' --> ',
      '\r',
      '\r\n',
      '99:99:99,999',
      '-00:00:01,000',
      '00:00:01',
      '1e9',
      '00:00:01.000',
      '00:00:01,000 --> ',
      '00:00:03,000 --> 00:00:01,000',
      '<i>',
      '</i>',
      '<i><b>x</b></i>',
      '{\\an8',
      '{\\i1}',
      '<font color="#ff0">',
      'WEBVTT',
      'NOTE x',
      'STYLE',
      '::cue',
      'ماذا تفعل؟',
      '🎬',
      'a' * 3000,
      '00:00:00,000 --> 99:59:59,999',
      '1',
      '0',
      '\t',
    ];

    String mutate(Random r, String base) {
      final lines = base.split('\n');
      final out = <String>[];
      for (final l in lines) {
        switch (r.nextInt(10)) {
          case 0:
            break; // dropped
          case 1:
            out.add(nasty[r.nextInt(nasty.length)]);
          case 2:
            out
              ..add(l)
              ..add(nasty[r.nextInt(nasty.length)]);
          case 3:
            out.add(l.replaceAll('-->', nasty[r.nextInt(nasty.length)]));
          case 4:
            out.add(l.replaceAll(RegExp(r'\d'), '${r.nextInt(10)}'));
          default:
            out.add(l);
        }
      }
      return out.join(r.nextBool() ? '\n' : '\r\n');
    }

    final vtt =
        'WEBVTT\n\n${srt.replaceAll(',', '.').replaceAll(RegExp(r'^\d+\n', multiLine: true), '')}';

    for (final (name, base) in [('SubRip', srt), ('WebVTT', vtt)]) {
      test('broken $name files', () async {
        await engine.open(stream);
        await settle();
        for (var seed = 0; seed < 300; seed++) {
          final r = Random(seed);
          final text = r.nextInt(8) == 0
              ? List.generate(
                  r.nextInt(30),
                  (_) => nasty[r.nextInt(nasty.length)],
                ).join('\n')
              : mutate(r, base);
          files[track.uri] = text;
          final errorsBefore = seen.subtitleErrors.length;
          final linesBefore = seen.lines.length;
          await expectLater(
            engine.setSubtitle(track).timeout(const Duration(seconds: 2)),
            completes,
            reason: 'seed $seed',
          );
          for (final t in [0, 1500, 2000, 5500, 7200000]) {
            await engine.seek(Duration(milliseconds: t));
          }
          await settle();
          final shown = seen.lines.skip(linesBefore).expand((l) => l);
          for (final line in shown) {
            expect(line.trim(), isNotEmpty, reason: 'seed $seed');
            // plainCaptionText's contract: whole markup blocks go. (A
            // brace a broken file never closes shows as text.)
            expect(
              line,
              isNot(matches(RegExp(r'\{\\[^}]*\}|</?(i|b|u|s|font)\b[^>]*>'))),
              reason: 'seed $seed: $line',
            );
          }
          expect(
            seen.subtitleErrors.length - errorsBefore,
            lessThanOrEqualTo(1),
            reason: 'seed $seed',
          );
        }
      });
    }
  });
}
