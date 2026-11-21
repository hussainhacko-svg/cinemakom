// The TV UI's frame times and memory on the TV (docs/TV.md §9, TV-6):
// holding Right along a Home row, Down through Home, then the player on a
// 4K stream with the controls up, fading, seeking over the video with a
// held arrow, and a panel. Profile mode, live API, the real engine
// (ExoPlayer). The TV budget is 60 Hz:
//
//   fvm flutter drive --profile --no-dds -d <tv-ip>:5555 \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/tv_perf_test.dart --dart-define=PERF_HZ=60
//
// `flutter drive` reinstalls the app, which wipes its data on the TV.
import 'dart:io';

import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/features/player/player_controller.dart';
import 'package:cinemakom/features/player/player_state.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/tv_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;

/// Avengers: Endgame: 4K, with seek previews.
const request = PlaybackRequest(
  item: MediaItem(
    id: '301561',
    title: LocalizedText(en: 'Avengers: Endgame'),
    kind: VideoKind.movies,
  ),
  start: Duration(minutes: 20),
);

/// OK: the remote's Select on the TV; Enter on a desktop dry run (Linux has
/// no Select key).
final ok = Platform.isAndroid
    ? LogicalKeyboardKey.select
    : LogicalKeyboardKey.enter;

/// The physical key for [key]. Profile builds drop the keys' debug names,
/// which `simulateKeyDownEvent` uses to find it by itself.
PhysicalKeyboardKey physical(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowUp => PhysicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown => PhysicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft => PhysicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight => PhysicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.select => PhysicalKeyboardKey.select,
  LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
  LogicalKeyboardKey.escape => PhysicalKeyboardKey.escape,
  _ => throw ArgumentError('No physical key for $key'),
};

/// The stream quality to play: 2160 (the worst case), or 1080 to compare
/// (`--dart-define=PERF_QUALITY=1080`).
const quality = int.fromEnvironment('PERF_QUALITY', defaultValue: 2160);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Under the test binding the app draws about 60 frames a second even when
  // paused (benchmarkLive too); the real app draws ~30 while playing and
  // none when paused. So the player numbers here are a worst case: judge 4K
  // smoothness with tool/tv_cadence.sh on the real app (docs/TV.md §9).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();

  Future<void> wait(int ms) => binding.delayed(Duration(milliseconds: ms));

  Future<void> press(LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await simulateKeyDownEvent(key, physicalKey: physical(key));
      await simulateKeyUpEvent(key, physicalKey: physical(key));
      await wait(350);
    }
  }

  /// A held arrow: the key repeats every 50 ms, as on a remote.
  Future<void> hold(LogicalKeyboardKey key, {int repeats = 40}) async {
    await simulateKeyDownEvent(key, physicalKey: physical(key));
    await wait(400);
    for (var i = 0; i < repeats; i++) {
      await simulateKeyRepeatEvent(key, physicalKey: physical(key));
      await wait(50);
    }
    await simulateKeyUpEvent(key, physicalKey: physical(key));
    await wait(600);
  }

  testWidgets('TV performance', (tester) async {
    // TVs draw apps at 960 × 540 dp; a desktop dry run gets the same canvas.
    if (!Platform.isAndroid) {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          preferenceStoreProvider.overrideWith(
            (ref) => MemoryPreferenceStore({
              PreferenceKeys.language: 'en',
              PreferenceKeys.defaultQuality: quality,
            }),
          ),
          libraryRepositoryProvider.overrideWithValue(
            MemoryLibraryRepository(),
          ),
        ],
        child: const TvApp(),
      ),
    );
    // Home's hero and first rows, and their artwork.
    await wait(8000);

    // Down to the first poster row, then along it and back.
    await press(LogicalKeyboardKey.arrowDown, times: 2);
    await wait(2000);
    await binding.watchPerformance(() async {
      await hold(LogicalKeyboardKey.arrowRight);
      await hold(LogicalKeyboardKey.arrowLeft);
    }, reportKey: 'home_hold_right');

    await binding.watchPerformance(
      () => press(LogicalKeyboardKey.arrowDown, times: 12),
      reportKey: 'home_down',
    );
    await press(LogicalKeyboardKey.arrowUp, times: 14);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TvApp)),
    );
    container.read(tvRouterProvider).push('/watch/301561', extra: request);
    PlayerState state() => container.read(playerControllerProvider(request));
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (!(state().phase == PlayerPhase.ready && state().playing)) {
      if (DateTime.now().isAfter(end)) fail('4K never started playing');
      await wait(200);
    }
    // Let the buffer fill and the first previews load.
    await wait(8000);
    final playing = state().quality?.label;

    // The controls are up at first (Play/Pause focused), clock ticking.
    await press(LogicalKeyboardKey.arrowUp);
    await binding.watchPerformance(
      () => wait(5000),
      reportKey: 'playing_controls_up',
    );

    // They hide after 5 s; Down shows them again.
    await binding.watchPerformance(() async {
      for (var i = 0; i < 3; i++) {
        await wait(5600);
        await press(LogicalKeyboardKey.arrowDown);
      }
    }, reportKey: 'controls_fade');

    // Only the video: the controls hidden, nothing over it.
    await wait(5600);
    await binding.watchPerformance(() => wait(5000), reportKey: 'watching');

    // Seeking over the video: a held arrow with the preview frame.
    await binding.watchPerformance(
      () => hold(LogicalKeyboardKey.arrowRight, repeats: 30),
      reportKey: 'watching_hold_seek',
    );
    await wait(3000);

    // A panel over the playing video: Down shows the controls, Up twice
    // reaches the chips, OK opens the subtitles (or quality) panel.
    await binding.watchPerformance(() async {
      for (var i = 0; i < 3; i++) {
        await press(LogicalKeyboardKey.arrowDown);
        await press(LogicalKeyboardKey.arrowUp, times: 2);
        await press(ok);
        await wait(800);
        await press(LogicalKeyboardKey.escape);
        await wait(800);
      }
    }, reportKey: 'player_panel');

    // Paused with the controls up: no new video frames, so anything drawn
    // here is the UI's own.
    await wait(6000);
    await press(ok);
    await binding.watchPerformance(
      () => wait(5000),
      reportKey: 'paused_controls_up',
    );
    await press(ok);

    // Memory after about a minute of 4K.
    await wait(10000);
    binding.reportData = {
      ...?binding.reportData,
      // TVs run at 60 Hz; the driver can't see the app's --dart-define.
      'frame_hz': 60,
      'memory': {
        'quality': playing,
        'rss_mb': ProcessInfo.currentRss ~/ (1024 * 1024),
        'max_rss_mb': ProcessInfo.maxRss ~/ (1024 * 1024),
      },
    };
  });
}
