import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/features/details/widgets/episode_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../fixture.dart';
import '../helpers/app_harness.dart';
import '../repositories/fake_api_client.dart';

/// One season of [count] episodes (One Piece is one season of 1,179), made
/// from the first captured Friends episode.
List<Map<String, Object?>> longSeason(int count) {
  final one = (fixture('series_episodes')! as List).first as Map;
  return [
    for (var n = 1; n <= count; n++)
      {
        ...one.cast<String, Object?>(),
        'nb': '${900000 + n}',
        'season': '1',
        'episodeNummer': '$n',
        'episode_flag': '0000',
      },
  ];
}

Future<void> openSeries(
  WidgetTester tester, {
  MemoryLibraryRepository? library,
}) async {
  await pumpApp(
    tester,
    api: fixtureApi([FakeApiClient.path('videoSeason/', longSeason(120))]),
    library: library,
  );
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push('/home/title/4328');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('EPISODES'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  testWidgets('a long season is split into range chips', (tester) async {
    await openSeries(tester);
    expect(find.text('1–50'), findsOneWidget);
    expect(find.text('51–100'), findsOneWidget);
    expect(find.text('101–120'), findsOneWidget);
    expect(find.text('Episode 1'), findsOneWidget);

    await tester.tap(find.text('101–120'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 1'), findsNothing);
    expect(find.text('Episode 101'), findsOneWidget);
    // Only the block's 20 rows are on the page (the list is one Column, so
    // every row is built, on screen or not).
    expect(
      find.textContaining(RegExp(r'^Episode \d+$')),
      findsNWidgets(120 - 100),
    );
  });

  testWidgets('it opens on the block of the episode watched last', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 19);
    WatchProgress watched(int n, DateTime at) => WatchProgress(
      videoId: '${900000 + n}',
      position: const Duration(minutes: 5),
      duration: const Duration(minutes: 24),
      updatedAt: at,
      title: const LocalizedText(en: 'Friends'),
      seriesId: '4328',
      season: 1,
      episode: n,
    );
    await openSeries(
      tester,
      library: MemoryLibraryRepository([
        watched(3, now.subtract(const Duration(days: 2))),
        watched(73, now),
      ]),
    );
    expect(find.text('Episode 51'), findsOneWidget);
    expect(find.text('Episode 73'), findsOneWidget);
    expect(find.text('Episode 3'), findsNothing);
    expect(
      find.textContaining(RegExp(r'^Episode \d+$')),
      findsNWidgets(episodeBlockSize),
    );
  });
}
