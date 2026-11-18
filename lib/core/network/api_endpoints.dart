/// Every Cinemana endpoint the app uses, as request builders.
///
/// This file (with `api_client.dart`) is the only place that knows URL paths.
/// Document any new endpoint in `docs/API.md` in the same change. Behavior
/// notes below were verified against the live API on 2026-11-19.
library;

import 'dart:convert';

enum HttpMethod { get, post }

/// A request relative to [ApiClient.baseUrl], or an absolute URL for the
/// other Shabakaty services.
class ApiRequest {
  const ApiRequest(
    this.path, {
    this.query = const {},
    this.method = HttpMethod.get,
    this.form,
    this.json,
  });

  final String path;
  final Map<String, Object> query;
  final HttpMethod method;

  /// `application/x-www-form-urlencoded` body for POST requests.
  final Map<String, String>? form;

  /// JSON body for POST requests.
  final Map<String, Object?>? json;

  @override
  String toString() {
    if (query.isEmpty) return '${method.name.toUpperCase()} $path';
    final q = query.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '${method.name.toUpperCase()} $path?$q';
  }
}

/// `videoKind` / `kind` / `type` values. Any other code is treated as movies.
enum VideoKind {
  movies(1, 'movies'),
  series(2, 'series');

  const VideoKind(this.code, this.searchType);

  /// Numeric code used by most endpoints.
  final int code;

  /// String used by `AdvancedSearch?type=`.
  final String searchType;
}

/// `sortParam` (catalog) and `orderby` (videosByCategory…) values.
///
/// Never send any other code: the catalog silently falls back to `desc`, but
/// `videosByCategory…` falls back to a rating order. `AdvancedSearch` ignores
/// sorting entirely. The website also offers `views_asc`, parental-rating
/// sorts (`rating_*`) and IMDb-score sorts (`stars_*`); none is used (no
/// ratings, AGENTS.md).
enum SortOrder {
  /// Most recently uploaded first (`desc`). The server default.
  recentlyAdded('desc'),

  /// Oldest uploads first (`asc`).
  oldestAdded('asc'),

  /// Newest release date (`mDate`) first (`r_desc`). This is *not* "top
  /// rated".
  newestRelease('r_desc'),

  /// Oldest release date first (`r_asc`). Some `mDate`s are junk (year 201),
  /// so the first items can look odd.
  oldestRelease('r_asc'),

  /// Most watched first (`views_desc`).
  mostViewed('views_desc'),

  /// A→Z by English title (`title_asc`). Only `videosByCategory…`: the main
  /// catalog ignores it.
  titleAscending('title_asc', worksOnCatalog: false),

  /// Z→A by English title (`title_desc`). Only `videosByCategory…`.
  titleDescending('title_desc', worksOnCatalog: false);

  const SortOrder(this.code, {this.worksOnCatalog = true});
  final String code;

  /// Whether the main catalog (`video/V/2/…/sortParam/`) honours this sort.
  final bool worksOnCatalog;
}

/// Language of titles in endpoints that take `lang`. Anything else is
/// treated as English.
enum ApiLanguage { ar, en }

abstract final class ApiEndpoints {
  /// Parental level. Always 0: the unrestricted level (zero censorship, see
  /// AGENTS.md). Levels 2 and 3 hide titles.
  static const int level = 0;

  static const String recommendationUrl =
      'https://recommend.shabakaty.com/api/recommendation/recommend';

  // ---- Home and catalog -----------------------------------------------------

  /// Hero banners. Their `imgObjUrl` is a wide image (~2.7:1).
  static ApiRequest banners() => const ApiRequest('banner/level/$level');

  static ApiRequest videoGroups(ApiLanguage lang) =>
      ApiRequest('videoGroups/lang/${lang.name}/level/$level');

  /// Paged items for one video group. [page] is 0-based.
  static ApiRequest videoGroupPage(
    String groupId, {
    int page = 0,
    int itemsPerPage = 12,
  }) => ApiRequest(
    'videoListPagination/groupID/${_seg(groupId)}/level/$level'
    '/itemsPerPage/$itemsPerPage/page/$page',
  );

  static ApiRequest featured({int page = 0, int itemsPerPage = 12}) =>
      ApiRequest(
        'featuredMovies/level/$level/itemsPerPage/$itemsPerPage/page/$page',
      );

  static ApiRequest latestMovies({int page = 0, int itemsPerPage = 24}) =>
      ApiRequest(
        'latestMovies/level/$level/itemsPerPage/$itemsPerPage/page/$page/',
      );

  static ApiRequest latestSeries({int page = 0, int itemsPerPage = 24}) =>
      ApiRequest(
        'latestSeries/level/$level/itemsPerPage/$itemsPerPage/page/$page/',
      );

