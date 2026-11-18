/// Every Cinemana endpoint the app uses, as request builders.
///
/// This file (with `api_client.dart`) is the only place that knows URL paths.
/// Document any new endpoint in `docs/API.md` in the same change.
library;

import 'dart:convert';

enum HttpMethod { get, post }

/// A request relative to [ApiClient.baseUrl].
class ApiRequest {
  const ApiRequest(
    this.path, {
    this.query = const {},
    this.method = HttpMethod.get,
    this.form,
  });

  final String path;
  final Map<String, Object> query;
  final HttpMethod method;

  /// `application/x-www-form-urlencoded` body for POST requests.
  final Map<String, String>? form;

  @override
  String toString() {
    if (query.isEmpty) return '${method.name.toUpperCase()} $path';
    final q = query.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '${method.name.toUpperCase()} $path?$q';
  }
}

/// `videoKind` / `kind` / `type` values.
enum VideoKind {
  movies(1, 'movies'),
  series(2, 'series');

  const VideoKind(this.code, this.searchType);

  /// Numeric code used by most endpoints.
  final int code;

  /// String used by `AdvancedSearch?type=`.
  final String searchType;

  VideoKind get other => this == movies ? series : movies;
}

/// `sortParam` / `orderby` values.
enum SortOrder {
  newest('desc'),
  topRated('r_desc');

  const SortOrder(this.code);
  final String code;

  SortOrder get other => this == newest ? topRated : newest;
}

/// Language of titles in endpoints that take `lang`.
enum ApiLanguage { ar, en }

abstract final class ApiEndpoints {
  /// Parental level. Always 0 (public content).
  static const int level = 0;

  // ---- Home and catalog -----------------------------------------------------

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

  /// Returned `[]` when tested. Kept for completeness, not used in the UI.
  static ApiRequest latestVideosItems({int offset = 0}) =>
      ApiRequest('latestVideosItems/level/$level/offset/$offset/');

  static ApiRequest newlyAdded({int offset = 12}) =>
      ApiRequest('newlyVideosItems/level/$level/offset/$offset/');

  /// Main catalog by kind and sort. [page] is 0-based.
  static ApiRequest catalog({
    required VideoKind kind,
    required SortOrder sort,
    int page = 0,
    int itemsPerPage = 30,
  }) => ApiRequest(
    'video/V/2/itemsPerPage/$itemsPerPage/level/$level'
    '/videoKind/${kind.code}/sortParam/${sort.code}/pageNumber/$page',
  );

  /// Returned `[]` for every period when tested. Not used in the UI.
  static ApiRequest popularFilms({String period = 'M', int page = 0}) =>
      ApiRequest('popularFilms/kind/$period/level/$level/page/$page');

  // ---- Categories and languages ---------------------------------------------

  static ApiRequest categories() => const ApiRequest('category');

  static ApiRequest mainCategories(ApiLanguage lang) =>
      ApiRequest('mainCategories', query: {'lang': lang.name});

  static ApiRequest subCategories(ApiLanguage lang) =>
      ApiRequest('subCategories', query: {'lang': lang.name});

  /// Categories plus a `langArray` of (category, language, frequency).
  static ApiRequest categoryLanguages() =>
      const ApiRequest('categoryLangFreqVideo');

  static ApiRequest videosByCategory({
    required String categoryId,
    SortOrder sort = SortOrder.topRated,
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
    SortOrder sort = SortOrder.topRated,
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

  /// Title search. The query is URL-encoded (spaces as `%20`), then base64'd.
  static ApiRequest titleSearch(
    String query, {
    int page = 0,
    int itemsPerPage = 30,
  }) {
    final b64 = encodeTitleQuery(query);
    return ApiRequest(
      'video/V/2/itemsPerPage/$itemsPerPage/video_title_search/$b64'
      '/itemsPerPage/$itemsPerPage/pageNumber/$page/level/$level',
    );
  }

  /// Same encoding as the Kotlin app: `URLEncoder` (with `+` → `%20`), then
  /// standard base64 without line wrapping.
  static String encodeTitleQuery(String query) =>
      base64.encode(utf8.encode(Uri.encodeComponent(query.trim())));

  /// `AdvancedSearch`. Every filter is optional. The year range defaults to
  /// 1900 through the current year (computed, never hardcoded).
  static ApiRequest advancedSearch({
    String? videoTitle,
    String? staffTitle,
    VideoKind? kind,
    String? categoryId,
    int? yearFrom,
    int? yearTo,
    num? minStars,
    String? sort,
    int page = 0,
    DateTime? now,
  }) {
    final toYear = yearTo ?? (now ?? DateTime.now()).year;
    return ApiRequest(
      'AdvancedSearch',
      query: {
        'level': level,
        if (_has(videoTitle)) 'videoTitle': videoTitle!.trim(),
        if (_has(staffTitle)) 'staffTitle': staffTitle!.trim(),
        if (kind != null) 'type': kind.searchType,
        if (_has(categoryId)) 'category_id': categoryId!,
        'year': '${yearFrom ?? 1900},$toYear',
        'star': ?minStars,
        if (_has(sort)) 'sort': sort!,
        'page': page,
      },
    );
  }

  // ---- Media details and playback ------------------------------------------

  static ApiRequest videoInfo(String id) =>
      ApiRequest('allVideoInfo/id/${_seg(id)}');

  /// Stream qualities for a movie or a single episode.
  static ApiRequest streams(String id) =>
      ApiRequest('transcoddedFiles/id/${_seg(id)}');

  static ApiRequest subtitles(String id) =>
      ApiRequest('translationFiles/id/${_seg(id)}');

  /// Every episode of a series.
  static ApiRequest seriesEpisodes(String seriesId) =>
      ApiRequest('videoSeason/id/${_seg(seriesId)}');

  /// Season numbers only: `[{season}]`.
  static ApiRequest seriesSeasons(String seriesId) =>
      ApiRequest('videoSeasonNumber/id/${_seg(seriesId)}');

  static ApiRequest related(String id, VideoKind kind) =>
      ApiRequest('relatedVideos/id/${_seg(id)}/kind/${kind.code}/level/$level');

  static ApiRequest skipDurations(String id) =>
      ApiRequest('skippingDurations/id/${_seg(id)}');

  static ApiRequest thumbnails(String id) =>
      ApiRequest('video_thumbnails/video_id/${_seg(id)}');

  static ApiRequest parentalLevel(String id) =>
      ApiRequest('checkVideoParentalLevel/id/${_seg(id)}');

  /// Several items at once. Body: `ids=[id1, id2, …]`.
  static ApiRequest videosByIds(List<String> ids) => ApiRequest(
    'getVideosByIds',
    method: HttpMethod.post,
    form: {'ids': '[${ids.join(', ')}]'},
  );

  static ApiRequest staff(String staffId, ApiLanguage lang) => ApiRequest(
    'staff/actorID/${_seg(staffId)}/lang/${lang.name}/level/$level',
  );

  static ApiRequest comments(String id, {int limit = 20, int offset = 0}) =>
      ApiRequest('videoComment/id/${_seg(id)}/limit/$limit/offset/$offset');

  /// Returned `[]` when tested. Not used in the UI.
  static ApiRequest collectionIds() => const ApiRequest('collectionsId/');

  static ApiRequest faq() => const ApiRequest('faqQuestion');

  // ---- helpers ---------------------------------------------------------------

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  /// Encodes one path segment so an odd ID can't change the path.
  static String _seg(String s) => Uri.encodeComponent(s.trim());
}
