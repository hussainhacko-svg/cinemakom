import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/parsers/media_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixture.dart';

void main() {
  group('parseMediaItems on fixtures', () {
    for (final name in [
      'banners',
      'featured',
      'latest_movies',
      'latest_series',
      'newly_added',
      'catalog_movies_most_viewed',
      'catalog_series_newest',
      'title_search',
      'advanced_search_series',
      'related_movie',
      'videos_by_ids',
      'recommendations',
      'video_group_page',
    ]) {
      test(name, () {
        final items = parseMediaItems(fixture(name));
        expect(items, isNotEmpty);
        for (final item in items) {
          expect(item.id, isNotEmpty);
          expect(item.title.isEmpty, isFalse, reason: item.id);
          expect(item.kind, isNotNull, reason: item.id);
          if (item.posterUrl != null) {
            expect(item.posterUrl, startsWith('http'));
          }
        }
        expect(items.map((i) => i.id).toSet().length, items.length);
      });
    }

    test('latest_series items are series and resolve to their root', () {
      final items = parseMediaItems(fixture('latest_series'));
      expect(items.every((i) => i.isSeries), isTrue);
      for (final i in items) {
        expect(i.seriesId, i.rootSeriesId ?? i.id);
      }
    });

    test('latest_movies items are movies with years', () {
      final items = parseMediaItems(fixture('latest_movies'));
      expect(items.every((i) => i.kind == VideoKind.movies), isTrue);
      expect(items.any((i) => i.year != null), isTrue);
    });

    test('recommendations fixture (other service, other wrapper key)', () {
      final items = parseMediaItems(fixture('recommendations'));
      expect(items, isNotEmpty);
      expect(items.every((i) => i.kind != null), isTrue);
    });
  });

  group('parseMediaItem edge cases', () {
    test('numeric IDs, "null" strings and escaped URLs', () {
      final item = parseMediaItem({
        'nb': 42,
        'en_title': 'null',
        'ar_title': 'فيلم',
        'imgObjUrl': r'https:\/\/img.example.com\/p.jpg',
        'stars': '7.5',
        'rate': '0',
        'kind': 1,
      })!;
      expect(item.id, '42');
      expect(item.title.en, isNull);
      expect(item.title.ar, 'فيلم');
      expect(item.hdPosterUrl, 'https://img.example.com/p.jpg');
      expect(item.posterUrl, item.hdPosterUrl);
      expect(item.kind, VideoKind.movies);
    });

    test('card image prefers the medium thumbnail, HD prefers full size', () {
      final item = parseMediaItem({
        'nb': '1',
        'en_title': 'A',
        'imgObjUrl': 'https://x/full.jpg',
        'imgMediumThumbObjUrl': 'https://x/medium.jpg',
      })!;
      expect(item.posterUrl, 'https://x/medium.jpg');
      expect(item.hdPosterUrl, 'https://x/full.jpg');
    });

    test('episodeNummer spelling, rootSeries and duration', () {
      final item = parseMediaItem({
        'nb': '4401',
        'en_title': 'Friends',
        'kind': '2',
        'season': '2',
        'episodeNummer': '1',
        'rootSeries': '4328',
        'duration': '1331.79',
      })!;
      expect(item.isSeries, isTrue);
      expect(item.season, 2);
      expect(item.episode, 1);
      expect(item.seriesId, '4328');
      expect(item.duration, const Duration(milliseconds: 1331790));
    });

    test('rootSeries "0" means the item is the series root', () {
      final item = parseMediaItem({
        'nb': '4328',
        'title': 'F',
        'rootSeries': '0',
      })!;
      expect(item.rootSeriesId, isNull);
      expect(item.seriesId, '4328');
    });

    test('rejects items without an ID or a title, and non-maps', () {
      expect(parseMediaItem({'en_title': 'No id'}), isNull);
      expect(parseMediaItem({'nb': '1'}), isNull);
      expect(parseMediaItem({'nb': '0', 'en_title': 'zero'}), isNull);
      expect(parseMediaItem('nope'), isNull);
      expect(parseMediaItem(null), isNull);
    });

    test('falls back to other_title and to fallbackKind', () {
      final item = parseMediaItem({
        'nb': '9',
        'other_title': 'Original',
      }, fallbackKind: VideoKind.series)!;
      expect(item.title.en, 'Original');
      expect(item.kind, VideoKind.series);
    });

    test('banners: wide cover as backdrop, relative path as poster', () {
      final banners = parseBanners(fixture('banners'));
      expect(banners, isNotEmpty);
      for (final b in banners) {
        expect(
          b.posterUrl,
          startsWith(
            '$imageHost'
            'vascin-',
          ),
        );
        expect(b.backdropUrl, startsWith('https://'));
        expect(b.backdropUrl, isNot(b.posterUrl));
        expect(b.hdPosterUrl, isNull);
      }
    });

    test('banner links name the episode to open', () {
      expect(
        bannerEpisodeId(
          'https://cinemana.shabakaty.cc/video/ar/797119?lastEpisodeVideoID=3157016',
        ),
        '3157016',
      );
      expect(
        bannerEpisodeId(
          'https://cinemana.shabakaty.com/video/en/399243?showInfo=true',
        ),
        isNull,
      );
      expect(bannerEpisodeId(null), isNull);
      final banners = parseBanners([
        {
          'nb': '797119',
          'en_title': 'S',
          'kind': '2',
          'link': r'https:\/\/cinemana.shabakaty.com\/video\/en\/797119?lastEpisodeVideoID=3157016',
        },
        {'nb': '1', 'en_title': 'M', 'kind': '1', 'link': ''},
      ]);
      expect(banners.map((b) => b.linkedEpisodeId), ['3157016', null]);
    });

    test('resolveImageUrl', () {
      expect(
        resolveImageUrl('vascin-poster-images/a.jpg'),
        '${imageHost}vascin-poster-images/a.jpg',
      );
      expect(resolveImageUrl('/vascin-x/b.png'), '${imageHost}vascin-x/b.png');
      expect(resolveImageUrl('ABC_poster.jpg'), isNull);
      expect(resolveImageUrl('defaultImages/loading.gif'), isNull);
      expect(
        resolveImageUrl(
          'https://cinemana.shabakaty.com/loadingImages/loading.gif',
        ),
        isNull,
      );
      expect(
        resolveImageUrl(
          'https://cnth2.shabakaty.com/defaultImages/not_available.jpg',
        ),
        isNull,
      );
      expect(resolveImageUrl('https://x/y.jpg'), 'https://x/y.jpg');
    });

    test('ignores placeholder image paths', () {
      final item = parseMediaItem({
        'nb': '1',
        'title': 'A',
        'imgObjUrl': 'defaultImages/loading.gif',
      })!;
      expect(item.posterUrl, isNull);
    });

    test('episodes carry their numbering, movies none', () {
      final ep = parseMediaItem({
        'nb': '5',
        'en_title': 'S',
        'kind': '2',
        'season': '1',
        'episodeNummer': '807',
        'episode_flag': '0010',
      })!;
      expect(ep.numbering!.numbers, [807, 808]);
      final movie = parseMediaItem({
        'nb': '6',
        'en_title': 'M',
        'kind': '1',
        'season': '0',
        'episodeNummer': '0',
        'episode_flag': '0000',
      })!;
      expect(movie.numbering, isNull);
    });
  });

  test('parseMediaItems handles object roots, nesting and bad entries', () {
    final items = parseMediaItems({
      'data': [
        {'nb': '1', 'title': 'A'},
        'garbage',
        null,
        {'nb': '1', 'title': 'A again'},
        {
          'content': [
            {'nb': '2', 'title': 'B'},
          ],
        },
      ],
    });
    expect(items.map((i) => i.id), ['1', '2']);
    expect(items.first.title.en, 'A');
    expect(parseMediaItems('not json'), isEmpty);
    expect(parseMediaItems(null), isEmpty);
  });

  group('video groups', () {
    test('fixture', () {
      final groups = parseVideoGroups(fixture('video_groups_en'));
      expect(groups, isNotEmpty);
      for (final g in groups) {
        expect(g.id, isNotEmpty);
        expect(g.title, isNotEmpty);
        expect(g.items, isNotEmpty);
      }
    });

    test('skips groups without items, works with a bare list', () {
      final groups = parseVideoGroups([
        {'groupsID': '1', 'title': 'Empty', 'content': []},
        {
          'groupsID': '2',
          'title': 'Full',
          'hasPagination': 1,
          'content': [
            {'nb': '5', 'title': 'X'},
          ],
        },
      ]);
      expect(groups.single.id, '2');
      expect(groups.single.hasPagination, isTrue);
    });
  });

  group('offset pages', () {
    test('videos_by_category fixture (trimmed to a short page)', () {
      final page = parseOffsetPage(fixture('videos_by_category'));
      expect(page.items, isNotEmpty);
      expect(page.hasMore, isFalse);
    });

    test('videos_by_category_and_language fixture', () {
      final page = parseOffsetPage(
        fixture('videos_by_category_and_language'),
        fallbackKind: VideoKind.movies,
      );
      expect(page.items, isNotEmpty);
    });

    test(
      'a short or empty page ends paging even if the server sends an offset',
      () {
        final full = parseOffsetPage({
          'info': [
            for (var i = 1; i <= 30; i++) {'nb': '$i', 'title': 'T'},
          ],
          'offset': 30,
        });
        expect(full.nextOffset, 30);
        expect(full.hasMore, isTrue);
        final short = parseOffsetPage({
          'info': [
            {'nb': '1', 'title': 'T'},
          ],
          'offset': 60,
        });
        expect(short.hasMore, isFalse);
        expect(
          parseOffsetPage({'info': [], 'offset': 1000029}).hasMore,
          isFalse,
        );
      },
    );

    test('bare list has no next offset', () {
      final page = parseOffsetPage([
        {'nb': '1', 'title': 'A'},
      ]);
      expect(page.items, hasLength(1));
      expect(page.nextOffset, isNull);
    });
  });
}