  /// The 12 newest uploads (movies only). The `offset` segment is really a
  /// count, capped at 12.
  static ApiRequest newlyAdded() =>
      const ApiRequest('newlyVideosItems/level/$level/offset/12/');

  /// Most items the main catalog returns per page.
  static const int maxCatalogPageSize = 99;

  /// Main catalog by kind and sort. [page] is 0-based. The server caps
  /// [itemsPerPage] at [maxCatalogPageSize]. [sort] must be one the catalog
  /// honours ([SortOrder.worksOnCatalog]); title sorts are silently ignored.
  static ApiRequest catalog({
    required VideoKind kind,
    required SortOrder sort,
    int page = 0,
    int itemsPerPage = 30,
  }) => ApiRequest(
    'video/V/2/itemsPerPage/$itemsPerPage/level/$level'
    '/videoKind/${kind.code}/sortParam/${sort.code}/pageNumber/$page',
  );

  // ---- Categories and languages ---------------------------------------------

  static ApiRequest categories() => const ApiRequest('category');

  static ApiRequest mainCategories(ApiLanguage lang) =>
      ApiRequest('mainCategories', query: {'lang': lang.name});

  static ApiRequest subCategories(ApiLanguage lang) =>
      ApiRequest('subCategories', query: {'lang': lang.name});

  /// Categories plus a `langArray` of (category, language, frequency).
  static ApiRequest categoryLanguages() =>
      const ApiRequest('categoryLangFreqVideo');

  /// Items per page for `videosByCategory…`.
  static const int categoryPageSize = 30;

  /// [categoryPageSize] items per page. [offset] is an item offset; the
  /// response's `offset` is the next one (it keeps growing past the end).
  static ApiRequest videosByCategory({
    required String categoryId,
    SortOrder sort = SortOrder.recentlyAdded,
    VideoKind kind = VideoKind.movies,
    int offset = 0,
  }) => ApiRequest(
    'videosByCategory',
    query: {
      'categoryID': categoryId,
      'orderby': sort.code,
      'videoKind': kind.code,
      'offset': offset,
      'level': level,
    },
  );

  static ApiRequest videosByCategoryAndLanguage({
    required String categoryId,
    required String languageId,
    SortOrder sort = SortOrder.recentlyAdded,
    VideoKind kind = VideoKind.movies,
    int offset = 0,
  }) => ApiRequest(
    'videosByCategoryAndLanguage',
    query: {
      'category_id': categoryId,
      'language_id': languageId,
      'orderby': sort.code,
      'videoKind': kind.code,
      'offset': offset,
      'level': level,
    },
  );

  // ---- Search ---------------------------------------------------------------

  /// Title search across movies and series.
  ///
  /// The path has `itemsPerPage` twice: only the second one counts. The
  /// server sometimes returns one item fewer than asked, so a short page is
  /// not the end: stop paging on an empty page.
  static ApiRequest titleSearch(
    String query, {
    int page = 0,
    int itemsPerPage = 30,
  }) => ApiRequest(
    'video/V/2/itemsPerPage/$itemsPerPage'
    '/video_title_search/${Uri.encodeComponent(encodeTitleQuery(query))}'
    '/itemsPerPage/$itemsPerPage/pageNumber/$page/level/$level',
  );

  /// URL-encode (spaces as `%20`), then standard base64. The caller must
  /// percent-encode the result: a raw `=` or `+` in the path makes the server
  /// answer 400 ("the dark knight", "spider-man").
  ///
  /// The server decodes `urldecode(base64decode(segment))`. The website sends
  /// unpadded base64url of the raw text instead, which loses a literal `+`
  /// ("c++" becomes "c  ") and `%xx`; this encoding keeps every character.
  static String encodeTitleQuery(String query) =>
      base64.encode(utf8.encode(Uri.encodeComponent(query.trim())));

  /// Results per `AdvancedSearch` page. Pages are sometimes one short in the
  /// middle of a list, so stop paging on an empty page.
  static const int advancedSearchPageSize = 12;

  /// Earliest year of the `AdvancedSearch` year range.
  static const int firstYear = 1900;

