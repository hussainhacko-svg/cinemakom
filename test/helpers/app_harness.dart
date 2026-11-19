import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/widgets/media_image.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_providers.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../fixture.dart';
import '../repositories/fake_api_client.dart';

typedef Route = (bool Function(ApiRequest), Object? Function(ApiRequest));

/// The 0-based page or offset a request asks for (path or query).
int requestedPage(ApiRequest r) {
  final path = RegExp(r'/(?:page|pageNumber|offset)/(\d+)').firstMatch(r.path);
  if (path != null) return int.parse(path[1]!);
  final q = r.query['page'] ?? r.query['offset'];
  return q == null ? 0 : int.parse('$q');
}

/// Answers with fixture [name] for the first page and nothing after it.
Route firstPage(String prefix, String name, {Object? empty = const []}) =>
    FakeApiClient.path(
      prefix,
      (ApiRequest r) => requestedPage(r) == 0 ? fixture(name) : empty,
    );

/// Every endpoint the app calls, answered from the captured fixtures.
/// Put [overrides] first to change one endpoint.
FakeApiClient fixtureApi([List<Route> overrides = const []]) => FakeApiClient([
  ...overrides,
  FakeApiClient.fixtureAt('banner/', 'banners'),
  FakeApiClient.fixtureAt('videoGroups/', 'video_groups_en'),
  firstPage('featuredMovies/', 'featured'),
  firstPage('latestMovies/', 'latest_movies'),
  firstPage('latestSeries/', 'latest_series'),
  FakeApiClient.path(
    'video/V/2/',
    (ApiRequest r) => requestedPage(r) != 0
        ? const []
        : r.path.contains('video_title_search')
        ? fixture('title_search')
        : fixture('catalog_movies_most_viewed'),
  ),
  FakeApiClient.fixtureAt('mainCategories', 'main_categories_ar'),
  FakeApiClient.fixtureAt('subCategories', 'sub_categories_en'),
  FakeApiClient.fixtureAt('categoryLangFreqVideo', 'category_languages'),
  firstPage(
    'videosByCategoryAndLanguage',
    'videos_by_category_and_language',
    empty: const {'info': [], 'offset': 60},
  ),
  firstPage(
    'videosByCategory',
    'videos_by_category',
    empty: const {'info': [], 'offset': 60},
  ),
  firstPage('AdvancedSearch', 'advanced_search_series'),
  FakeApiClient.path(
    'allVideoInfo/',
    (ApiRequest r) => r.path.contains('/4328')
        ? fixture('video_info_series')
        : fixture('video_info_movie'),
  ),
  FakeApiClient.fixtureAt('videoSeason/', 'series_episodes'),
  FakeApiClient.fixtureAt('https://recommend', 'recommendations'),
  FakeApiClient.fixtureAt('relatedVideos/', 'related_movie'),
  FakeApiClient.fixtureAt('https://6b1m6vnfz2jk', 'service_status'),
]);

/// Pumps the whole app at [width]×[height] dp on [store] (English chosen by
/// default) with [api] behind every repository and no network images.
Future<void> pumpApp(
  WidgetTester tester, {
  MemoryPreferenceStore? store,
  FakeApiClient? api,
  double width = 390,
  double height = 844,
}) async {
  tester.view
    ..physicalSize = Size(width, height) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noRetry,
      overrides: [
        preferenceStoreProvider.overrideWith(
          (ref) =>
              store ?? MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
        ),
        apiClientProvider.overrideWithValue(api ?? fixtureApi()),
        networkImagesProvider.overrideWithValue(false),
      ],
      child: const CinemakomApp(),
    ),
  );
  await tester.pumpAndSettle();
}

TextDirection directionAt(WidgetTester tester, Finder finder) =>
    Directionality.of(tester.element(finder));
