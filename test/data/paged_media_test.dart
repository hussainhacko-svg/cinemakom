import 'package:cinemakom/core/network/api_providers.dart';
import 'package:cinemakom/data/paging/media_sources.dart';
import 'package:cinemakom/data/paging/paged_media.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../repositories/fake_api_client.dart';

/// [count] raw items with IDs from [start].
List<Map<String, Object>> rawItems(int start, int count) => [
  for (var i = start; i < start + count; i++)
    {'nb': '${i + 1}', 'en_title': 'Title ${i + 1}', 'kind': 1},
];

/// Listens to [source] and waits until its current load has finished.
Future<PagedMedia> settle(ProviderContainer c, MediaSource source) async {
  final provider = pagedMediaProvider(source);
  c.listen(provider, (_, _) {});
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
    final s = c.read(provider);
    if (s.started && !s.isLoading) return s;
  }
  fail('$source never settled');
}

Future<PagedMedia> more(ProviderContainer c, MediaSource source) async {
  await c.read(pagedMediaProvider(source).notifier).loadMore();
  return c.read(pagedMediaProvider(source));
}

ProviderContainer containerWith(FakeApiClient api) {
  final c = ProviderContainer(
    retry: noRetry,
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('sources with the same parameters are equal', () {
    expect(
      const GenreSource(categoryId: '1', sort: SortOrder.mostViewed),
      const GenreSource(categoryId: '1', sort: SortOrder.mostViewed),
    );
    expect(
      const GenreSource(categoryId: '1'),
      isNot(const GenreSource(categoryId: '1', languageId: '22')),
    );
    expect(const LatestSource(VideoKind.movies), isNot(const FeaturedSource()));
  });

  test('a genre pages by item offset and stops on a short page', () async {
    final api = fixtureApi([
      FakeApiClient.path('videosByCategory', (ApiRequest r) {
        final offset = int.parse('${r.query['offset']}');
        return {
          'info': rawItems(offset, offset < 60 ? 30 : 5),
          // The server keeps sending a next offset past the end.
          'offset': offset + 30,
        };
      }),
    ]);
    final c = containerWith(api);
    const source = GenreSource(categoryId: '1');

    var s = await settle(c, source);
    expect(s.items, hasLength(30));
    expect(s.hasMore, isTrue);
    s = await more(c, source);
    s = await more(c, source);
    expect(s.items, hasLength(65));
    expect(s.hasMore, isFalse);
    expect([for (final r in api.requests) r.query['offset']], [0, 30, 60]);

    // Past the end nothing more is asked for.
    await more(c, source);
    expect(api.requests, hasLength(3));
  });

  test('numbered lists stop on an empty page', () async {
    final api = fixtureApi([
      FakeApiClient.path(
        'latestMovies/',
        (ApiRequest r) =>
            requestedPage(r) < 2 ? rawItems(requestedPage(r) * 24, 24) : [],
      ),
    ]);
    final c = containerWith(api);
    const source = LatestSource(VideoKind.movies);
    await settle(c, source);
    await more(c, source);
    final s = await more(c, source);
    expect(s.items, hasLength(48));
    expect(s.hasMore, isFalse);
  });

  test('a video group stops on a short page', () async {
    final api = fixtureApi([
      FakeApiClient.path(
        'videoListPagination/',
        (ApiRequest r) =>
            rawItems(requestedPage(r) * 12, requestedPage(r) == 0 ? 12 : 7),
      ),
    ]);
    final c = containerWith(api);
    const source = GroupSource('9');
    await settle(c, source);
    final s = await more(c, source);
    expect(s.items, hasLength(19));
    expect(s.hasMore, isFalse);
  });

  test('titles repeated across pages are shown once', () async {
    final api = fixtureApi([
      FakeApiClient.path(
        'featuredMovies/',
        (ApiRequest r) => switch (requestedPage(r)) {
          0 => rawItems(0, 12),
          1 => rawItems(6, 12), // overlaps the first page by 6
          _ => [],
        },
      ),
    ]);
    final c = containerWith(api);
    const source = FeaturedSource();
    await settle(c, source);
    final s = await more(c, source);
    expect(s.items.map((i) => i.id).toSet(), hasLength(18));
    expect(s.items, hasLength(18));
  });

  test('a failed page keeps what was loaded, and retry resumes', () async {
    var fail = true;
    final api = fixtureApi([
      FakeApiClient.path('featuredMovies/', (ApiRequest r) {
        if (requestedPage(r) == 0) return rawItems(0, 12);
        if (requestedPage(r) == 1 && fail) return offline;
        return requestedPage(r) == 1 ? rawItems(12, 12) : [];
      }),
    ]);
    final c = containerWith(api);
    const source = FeaturedSource();
    await settle(c, source);
    var s = await more(c, source);
    expect(s.error, offline);
    expect(s.items, hasLength(12));
    expect(s.failedFirstPage, isFalse);

    // loadMore doesn't hammer a failing page; retry does.
    await more(c, source);
    expect(api.requests, hasLength(2));
    fail = false;
    await c.read(pagedMediaProvider(source).notifier).retry();
    s = c.read(pagedMediaProvider(source));
    expect(s.error, isNull);
    expect(s.items, hasLength(24));
  });

  test('search pages until every source is empty', () async {
    final api = fixtureApi([
      FakeApiClient.path(
        'video/V/2/',
        (ApiRequest r) => requestedPage(r) == 0 ? rawItems(0, 3) : [],
      ),
      FakeApiClient.path(
        'AdvancedSearch',
        (ApiRequest r) => requestedPage(r) <= 1
            ? rawItems(100 + requestedPage(r) * 12, 12)
            : [],
      ),
    ]);
    final c = containerWith(api);
    const source = SearchSource('batman');
    var s = await settle(c, source);
    expect(s.hasMore, isTrue);
    s = await more(c, source);
    expect(s.hasMore, isTrue, reason: 'AdvancedSearch still had results');
    s = await more(c, source);
    expect(s.hasMore, isFalse);
    expect(s.items, hasLength(3 + 12 + 12));
  });
}
