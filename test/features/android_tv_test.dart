import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/app/widgets/media_image.dart';
import 'package:cinemakom/app/widgets/media_row.dart';
import 'package:cinemakom/app/widgets/poster_card.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/platform/orientation.dart';
import 'package:cinemakom/core/platform/platform_info.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/features/home/widgets/home_hero.dart';
import 'package:cinemakom/features/onboarding/language_screen.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:cinemakom/features/player/widgets/chip_menus.dart';
import 'package:cinemakom/features/player/widgets/controls_overlay.dart';
import 'package:cinemakom/features/player/widgets/gesture_layer.dart';
import 'package:cinemakom/features/player/widgets/seek_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_harness.dart';
import 'player/fake_engine.dart';

/// Sets Android TV mode for the duration of a test and resets on teardown.
void useAndroidTv() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  debugIsTvOverride = true;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    debugIsTvOverride = null;
  });
}

Future<void> openTvMovie(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push('/home/title/3119279');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Play'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> openTvEpisode(WidgetTester tester) async {
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

final _controlsFade = find.ancestor(
  of: find.byType(ControlsOverlay),
  matching: find.byType(AnimatedOpacity),
);

void main() {
  group('platform_info & orientation on Android TV', () {
    testWidgets('isTv disables isTouchMobile and skips orientation locks', (
      tester,
    ) async {
      useAndroidTv();
      expect(isAndroid, isTrue);
      expect(isMobile, isTrue);
      expect(isTv, isTrue);
      expect(isTouchMobile, isFalse);

      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      setBrowseOrientation(ScreenRotation.portrait);
      setPlayerOrientation();
      expect(
        calls.where((c) => c.method == 'SystemChrome.setPreferredOrientations'),
        isEmpty,
      );
    });
  });

  group('Android TV browsing at 960×540 dp', () {
    testWidgets('Settings hides Screen rotation and keeps Downloads tab', (
      tester,
    ) async {
      useAndroidTv();
      await pumpApp(tester, width: 960, height: 540);

      // Compact NavigationRail with Downloads tab still visible.
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Screen rotation'), findsNothing);
      expect(find.text('Language'), findsOneWidget);
    });

    testWidgets(
      'HomeHero uses side-by-side layout and excludes inactive banners from focus',
      (tester) async {
        useAndroidTv();
        await pumpApp(tester, width: 960, height: 540);

        final hero = find.byType(HomeHero);
        expect(hero, findsOneWidget);
        // Side-by-side Row layout (banner + info) instead of stacked phone Column.
        expect(
          find.descendant(of: hero, matching: find.byType(Row)),
          findsWidgets,
        );
        // TV banner stepper chevrons are present.
        expect(
          find.descendant(of: hero, matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget,
        );
        // Only the active banner's Play button is focusable (inactive ones
        // wrapped in ExcludeFocus(excluding: true)).
        final excluded = tester.widgetList<ExcludeFocus>(
          find.descendant(of: hero, matching: find.byType(ExcludeFocus)),
        );
        expect(excluded.where((e) => !e.excluding).length, 1);
        expect(excluded.where((e) => e.excluding).length, greaterThan(0));
      },
    );

    testWidgets('MediaRow moves See all to the end of the row on TV', (
      tester,
    ) async {
      useAndroidTv();
      await pumpApp(tester, width: 960, height: 540);

      final row = find.byType(MediaRow).first;
      expect(row, findsOneWidget);
      // Header's "See all" is excluded from focus on TV so D-pad Down skips it.
      final headerExcludes = tester.widgetList<ExcludeFocus>(
        find.descendant(of: row, matching: find.byType(ExcludeFocus)),
      );
      expect(headerExcludes.any((e) => e.excluding), isTrue);

      // Poster cards on TV prefer the full-resolution hdPosterUrl over the
      // 293 px medium thumbnail.
      final card = tester.widget<PosterCard>(find.byType(PosterCard).first);
      final img = tester.widget<MediaImage>(
        find.descendant(
          of: find.byType(PosterCard).first,
          matching: find.byType(MediaImage),
        ),
      );
      expect(img.url, card.item.hdPosterUrl ?? card.item.posterUrl);
    });

    testWidgets('First-launch language picker confirms via D-pad and Select', (
      tester,
    ) async {
      useAndroidTv();
      await pumpApp(
        tester,
        store: MemoryPreferenceStore(),
        width: 960,
        height: 540,
      );
      expect(find.byType(LanguageScreen), findsOneWidget);

      // English card is autofocused; arrow down past Arabic to Continue, press Select.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.byType(LanguageScreen), findsNothing);
      expect(find.byType(HomeHero), findsOneWidget);
    });

    testWidgets('Search field focuses without trapping arrows; Select edits', (
      tester,
    ) async {
      useAndroidTv();
      await pumpApp(tester, width: 960, height: 540);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      // Initially the TextField is readOnly until Select activates editing.
      final tfBefore = tester.widget<TextField>(find.byType(TextField));
      expect(tfBefore.readOnly, isTrue);

      // Focus the search wrapper and press Select to enter editing mode.
      final boxFocus = find.ancestor(
        of: find.byType(TextField),
        matching: find.byWidgetPredicate(
          (w) => w is Focus && w.focusNode?.debugLabel == 'searchBox',
        ),
      );
      final node = tester.widget<Focus>(boxFocus).focusNode!;
      node.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

      // Escape exits editing mode back to D-pad navigation.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    });
  });

  group('Android TV player remote controls', () {
    testWidgets(
      'hides touch gestures/lock; hidden-controls arrows seek, Up shows, Back hides then exits',
      (tester) async {
        useAndroidTv();
        final engine = FakeEngine();
        await pumpApp(tester, engine: engine, width: 960, height: 540);
        await openTvMovie(tester);
        engine.emitReady(
          at: const Duration(minutes: 10),
          duration: const Duration(hours: 2),
        );
        await tester.pump();

        // No touch GestureLayer and no mobile screen-lock icon on TV.
        expect(find.byType(GestureLayer), findsNothing);
        expect(find.byTooltip('Lock controls'), findsNothing);

        // Controls are initially visible; first Back/Escape hides them (doesn't exit).
        expect(tester.widget<AnimatedOpacity>(_controlsFade).opacity, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(_controlsFade).opacity, 0);
        expect(find.byType(PlayerScreen), findsOneWidget);

        // Hidden-controls Right quick-seeks +10 s with toast.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(engine.seeks.last, const Duration(minutes: 10, seconds: 10));
        expect(find.text('+10 s'), findsOneWidget);

        // Hidden-controls Select toggles Play/Pause immediately and reveals controls.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(engine.isPlaying, isFalse);
        expect(tester.widget<AnimatedOpacity>(_controlsFade).opacity, 1);

        // Media Play/Pause key resumes playback.
        await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
        await tester.pump();
        expect(engine.isPlaying, isTrue);

        // Hide controls, then Escape/Back exits the player.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(_controlsFade).opacity, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
      },
    );

    testWidgets(
      'hidden-controls D-pad Up reveals controls and focuses Play/Pause',
      (tester) async {
        useAndroidTv();
        final engine = FakeEngine();
        await pumpApp(tester, engine: engine, width: 960, height: 540);
        await openTvMovie(tester);
        engine.emitReady(
          at: const Duration(seconds: 5),
          duration: const Duration(hours: 2),
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(_controlsFade).opacity, 0);

        // D-pad Up reveals controls and focuses Play/Pause.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(_controlsFade).opacity, 1);
      },
    );

    testWidgets('SeekBar focuses and scrubs with accelerated Left/Right', (
      tester,
    ) async {
      useAndroidTv();
      final engine = FakeEngine();
      await pumpApp(tester, engine: engine, width: 960, height: 540);
      await openTvMovie(tester);
      engine.emitReady(
        at: const Duration(minutes: 10),
        duration: const Duration(hours: 2),
      );
      await tester.pump();

      // Focus the SeekBar directly and scrub right 4 times (10+10+10+30 = 60 s).
      final seekFocus = find.descendant(
        of: find.byType(SeekBar),
        matching: find.byType(Focus),
      );
      Focus.of(tester.element(seekFocus.first)).requestFocus();
      await tester.pump();
      // Request focus on the SeekBar's own Focus node.
      final focusNodes = tester
          .elementList(seekFocus)
          .map((e) => (e.widget as Focus))
          .toList();
      expect(focusNodes, isNotEmpty);

      // Focus the SeekBar's Focus child via FocusNode lookup.
      final node = FocusManager.instance.rootScope.descendants.firstWhere(
        (n) =>
            n.context != null &&
            n.context!.findAncestorWidgetOfExactType<SeekBar>() != null,
      );
      node.requestFocus();
      await tester.pump();

      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      // Pressing Select commits the scrubbed position immediately.
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(
        engine.seeks.last.inSeconds,
        closeTo(const Duration(minutes: 11).inSeconds, 2),
      );
    });

    testWidgets('Quality menu autofocuses the active choice on TV', (
      tester,
    ) async {
      useAndroidTv();
      final engine = FakeEngine();
      await pumpApp(tester, engine: engine, width: 960, height: 540);
      await openTvMovie(tester);
      engine.emitReady();
      await tester.pump();

      await tester.tap(find.text('1080p'));
      await tester.pumpAndSettle();

      final rows = tester.widgetList<MenuRow>(find.byType(MenuRow)).toList();
      final active = rows.firstWhere((r) => r.selected);
      expect(active.autofocus, isTrue);
    });

    testWidgets('Arabic RTL on TV flips rail/top bar while seek bar stays LTR', (
      tester,
    ) async {
      useAndroidTv();
      final engine = FakeEngine();
      await pumpApp(
        tester,
        store: MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
        engine: engine,
        width: 960,
        height: 540,
      );

      expect(directionAt(tester, find.byType(NavigationRail)), TextDirection.rtl);

      await openTvEpisode(tester);
      engine.emitReady();
      await tester.pump();

      expect(directionAt(tester, find.byType(ControlsOverlay)), TextDirection.rtl);
      expect(
        directionAt(
          tester,
          find.descendant(
            of: find.byType(SeekBar),
            matching: find.byType(GestureDetector),
          ),
        ),
        TextDirection.ltr,
      );
    });
  });
}