  /// `AdvancedSearch`. Verified behaviour:
  /// - [kind] is required: without `type` (or with an unknown one) the server
  ///   returns movies only.
  /// - [videoTitle] and [staffTitle] are OR-ed (the website sends the same
  ///   text in both).
  /// - [categoryId] is a single ID. A comma list uses only one of them, and an
  ///   unknown ID is ignored (unfiltered results).
  /// - The year range defaults to 1900 through the current year (computed,
  ///   never hardcoded). A reversed range returns nothing, so it is swapped.
  /// - `sort` and `itemsPerPage` are ignored, so they aren't offered.
  static ApiRequest advancedSearch({
    required VideoKind kind,
    String? videoTitle,
    String? staffTitle,
    String? categoryId,
    int? yearFrom,
    int? yearTo,
    int page = 0,
    DateTime? now,
  }) {
    var from = yearFrom ?? firstYear;
    var to = yearTo ?? (now ?? DateTime.now()).year;
    if (from > to) (from, to) = (to, from);
    return ApiRequest(
      'AdvancedSearch',
      query: {
        'level': level,
        if (_has(videoTitle)) 'videoTitle': videoTitle!.trim(),
        if (_has(staffTitle)) 'staffTitle': staffTitle!.trim(),
        'type': kind.searchType,
        if (_has(categoryId)) 'category_id': categoryId!.trim(),
        'year': '$from,$to',
        'page': page < 0 ? 0 : page,
      },
    );
  }

  // ---- Media details and playback ------------------------------------------

  static ApiRequest videoInfo(String id) =>
      ApiRequest('allVideoInfo/id/${_seg(id)}');

  /// Stream qualities for a movie or a single episode.
  ///
  /// A cache in front of the API sometimes serves this response after the
  /// signed URLs inside it have expired. Pass [cacheBuster] (any unique
  /// value, sent as `_`) to bypass that cache and get the server's current,
  /// unexpired URLs. The server reuses a signature until it expires (at most
  /// 7 days), so they may still expire within days or hours.
  static ApiRequest streams(String id, {String? cacheBuster}) =>
      ApiRequest('transcoddedFiles/id/${_seg(id)}', query: {'_': ?cacheBuster});

  static ApiRequest subtitles(String id) =>
      ApiRequest('translationFiles/id/${_seg(id)}');

  /// Every episode of a series, unsorted. Pass the series ID (S1E1's `nb`).
  static ApiRequest seriesEpisodes(String seriesId) =>
      ApiRequest('videoSeason/id/${_seg(seriesId)}');

  /// Season numbers only: `[{season}]`.
  static ApiRequest seriesSeasons(String seriesId) =>
      ApiRequest('videoSeasonNumber/id/${_seg(seriesId)}');

  /// "More like this" from the recommendation service (what the website
  /// uses): same collection first, then shared cast. No login needed.
  static ApiRequest recommendations(String id, {String? title}) => ApiRequest(
    recommendationUrl,
    method: HttpMethod.post,
    json: {
      'MovieId': id,
      if (_has(title)) 'MovieName': title!.trim(),
      'ReProcessIfExpired': true,
    },
  );

  /// Older "similar titles" endpoint (up to 30 items). The website no longer
  /// calls it. [kind] changes the results.
  static ApiRequest related(String id, VideoKind kind) =>
      ApiRequest('relatedVideos/id/${_seg(id)}/kind/${kind.code}/level/$level');

  /// Seek-bar preview sprite sheets (not every title has them).
  static ApiRequest thumbnails(String id) =>
      ApiRequest('video_thumbnails/video_id/${_seg(id)}');

  /// Most IDs `getVideosByIds` accepts; 41 or more answer 400.
  static const int maxIdsPerRequest = 40;

  /// Several items at once. POST only (GET answers 404). Form body
  /// `ids=[id1, id2, …]`; without the brackets the answer is empty. The
  /// response keeps the request order; unknown numeric IDs are skipped, but a
  /// single non-numeric ID makes the whole response empty. Send at most
  /// [maxIdsPerRequest] numeric IDs (more answer 400 "max array 40 item").
  static ApiRequest videosByIds(List<String> ids) => ApiRequest(
    'getVideosByIds',
    method: HttpMethod.post,
    form: {'ids': '[${ids.join(', ')}]'},
  );

  /// A person's titles (all at once, not paged), with a localized role.
  static ApiRequest staff(String staffId, ApiLanguage lang) => ApiRequest(
    'staff/actorID/${_seg(staffId)}/lang/${lang.name}/level/$level',
  );

  static ApiRequest faq() => const ApiRequest('faqQuestion');

  // ---- Service status ---------------------------------------------------------

  /// Shabakaty's public status page (Atlassian Statuspage, no login or
  /// keys). The official Android app uses this host. Ask it only after API
  /// calls fail, to tell "Cinemana is down" from "your connection is down".
  static const String statusUrl =
      'https://6b1m6vnfz2jk.statuspage.io/api/v2/components.json';

  /// `{page, components: [{id, name, status, group, group_id, components}]}`.
  static ApiRequest serviceStatus() => const ApiRequest(statusUrl);

  // ---- helpers ---------------------------------------------------------------

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  /// Encodes one path segment so an odd ID can't change the path.
  static String _seg(String s) => Uri.encodeComponent(s.trim());
}
