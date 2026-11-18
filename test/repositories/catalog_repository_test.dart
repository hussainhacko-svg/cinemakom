import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
import 'package:cinemakom/data/parsers/category_parser.dart';
import 'package:cinemakom/data/repositories/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api_client.dart';

typedef F = FakeApiClient;

void main() {
  test('home endpoints parse their fixtures', () async {
    final repo = CatalogRepository(
      F([
        F.fixtureAt('banner/', 'banners'),
        F.fixtureAt('videoGroups/', 'video_groups_en'),
        F.fixtureAt('latestSeries/', 'latest_series'),
        F.fixtureAt('faqQuestion', 'faq'),
      ]),
    );
    expect(await repo.banners(), isNotEmpty);
    expect(await repo.videoGroups(ApiLanguage.en), isNotEmpty);
    expect((await repo.latestSeries()).every((i) => i.isSeries), isTrue);
    expect(await repo.faq(), isNotEmpty);
  });

  test('top-rated catalog asks for 60 items and keeps only 7+', () async {
    final api = F([
      F.path('video/V/2/', [
        for (final (id, stars) in [
          ('a', '9'),
          ('b', '6'),
          ('c', '8'),
          ('d', '7.2'),
          ('e', '7'),
        ])
          {'nb': id, 'en_title': id, 'stars': stars},
      ]),
    ]);
    final items = await CatalogRepository(api)
        .catalog(kind: VideoKind.movies, sort: SortOrder.topRated);
    expect(api.requests.single.path, contains('itemsPerPage/60/'));
    expect(items.map((i) => i.id), ['a', 'c', 'd', 'e']);
    expect(items.every((i) => i.kind == VideoKind.movies), isTrue);
  });

  test('genres merge main and sub categories without duplicates', () async {
    final repo = CatalogRepository(
      F([
        F.path('mainCategories', [
          {'nb': '84', 'title': 'Action'},
          {'nb': '59', 'title': 'Comedy'},
        ]),
        F.path('subCategories', [
          {'nb': '59', 'title': 'Comedy'},
          {'nb': '58', 'title': 'Biography'},
        ]),
      ]),
    );
    final genres = await repo.genres(ApiLanguage.en);
    expect(genres.map((g) => g.id), ['84', '59', '58']);
  });

  test('genres fall back to the built-in list when the API fails', () async {
    final repo = CatalogRepository(
      F([F.path('mainCategories', offline), F.path('subCategories', [])]),
    );
    expect(await repo.genres(ApiLanguage.ar), fallbackGenres);
  });

  group('videosByCategory', () {
    Map<String, Object?> page(List<String> ids) => {
      'info': [
        for (final id in ids) {'nb': id, 'en_title': id},
      ],
      'offset': 30,
    };

    test('a full first page is returned as is', () async {
      final api = F([
        F.path('videosByCategory', page(['1', '2', '3', '4', '5', '6'])),
      ]);
      final result = await CatalogRepository(api)
          .videosByCategory(categoryId: '84');
      expect(result.items, hasLength(6));
      expect(result.nextOffset, 30);
      expect(api.requests, hasLength(1));
    });

    test('a short first page merges other sorts and kinds', () async {
      final api = F([
        F.path('videosByCategory', (r) {
          final q = r.query;
          return switch ((q['videoKind'], q['orderby'])) {
            (1, 'r_desc') => page(['1', '2']),
            (1, 'desc') => page(['2', '3']),
            (2, 'r_desc') => offline,
            (2, 'desc') => page(['4']),
            _ => page([]),
          };
        }),
      ]);
      final result = await CatalogRepository(api)
          .videosByCategory(categoryId: '84');
      expect(result.items.map((i) => i.id), ['1', '2', '3', '4']);
      expect(api.requests, hasLength(4));
    });

    test('later pages never merge, and the main request can fail', () async {
      final api = F([
        F.path('videosByCategory', page(['9'])),
      ]);
      final result = await CatalogRepository(api)
          .videosByCategory(categoryId: '84', offset: 30);
      expect(result.items, hasLength(1));
      expect(api.requests, hasLength(1));

      final failing = CatalogRepository(
        F([F.path('videosByCategory', offline)]),
      );
      await expectLater(
        failing.videosByCategory(categoryId: '84'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('category × language pages use the fixture', () async {
    final repo = CatalogRepository(
      F([
        F.fixtureAt('categoryLangFreqVideo', 'category_languages'),
        F.fixtureAt(
          'videosByCategoryAndLanguage',
          'videos_by_category_and_language',
        ),
      ]),
    );
    final langs = await repo.categoryLanguages();
    expect(langs, isNotEmpty);
    final page = await repo.videosByCategoryAndLanguage(
      categoryId: langs.first.categoryId,
      languageId: langs.first.languageId,
    );
    expect(page.items, isNotEmpty);
  });
}
