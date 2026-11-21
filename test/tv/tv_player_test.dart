import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/features/player/player_labels.dart';
import 'package:cinemakom/tv/player/tv_player_screen.dart';
import 'package:cinemakom/tv/player/tv_seek.dart';
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/tv_router.dart';

import '../features/player/fake_engine.dart';
import '../helpers/app_harness.dart';
import '../repositories/fake_api_client.dart';
import 'reachability.dart';
import 'tv_driver.dart';

// The TV player (docs/TV.md §8, TV-4) with a FakeEngine: the controls by
// remote, seeking with the controls hidden, the panels, Skip intro and the
// episodes. The fixture movie (3119279) has a 0–27.1 s intro; the fixture
// series (4328) has six episodes, one per season.

const _movie = PlaybackRequest(item: MediaItem(id: '3119279'));
const _episode = PlaybackRequest(
  item: MediaItem(
    id: '4328',
    title: LocalizedText(en: 'Friends'),
    kind: VideoKind.series,
  ),
  episodeId: '4401',
);

final _player = find.byType(TvPlayerScreen);

/// The app on TV, then the player for [request], ready at [at].
Future<TvDriver> _open(
  WidgetTester tester,
  FakeEngine engine, {
  PlaybackRequest request = _movie,
  Duration at = const Duration(minutes: 10),
  Duration duration = const Duration(hours: 2),
  bool arabic = false,
  bool pause = false,
}) async {
  await tester.pumpWidget(const SizedBox());
  await pumpApp(
    tester,
    tv: true,
    engine: engine,
    store: MemoryPreferenceStore({
      PreferenceKeys.language: arabic ? 'ar' : 'en',
    }),
  );
  ProviderScope.containerOf(tester.element(find.byType(TvApp)))
      .read(tvRouterProvider)
      .push('/watch/${request.videoId}', extra: request);
  // The bulbs show while it opens: no pumpAndSettle yet.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  engine.emitReady(at: at, duration: duration);
  if (pause) await engine.pause();
  await tester.pumpAndSettle();
  return TvDriver(tester);
}

