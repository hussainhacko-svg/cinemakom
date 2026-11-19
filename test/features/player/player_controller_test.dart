import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
import 'package:cinemakom/core/network/api_providers.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/features/player/player_controller.dart';
import 'package:cinemakom/features/player/player_state.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repositories/fake_api_client.dart';
import 'fake_engine.dart';

typedef Route = (bool Function(ApiRequest), Object? Function(ApiRequest));
typedef F = FakeApiClient;

/// Streams that stay valid, so the repository's own refresh never kicks in.
List<Map<String, String>> streams([
  List<String> qualities = const ['1080p', '720p', '480p'],
  String tag = 'a',
]) => [
  for (final q in qualities)
    {
      'resolution': q,
      'videoUrl':
          'https://cdn.shabakaty.com/$tag-$q.mp4?Expires=4070908800&Signature=S',
    },
];

bool _fresh(ApiRequest r) => r.query.containsKey('_');

const movie = PlaybackRequest(
  item: MediaItem(
    id: '7',
    title: LocalizedText(en: 'Movie'),
    kind: VideoKind.movies,
  ),
);

class Env {
  Env(this.async, this.c, this.engine, this.api, this.request);

  final FakeAsync async;
  final ProviderContainer c;
  final FakeEngine engine;
  final FakeApiClient api;
  final PlaybackRequest request;

  PlayerController get controller =>
      c.read(playerControllerProvider(request).notifier);
  PlayerState get state => c.read(playerControllerProvider(request));
  int get freshRequests => api.requests.where(_fresh).length;

  void flush([Duration d = Duration.zero]) {
    async.elapse(d);
    async.flushMicrotasks();
  }
}

Env start(
  FakeAsync async, {
  List<Route> routes = const [],
  PlaybackRequest request = movie,
  Map<String, Object> prefs = const {},
  FakeEngine? fake,
}) {
  final engine = fake ?? FakeEngine();
  final api = F([
    ...routes,
    F.path('transcoddedFiles/', streams()),
    F.fixtureAt('translationFiles/', 'subtitles_movie'),
    F.fixtureAt('allVideoInfo/', 'video_info_movie'),
    F.fixtureAt('video_thumbnails/', 'thumbnails_none'),
    F.fixtureAt('videoSeason/', 'series_episodes'),
  ]);
  final c = ProviderContainer(
    retry: noRetry,
    overrides: [
      preferenceStoreProvider.overrideWith(
        (ref) =>
            MemoryPreferenceStore({PreferenceKeys.language: 'en', ...prefs}),
      ),
      apiClientProvider.overrideWithValue(api),
      playerEngineFactoryProvider.overrideWithValue(() => engine),
    ],
  );
  c.read(preferenceStoreProvider.future);
  async.flushMicrotasks();
  c.listen(playerControllerProvider(request), (_, _) {});
  final env = Env(async, c, engine, api, request)..flush();
  return env;
}

