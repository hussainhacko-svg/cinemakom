import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/app/widgets/poster_card.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/features/details/details_screen.dart';
import 'package:cinemakom/features/library/widgets/continue_card.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_harness.dart';
import '../repositories/fake_api_client.dart';

const _min = Duration(minutes: 1);

/// Friends (fixture series 4328): Season 2 Episode 1 watched to the end.
/// Its fixture episode list goes on with Season 3 Episode 1.
WatchProgress _finishedEpisode({int at = 5}) => WatchProgress(
  videoId: '4401',
  seriesId: '4328',
  season: 2,
  episode: 1,
  position: _min * 99,
  duration: _min * 100,
  updatedAt: DateTime(2026, 11, 19, 12, at),
  title: const LocalizedText(en: 'Friends'),
  kind: VideoKind.series,
);

/// Eve of Destruction (fixture movie), 14 minutes left.
WatchProgress _movie({int at = 1}) => WatchProgress(
  videoId: '3119279',
  position: _min * 86,
  duration: _min * 100,
  updatedAt: DateTime(2026, 11, 19, 12, at),
  title: const LocalizedText(en: 'Eve of Destruction'),
  kind: VideoKind.movies,
);

/// Taps the Library tab (bottom bar or rail).
Future<void> _openLibrary(WidgetTester tester) async {
  await tester.tap(find.text('Library'));
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, String location) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty library says what goes there', (tester) async {
    await pumpApp(tester);
    await _openLibrary(tester);
    expect(find.text('LIBRARY'), findsOneWidget);
    expect(
      find.text('Movies and episodes you start watching show up here.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(
      find.text('Tap Favorite on any title to keep it here.'),
      findsOneWidget,
    );
  });

  testWidgets('a finished episode offers the next one, newest first', (
    tester,
  ) async {
    // Desktop width: the player's top bar needs it with the test font.
    await pumpApp(
      tester,
      width: 1280,
      height: 800,
      library: MemoryLibraryRepository([_movie(), _finishedEpisode()]),
    );
    await _openLibrary(tester);
    final cards = find.byType(ContinueCard);
    expect(cards, findsNWidgets(2));
    expect(
      find.descendant(of: cards.first, matching: find.text('Friends')),
      findsOneWidget,
    );
    expect(find.text('Up next · Season 3 · Episode 1'), findsOneWidget);
    expect(find.text('14 min left'), findsOneWidget);

    // The play button plays the next episode; the card opens the title.
    await tester.tap(find.byTooltip('Play').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    expect(player.request.episode?.id, '5834');
  });

  testWidgets('a continue card opens its title in the Library tab', (
    tester,
  ) async {
    await pumpApp(tester, library: MemoryLibraryRepository([_movie()]));
    await _openLibrary(tester);
    await tester.tap(find.text('Eve of Destruction'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the last episode of a series leaves Continue watching', (
    tester,
  ) async {
    // 17027 is the fixture's last episode (Season 10).
    final last = WatchProgress(
      videoId: '17027',
      seriesId: '4328',
      season: 10,
      episode: 1,
      position: _min * 99,
      duration: _min * 100,
      updatedAt: DateTime(2026, 11, 19, 12, 5),
      title: const LocalizedText(en: 'Friends'),
    );
    await pumpApp(tester, library: MemoryLibraryRepository([last]));
    await _openLibrary(tester);
    expect(find.byType(ContinueCard), findsNothing);
  });

  testWidgets('a long press removes a title until it is watched again', (
    tester,
  ) async {
    final library = MemoryLibraryRepository([_movie(), _finishedEpisode()]);
    await pumpApp(tester, library: library);
    await _openLibrary(tester);
    await tester.longPress(find.text('Friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from Continue watching'));
    await tester.pumpAndSettle();
    expect(find.byType(ContinueCard), findsOneWidget);
    expect(find.text('Friends'), findsNothing);
    // Its history is kept.
    expect(library.rows.keys, contains('4401'));

    await library.save(
      _finishedEpisode().copyAt(DateTime.now().add(const Duration(minutes: 1))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Friends'), findsOneWidget);
  });

  testWidgets('a right click offers the same removal on desktop', (
    tester,
  ) async {
    final library = MemoryLibraryRepository([_movie()]);
    await pumpApp(tester, width: 1280, height: 800, library: library);
    await _openLibrary(tester);
    await tester.tap(
      find.text('Eve of Destruction'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Remove from Continue watching'));
    await tester.pumpAndSettle();
    expect(find.byType(ContinueCard), findsNothing);
    expect(library.hidden.keys, ['3119279']);
  });

  testWidgets('Favorite on details saves the title to the Library', (
    tester,
  ) async {
    final library = MemoryLibraryRepository();
    await pumpApp(tester, library: library);
    await _push(tester, '/home/title/3119279');
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    expect(find.text('In favorites'), findsOneWidget);
    expect(library.favorites.keys, ['3119279']);

    await _openLibrary(tester);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.byType(PosterCard), findsOneWidget);
    expect(find.text('Eve of Destruction'), findsOneWidget);

    // And off again.
    await tester.tap(find.byType(PosterCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In favorites'));
    await tester.pumpAndSettle();
    expect(library.favorites, isEmpty);
  });

  testWidgets('the hero saves its banner title', (tester) async {
    final library = MemoryLibraryRepository();
    await pumpApp(tester, library: library);
    // Every banner's text is laid out; the current one is hit-testable.
    await tester.tap(find.byTooltip('Add to favorites').first);
    await tester.pumpAndSettle();
    expect(library.favorites, hasLength(1));
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
  });

  testWidgets('opening the Library refreshes stored titles once', (
    tester,
  ) async {
    final api = fixtureApi();
    final library = MemoryLibraryRepository(
      [_movie()],
      [
        const MediaItem(
          id: '3157703',
          title: LocalizedText(en: 'Old name'),
        ),
      ],
    );
    await pumpApp(tester, api: api, library: library);
    await _openLibrary(tester);
    final calls = api.requests.where((r) => r.path == 'getVideosByIds');
    expect(calls, hasLength(1));
    expect(calls.single.form!['ids'], contains('3119279'));
    expect(library.favorites['3157703']!.title.en, 'The Beast');

    // Back to Home and again: no second request.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
    );
    await tester.pumpAndSettle();
    await _openLibrary(tester);
    expect(api.requests.where((r) => r.path == 'getVideosByIds'), hasLength(1));
  });

  testWidgets('a failed refresh changes nothing', (tester) async {
    final library = MemoryLibraryRepository([_movie()]);
    await pumpApp(
      tester,
      api: fixtureApi([
        FakeApiClient.path('getVideosByIds', (_) => throw Exception('offline')),
      ]),
      library: library,
    );
    await _openLibrary(tester);
    expect(find.byType(ContinueCard), findsOneWidget);
    expect(library.updated, isEmpty);
  });

  testWidgets('Home shows the Up next card too', (tester) async {
    await pumpApp(
      tester,
      library: MemoryLibraryRepository([_finishedEpisode()]),
    );
    await tester.scrollUntilVisible(
      find.byType(ContinueCard),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Up next · Season 3 · Episode 1'), findsOneWidget);
  });
}

extension on WatchProgress {
  WatchProgress copyAt(DateTime at) => WatchProgress(
    videoId: videoId,
    seriesId: seriesId,
    season: season,
    episode: episode,
    position: position,
    duration: duration,
    updatedAt: at,
    title: title,
    kind: kind,
  );
}
