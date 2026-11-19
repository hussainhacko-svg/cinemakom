// Live check of PlayerController on the real MediaKitEngine (Phase 4 M1):
// open, play, switch quality, and plain subtitle text for the Flutter layer.
//
//   fvm flutter test integration_test/player_engine_test.dart -d linux
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/features/player/player_controller.dart';
import 'package:cinemakom/features/player/player_state.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

const avengers = PlaybackRequest(
  item: MediaItem(
    id: '191463',
    title: LocalizedText(en: 'Avengers'),
    kind: VideoKind.movies,
  ),
  start: Duration(minutes: 10),
);

const attackOnTitan = PlaybackRequest(
  item: MediaItem(
    id: '279230',
    title: LocalizedText(en: 'Attack on Titan'),
    kind: VideoKind.series,
    rootSeriesId: '279230',
  ),
  start: Duration(seconds: 95),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();

  Future<void> until(
    WidgetTester tester,
    bool Function() done, {
    int seconds = 30,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!done() && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<PlayerController> pumpPlayer(
    WidgetTester tester,
    PlaybackRequest request,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          preferenceStoreProvider.overrideWith(
            (ref) => MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(playerControllerProvider(request));
              final c = ref.read(playerControllerProvider(request).notifier);
              return ColoredBox(
                color: const Color(0xFF000000),
                child: c.engine.buildVideo(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final element = tester.element(find.byType(Consumer));
    return ProviderScope.containerOf(element)
        .read(playerControllerProvider(request).notifier);
  }

  testWidgets('plays, then switches quality at the same position', (
    tester,
  ) async {
    final c = await pumpPlayer(tester, avengers);
    await until(
      tester,
      () => c.position.value > const Duration(minutes: 10, seconds: 2),
    );
    expect(c.state.phase, PlayerPhase.ready);
    expect(c.state.quality!.height, 1080);
    expect(c.state.playing, isTrue);

    final at = c.position.value;
    await c.selectQuality(c.state.sources.firstWhere((s) => s.height == 720));
    await until(
      tester,
      () => c.position.value > at + const Duration(seconds: 1),
    );
    expect(c.state.phase, PlayerPhase.ready);
    expect(c.state.quality!.height, 720);
    expect(c.position.value - at, lessThan(const Duration(seconds: 15)));
  });

  testWidgets('plain Arabic subtitles reach the Flutter layer', (tester) async {
    final c = await pumpPlayer(tester, attackOnTitan);
    await until(tester, () => c.position.value > const Duration(seconds: 96));
    expect(c.state.subtitle.languageCode, 'ar');
    expect(c.state.subtitle.isStyled, isFalse);
    await until(tester, () => c.subtitleLines.value.isNotEmpty, seconds: 15);
    expect(c.subtitleLines.value, isNotEmpty);
    expect(c.state.episodes, isNotEmpty);
  });
}
