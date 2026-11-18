import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
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
      F.fixtureAt(ApiEndpoints.recommendationUrl, 'recommendations'),
      F.fixtureAt('video_thumbnails/', 'thumbnails'),
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
    expect((await repo.seekPreview('movie'))!.sheetUrls, isNotEmpty);
    const movie = MediaItem(
      id: 'movie',
      title: LocalizedText(en: 'M'),
    );
    expect(await repo.recommendations(movie), isNotEmpty);
  });

  test('staff page', () async {
    expect((await repo.staff('1', ApiLanguage.en))!.items, isNotEmpty);
  });

  test(
    'byIds: numeric only, de-duplicated, chunks of 40, request order',
    () async {
      final api = F([
        F.path('getVideosByIds', (ApiRequest r) {
          final ids = r.form!['ids']!
              .replaceAll(RegExp(r'[\[\] ]'), '')
              .split(',');
          expect(ids.length, lessThanOrEqualTo(ApiEndpoints.maxIdsPerRequest));
          expect(ids.every((id) => RegExp(r'^[1-9]\d*$').hasMatch(id)), isTrue);
          return [
            for (final id in ids) {'nb': id, 'en_title': 'T$id'},
          ];
        }),
      ]);
      final ids = [
        for (var i = 1; i <= 100; i++) '$i',
        '1',
        ' 2 ',
        'abc',
        '0',
        '',
        '-5',
      ];
      final items = await MediaRepository(api).byIds(ids);
      expect(items.map((i) => i.id), [for (var i = 1; i <= 100; i++) '$i']);
      expect(api.requests, hasLength(3));
      expect(await MediaRepository(F([])).byIds(['x', '0']), isEmpty);
    },
  );

  test(
    'recommendations fall back to relatedVideos when the service fails',
    () async {
      final api = F([
        F.path(ApiEndpoints.recommendationUrl, offline),
        F.fixtureAt('relatedVideos/', 'related_movie'),
      ]);
      const series = MediaItem(
        id: '4401',
        rootSeriesId: '4328',
        kind: VideoKind.series,
        title: LocalizedText(en: 'Friends'),
      );
      expect(await MediaRepository(api).recommendations(series), isNotEmpty);
      expect(api.requests.first.json!['MovieId'], '4328');
      expect(
        api.requests.last.path,
        startsWith('relatedVideos/id/4328/kind/2'),
      );
    },
  );
}
