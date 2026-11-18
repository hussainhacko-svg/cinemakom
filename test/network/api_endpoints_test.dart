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

  test('title search keeps a literal + and % (the server URL-decodes)', () {
    // urldecode(base64decode(segment)) must give back the query.
    String roundTrip(String q) => Uri.decodeComponent(
      utf8.decode(base64.decode(ApiEndpoints.encodeTitleQuery(q))),
    );
    for (final q in ['c++', '100%', '%41', 'fast & furious', "ocean's"]) {
      expect(roundTrip(q), q);
    }
  });

  test('advanced search computes the year range instead of hardcoding it', () {
    final q = ApiEndpoints.advancedSearch(
      kind: VideoKind.movies,
      videoTitle: 'x',
      now: DateTime(2031, 3, 1),
    ).query;
    expect(q['year'], '1900,2031');
    expect(q['type'], 'movies');
    expect(q.containsKey('staffTitle'), isFalse);
  });

  test('advanced search swaps a reversed year range and clamps the page', () {
    final q = ApiEndpoints.advancedSearch(
      kind: VideoKind.series,
      yearFrom: 2020,
      yearTo: 2000,
      page: -3,
    ).query;
    expect(q['year'], '2000,2020');
    expect(q['page'], 0);
  });

  test('advanced search includes only the filters that are set', () {
    final q = ApiEndpoints.advancedSearch(
      staffTitle: 'Nolan',
      kind: VideoKind.series,
      categoryId: ' 84 ',
      yearFrom: 2000,
      yearTo: 2010,
      page: 2,
    ).query;
    expect(q, {
      'level': 0,
      'staffTitle': 'Nolan',
      'type': 'series',
      'category_id': '84',
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
        'oldestRelease': 'r_asc',
        'mostViewed': 'views_desc',
        'titleAscending': 'title_asc',
        'titleDescending': 'title_desc',
      },
    );
    expect(SortOrder.values.where((s) => !s.worksOnCatalog), [
      SortOrder.titleAscending,
      SortOrder.titleDescending,
    ]);
  });

  test('streams can bypass the API cache', () {
    expect(ApiEndpoints.streams('7').query, isEmpty);
    final fresh = ApiEndpoints.streams('7', cacheBuster: '123');
    expect(fresh.path, 'transcoddedFiles/id/7');
    expect(fresh.query, {'_': '123'});
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
    final codes = SortOrder.values.map((s) => s.code);
    for (final banned in ['stars', 'rating']) {
      expect(codes.where((c) => c.startsWith(banned)), isEmpty);
    }
    expect(
      ApiEndpoints.advancedSearch(kind: VideoKind.movies).query
          .containsKey('star'),
      isFalse,
    );
  });
}