void main() {
  testWidgets('opens with Play/Pause focused; the chips are there', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine);
    expect(_player, findsOneWidget);
    expect(tv.focused, 'Pause');
    expect(find.text('Eve of Destruction'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);

    // Up twice: the seek bar, then (Skip intro is gone at 10 min) the chips.
    await tv.up();
    expect(tv.focused, 'Playback position');
    await tv.up();
    expect(tv.focused, anyOf(startsWith('Subtitles'), startsWith('Quality')));
  });

  testWidgets('the controls hide after 5 s; then OK pauses and shows them', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine);
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pumpAndSettle();
    expect(tv.focused, 'Video');

    await tv.ok();
    expect(engine.isPlaying, isFalse);
    expect(tv.focused, 'Play');
    // Paused, they stay.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tv.focused, 'Play');
  });

  testWidgets('the controls fade out and back in', (tester) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine);
    double opacity() => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('Eve of Destruction'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(opacity(), 1);

    // Halfway through hiding: neither shown nor gone (it used to jump).
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pump();
    await tester.pump(controlsFadeOut ~/ 2);
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacity(), 0);

    // Down shows them again, fading in.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(controlsFadeIn ~/ 2);
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(tv.focused, 'Pause');
  });

  testWidgets('hidden: Right seeks 10 s once the keys stop; Back cancels', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine);
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pumpAndSettle();
    expect(tv.focused, 'Video');

    await tv.right();
    await tv.right();
    // The target moved, the video didn't.
    expect(engine.seeks, isEmpty);
    expect(find.text('+0:20'), findsOneWidget);
    expect(find.textContaining('was 10:00'), findsOneWidget);
    await tester.pump(TvScrub.settle);
    expect(engine.seeks.last, const Duration(minutes: 10, seconds: 20));
    // Still watching: the controls didn't come up.
    expect(tv.focused, 'Video');

    await tv.left();
    await tv.back();
    await tester.pump(TvScrub.settle);
    expect(engine.seeks, hasLength(1));
    expect(_player, findsOneWidget);

    // Back again leaves the player.
    await tv.back();
    expect(_player, findsNothing);
    expect(engine.disposed, isTrue);
  });

  testWidgets('a held arrow speeds up: 10 s, then 30 s, then 60 s steps', (
    tester,
  ) async {
    final scrub = TvScrub(onCommit: (_) {});
    addTearDown(scrub.dispose);
    const total = Duration(hours: 5);
    void step({bool repeat = true}) => scrub.step(
      forward: true,
      repeat: repeat,
      position: Duration.zero,
      duration: total,
    );
    // A key repeat every 100 ms, as a held arrow sends them.
    final steps = <Duration>[];
    var last = Duration.zero;
    step(repeat: false);
    for (var t = 100; t <= 6000; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      step();
      steps.add(scrub.target! - last);
      last = scrub.target!;
    }
    expect(steps[5], const Duration(seconds: 10)); // at 0.6 s
    expect(steps[25], const Duration(seconds: 30)); // at 2.6 s
    expect(steps[55], const Duration(seconds: 60)); // at 5.6 s
    // A fresh press starts again at 10 s.
    final before = scrub.target!;
    step(repeat: false);
    expect(scrub.target! - before, const Duration(seconds: 10));
    scrub.cancel();
  });

  testWidgets('the seek bar scrubs; OK plays from there; Up leaves it', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine, pause: true);
    await tv.up();
    expect(tv.focused, 'Playback position');
    await tv.right();
    await tv.right();
    await tv.right();
    await tv.ok();
    expect(engine.seeks.last, const Duration(minutes: 10, seconds: 30));

    await tv.left();
    await tv.up();
    await tester.pump(TvScrub.settle);
    expect(engine.seeks, hasLength(1));
  });

  testWidgets('Back hides the controls first, then leaves', (tester) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine, pause: true);
    await tv.back();
    expect(tv.focused, 'Video');
    expect(_player, findsOneWidget);
    await tv.back();
    expect(_player, findsNothing);
  });

  testWidgets('media keys work with the controls hidden or shown', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine);
    await tv.press(LogicalKeyboardKey.mediaPlayPause);
    expect(engine.isPlaying, isFalse);
    await tv.press(LogicalKeyboardKey.mediaPlay);
    expect(engine.isPlaying, isTrue);
    await tv.press(LogicalKeyboardKey.mediaFastForward);
    await tester.pump(TvScrub.settle);
    expect(engine.seeks.last, const Duration(minutes: 10, seconds: 10));
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pumpAndSettle();
    await tv.press(LogicalKeyboardKey.space);
    expect(engine.isPlaying, isFalse);
  });

  testWidgets('the quality panel opens on the current one and switches', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine, pause: true);
    await tv.focusLabel('Quality: 1080p');
    await tv.ok();
    expect(find.text('QUALITY'), findsOneWidget);
    expect(tv.focused, '1080p');
    await tv.down();
    final picked = tv.focused;
    // It reopens at the same place: the bulbs show until it's ready.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    engine.emitReady(at: const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(find.text('QUALITY'), findsNothing);
    // Back on the chip, which says the new quality.
    expect(tv.focused, 'Quality: ${picked.split(',').first}');
    expect(engine.opened.last.start, const Duration(minutes: 10));
  });

  testWidgets('the subtitles panel: Sync steps in place, a track closes it', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine, pause: true);
    await tv.focusLabel('Subtitles: Arabic');
    await tv.ok();
    expect(find.text('SUBTITLES'), findsOneWidget);
    expect(tv.focused, 'Arabic');

    await tv.focusLabel('Show subtitles later');
    await tv.ok();
    await tv.ok();
    expect(engine.subtitleDelay, const Duration(seconds: 1));
    expect(find.text('+1 s'), findsOneWidget);
    // Reset is reachable now, and puts it back.
    await tv.right();
    expect(tv.focused, 'Reset');
    await tv.ok();
    expect(engine.subtitleDelay, Duration.zero);

    await tv.focusLabel('Off');
    await tv.ok();
    expect(find.text('SUBTITLES'), findsNothing);
    expect(engine.subtitles.last, isNull);
  });

  testWidgets('Skip intro takes the focus over the video; OK skips', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine, at: const Duration(seconds: 2));
    // With the controls up it sits above the bar.
    expect(find.text('Skip intro'), findsOneWidget);
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pumpAndSettle();
    expect(tv.focused, 'Skip intro');

    // Left and Right still seek from it.
    await tv.right();
    expect(find.text('+0:10'), findsOneWidget);
    await tv.back();

    await tv.ok();
    expect(engine.seeks.last, const Duration(milliseconds: 27121));
    expect(find.text('Skip intro'), findsNothing);
    expect(tv.focused, 'Video');
  });

  testWidgets('a series: Episodes panel opens on the episode playing', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(tester, engine, request: _episode, pause: true);
    expect(find.text('Season 2 · Episode 1'), findsOneWidget);
    await tv.focusLabel('Episodes');
    await tv.ok();
    expect(find.text('EPISODES'), findsOneWidget);
    expect(tv.focused, startsWith('Episode 1'));
    expect(tv.focused, contains('Playing'));

    // Left to the seasons, down one: Season 3's episode.
    await tv.left();
    expect(tv.focused, 'Season 2');
    await tv.down();
    await tv.right();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('EPISODES'), findsNothing);
    // The fixture streams are the same file for every episode.
    expect(engine.opened, hasLength(2));
    await tester.pump(const Duration(milliseconds: 500));
    engine.emitReady();
    await tester.pumpAndSettle();
    expect(find.text('Season 3 · Episode 1'), findsOneWidget);
  });

  testWidgets('Up next waits for the last 10 s, then takes the focus', (
    tester,
  ) async {
    final engine = FakeEngine();
    final tv = await _open(
      tester,
      engine,
      request: _episode,
      duration: const Duration(minutes: 22),
      at: const Duration(minutes: 20, seconds: 30),
    );
    // Watched (95%), but not the countdown yet: nothing on TV.
    expect(find.text('Up next'), findsNothing);
    expect(tv.focused, 'Pause');

    engine.emitPosition(const Duration(minutes: 21, seconds: 51));
    await tester.pump();
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Season 3 · Episode 1'), findsOneWidget);
    // With the controls up, Play/Pause keeps the focus; hidden, the card
    // takes it. (The countdown animates: no pumpAndSettle, so keys by hand.)
    expect(tv.focused, 'Pause');
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tv.focused, 'Play now');
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Right reaches Hide; Down shows the controls.
    await press(LogicalKeyboardKey.arrowRight);
    expect(tv.focused, 'Hide');
    await press(LogicalKeyboardKey.arrowDown);
    expect(tv.focused, 'Pause');
    // The countdown ends: the next episode plays.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.opened, hasLength(2));
  });

  testWidgets('OK on Up next plays the next episode', (tester) async {
    final engine = FakeEngine();
    final tv = await _open(
      tester,
      engine,
      request: _episode,
      duration: const Duration(minutes: 22),
      at: const Duration(minutes: 20, seconds: 30),
    );
    engine.emitPosition(const Duration(minutes: 21, seconds: 52));
    await tester.pump();
    expect(find.text('Up next'), findsOneWidget);
    await tester.pump(TvPlayerScreen.hideAfter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tv.focused, 'Play now');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.opened, hasLength(2));
  });

  testWidgets('a title without streams says so, with Back focused', (
    tester,
  ) async {
    await pumpApp(
      tester,
      tv: true,
      api: fixtureApi([FakeApiClient.path('transcoddedFiles/', <Object?>[])]),
    );
    ProviderScope.containerOf(tester.element(find.byType(TvApp)))
        .read(tvRouterProvider)
        .push('/watch/3119279', extra: _movie);
    await tester.pumpAndSettle();
    final tv = TvDriver(tester);
    expect(find.text("This video isn't available right now."), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(tv.focused, 'Back');
    await tv.ok();
    expect(_player, findsNothing);
  });

  testWidgets('in Arabic the ±10 s buttons keep their places', (tester) async {
    final engine = FakeEngine();
    final tv = await _open(
      tester,
      engine,
      request: _episode,
      arabic: true,
      pause: true,
    );
    final back = tester.getCenter(find.bySemanticsLabel('رجوع 10 ثوانٍ'));
    final forward = tester.getCenter(find.bySemanticsLabel('تقديم 10 ثوانٍ'));
    expect(back.dx, lessThan(forward.dx));
    // Right on the screen is forward, along the buttons.
    await tv.right();
    expect(tester.getCenter(find.bySemanticsLabel(tv.focused)), forward);
  });

  for (final arabic in [false, true]) {
    testWidgets('no traps in the controls (${arabic ? 'Arabic' : 'English'})', (
      tester,
    ) async {
      FakeEngine engine = FakeEngine();
      await expectNoTraps(
        tester,
        pumpScreen: () async {
          engine = FakeEngine();
          await _open(
            tester,
            engine,
            request: _episode,
            arabic: arabic,
            pause: true,
          );
        },
        leftScreen: () => _player.evaluate().isEmpty,
        backChecks: 6,
      );
    });
  }
}
