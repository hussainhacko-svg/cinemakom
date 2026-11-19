// Phase 4 M0 spike (docs/PLAYER.md §10): measures media_kit against the
// live CDN. Throwaway: the findings go into PLAYER.md, then this file goes.
//
//   fvm flutter test integration_test/player_spike_test.dart -d linux \
//     --dart-define=PROXY=http://127.0.0.1
//
// The failure tests need the spike proxy (scratchpad tools/cut_proxy.py) on
// ports 8765 (403after) and 8766 (deny). On the Android emulator use
// PROXY=http://10.0.2.2.
import 'dart:async';
import 'dart:io';

import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/data/models/playback_models.dart' as m;
import 'package:cinemakom/data/repositories/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

const movieId = '191463'; // Avengers: 240p–1080p and 4K, 1080p not fast-start
const animeId = '279230'; // Attack on Titan S4E3: SRT, VTT and styled ASS
const proxy = String.fromEnvironment('PROXY');
const vo = String.fromEnvironment('VO');
const hwdec = String.fromEnvironment('HWDEC');

final out = <String>[];
void log(String s) {
  out.add(s);
  // ignore: avoid_print
  print('SPIKE: $s');
}

Future<T?> waitFor<T>(
  Stream<T> stream,
  bool Function(T) test, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  try {
    return await stream.firstWhere(test).timeout(timeout);
  } on TimeoutException {
    return null;
  }
}

Future<(Player, VideoController)> pumpPlayer(
  WidgetTester tester, {
  bool libass = false,
  String? androidFont,
}) async {
  final player = Player(
    configuration: PlayerConfiguration(
      bufferSize: 64 * 1024 * 1024,
      libass: libass,
      libassAndroidFont: androidFont,
      libassAndroidFontName: androidFont == null
          ? null
          : 'IBM Plex Sans Arabic',
      logLevel: MPVLogLevel.warn,
    ),
  );
  final controller = VideoController(
    player,
    configuration: VideoControllerConfiguration(
      vo: vo.isEmpty ? null : vo,
      hwdec: hwdec.isEmpty ? null : hwdec,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Video(controller: controller, controls: NoVideoControls),
      ),
    ),
  );
  final native = player.platform! as NativePlayer;
  await native.setProperty('ytdl', 'no');
  await native.setProperty('network-timeout', '20');
  return (player, controller);
}

