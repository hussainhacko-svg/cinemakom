import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/repositories/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_client.dart';

typedef F = FakeApiClient;

Map<String, Object?> item(String id, String title, {String? kind}) => {
  'nb': id,
  'en_title': title,
  'kind': ?kind,
};

bool isAdvanced(VideoKind kind, ApiRequest r) =>
    r.path == 'AdvancedSearch' && r.query['type'] == kind.searchType;

void main() {
  test(
    'runs three searches with a computed year and ranks the merge',
    () async {
      final api = F([
        F.path('video/V/2/', [
          item('1', 'Monster Hunter'),
          item('2', 'Monster'),
        ]),
        (
          (r) => isAdvanced(VideoKind.series, r),
          (_) => [item('3', 'Monsters, Inc. Series')],
        ),
        (
          (r) => isAdvanced(VideoKind.movies, r),
          (_) => [item('4', 'Monster (2004)'), item('2', 'Monster')],
        ),
      ]);
      final repo = SearchRepository(api, clock: () => DateTime(2030));
      final results = await repo.search('  monster ');
      expect(results.map((i) => i.id), ['2', '4', '1', '3']);
      expect(api.requests, hasLength(3));
      // Like the website: the query is both a title and a staff name.
      for (final r in api.requests.where((r) => r.path == 'AdvancedSearch')) {
        expect(r.query['videoTitle'], 'monster');
        expect(r.query['staffTitle'], 'monster');
      }
      expect(
        api.requests
            .where((r) => r.path == 'AdvancedSearch')
            .map((r) => r.query['year']),
        everyElement('1900,2030'),
      );
    },
  );

  test('a failing source is ignored, all failing throws', () async {
    final partial = SearchRepository(
      F([
        F.path('video/V/2/', offline),
        F.path('AdvancedSearch', [item('5', 'X')]),
      ]),
    );
    expect((await partial.search('x')).single.id, '5');

    final dead = SearchRepository(F([F.path('', offline)]));
    await expectLater(dead.search('x'), throwsA(isA<ApiException>()));
  });

  test('empty query makes no requests', () async {
    final api = F([]);
    expect(await SearchRepository(api).search('   '), isEmpty);
    expect(api.requests, isEmpty);
  });

  test('merge marks series-search hits as series and keeps known kinds', () {
    const noKind = MediaItem(
      id: '1',
      title: LocalizedText(en: 'A'),
    );
    const asSeries = MediaItem(
      id: '1',
      title: LocalizedText(en: 'A'),
      kind: VideoKind.series,
    );
    const movie = MediaItem(
      id: '2',
      title: LocalizedText(en: 'B'),
      kind: VideoKind.movies,
    );
    final merged = mergeSearchResults([noKind, movie], [asSeries], [movie]);
    expect(merged.map((i) => (i.id, i.kind)), [
      ('1', VideoKind.series),
      ('2', VideoKind.movies),
    ]);
  });

  test('ranking: whole-word matches beat partial ones, Arabic works', () {
    MediaItem m(String id, String en, [String? ar]) => MediaItem(
      id: id,
      title: LocalizedText(en: en, ar: ar),
    );
    final ranked = rankSearchResults('war', [
      m('1', 'Starwars'),
      m('2', 'The War Game'),
      m('3', 'Unrelated', 'war'),
    ]);
    expect(ranked.map((i) => i.id), ['3', '2', '1']);
    final arabic = rankSearchResults('صراع', [
      m('a', 'x', 'نهاية صراع'),
      m('b', 'y', 'صراع العروش'),
    ]);
    expect(arabic.map((i) => i.id), ['b', 'a']);
  });

  test('advancedSearch passes the filters through', () async {
    final api = F([
      F.path('AdvancedSearch', [item('9', 'Inception')]),
    ]);
    final result = await SearchRepository(
      api,
      clock: () => DateTime(2027),
    ).advancedSearch(staffName: 'Nolan', kind: VideoKind.movies);
    expect(result.single.kind, VideoKind.movies);
    expect(api.requests.single.query, containsPair('staffTitle', 'Nolan'));
    expect(api.requests.single.query, containsPair('year', '1900,2027'));
  });
}
