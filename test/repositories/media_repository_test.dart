import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
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

  group('streams', () {
    final now = DateTime.utc(2026, 11, 19, 12);
    String url(DateTime expires) =>
        'https://cdn.shabakaty.com/v.mp4?AWSAccessKeyId=K'
        '&Expires=${expires.millisecondsSinceEpoch ~/ 1000}&Signature=S';
    List<Map<String, String>> streams(DateTime expires) => [
      {'resolution': '720p', 'videoUrl': url(expires)},
      {'resolution': '480p', 'videoUrl': '${url(expires)}&q=480'},
    ];

    test('fresh URLs are used as they are', () async {
      final api = F([
        F.path('transcoddedFiles/', streams(now.add(const Duration(days: 5)))),
      ]);
      final sources = await MediaRepository(api, clock: () => now).streams('7');
      expect(sources, hasLength(2));
      expect(api.requests, hasLength(1));
    });

    test('stale cached URLs are refetched past the cache', () async {
      final api = F([
        (
          (r) => r.path.startsWith('transcoddedFiles/') && r.query.isEmpty,
          (_) => streams(now.subtract(const Duration(hours: 1))),
        ),
        (
          (r) => r.path.startsWith('transcoddedFiles/') && r.query.isNotEmpty,
          (_) => streams(now.add(const Duration(days: 7))),
        ),
      ]);
      final sources = await MediaRepository(api, clock: () => now).streams('7');
      expect(api.requests, hasLength(2));
      expect(api.requests.last.query['_'], '${now.millisecondsSinceEpoch}');
      expect(
        sources.every(
          (s) => s.isValidFor(MediaRepository.minStreamValidity, now: now),
        ),
        isTrue,
      );
    });

    test('URLs expiring within the margin are refreshed too', () async {
      final api = F([
        F.path('transcoddedFiles/', streams(now.add(const Duration(hours: 2)))),
      ]);
      await MediaRepository(api, clock: () => now).streams('7');
      expect(api.requests, hasLength(2));
    });

    test('fresh always skips the API cache, in one request', () async {
      final api = F([
        F.path('transcoddedFiles/', streams(now.add(const Duration(days: 5)))),
      ]);
      await MediaRepository(api, clock: () => now).streams('7', fresh: true);
      expect(api.requests, hasLength(1));
      expect(api.requests.single.query['_'], isNotNull);
    });
  });

  test('seasons fall back to the episodes when the list is empty', () async {
    for (final answer in <Object?>[
      <Object?>[],
      const ApiException(ApiErrorKind.http, statusCode: 400),
    ]) {
      final api = F([
        F.path('videoSeasonNumber/', answer),
        F.path('videoSeason/', [
          {'nb': '1', 'en_title': 'S', 'season': '2', 'episodeNummer': '1'},
          {'nb': '2', 'en_title': 'S', 'season': '1', 'episodeNummer': '1'},
          {'nb': '3', 'en_title': 'S', 'season': '2', 'episodeNummer': '2'},
        ]),
      ]);
      expect(await MediaRepository(api).seasons('1'), [1, 2]);
    }
    final dead = MediaRepository(F([F.path('videoSeasonNumber/', offline)]));
    await expectLater(dead.seasons('1'), throwsA(isA<ApiException>()));
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
