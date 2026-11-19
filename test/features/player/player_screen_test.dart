import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/features/details/details_screen.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:cinemakom/features/player/widgets/chip_menus.dart';
import 'package:cinemakom/features/player/widgets/controls_overlay.dart';
import 'package:cinemakom/features/player/widgets/seek_bar.dart';
import 'package:cinemakom/features/player/widgets/seek_preview_frame.dart';
import 'package:cinemakom/features/player/widgets/skip_intro_button.dart';
import 'package:cinemakom/features/player/widgets/subtitle_layer.dart';
import 'package:cinemakom/features/player/widgets/up_next_card.dart';
import 'package:cinemakom/features/details/widgets/episode_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/app_harness.dart';
import '../../repositories/fake_api_client.dart';
import 'fake_engine.dart';

/// Details of the fixture movie, then Play.
Future<void> openMovie(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push('/home/title/3119279');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play'));
  // The player shows a BulbLoader while it opens: no pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Friends Season 2 Episode 1 (the fixture has six episodes, one per
/// season), opened straight in the player.
Future<void> openEpisode(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push(
        '/watch/4401',
        extra: const PlaybackRequest(
          item: MediaItem(
            id: '4328',
            title: LocalizedText(en: 'Friends'),
            kind: VideoKind.series,
          ),
          episodeId: '4401',
        ),
      );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The fade of the controls (Skip intro has its own).
final controlsFade = find.ancestor(
  of: find.byType(ControlsOverlay),
  matching: find.byType(AnimatedOpacity),
);

final choiceMenu = find.byWidgetPredicate((w) => w is ChoiceMenu);

void main() {
  testWidgets('Play opens the player full screen, and back returns', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);

    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(engine.opened.single.source.uri, contains('cdn.shabakaty.com'));

    engine.emitReady();
    await tester.pump();
    // Title, the quality chip (Settings: 1080p) and the subtitle chip.
    expect(find.text('Eve of Destruction'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Arabic'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(PlayerScreen),
        matching: find.byTooltip('Back'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.byType(DetailsScreen), findsOneWidget);
    expect(engine.disposed, isTrue);
  });

  testWidgets('controls hide while playing and come back on tap', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady();
    await tester.pump();

    double opacity() => tester.widget<AnimatedOpacity>(controlsFade).opacity;
    expect(opacity(), 1);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(), 0);

    await tester.tapAt(const Offset(422, 195));
    await tester.pump();
    expect(opacity(), 1);

    // Paused: the controls stay, until a tap on the video hides them.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 5));
    expect(opacity(), 1);
    expect(find.byTooltip('Play'), findsOneWidget);
    await tester.tapAt(const Offset(120, 200)); // clear of the centre buttons
    await tester.pump();
    expect(opacity(), 0);
  });

  testWidgets('a tap outside a menu closes it and hides the controls', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady();
    await tester.pump();

    await tester.tap(find.text('1080p'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(choiceMenu, findsOneWidget);

    await tester.tapAt(const Offset(120, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(choiceMenu, findsNothing);
    final opacity = tester.widget<AnimatedOpacity>(controlsFade).opacity;
    expect(opacity, 0);
  });

  testWidgets('the quality menu switches at the current position', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady(at: const Duration(minutes: 3));
    await tester.pump();

    final chip = tester.getRect(
      find.ancestor(of: find.text('1080p'), matching: find.byType(TextButton)),
    );
    await tester.tap(find.text('1080p'));
    await tester.pump(const Duration(milliseconds: 400));
    // From 600 dp: a popover under the chip, not a sheet.
    expect(find.byType(BottomSheet), findsNothing);
    final menu = tester.getRect(choiceMenu.first);
    expect(menu.top, greaterThan(chip.bottom));
    expect(menu.right, closeTo(chip.right, 1));

    await tester.tap(find.text('720p').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(choiceMenu, findsNothing);
    expect(engine.opened, hasLength(2));
    expect(engine.opened.last.start, const Duration(minutes: 3));
  });

  testWidgets('the subtitle menu: sync, size, then another track', (
    tester,
  ) async {
    final engine = FakeEngine();
    final store = MemoryPreferenceStore({PreferenceKeys.language: 'en'});
    await pumpApp(
      tester,
      engine: engine,
      store: store,
      width: 844,
      height: 390,
    );
    await openMovie(tester);
    engine.emitReady();
    await tester.pump();

    await tester.tap(find.text('Arabic'));
    await tester.pump(const Duration(milliseconds: 400));
    final menu = find.byType(SubtitleMenu);
    expect(menu, findsOneWidget);
    expect(find.text('0 s'), findsOneWidget);

    await tester.tap(find.byTooltip('Show subtitles later'));
    await tester.pump();
    await tester.tap(find.byTooltip('Show subtitles later'));
    await tester.pump();
    await tester.tap(find.byTooltip('Show subtitles later'));
    await tester.pump();
    expect(find.text('+1.5 s'), findsOneWidget);
    expect(engine.subtitleDelay, const Duration(milliseconds: 1500));
    await tester.tap(find.byTooltip('Show subtitles earlier'));
    await tester.pump();
    expect(find.text('+1 s'), findsOneWidget);

    // Size is the Settings value, and the Flutter layer follows it.
    await tester.tap(find.descendant(of: menu, matching: find.text('Large')));
    await tester.pump();
    expect(store.values[PreferenceKeys.subtitleSize], 'large');
    expect(engine.subtitleScale, 1.2);
    expect(tester.widget<SubtitleLayer>(find.byType(SubtitleLayer)).scale, 1.2);

    // Playback goes on and the controls stay while the menu is open.
    await tester.pump(const Duration(seconds: 5));
    expect(menu, findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.descendant(of: menu, matching: find.text('Reset')));
    await tester.pump();
    expect(engine.subtitleDelay, Duration.zero);

    await tester.tap(find.descendant(of: menu, matching: find.text('English')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(menu, findsNothing);
    expect(engine.subtitles.last!.language, 'en');
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('the fit chip cycles with a short note', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady();
    await tester.pump();

    await tester.tap(find.byTooltip('Screen fit'));
    await tester.pump();
    expect(find.text('Fill'), findsOneWidget);
    expect(find.byIcon(Icons.crop_free), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Fill'), findsNothing);

    await tester.tap(find.byTooltip('Screen fit'));
    await tester.pump();
    expect(find.text('Stretch'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('below 480 dp the chips fold into one menu', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 460, height: 300);
    ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
        .read(routerProvider)
        .push('/watch/3119279');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    engine.emitReady();
    await tester.pump();

    expect(find.text('1080p'), findsNothing);
    await tester.tap(find.byTooltip('More options'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Below 600 dp menus are bottom sheets.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);

    await tester.tap(find.text('Speed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text(speedLabel(1.5)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(engine.rate, 1.5);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a title without streams says so, with Try again', (
    tester,
  ) async {
    await pumpApp(
      tester,
      width: 844,
      height: 390,
      api: fixtureApi([FakeApiClient.path('transcoddedFiles/', <Object?>[])]),
    );
    await openMovie(tester);
    expect(find.text("This video isn't available right now."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('in Arabic the top bar flips but the seek bar stays LTR', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(
      tester,
      engine: engine,
      width: 844,
      height: 390,
      store: MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
    );
    ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
        .read(routerProvider)
        .push('/home/title/3119279');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    engine.emitReady();
    await tester.pump();

    expect(directionAt(tester, find.byType(PlayerScreen)), TextDirection.rtl);
    final bar = find.byType(SeekBar);
    expect(
      Directionality.of(
        tester.element(
          find.descendant(of: bar, matching: find.byType(CustomPaint)),
        ),
      ),
      TextDirection.ltr,
    );
    // Back sits at the start edge: the right side in RTL.
    final back = tester.getCenter(find.byIcon(Icons.arrow_back));
    expect(back.dx, greaterThan(844 / 2));
  });
  testWidgets('Up next shows near the end; Play now and Hide', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openEpisode(tester);
    engine.emitReady(
      duration: const Duration(minutes: 22),
      at: const Duration(minutes: 10),
    );
    await tester.pump();
    expect(find.byType(UpNextCard), findsNothing);
    expect(find.text('Season 2 · Episode 1'), findsOneWidget);

    engine.emitPosition(const Duration(minutes: 20, seconds: 30));
    await tester.pump();
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Season 3 · Episode 1'), findsOneWidget);
    // It stays when the controls hide.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(UpNextCard), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(find.byType(UpNextCard), findsNothing);

    await tester.tap(find.byType(PlayerScreen), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Next episode'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(engine.opened, hasLength(2));
    engine.emitReady(duration: const Duration(minutes: 22));
    await tester.pump();
    expect(find.text('Season 3 · Episode 1'), findsOneWidget);
  });

  testWidgets('the Episodes panel switches episode in place', (tester) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openEpisode(tester);
    engine.emitReady(duration: const Duration(minutes: 22));
    engine.pause();
    await tester.pump();

    await tester.tap(find.text('Episodes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // A side panel at the end edge, from 600 dp.
    expect(find.byType(BottomSheet), findsNothing);
    final panel = tester.getRect(find.byType(EpisodeList));
    expect(panel.right, closeTo(844, 1));
    expect(panel.left, greaterThan(844 / 2));

    await tester.ensureVisible(find.text('Season 5'));
    await tester.pump();
    await tester.tap(find.text('Season 5'));
    await tester.pump();
    await tester.tap(find.text('Episode 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EpisodeList), findsNothing);
    expect(engine.opened, hasLength(2));
    expect(engine.opened.last.play, isTrue);
    engine.emitReady(duration: const Duration(minutes: 22));
    await tester.pump();
    expect(find.text('Season 5 · Episode 1'), findsOneWidget);
  });
  testWidgets('Skip intro: up by itself for 8 s, then with the controls', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    // The fixture movie's intro runs 0–27.1 s.
    engine.emitReady(at: const Duration(seconds: 2));
    await tester.pump();
    final skip = find.byType(SkipIntroButton);
    bool shown() => tester.widget<SkipIntroButton>(skip).visible;
    expect(find.text('Skip intro'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(tester.widget<AnimatedOpacity>(controlsFade).opacity, 0);
    expect(shown(), isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(shown(), isFalse);

    await tester.tapAt(const Offset(422, 195));
    await tester.pump();
    expect(shown(), isTrue);
    await tester.tap(find.text('Skip intro'));
    await tester.pump();
    expect(engine.seeks.last, const Duration(milliseconds: 27121));
    expect(skip, findsNothing);
  });

  testWidgets('dragging the seek bar shows the frame and the time', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(
      tester,
      engine: engine,
      width: 844,
      height: 390,
      api: fixtureApi([
        FakeApiClient.fixtureAt('video_thumbnails/', 'thumbnails'),
      ]),
    );
    await openMovie(tester);
    engine.emitReady(
      duration: const Duration(hours: 1),
      at: const Duration(minutes: 1),
    );
    await tester.pump();

    final bar = tester.getRect(find.byType(SeekBar));
    final drag = await tester.startGesture(
      bar.centerLeft + const Offset(20, 0),
    );
    await tester.pump();
    await drag.moveTo(bar.center);
    await tester.pump();
    // 6 sheets of 100 frames, one every 10 s: frames up to 100 min.
    expect(find.byType(SeekPreviewFrame), findsOneWidget);
    expect(find.text('30:00'), findsOneWidget);
    await drag.up();
    await tester.pump();
    expect(find.byType(SeekPreviewFrame), findsNothing);
    expect(engine.seeks.last, const Duration(minutes: 30));
  });

  testWidgets('without previews the seek bar shows the time alone', (
    tester,
  ) async {
    final engine = FakeEngine();
    await pumpApp(tester, engine: engine, width: 844, height: 390);
    await openMovie(tester);
    engine.emitReady(duration: const Duration(hours: 1));
    await tester.pump();

    final bar = tester.getRect(find.byType(SeekBar));
    final drag = await tester.startGesture(
      bar.centerLeft + const Offset(20, 0),
    );
    await tester.pump();
    await drag.moveTo(bar.center);
    await tester.pump();
    expect(find.byType(SeekPreviewFrame), findsNothing);
    expect(find.text('30:00'), findsOneWidget);
    // A finger is on the thumb: the time sits well above it.
    expect(tester.getRect(find.text('30:00')).bottom, lessThan(bar.top - 48));
    await drag.up();
  });
}
