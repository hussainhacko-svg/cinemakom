import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/api_providers.dart';
import '../models/catalog_models.dart';
import '../models/media_item.dart';
import '../parsers/category_parser.dart';
import '../parsers/details_parser.dart';
import '../parsers/media_parser.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);

/// Home rows, genres and catalog browsing.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  /// When the first page of a genre has fewer items than this, other kinds and
  /// sorts are merged in (same as the Kotlin app).
  static const int genreFallbackThreshold = 6;

  Future<List<MediaItem>> banners() async =>
      parseMediaItems(await _api.fetch(ApiEndpoints.banners()));

  Future<List<VideoGroup>> videoGroups(ApiLanguage lang) async =>
      parseVideoGroups(await _api.fetch(ApiEndpoints.videoGroups(lang)));

  /// "See all" for one group. [page] is 0-based.
  Future<List<MediaItem>> videoGroupPage(
    String groupId, {
    int page = 0,
  }) async => parseMediaItems(
    await _api.fetch(ApiEndpoints.videoGroupPage(groupId, page: page)),
  );

  Future<List<MediaItem>> featured({int page = 0}) async =>
      parseMediaItems(await _api.fetch(ApiEndpoints.featured(page: page)));

  Future<List<MediaItem>> latestMovies({int page = 0}) async => parseMediaItems(
    await _api.fetch(ApiEndpoints.latestMovies(page: page)),
    fallbackKind: VideoKind.movies,
  );

  Future<List<MediaItem>> latestSeries({int page = 0}) async => parseMediaItems(
    await _api.fetch(ApiEndpoints.latestSeries(page: page)),
    fallbackKind: VideoKind.series,
  );

  Future<List<MediaItem>> newlyAdded() async =>
      parseMediaItems(await _api.fetch(ApiEndpoints.newlyAdded()));

  /// The main catalog. For [SortOrder.topRated], a larger page is fetched and
  /// filtered to titles rated 7+ (same as the Kotlin app).
  Future<List<MediaItem>> catalog({
    required VideoKind kind,
    required SortOrder sort,
    int page = 0,
  }) async {
    final topRated = sort == SortOrder.topRated;
    final items = parseMediaItems(
      await _api.fetch(
        ApiEndpoints.catalog(
          kind: kind,
          sort: sort,
          page: page,
          itemsPerPage: topRated ? 60 : 24,
        ),
      ),
      fallbackKind: kind,
    );
    return topRated ? sortAndFilterTopRated(items) : items;
  }

  /// Genres for the home rows and filters: the main genres first, then the
  /// sub-genres. Falls back to [fallbackGenres] when both requests fail or
  /// return nothing.
  Future<List<Category>> genres(ApiLanguage lang) async {
    final results = await Future.wait([
      _quiet(
        () async => parseCategories(
          await _api.fetch(ApiEndpoints.mainCategories(lang)),
          lang: lang,
        ),
      ),
      _quiet(
        () async => parseCategories(
          await _api.fetch(ApiEndpoints.subCategories(lang)),
          lang: lang,
        ),
      ),
    ]);
    final seen = <String>{};
    final merged = [
      for (final c in [...?results[0], ...?results[1]])
        if (seen.add(c.id)) c,
    ];
    return merged.isEmpty ? fallbackGenres : merged;
  }

  /// Every category with both English and Arabic names.
  Future<List<Category>> allCategories() async =>
      parseCategories(await _api.fetch(ApiEndpoints.categories()));

  Future<List<CategoryLanguage>> categoryLanguages() async =>
      parseCategoryLanguages(
        await _api.fetch(ApiEndpoints.categoryLanguages()),
      );

  /// One page of a genre. On the first page, when there are fewer than
  /// [genreFallbackThreshold] items, the other sort and the other kind are
  /// merged in so the screen isn't nearly empty.
  Future<OffsetPage> videosByCategory({
    required String categoryId,
    VideoKind kind = VideoKind.movies,
    SortOrder sort = SortOrder.topRated,
    int offset = 0,
  }) async {
    Future<OffsetPage> load(VideoKind k, SortOrder s) async => parseOffsetPage(
      await _api.fetch(
        ApiEndpoints.videosByCategory(
          categoryId: categoryId,
          kind: k,
          sort: s,
          offset: offset,
        ),
      ),
      fallbackKind: k,
    );

    final primary = await load(kind, sort);
    if (offset != 0 || primary.items.length >= genreFallbackThreshold) {
      return primary;
    }
    final extras = await Future.wait([
      _quiet(() => load(kind, sort.other)),
      _quiet(() => load(kind.other, sort)),
      _quiet(() => load(kind.other, SortOrder.newest)),
    ]);
    final seen = <String>{};
    return OffsetPage(
      items: [
        for (final item in [
          ...primary.items,
          for (final page in extras) ...?page?.items,
        ])
          if (seen.add(item.id)) item,
      ],
      nextOffset: primary.nextOffset,
    );
  }

  Future<OffsetPage> videosByCategoryAndLanguage({
    required String categoryId,
    required String languageId,
    VideoKind kind = VideoKind.movies,
    SortOrder sort = SortOrder.topRated,
    int offset = 0,
  }) async => parseOffsetPage(
    await _api.fetch(
      ApiEndpoints.videosByCategoryAndLanguage(
        categoryId: categoryId,
        languageId: languageId,
        kind: kind,
        sort: sort,
        offset: offset,
      ),
    ),
    fallbackKind: kind,
  );

  Future<List<FaqEntry>> faq() async =>
      parseFaq(await _api.fetch(ApiEndpoints.faq()));
}

/// Runs [load] and returns `null` on an API error, for optional extras.
Future<T?> _quiet<T>(Future<T> Function() load) async {
  try {
    return await load();
  } on ApiException {
    return null;
  }
}
