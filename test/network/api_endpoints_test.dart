import 'dart:convert';

import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('title search: URL-encode with %20, then base64', () {
    final encoded = ApiEndpoints.encodeTitleQuery(' the office ');
    expect(utf8.decode(base64.decode(encoded)), 'the%20office');
    final arabic = ApiEndpoints.encodeTitleQuery('صراع');
    expect(utf8.decode(base64.decode(arabic)), Uri.encodeComponent('صراع'));
    expect(
      ApiEndpoints.titleSearch('batman').path,
      'video/V/2/itemsPerPage/30/video_title_search/${base64.encode(utf8.encode('batman'))}'
      '/itemsPerPage/30/pageNumber/0/level/0',
    );
  });

  test(
    'title search percent-encodes the base64 (= and + break the server)',
    () {
      final path = ApiEndpoints.titleSearch('the dark knight').path;
      final segment = path.split('/')[6];
      expect(segment, endsWith('%3D%3D'));
      expect(segment, isNot(contains('=')));
      expect(ApiEndpoints.titleSearch('aa~').path, contains('YWF%2B'));
    },
  );

  test('advanced search computes the year range instead of hardcoding it', () {
    final q = ApiEndpoints.advancedSearch(
      videoTitle: 'x',
      now: DateTime(2031, 3, 1),
    ).query;
    expect(q['year'], '1900,2031');
    expect(q.containsKey('type'), isFalse);
    expect(q.containsKey('staffTitle'), isFalse);
  });

  test('advanced search includes only the filters that are set', () {
    final q = ApiEndpoints.advancedSearch(
      staffTitle: 'Nolan',
      kind: VideoKind.series,
      yearFrom: 2000,
      yearTo: 2010,
      page: 2,
    ).query;
    expect(q, {
      'level': 0,
      'staffTitle': 'Nolan',
      'type': 'series',
      'year': '2000,2010',
      'page': 2,
    });
  });

  test('IDs are encoded as single path segments', () {
    expect(
      ApiEndpoints.videoInfo('12/../x').path,
      'allVideoInfo/id/12%2F..%2Fx',
    );
  });

  test('kind and sort codes match the live API', () {
    expect(VideoKind.series.code, 2);
    expect(VideoKind.movies.searchType, 'movies');
    expect(
      {for (final s in SortOrder.values) s.name: s.code},
      {
        'recentlyAdded': 'desc',
        'oldestAdded': 'asc',
        'newestRelease': 'r_desc',
        'mostViewed': 'views_desc',
      },
    );
  });

  test('recommendations POST JSON to the recommendation service', () {
    final r = ApiEndpoints.recommendations('191463', title: ' Avengers ');
    expect(r.path, startsWith('https://recommend.shabakaty.com/'));
    expect(r.method, HttpMethod.post);
    expect(r.json, {
      'MovieId': '191463',
      'MovieName': 'Avengers',
      'ReProcessIfExpired': true,
    });
    expect(
      ApiEndpoints.recommendations('1').json!.containsKey('MovieName'),
      isFalse,
    );
  });

  test('always the unrestricted parental level', () {
    expect(ApiEndpoints.level, 0);
    expect(ApiEndpoints.banners().path, 'banner/level/0');
  });

  test('no rating filter or rating sort exists', () {
    expect(SortOrder.values.map((s) => s.code), isNot(contains('stars_desc')));
    expect(ApiEndpoints.advancedSearch().query.containsKey('star'), isFalse);
  });
}
