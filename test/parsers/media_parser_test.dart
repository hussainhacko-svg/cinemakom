import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/media_item.dart';
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
      'catalog_movies_top_rated',
      'catalog_series_newest',
      'title_search',
      'advanced_search_series',
      'related_movie',
      'videos_by_ids',
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

    test('latest_movies items are movies with years and ratings', () {
      final items = parseMediaItems(fixture('latest_movies'));
      expect(items.every((i) => i.kind == VideoKind.movies), isTrue);
      expect(items.any((i) => i.year != null), isTrue);
      expect(items.any((i) => i.rating != null), isTrue);
    });

    test('empty endpoints give empty lists', () {
      expect(parseMediaItems(fixture('latest_videos_items')), isEmpty);
      expect(parseMediaItems(fixture('popular_films')), isEmpty);
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
      expect(item.rating, 7.5);
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

    test('ignores placeholder image paths', () {
      final item = parseMediaItem({
        'nb': '1',
        'title': 'A',
        'imgObjUrl': 'defaultImages/loading.gif',
      })!;
      expect(item.posterUrl, isNull);
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
    test('videos_by_category fixture', () {
      final page = parseOffsetPage(fixture('videos_by_category'));
      expect(page.items, isNotEmpty);
      expect(page.nextOffset, isNotNull);
    });

    test('videos_by_category_and_language fixture', () {
      final page = parseOffsetPage(
        fixture('videos_by_category_and_language'),
        fallbackKind: VideoKind.movies,
      );
      expect(page.items, isNotEmpty);
    });

    test('bare list has no next offset', () {
      final page = parseOffsetPage([
        {'nb': '1', 'title': 'A'},
      ]);
      expect(page.items, hasLength(1));
      expect(page.nextOffset, isNull);
    });
  });

  test('sortAndFilterTopRated keeps the Kotlin behavior', () {
    MediaItem m(String id, double r) => MediaItem(id: id, rating: r);
    final many = [m('a', 6), m('b', 8), m('c', 7.5), m('d', 9), m('e', 7)];
    expect(sortAndFilterTopRated(many).map((i) => i.id), ['d', 'b', 'c', 'e']);
    final few = [m('a', 6), m('b', 8), m('c', 5)];
    expect(sortAndFilterTopRated(few).map((i) => i.id), ['b', 'a', 'c']);
  });
}
