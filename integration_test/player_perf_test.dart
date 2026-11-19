// The player's frame times and memory on a device (PLAYER.md §1 and M9):
// 4K playing with the controls up, the controls fading in and out,
// scrubbing the seek bar with previews, and a menu. Profile mode, live API,
// the real engine (ExoPlayer on Android).
//
//   fvm flutter drive --profile --no-dds -d <android-device-id> \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/player_perf_test.dart
//
// `flutter drive` reinstalls the app, which wipes its data on the device.
import 'dart:io';

import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/features/player/player_controller.dart';
import 'package:cinemakom/features/player/player_state.dart';
import 'package:cinemakom/features/player/quality.dart';
import 'package:cinemakom/features/player/widgets/seek_bar.dart';
import 'package:cinemakom/main.dart' show noRetry;
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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();

  Future<void> wait(int ms) => binding.delayed(Duration(milliseconds: ms));

  testWidgets('player performance', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          preferenceStoreProvider.overrideWith(
            (ref) => MemoryPreferenceStore({
              PreferenceKeys.language: 'en',
              PreferenceKeys.defaultQuality: 2160,
            }),
          ),
          libraryRepositoryProvider.overrideWithValue(
            MemoryLibraryRepository(),
          ),
        ],
        child: const CinemakomApp(),
      ),
    );
    await wait(1500);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CinemakomApp)),
    );
    container.read(routerProvider).push('/watch/301561', extra: request);

    PlayerState state() => container.read(playerControllerProvider(request));
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (!(state().phase == PlayerPhase.ready && state().playing)) {
      if (DateTime.now().isAfter(end)) fail('4K never started playing');
      await wait(200);
    }
    // Let the buffer fill and the first previews load.
    await wait(8000);
    final quality = state().quality?.label;

    Future<void> showControls() async {
      await tester.tapAt(
        tester.getCenter(find.byType(SeekBar)) - const Offset(0, 200),
      );
      await wait(400);
    }

    await showControls();
    await binding.watchPerformance(() async {
      // The clock and the seek bar tick; the controls stay up while
      // the screen is touched every 2 s.
      for (var i = 0; i < 4; i++) {
        await wait(2000);
        final bar = tester.getRect(find.byType(SeekBar));
        await tester.tapAt(Offset(bar.left - 30, bar.center.dy - 120));
      }
    }, reportKey: 'playing_controls_up');

    await binding.watchPerformance(() async {
      for (var i = 0; i < 6; i++) {
        await tester.tapAt(const Offset(400, 150));
        await wait(700);
      }
    }, reportKey: 'controls_fade');

    await showControls();
    await binding.watchPerformance(() async {
      final bar = tester.getRect(find.byType(SeekBar));
      final drag = await tester.startGesture(
        bar.centerLeft + const Offset(20, 0),
      );
      for (var x = 20.0; x < bar.width - 20; x += bar.width / 60) {
        await drag.moveTo(bar.centerLeft + Offset(x, 0));
        await wait(50);
      }
      await drag.up();
      await wait(2000);
    }, reportKey: 'scrub_with_previews');

    await showControls();
    await binding.watchPerformance(() async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(qualityChipLabel(state().quality!)).first);
        await wait(800);
        await tester.tapAt(const Offset(200, 200));
        await wait(800);
        await showControls();
      }
    }, reportKey: 'quality_menu');

    // Memory after about a minute of 4K.
    await wait(10000);
    binding.reportData = {
      ...?binding.reportData,
      'memory': {
        'quality': quality,
        'rss_mb': ProcessInfo.currentRss ~/ (1024 * 1024),
        'max_rss_mb': ProcessInfo.maxRss ~/ (1024 * 1024),
      },
    };
  });
}
