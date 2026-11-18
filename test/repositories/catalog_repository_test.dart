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

  test('catalog passes kind, sort and page through', () async {
    final api = F([
      F.path('video/V/2/', [
        {'nb': 'a', 'en_title': 'A', 'stars': '9'},
      ]),
    ]);
    final items = await CatalogRepository(api)
        .catalog(kind: VideoKind.series, sort: SortOrder.mostViewed, page: 2);
    expect(
      api.requests.single.path,
      'video/V/2/itemsPerPage/30/level/0/videoKind/2/sortParam/views_desc/pageNumber/2',
    );
    expect(items.single.kind, VideoKind.series);
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

  test('videosByCategory returns one page and the next offset', () async {
    final api = F([
      F.path('videosByCategory', {
        'info': [
          for (var i = 1; i <= 30; i++) {'nb': '$i', 'en_title': 'T$i'},
        ],
        'offset': 30,
      }),
    ]);
    final page = await CatalogRepository(api)
        .videosByCategory(categoryId: '84');
    expect(page.items, hasLength(30));
    expect(page.items.first.kind, VideoKind.movies);
    expect(page.nextOffset, 30);
    expect(api.requests.single.query['orderby'], 'desc');

    final failing = CatalogRepository(F([F.path('videosByCategory', offline)]));
    await expectLater(
      failing.videosByCategory(categoryId: '84'),
      throwsA(isA<ApiException>()),
    );
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