void main() {
  test('opens the default quality with the shared headers and subtitles', () {
    fakeAsync((async) {
      final env = start(async);
      final open = env.engine.opened.single;
      expect(open.source.uri, contains('a-1080p'));
      expect(open.source.headers, ApiClient.defaultHeaders);
      expect(open.start, Duration.zero);
      expect(env.state.phase, PlayerPhase.loading);
      // Settings default: Arabic, drawn by Flutter (not styled).
      final sub = env.engine.subtitles.last!;
      expect((sub.language, sub.styled), ('ar', false));

      env.engine.emitReady();
      expect(env.state.phase, PlayerPhase.ready);
      expect(env.state.playing, isTrue);
    });
  });

  test('a missing preferred quality picks the nearest lower one', () {
    fakeAsync((async) {
      final env = start(
        async,
        routes: [
          F.path('transcoddedFiles/', streams(['2160p', '720p'])),
        ],
        prefs: {PreferenceKeys.defaultQuality: 1080},
      );
      expect(env.engine.opened.single.source.uri, contains('a-720p'));
    });
  });

  test('an early "completed" is a failure: fresh URLs, same position', () {
    fakeAsync((async) {
      final env = start(
        async,
        routes: [
          (
            (r) => r.path.startsWith('transcoddedFiles/') && _fresh(r),
            (_) => streams(const ['1080p', '720p'], 'b'),
          ),
        ],
      );
      env.engine.emitReady(at: const Duration(seconds: 16));
      env.engine.emitCompleted();
      env.flush();

      expect(env.freshRequests, 1);
      expect(env.engine.opened, hasLength(2));
      final reopen = env.engine.opened.last;
      expect(reopen.source.uri, contains('b-1080p'));
      expect(reopen.start, const Duration(seconds: 16));
      // The subtitle is set again after reopening.
      expect(env.engine.subtitles, hasLength(2));
      expect(env.state.phase, PlayerPhase.loading);
    });
  });

  test('"completed" near the end is the end', () {
    fakeAsync((async) {
      final env = start(async);
      env.engine.emitReady(
        duration: const Duration(minutes: 100),
        at: const Duration(minutes: 100) - const Duration(seconds: 3),
      );
      env.engine.emitCompleted();
      env.flush();
      expect(env.state.phase, PlayerPhase.ended);
      expect(env.engine.opened, hasLength(1));
    });
  });

  test('open errors retry with backoff, then fail', () {
    fakeAsync((async) {
      final env = start(async);
      for (final delay in PlayerController.recoveryDelays) {
        env.engine.emitError('Failed to open https://cdn/x.mp4.');
        env.flush(delay);
      }
      expect(
        env.engine.opened,
        hasLength(1 + PlayerController.recoveryDelays.length),
      );
      expect(env.freshRequests, PlayerController.recoveryDelays.length);
      env.engine.emitError('Failed to open https://cdn/x.mp4.');
      env.flush();
      expect(env.state.phase, PlayerPhase.failed);
      expect(env.state.error, PlayerFailure.playback);
    });
  });

  test('errors while playing are left to the player', () {
    fakeAsync((async) {
      final env = start(async);
      env.engine.emitReady();
      env.engine.emitError('tcp: Connection reset by peer');
      env.flush(const Duration(seconds: 3));
      expect(env.engine.opened, hasLength(1));
      expect(env.state.phase, PlayerPhase.ready);
    });
  });

  test('the watchdog reopens a stalled stream, but not a paused one', () {
    fakeAsync((async) {
      final env = start(async);
      env.engine.emitReady(at: const Duration(minutes: 5));

      env.controller.pause();
      env.flush(const Duration(seconds: 30));
      expect(env.engine.opened, hasLength(1));

      env.controller.play();
      env.flush(
        const Duration(seconds: PlayerController.stallLimitPlaying + 1),
      );
      expect(env.engine.opened, hasLength(2));
      expect(env.engine.opened.last.start, const Duration(minutes: 5));
    });
  });

  test('a failure refreshing the URLs shows the API error', () {
    fakeAsync((async) {
      final env = start(
        async,
        routes: [
          (
            (r) => r.path.startsWith('transcoddedFiles/') && _fresh(r),
            (_) => offline,
          ),
        ],
      );
      env.engine.emitReady();
      env.engine.emitCompleted();
      env.flush();
      expect(env.state.phase, PlayerPhase.failed);
      expect(env.state.error, isA<ApiException>());
    });
  });

  test('loading errors: API failure, and no streams at all', () {
    fakeAsync((async) {
      var env = start(async, routes: [F.path('transcoddedFiles/', offline)]);
      expect(env.state.phase, PlayerPhase.failed);
      expect(env.state.error, isA<ApiException>());
      expect(env.engine.opened, isEmpty);

      env = start(async, routes: [F.path('transcoddedFiles/', <Object?>[])]);
      expect(env.state.error, PlayerFailure.unavailable);
    });
  });

  test('switching quality keeps the position, pause and subtitle', () {
    fakeAsync((async) {
      final env = start(async);
      env.engine.emitReady(at: const Duration(minutes: 10));
      env.controller.pause();
      env.flush();
      final hd = env.state.sources.firstWhere((s) => s.height == 720);
      env.controller.selectQuality(hd);
      env.flush();

      final reopen = env.engine.opened.last;
      expect(reopen.source.uri, contains('a-720p'));
      expect(reopen.start, const Duration(minutes: 10));
      expect(reopen.play, isFalse);
      expect(env.engine.subtitles.last!.language, 'ar');

      // Opened paused: ready once buffered, and the watchdog stays quiet.
      env.engine.emitReady(at: const Duration(minutes: 10));
      env.flush(const Duration(seconds: 30));
      expect(env.state.phase, PlayerPhase.ready);
      expect(env.engine.opened, hasLength(2));
    });
  });

  test(
    'plain subtitle text is passed on; styled and failed tracks are not',
    () {
      fakeAsync((async) {
        final env = start(async);
        env.engine.emitSubtitleText([' مرحبا ', '']);
        expect(env.controller.subtitleLines.value, ['مرحبا']);

        env.engine.emitSubtitleError();
        expect(env.state.subtitle.isOff, isTrue);
        expect(env.state.subtitleFailed, isTrue);
        env.engine.emitSubtitleText(['x']);
        expect(env.controller.subtitleLines.value, isEmpty);
      });
    },
  );

  test('an episode switch keeps the chosen quality, subtitle and speed', () {
    fakeAsync((async) {
      const series = PlaybackRequest(
        item: MediaItem(
          id: '4328',
          title: LocalizedText(en: 'Friends'),
          kind: VideoKind.series,
        ),
      );
      final env = start(async, request: series);
      expect(env.state.episodes, isNotEmpty);

      final english = env.state.subtitles.firstWhere(
        (o) => o.languageCode == 'en',
      );
      env.controller
        ..selectQuality(env.state.sources.firstWhere((s) => s.height == 480))
        ..selectSubtitle(english)
        ..setSpeed(1.5);
      env.flush();

      final next = env.state.episodes[1];
      env.controller.playEpisode(next);
      env.flush();
      expect(env.state.videoId, next.id);
      expect(env.engine.opened.last.source.uri, contains('a-480p'));
      expect(env.engine.subtitles.last!.language, 'en');
      expect(env.state.speed, 1.5);
      expect(env.engine.rate, 1.5);
    });
  });

  test('a quality switch keeps speed, subtitle delay and fit', () {
    fakeAsync((async) {
      final env = start(async);
      env.engine.emitReady(at: const Duration(minutes: 4));
      env.controller
        ..setSpeed(1.25)
        ..nudgeSubtitleDelay(const Duration(milliseconds: 500))
        ..nudgeSubtitleDelay(const Duration(milliseconds: 500))
        ..setFit(VideoFit.fill);
      env.flush();
      env.controller.selectQuality(
        env.state.sources.firstWhere((s) => s.height == 480),
      );
      env.flush();

      expect(env.engine.opened.last.start, const Duration(minutes: 4));
      expect(env.engine.opened.last.play, isTrue);
      expect(env.state.speed, 1.25);
      expect(env.engine.rate, 1.25);
      expect(env.state.subtitleDelay, const Duration(seconds: 1));
      expect(env.engine.subtitleDelay, const Duration(seconds: 1));
      expect(env.state.fit, VideoFit.fill);
      expect(env.engine.subtitles.last!.language, 'ar');
    });
  });

  test('the subtitle delay steps, resets and stays within a minute', () {
    fakeAsync((async) {
      final env = start(async);
      env.controller.nudgeSubtitleDelay(const Duration(milliseconds: -500));
      env.flush();
      expect(env.engine.subtitleDelay, const Duration(milliseconds: -500));
      env.controller.setSubtitleDelay(const Duration(minutes: 5));
      env.flush();
      expect(env.state.subtitleDelay, const Duration(seconds: 60));
      env.controller.setSubtitleDelay(Duration.zero);
      env.flush();
      expect(env.engine.subtitleDelay, Duration.zero);
    });
  });

  test('the fit cycles Fit, Fill, Stretch', () {
    fakeAsync((async) {
      final env = start(async);
      expect(env.state.fit, VideoFit.fit);
      expect(env.controller.cycleFit(), VideoFit.fill);
      expect(env.controller.cycleFit(), VideoFit.stretch);
      expect(env.controller.cycleFit(), VideoFit.fit);
    });
  });

  test('the subtitle size setting sizes libass, also when it changes', () {
    fakeAsync((async) {
      final env = start(async, prefs: {PreferenceKeys.subtitleSize: 'small'});
      expect(env.engine.subtitleScale, 0.85);
      env.c.read(settingsProvider.notifier).setSubtitleSize(SubtitleSize.large);
      env.flush();
      expect(env.engine.subtitleScale, 1.2);
    });
  });

  test('the next episode starts at 0, though the old one plays on', () {
    fakeAsync((async) {
      const series = PlaybackRequest(
        item: MediaItem(
          id: '4328',
          title: LocalizedText(en: 'Friends'),
          kind: VideoKind.series,
        ),
      );
      final env = start(async, request: series);
      env.engine.emitReady(at: const Duration(minutes: 12));
      env.controller.playEpisode(env.state.episodes[1]);
      // The old file is still playing while the new streams load.
      env.engine.emitPosition(const Duration(minutes: 12, seconds: 1));
      env.flush();
      expect(env.engine.opened.last.start, Duration.zero);
      expect(env.controller.position.value, Duration.zero);
    });
  });

  test('styled subtitles are offered only where the engine draws them', () {
    fakeAsync((async) {
      final routes = [F.fixtureAt('translationFiles/', 'subtitles_special')];
      final mpv = start(async, routes: routes);
      expect(mpv.state.subtitles.where((o) => o.isStyled), isNotEmpty);

      final exo = start(
        async,
        routes: routes,
        fake: FakeEngine(supportsStyledSubtitles: false),
      );
      expect(exo.state.subtitles.where((o) => o.isStyled), isEmpty);
      expect(exo.state.subtitles.where((o) => o.languageCode == 'ar'), [
        isA<Object>(),
      ]);
    });
  });

  test('closing the player disposes the engine', () {
    fakeAsync((async) {
      final env = start(async);
      env.c.dispose();
      env.flush();
      expect(env.engine.disposed, isTrue);
    });
  });
}
