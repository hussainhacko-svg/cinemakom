import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/repositories/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_client.dart';

typedef F = FakeApiClient;

void main() {
  final repo = MediaRepository(
    F([
      F.fixtureAt('allVideoInfo/id/movie', 'video_info_movie'),
      F.fixtureAt('allVideoInfo/id/series', 'video_info_series'),
      F.fixtureAt('videoSeason/', 'series_episodes'),
      F.fixtureAt('videoSeasonNumber/', 'series_seasons'),
      F.fixtureAt('transcoddedFiles/', 'streams_movie'),
      F.fixtureAt('translationFiles/', 'subtitles_movie'),
      F.fixtureAt('relatedVideos/', 'related_movie'),
      F.fixtureAt('skippingDurations/', 'skip_durations'),
      F.fixtureAt('staff/', 'staff'),
    ]),
  );

  test('details, episodes and seasons', () async {
    expect((await repo.details('movie'))!.actors, isNotEmpty);
    expect((await repo.details('series'))!.item.isSeries, isTrue);
    expect(await repo.episodes('series'), isNotEmpty);
    expect(await repo.seasons('series'), isNotEmpty);
  });

  test('playback data', () async {
    expect(await repo.streams('movie'), isNotEmpty);
    expect(await repo.subtitles('movie'), isNotEmpty);
    expect(await repo.related('movie', VideoKind.movies), isNotEmpty);
    expect(await repo.parentalSkipRanges('movie'), isA<List>());
  });

  test('staff page', () async {
    expect((await repo.staff('1', ApiLanguage.en))!.items, isNotEmpty);
  });

  test('byIds de-duplicates and sends chunks', () async {
    final api = F([
      F.path('getVideosByIds', (ApiRequest r) {
        final ids = r.form!['ids']!
            .replaceAll(RegExp(r'[\[\] ]'), '')
            .split(',');
        return [
          for (final id in ids) {'nb': id, 'en_title': 'T$id'},
        ];
      }),
    ]);
    final ids = [for (var i = 1; i <= 120; i++) '$i', '1', '2'];
    final items = await MediaRepository(api).byIds(ids);
    expect(items, hasLength(120));
    expect(api.requests, hasLength(3));
  });
}