Future<void> settle(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();
  final repo = MediaRepository(ApiClient());
  final platform = Platform.operatingSystem;

  tearDownAll(() async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/player_spike_$platform.txt');
    await f.writeAsString(out.join('\n'));
    // ignore: avoid_print
    print('SPIKE report: ${f.path}');
  });

  testWidgets('start, seek and quality switch', (tester) async {
    final sources = await repo.streams(movieId);
    log('streams: ${sources.map((s) => s.label).join(', ')}');
    final (player, _) = await pumpPlayer(tester);
    final errors = <String>[];
    final logs = <String>[];
    player.stream.error.listen(errors.add);
    player.stream.log.listen((l) => logs.add('${l.prefix}: ${l.text.trim()}'));
    String stateNow() =>
        'pos=${player.state.position} dur=${player.state.duration} '
        'playing=${player.state.playing} buffering=${player.state.buffering} '
        'w=${player.state.width} errors=$errors logs=${logs.take(6).toList()}';

    for (final q in [1080, 2160, 720]) {
      final src = sources.firstWhere((s) => s.height == q);
      for (final start in [Duration.zero, const Duration(minutes: 60)]) {
        errors.clear();
        logs.clear();
        final t = Stopwatch()..start();
        await player.open(
          Media(src.url, httpHeaders: ApiClient.defaultHeaders, start: start),
        );
        // Playing: position moves past the start.
        final p = await waitFor(
          player.stream.position,
          (p) => p > start + const Duration(milliseconds: 500),
        );
        log(
          '${q}p start=${start.inMinutes}min: '
          '${p == null ? 'TIMEOUT ${stateNow()}' : 'playing ${t.elapsedMilliseconds}ms (w=${player.state.width})'}',
        );
        await settle(tester, const Duration(seconds: 2));
      }
    }

    // Seek far outside the buffer, on 1080p.
    final hd = sources.firstWhere((s) => s.height == 1080);
    await player.open(Media(hd.url, httpHeaders: ApiClient.defaultHeaders));
    await waitFor(
      player.stream.position,
      (p) => p > const Duration(seconds: 1),
    );
    for (final to in [
      const Duration(minutes: 30),
      const Duration(minutes: 120),
    ]) {
      final t = Stopwatch()..start();
      await player.seek(to);
      await waitFor(
        player.stream.position,
        (p) => p > to + const Duration(milliseconds: 500),
      );
      log(
        'seek to ${to.inMinutes}min on 1080p: playing after ${t.elapsedMilliseconds}ms',
      );
    }

    // Quality switch at a position: 720p at 10 min → 1080p at the same spot.
    final sd = sources.firstWhere((s) => s.height == 720);
    await player.open(
      Media(
        sd.url,
        httpHeaders: ApiClient.defaultHeaders,
        start: const Duration(minutes: 10),
      ),
    );
    await waitFor(
      player.stream.position,
      (p) => p > const Duration(minutes: 10, seconds: 2),
    );
    final at = player.state.position;
    final t = Stopwatch()..start();
    await player.open(
      Media(hd.url, httpHeaders: ApiClient.defaultHeaders, start: at),
    );
    final resumed = await waitFor(player.stream.position, (p) => p > at);
    log(
      'quality switch 720p→1080p at $at: resumed at $resumed '
      'after ${t.elapsedMilliseconds}ms, playing=${player.state.playing}',
    );
    log('errors: $errors');
    await player.dispose();
  });

  // Android: only the first open() shows video (EGL context fails on the
  // next). Try keeping the VO alive, and a new Player per file.
  for (final variant in ['force-window', 'new-player']) {
    testWidgets('reopen: $variant', (tester) async {
      final sources = await repo.streams(movieId);
      Player? player;
      final logs = <String>[];
      Future<Player> fresh() async {
        await player?.dispose();
        final (p, _) = await pumpPlayer(tester);
        p.stream.log.listen((l) => logs.add('${l.prefix}: ${l.text.trim()}'));
        if (variant == 'force-window') {
          await (p.platform! as NativePlayer).setProperty(
            'force-window',
            'yes',
          );
        }
        return p;
      }

      player = await fresh();
      for (final q in [1080, 720, 2160, 480]) {
        if (variant == 'new-player' && q != 1080) player = await fresh();
        logs.clear();
        final src = sources.firstWhere((s) => s.height == q);
        final t = Stopwatch()..start();
        await player!.open(
          Media(src.url, httpHeaders: ApiClient.defaultHeaders),
        );
        final p = await waitFor(
          player.stream.position,
          (p) => p > const Duration(milliseconds: 500),
        );
        await settle(tester, const Duration(seconds: 2));
        final shot = await player.screenshot(format: 'image/jpeg');
        log(
          '$variant ${q}p: ${p == null ? 'TIMEOUT' : 'playing ${t.elapsedMilliseconds}ms'} '
          'w=${player.state.width} pos=${player.state.position} '
          'screenshot=${shot?.length ?? 0}B '
          'vo errors=${logs.where((l) => l.contains('vo')).take(2).toList()}',
        );
      }
      await player?.dispose();
    });
  }

  testWidgets('hold: play 1080p for 20 s (screen capture from outside)', (
    tester,
  ) async {
    final sources = await repo.streams(movieId);
    final (player, _) = await pumpPlayer(tester);
    final logs = <String>[];
    player.stream.log.listen((l) => logs.add('${l.prefix}: ${l.text.trim()}'));
    final src = sources.firstWhere((s) => s.height == 1080);
    await player.open(Media(src.url, httpHeaders: ApiClient.defaultHeaders));
    final p = await waitFor(
      player.stream.position,
      (p) => p > const Duration(milliseconds: 500),
    );
    log(
      'hold vo=$vo hwdec=$hwdec: ${p == null ? 'TIMEOUT' : 'playing'} '
      'w=${player.state.width} hwdec-current=${await (player.platform! as NativePlayer).getProperty('hwdec-current')} '
      'logs=${logs.take(4).toList()}',
    );
    await settle(tester, const Duration(seconds: 20));
    await player.dispose();
  });

  testWidgets('hybrid subtitles and the libass font', (tester) async {
    // libass needs the font as a file. Android reads it from the assets
    // (libassAndroidFont); elsewhere copy it to disk and set sub-fonts-dir.
    final fontAsset = 'assets/fonts/IBMPlexSansArabic-Regular.ttf';
    final (player, _) = await pumpPlayer(
      tester,
      libass: true,
      androidFont: Platform.isAndroid ? fontAsset : null,
    );
    final native = player.platform! as NativePlayer;
    if (!Platform.isAndroid) {
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/fonts',
      )..createSync(recursive: true);
      final data = await rootBundle.load(fontAsset);
      File('${dir.path}/IBMPlexSansArabic-Regular.ttf')
          .writeAsBytesSync(data.buffer.asUint8List());
      await native.setProperty('sub-fonts-dir', dir.path);
      await native.setProperty('sub-font', 'IBM Plex Sans Arabic');
      log('sub-fonts-dir set at runtime: ${dir.path}');
    }

    final sources = await repo.streams(animeId);
    final tracks = await repo.subtitles(animeId);
    final plain = m.oneTrackPerLanguage(tracks);
    final srt = plain.firstWhere((t) => t.languageCode == 'ar' && !t.isStyled);
    final ass = plain.firstWhere((t) => t.isStyled);
    log('subtitle tracks: $plain');

    final src = sources.firstWhere((s) => s.height == 720);
    await player.open(
      Media(
        src.url,
        httpHeaders: ApiClient.defaultHeaders,
        start: const Duration(seconds: 95),
      ),
    );
    await waitFor(
      player.stream.position,
      (p) => p > const Duration(seconds: 95),
    );

    // 1. Plain SRT drawn by Flutter: libass off for it, text from sub-text.
    await native.setProperty('sub-visibility', 'no');
    final texts = <String>[];
    final sub = player.stream.subtitle.listen((l) {
      final s = l.where((e) => e.trim().isNotEmpty).join(' / ');
      if (s.isNotEmpty) texts.add(s);
    });
    await player.setSubtitleTrack(
      SubtitleTrack.uri(srt.url, title: 'Arabic', language: 'ar'),
    );
    await player.seek(const Duration(seconds: 97));
    await settle(tester, const Duration(seconds: 6));
    log(
      'SRT with sub-visibility=no: ${texts.length} texts, first: ${texts.take(2).toList()}',
    );
    final shotSrt = await player.screenshot(
      format: 'image/png',
      includeLibassSubtitles: true,
    );

    // 2. Styled ASS drawn by libass.
    texts.clear();
    await native.setProperty('sub-visibility', 'yes');
    await player.setSubtitleTrack(
      SubtitleTrack.uri(ass.url, title: 'Arabic (styled)', language: 'ar'),
    );
    await player.seek(const Duration(seconds: 97));
    await settle(tester, const Duration(seconds: 3));
    await player.pause();
    await settle(tester, const Duration(seconds: 1));
    final shotAss = await player.screenshot(
      format: 'image/png',
      includeLibassSubtitles: true,
    );
    log(
      'ASS with sub-visibility=yes: sub-text still sent: ${texts.length} texts',
    );

    // 3. Delay and scale work at runtime.
    await native.setProperty('sub-delay', '1.5');
    await native.setProperty('sub-scale', '1.2');
    log(
      'sub-delay now ${await native.getProperty('sub-delay')}, sub-scale ${await native.getProperty('sub-scale')}',
    );

    final dir = await getTemporaryDirectory();
    for (final (name, bytes) in [('srt', shotSrt), ('ass', shotAss)]) {
      if (bytes == null) continue;
      final f = File('${dir.path}/spike_${platform}_$name.png')
        ..writeAsBytesSync(bytes);
      log('screenshot $name: ${f.path}');
    }
    await sub.cancel();
    await player.dispose();
  });

  testWidgets('failures: cut mid-play then 403, and 403 at open', (
    tester,
  ) async {
    if (proxy.isEmpty) {
      log('no PROXY define, skipping failure tests');
      return;
    }
    final (player, _) = await pumpPlayer(tester);
    final errors = <String>[];
    final completed = <Duration>[];
    player.stream.error.listen((e) => errors.add(e));
    player.stream.completed.listen((c) {
      if (c) completed.add(player.state.position);
    });

    // Mid-play: the proxy cuts the body read after 6 MB, then answers 403.
    await player.open(
      Media('$proxy:8765/v', httpHeaders: ApiClient.defaultHeaders),
    );
    await waitFor(
      player.stream.position,
      (p) => p > const Duration(seconds: 1),
    );
    final sawCompleted = await waitFor(
      player.stream.completed,
      (c) => c,
      timeout: const Duration(seconds: 90),
    );
    log(
      'mid-play cut+403: completed=$sawCompleted at ${player.state.position} '
      'of ${player.state.duration}, buffering=${player.state.buffering}, '
      'errors=$errors',
    );

    // At open: every request answers 403.
    errors.clear();
    completed.clear();
    final t = Stopwatch()..start();
    Object? thrown;
    try {
      await player.open(
        Media('$proxy:8766/v', httpHeaders: ApiClient.defaultHeaders),
      );
    } catch (e) {
      thrown = e;
    }
    await waitFor(
      player.stream.error,
      (_) => true,
      timeout: const Duration(seconds: 30),
    );
    await settle(tester, const Duration(seconds: 2));
    log(
      '403 at open: thrown=$thrown, errors=$errors after ${t.elapsedMilliseconds}ms, '
      'completed=$completed, duration=${player.state.duration}, '
      'buffering=${player.state.buffering}',
    );
    await player.dispose();
  });
}
