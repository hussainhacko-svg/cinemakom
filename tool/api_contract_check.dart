// Live contract check: verifies that the Cinemana API still behaves the way
// docs/API.md says and the parsers expect. Uses the app's own request
// builders, client and parsers.
//
//   fvm dart run tool/api_contract_check.dart
//
// Exits with 1 when any contract is broken. Run it before a release, and
// whenever something looks wrong with data.
import 'dart:convert';
import 'dart:io';

import 'package:cinemakom/core/json/json_utils.dart';
import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';
import 'package:cinemakom/data/parsers/category_parser.dart';
import 'package:cinemakom/data/parsers/details_parser.dart';
import 'package:cinemakom/data/parsers/media_parser.dart';
import 'package:cinemakom/data/models/catalog_models.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/parsers/playback_parser.dart';
import 'package:cinemakom/data/parsers/status_parser.dart';
import 'package:cinemakom/data/models/service_status.dart';

final _api = ApiClient();
var _failures = 0;
var _warnings = 0;

void _ok(bool condition, String name, [String detail = '']) {
  if (condition) {
    stdout.writeln('  ✓ $name');
  } else {
    _failures++;
    stdout.writeln('  ✗ $name${detail.isEmpty ? '' : ': $detail'}');
  }
}

void _warn(bool condition, String name, [String detail = '']) {
  if (condition) return;
  _warnings++;
  stdout.writeln('  ! $name${detail.isEmpty ? '' : ': $detail'}');
}

Future<Object?> _get(ApiRequest r) async {
  try {
    return await _api.fetch(r);
  } on ApiException catch (e) {
    _ok(false, r.path, '$e');
    return null;
  }
}

final _digits = RegExp(r'^\d+$');
final _decimal = RegExp(r'^\d+(\.\d+)?$');
final _year = RegExp(r'^(0|1[89]\d\d|2\d\d\d)$');

List<Map<String, Object?>> _rawItems(Object? json) {
  Object? list = json;
  if (json is Map) {
    list = json['info'] ?? json['items'] ?? json['recommendations'];
    if (json['groups'] is List) {
      list = [
        for (final g in json['groups'] as List)
          ...((g as Map)['content'] as List? ?? const []),
      ];
    }
  }
  return [
    if (list is List)
      for (final e in list)
        if (e is Map) e.cast<String, Object?>(),
  ];
}

/// The record contract shared by every list endpoint, plus parser yield.
void _checkMediaList(String name, Object? json, {bool banners = false}) {
  final raw = _rawItems(json);
  stdout.writeln('$name (${raw.length} items)');
  _ok(raw.isNotEmpty, 'returns items');
  final bad = <String>[];
  for (final m in raw) {
    final id = '${m['nb']}';
    String? problem;
    if (!_digits.hasMatch(id)) {
      problem = 'nb "$id"';
    } else if ('${m['en_title'] ?? ''}'.trim().isEmpty &&
        '${m['ar_title'] ?? ''}'.trim().isEmpty) {
      problem = 'no title';
    } else if (!{'1', '2'}.contains('${m['kind']}')) {
      problem = 'kind "${m['kind']}"';
    } else if (m.containsKey('year') && !_year.hasMatch('${m['year']}')) {
      problem = 'year "${m['year']}"';
    } else if (m.containsKey('season') && !_digits.hasMatch('${m['season']}')) {
      problem = 'season "${m['season']}"';
    } else if (m.containsKey('episodeNummer') &&
        !_digits.hasMatch('${m['episodeNummer']}')) {
      problem = 'episodeNummer "${m['episodeNummer']}"';
    } else if (m.containsKey('rootSeries') &&
        !_digits.hasMatch('${m['rootSeries']}')) {
      problem = 'rootSeries "${m['rootSeries']}"';
    } else if (m['duration'] != null &&
        !_decimal.hasMatch('${m['duration']}')) {
      problem = 'duration "${m['duration']}"';
    } else if (resolveImageUrl('${m['imgMediumThumbObjUrl'] ?? ''}') == null &&
        resolveImageUrl('${m['imgObjUrl'] ?? ''}') == null) {
      problem = 'no usable image';
    }
    if (problem != null) bad.add('$id: $problem');
  }
  _ok(bad.isEmpty, 'every record matches the contract', bad.take(5).join('; '));
  final parsed = banners ? parseBanners(json) : parseMediaItems(json);
  final uniqueIds = {for (final m in raw) '${m['nb']}'}.length;
  _ok(
    parsed.length == uniqueIds,
    'parser keeps every item',
    'raw $uniqueIds unique, parsed ${parsed.length}',
  );
  _warn(
    parsed.every((i) => i.posterUrl != null),
    'every item has a poster',
    '${parsed.where((i) => i.posterUrl == null).length} without',
  );
}

Future<void> main() async {
  final now = DateTime.now();

  // ---- Lists ----------------------------------------------------------------
  final banners = await _get(ApiEndpoints.banners());
  _checkMediaList('banner', banners, banners: true);
  final parsedBanners = parseBanners(banners);
  _ok(
    parsedBanners.every(
      (b) => b.backdropUrl != null && b.backdropUrl != b.posterUrl,
    ),
    'banners have a wide cover distinct from the poster',
  );

  final groups = await _get(ApiEndpoints.videoGroups(ApiLanguage.en));
  _checkMediaList('videoGroups', groups);
  final parsedGroups = parseVideoGroups(groups);
  _ok(
    parsedGroups.isNotEmpty &&
        parsedGroups.every((g) => _digits.hasMatch(g.id)),
    'groups have numeric groupsID',
  );
  if (parsedGroups.isNotEmpty) {
    _checkMediaList(
      'videoListPagination',
      await _get(ApiEndpoints.videoGroupPage(parsedGroups.first.id)),
    );
  }
  _checkMediaList('featuredMovies', await _get(ApiEndpoints.featured()));
  final latestMovies = await _get(ApiEndpoints.latestMovies());
  _checkMediaList('latestMovies', latestMovies);
  _ok(
    parseMediaItems(latestMovies).every((i) => i.kind == VideoKind.movies),
    'latestMovies are all movies',
  );
  final latestSeries = await _get(ApiEndpoints.latestSeries());
  _checkMediaList('latestSeries', latestSeries);
  _ok(
    parseMediaItems(latestSeries).every((i) => i.isSeries),
    'latestSeries are all series',
  );
  _checkMediaList('newlyVideosItems', await _get(ApiEndpoints.newlyAdded()));

  for (final sort in SortOrder.values) {
    for (final kind in VideoKind.values) {
      final json = await _get(ApiEndpoints.catalog(kind: kind, sort: sort));
      _checkMediaList('catalog ${kind.name}/${sort.name}', json);
      _ok(
        parseMediaItems(json).every((i) => i.kind == kind),
        'all items have kind ${kind.name}',
      );
    }
  }

  // Sort semantics.
  final release = parseMediaItems(
    await _get(
      ApiEndpoints.catalog(
        kind: VideoKind.movies,
        sort: SortOrder.newestRelease,
      ),
    ),
  );
  final oldest = parseMediaItems(
    await _get(
      ApiEndpoints.catalog(kind: VideoKind.movies, sort: SortOrder.oldestAdded),
    ),
  );
  stdout.writeln('sort semantics');
  _ok(
    release.isNotEmpty && (release.first.year ?? 0) >= now.year - 1,
    'newestRelease starts with this or last year',
    'first year ${release.firstOrNull?.year}',
  );
  _ok(
    oldest.isNotEmpty &&
        latestMovies is List &&
        oldest.first.id != parseMediaItems(latestMovies).first.id,
    'oldestAdded differs from recentlyAdded',
  );
  final cap = await _get(
    ApiEndpoints.catalog(
      kind: VideoKind.movies,
      sort: SortOrder.recentlyAdded,
      itemsPerPage: 150,
    ),
  );
  _ok(
    cap is List && cap.length <= 99,
    'itemsPerPage is capped at 99',
    'got ${cap is List ? cap.length : cap}',
  );

  // ---- Categories -----------------------------------------------------------
  stdout.writeln('categories');
  final main = parseCategories(
    await _get(ApiEndpoints.mainCategories(ApiLanguage.en)),
    lang: ApiLanguage.en,
  );
  _ok(
    {for (final g in fallbackGenres) g.id}
        .difference({for (final c in main) c.id})
        .isEmpty,
    'fallbackGenres IDs still exist in mainCategories',
  );
  final langs = parseCategoryLanguages(
    await _get(ApiEndpoints.categoryLanguages()),
  );
  _ok(langs.isNotEmpty, 'categoryLangFreqVideo has language pairs');
  final byCat = await _get(ApiEndpoints.videosByCategory(categoryId: '84'));
  _checkMediaList('videosByCategory (Action)', byCat);
  _ok(
    byCat is Map && parseIntLoose(byCat['offset']) == 30,
    'videosByCategory sends next offset 30',
  );
  final pastEnd = parseOffsetPage(
    await _get(
      ApiEndpoints.videosByCategory(categoryId: '84', offset: 99999999),
    ),
  );
  _ok(pastEnd.items.isEmpty && !pastEnd.hasMore, 'paging past the end stops');
  if (langs.isNotEmpty) {
    final best = langs.reduce((a, b) => a.movieCount >= b.movieCount ? a : b);
    _checkMediaList(
      'videosByCategoryAndLanguage',
      await _get(
        ApiEndpoints.videosByCategoryAndLanguage(
          categoryId: best.categoryId,
          languageId: best.languageId,
        ),
      ),
    );
  }

  // ---- Search ---------------------------------------------------------------
  for (final q in ['the dark knight', 'spider-man', 'صراع العروش', "ocean's"]) {
    final json = await _get(ApiEndpoints.titleSearch(q));
    _checkMediaList('titleSearch "$q"', json);
  }
  _checkMediaList(
    'AdvancedSearch staffTitle',
    await _get(
      ApiEndpoints.advancedSearch(
        staffTitle: 'Christopher Nolan',
        kind: VideoKind.movies,
      ),
    ),
  );
  final series = parseMediaItems(
    await _get(
      ApiEndpoints.advancedSearch(
        videoTitle: 'friends',
        kind: VideoKind.series,
      ),
    ),
  );
  _ok(series.every((i) => i.isSeries), 'AdvancedSearch type=series');

  // ---- Details, playback ----------------------------------------------------
  final topMovie = parseMediaItems(
    await _get(
      ApiEndpoints.catalog(kind: VideoKind.movies, sort: SortOrder.mostViewed),
    ),
  ).first;
  stdout.writeln('allVideoInfo (${topMovie.id})');
  final infoJson = await _get(ApiEndpoints.videoInfo(topMovie.id));
  final info = infoJson is Map ? infoJson.cast<String, Object?>() : null;
  for (final key in ['actorsInfo', 'directorsInfo', 'introSkipping']) {
    _ok(info?[key] is List, '$key is a list', '${info?[key].runtimeType}');
  }
  final details = parseMediaDetails(infoJson);
  _ok(details != null && details.actors.isNotEmpty, 'parses with cast');
  _ok(details?.item.duration != null, 'has a duration');

  stdout.writeln('transcoddedFiles');
  final streams = parseVideoSources(
    await _get(ApiEndpoints.streams(topMovie.id)),
  );
  _ok(streams.isNotEmpty, 'has streams');
  _ok(
    streams.every((s) => RegExp(r'^\d+p$').hasMatch(s.resolution ?? '')),
    'resolutions look like "720p"',
  );
  _warn(
    streams.every((s) => s.container == 'mp4'),
    'all streams are mp4',
    '${streams.map((s) => s.container).toSet()}',
  );
  if (streams.isNotEmpty) {
    final status = await _rangeStatus(streams.last.url);
    _ok(status == 206, 'video CDN answers byte ranges', 'HTTP $status');
  }

  stdout.writeln('translationFiles');
  final subs = parseSubtitles(await _get(ApiEndpoints.subtitles(topMovie.id)));
  _ok(subs.isNotEmpty, 'has subtitles');
  if (subs.isNotEmpty) {
    final body = await _download(subs.first.url);
    var utf8Ok = body != null;
    try {
      if (body != null) utf8.decode(body);
    } on FormatException {
      utf8Ok = false;
    }
    _ok(utf8Ok, 'subtitle file is UTF-8');
  }
  final none = parseSubtitles(await _get(ApiEndpoints.subtitles('999999999')));
  _ok(
    none.isEmpty,
    'unknown ID gives no subtitle tracks (placeholder rejected)',
  );

  stdout.writeln('video_thumbnails');
  final preview = parseSeekPreview(
    await _get(ApiEndpoints.thumbnails(topMovie.id)),
  );
  _ok(preview != null && preview.sheetUrls.isNotEmpty, 'has sprite sheets');
  if (preview != null) {
    final png = await _download(preview.sheetUrls.first);
    final width = png != null && png.length > 24
        ? (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19]
        : 0;
    _ok(width == 1200, 'sheet is 1200 px wide (10 × 120)', 'width $width');
  }

  _checkMediaList(
    'recommendations',
    await _get(
      ApiEndpoints.recommendations(topMovie.id, title: topMovie.title.en),
    ),
  );
  _checkMediaList(
    'relatedVideos',
    await _get(ApiEndpoints.related(topMovie.id, VideoKind.movies)),
  );
  if (details != null && details.actors.isNotEmpty) {
    final staff = await _get(
      ApiEndpoints.staff(details.actors.first.id, ApiLanguage.en),
    );
    _checkMediaList('staff', staff);
  }

  // ---- Series ---------------------------------------------------------------
  final friends = series.firstWhere(
    (s) => (s.title.en ?? '').toLowerCase() == 'friends',
    orElse: () => series.first,
  );
  stdout.writeln('series (${friends.seriesId})');
  final episodesJson = await _get(
    ApiEndpoints.seriesEpisodes(friends.seriesId),
  );
  final rawEpisodes = _rawItems(episodesJson);
  _ok(
    rawEpisodes.every(
      (e) =>
          '${e['rootSeries']}' == friends.seriesId ||
          ('${e['rootSeries']}' == '0' && '${e['nb']}' == friends.seriesId),
    ),
    'every episode points to the root (S1E1 has rootSeries 0)',
  );
  final episodes = parseEpisodes(episodesJson);
  _ok(episodes.length == rawEpisodes.length, 'parser keeps every episode');
  final seasons = parseSeasons(
    await _get(ApiEndpoints.seriesSeasons(friends.seriesId)),
  );
  _ok(
    seasons.toSet().containsAll({for (final e in episodes) e.season}),
    'videoSeasonNumber covers every episode season',
  );
  if (episodes.length > 1) {
    _ok(
      parseVideoSources(await _get(ApiEndpoints.streams(episodes[1].id)))
          .isNotEmpty,
      'episodes have their own streams',
    );
  }

  // ---- getVideosByIds limits ------------------------------------------------
  stdout.writeln('getVideosByIds');
  final pool = [
    for (final i in parseMediaItems(
      await _get(
        ApiEndpoints.catalog(
          kind: VideoKind.movies,
          sort: SortOrder.recentlyAdded,
          itemsPerPage: 60,
        ),
      ),
    ))
      i.id,
  ];
  final max = ApiEndpoints.maxIdsPerRequest;
  final atLimit = await _get(ApiEndpoints.videosByIds(pool.take(max).toList()));
  _ok(
    atLimit is List && atLimit.length == max,
    '$max IDs work and keep order',
    '${atLimit is List ? atLimit.length : atLimit}',
  );
  if (atLimit is List && atLimit.isNotEmpty) {
    _ok('${(atLimit.first as Map)['nb']}' == pool.first, 'order is kept');
  }
  try {
    await _api.fetch(ApiEndpoints.videosByIds(pool.take(max + 1).toList()));
    _warn(false, '${max + 1} IDs now work: the limit may have been raised');
  } on ApiException catch (e) {
    _ok(e.statusCode == 400, '${max + 1} IDs are rejected (limit unchanged)');
  }

  await _searchContracts(now);
  await _sortContracts();
  await _pagingContracts(parsedGroups);
  await _mediaContracts(topMovie.id);
  await _metadataContracts(banners, episodesJson, topMovie.id);

  stdout.writeln('status page');
  final health = parseCinemanaHealth(await _get(ApiEndpoints.serviceStatus()));
  _ok(
    health != ServiceHealth.unknown,
    'the status page lists a Cinemana group',
    health.name,
  );

  // ---- Parental level -------------------------------------------------------
  stdout.writeln('parental level');
  final level2 = await _get(const ApiRequest('banner/level/2'));
  _ok(
    banners is List && level2 is List && banners.length > level2.length,
    'level 0 is unrestricted (more banners than level 2)',
    '${banners is List ? banners.length : '?'} vs ${level2 is List ? level2.length : '?'}',
  );

  stdout.writeln(
    '\n${_failures == 0 ? 'All contracts hold' : '$_failures contract(s) broken'}'
    '${_warnings == 0 ? '' : ', $_warnings warning(s)'}.',
  );
  exit(_failures == 0 ? 0 : 1);
}

// ---- Contracts added by the second deep dive (docs/API.md) -----------------

List<Map<String, Object?>> _list(Object? json) => _rawItems(json);

Set<String> _genres(Map<String, Object?> m) => {
  for (final c in m['categories'] is List ? m['categories'] as List : const [])
    if (c is Map) '${c['en_title']}',
};

Future<void> _searchContracts(DateTime now) async {
  stdout.writeln('search semantics');
  final seg = Uri.encodeComponent(ApiEndpoints.encodeTitleQuery('batman'));
  final five = await _get(
    ApiRequest(
      'video/V/2/itemsPerPage/30/video_title_search/$seg'
      '/itemsPerPage/5/pageNumber/0/level/0',
    ),
  );
  _ok(
    five is List && five.length <= 5 && five.isNotEmpty,
    'title search: the second itemsPerPage is the page size',
    '${five is List ? five.length : five}',
  );
  try {
    await _api.fetch(
      const ApiRequest(
        'video/V/2/itemsPerPage/30/video_title_search/c3BpZGVyLW1hbg=='
        '/itemsPerPage/30/pageNumber/0/level/0',
      ),
    );
    _warn(false, 'raw "=" in the search segment now works');
  } on ApiException catch (e) {
    _ok(e.statusCode == 400, 'raw "=" padding answers 400 (so we encode it)');
  }
  final plus = parseMediaItems(await _get(ApiEndpoints.titleSearch('c++')));
  _ok(plus.isNotEmpty, 'title search with "+" works');

  final noType = _list(
    await _get(
      ApiRequest(
        'AdvancedSearch',
        query: {
          'level': 0,
          'videoTitle': 'friends',
          'year': '1900,${now.year}',
        },
      ),
    ),
  );
  _ok(
    noType.isNotEmpty && noType.every((m) => '${m['kind']}' == '1'),
    'AdvancedSearch without type returns movies only (kind is required)',
  );
  final both = parseMediaItems(
    await _get(
      ApiEndpoints.advancedSearch(
        kind: VideoKind.movies,
        videoTitle: 'inception',
        staffTitle: 'Christopher Nolan',
      ),
    ),
  );
  final titles = both.map((i) => (i.title.en ?? '').toLowerCase()).toList();
  _ok(
    titles.any((t) => t.contains('inception')) &&
        titles.any((t) => !t.contains('inception')),
    'AdvancedSearch ORs videoTitle and staffTitle',
    titles.take(4).join(', '),
  );
  final horror = _list(
    await _get(
      ApiEndpoints.advancedSearch(kind: VideoKind.movies, categoryId: '70'),
    ),
  );
  _ok(
    horror.isNotEmpty && horror.every((m) => _genres(m).contains('Horror')),
    'AdvancedSearch category_id filters by one genre',
  );
  final reversed = await _get(
    ApiRequest(
      'AdvancedSearch',
      query: {'level': 0, 'type': 'movies', 'year': '2020,2000'},
    ),
  );
  _ok(
    reversed is List && reversed.isEmpty,
    'a reversed year range returns nothing (so the builder swaps it)',
  );
}

Future<void> _sortContracts() async {
  stdout.writeln('sort codes');
  // The server sorts with its database collation (leading spaces and
  // punctuation first), so allow a few pairs that Dart orders differently.
  bool ordered(List<String> v, {required bool descending}) {
    if (v.length < 2) return true;
    var good = 0;
    for (var i = 1; i < v.length; i++) {
      final c = v[i - 1].compareTo(v[i]);
      if (descending ? c >= 0 : c <= 0) good++;
    }
    return good / (v.length - 1) >= 0.85;
  }

  final catDesc = _list(
    await _get(
      ApiEndpoints.catalog(
        kind: VideoKind.movies,
        sort: SortOrder.recentlyAdded,
      ),
    ),
  );
  for (final (sort, descending) in [
    (SortOrder.newestRelease, true),
    (SortOrder.oldestRelease, false),
  ]) {
    final list = _list(
      await _get(ApiEndpoints.catalog(kind: VideoKind.movies, sort: sort)),
    );
    _ok(
      list.isNotEmpty &&
          ordered([
            for (final m in list) '${m['mDate']}',
          ], descending: descending),
      'catalog ${sort.code} orders by mDate',
    );
  }
  final catTitle = _list(
    await _get(
      ApiRequest(
        'video/V/2/itemsPerPage/30/level/0/videoKind/1'
        '/sortParam/${SortOrder.titleAscending.code}/pageNumber/0',
      ),
    ),
  );
  _ok(
    catTitle.isNotEmpty &&
        catDesc.isNotEmpty &&
        '${catTitle.first['nb']}' == '${catDesc.first['nb']}',
    'catalog ignores title sorts (worksOnCatalog: false)',
  );
  for (final (sort, descending) in [
    (SortOrder.titleAscending, false),
    (SortOrder.titleDescending, true),
  ]) {
    final page = _list(
      await _get(ApiEndpoints.videosByCategory(categoryId: '84', sort: sort)),
    );
    _ok(
      page.isNotEmpty &&
          ordered([
            for (final m in page) '${m['en_title']}'.trim().toLowerCase(),
          ], descending: descending),
      'videosByCategory ${sort.code} sorts by title',
    );
  }
  final unknown = _list(
    await _get(
      const ApiRequest(
        'videosByCategory',
        query: {
          'categoryID': '84',
          'orderby': 'no_such_sort',
          'videoKind': 1,
          'offset': 0,
          'level': 0,
        },
      ),
    ),
  );
  final recent = _list(
    await _get(ApiEndpoints.videosByCategory(categoryId: '84')),
  );
  _warn(
    unknown.isNotEmpty &&
        recent.isNotEmpty &&
        '${unknown.first['nb']}' != '${recent.first['nb']}',
    'videosByCategory falls back to desc for unknown sorts now',
  );
}

Future<void> _pagingContracts(List<VideoGroup> groups) async {
  stdout.writeln('paging');
  if (groups.isEmpty) return;
  // The smallest group (the "4K" collections hold about 10 titles).
  final group = groups.reduce(
    (a, b) => a.items.length <= b.items.length ? a : b,
  );
  var page = 0;
  var total = 0;
  List<Object?> last = const [];
  while (page < 100) {
    final json = await _get(ApiEndpoints.videoGroupPage(group.id, page: page));
    last = json is List ? json : const [];
    total += last.length;
    if (last.length < 12) break;
    page++;
  }
  final after = await _get(
    ApiEndpoints.videoGroupPage(group.id, page: page + 1),
  );
  _ok(
    total > 0 && after is List && after.isEmpty,
    'videoListPagination ends with a short page, then empty pages',
    'group ${group.id}: $total items, ${page + 1} pages',
  );
  final big = await _get(ApiEndpoints.latestMovies(itemsPerPage: 100));
  _ok(
    big is List && big.length == 100,
    'latestMovies accepts 100 items per page',
  );
}

Future<void> _mediaContracts(String movieId) async {
  stdout.writeln('streams freshness');
  final now = DateTime.now().toUtc();
  final fresh = parseVideoSources(
    await _get(
      ApiEndpoints.streams(
        movieId,
        cacheBuster: '${now.millisecondsSinceEpoch}',
      ),
    ),
  );
  _ok(
    fresh.isNotEmpty &&
        fresh.every(
          (s) =>
              s.isValidFor(const Duration(minutes: 1), now: now) &&
              s.expiresAt!.isBefore(now.add(const Duration(days: 8))),
        ),
    'cache-busted transcoddedFiles gives unexpired URLs (≤ 7 days)',
    fresh.map((s) => s.expiresAt).toSet().join(', '),
  );
  final cached = parseVideoSources(await _get(ApiEndpoints.streams(movieId)));
  _warn(
    cached.every((s) => s.isValidFor(const Duration(hours: 6), now: now)),
    'the cached transcoddedFiles answer is stale right now (handled by '
    'MediaRepository.streams)',
  );
  _ok(
    fresh.every((s) => !s.url.contains('.m3u8') && s.container == 'mp4'),
    'streams are progressive MP4 (no HLS)',
  );

  stdout.writeln('special subtitles');
  final special = parseSubtitles(await _get(ApiEndpoints.subtitles('279230')));
  final styled = special.where((t) => t.isStyled).toList();
  _ok(
    styled.length == 1 && styled.single.languageCode == 'ar',
    'translationFiles lists the styled ass track (type "arabic")',
    '$special',
  );
  final info = parseMediaDetails(await _get(ApiEndpoints.videoInfo('279230')));
  _ok(
    info != null && info.subtitles.where((t) => t.isStyled).length == 1,
    'allVideoInfo lists the styled ass track (type "sp")',
  );
  if (styled.isNotEmpty) {
    final body = await _download(styled.single.url);
    final head = body == null ? '' : utf8.decode(body, allowMalformed: true);
    _ok(
      head.replaceFirst('﻿', '').startsWith('[Script Info]'),
      'the ass file is a real ASS script',
    );
  }

  stdout.writeln('seek-preview sheets');
  final thumbs = await _get(ApiEndpoints.thumbnails(movieId));
  final entries = [
    if (thumbs is Map && thumbs['videoThumbnails'] is List)
      for (final e in thumbs['videoThumbnails'] as List)
        if (e is Map) e,
  ];
  _ok(
    entries.isNotEmpty &&
        entries.every((e) {
          final h = parseIntLoose(e['height']) ?? -1;
          return h >= 0 && h <= 680 && h % 68 == 0;
        }),
    'sheet height is 68 px per row, at most 680',
  );
  final preview = parseSeekPreview(thumbs);
  if (preview != null && preview.sheets.isNotEmpty) {
    final lastSheet = preview.sheets.last;
    final png = await _download(lastSheet.url);
    final height = png != null && png.length > 24
        ? (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23]
        : 0;
    _ok(
      height == lastSheet.rows * SeekPreview.frameHeight,
      'the last sheet is as tall as its height field says',
      'png $height, rows ${lastSheet.rows}',
    );
  }
  final broken = await _get(ApiEndpoints.thumbnails('816721'));
  final brokenEntries = broken is Map ? broken['videoThumbnails'] : null;
  if (brokenEntries is List && brokenEntries.isNotEmpty) {
    _ok(
      brokenEntries.every((e) => e is Map && '${e['height']}' == '0') &&
          parseSeekPreview(broken) == null,
      'a sheet with height 0 is broken and dropped',
    );
  } else {
    _warn(false, 'title 816721 has no broken sheet any more');
  }
}

Future<void> _metadataContracts(
  Object? banners,
  Object? episodes,
  String movieId,
) async {
  stdout.writeln('metadata');
  final known = {'0000', '1000', '0001', '1001', '0010', '0020', '0100'};
  final flags = {for (final e in _list(episodes)) '${e['episode_flag']}'};
  _warn(
    known.containsAll(flags),
    'unknown episode_flag values',
    '${flags.difference(known)}',
  );
  final linked = parseBanners(banners).where((b) => b.linkedEpisodeId != null);
  if (linked.isNotEmpty) {
    final b = linked.first;
    final ep = parseMediaDetails(
      await _get(ApiEndpoints.videoInfo(b.linkedEpisodeId!)),
    );
    _ok(
      ep != null && ep.item.seriesId == b.id,
      'a banner lastEpisodeVideoID is an episode of that series',
      '${b.id} → ${b.linkedEpisodeId} (series ${ep?.item.seriesId})',
    );
  }
  final cats = await _get(ApiEndpoints.categories());
  final images = [for (final c in _list(cats)) '${c['imgObjUrl'] ?? ''}']
      .where((u) => u.startsWith('http'));
  _ok(
    images.every((u) => isPlaceholderImage(u) || u.contains('/vascin-')),
    'category images are real files or recognised placeholders',
  );
  final infoJson = await _get(ApiEndpoints.videoInfo(movieId));
  final details = parseMediaDetails(infoJson);
  for (final person in (details?.actors ?? const []).take(3)) {
    final raw = await _get(ApiEndpoints.staff(person.id, ApiLanguage.en));
    final img = raw is Map ? '${raw['imgObjUrl']}' : '';
    _ok(
      isPlaceholderImage(img) || img.contains('/vascin-staff-poster/'),
      'staff image ${person.id} is a photo or a recognised placeholder',
      img,
    );
  }
  final ranges = infoJson is Map ? infoJson['introSkipping'] : null;
  _ok(
    ranges == null ||
        (ranges is List &&
            ranges.every(
              (r) =>
                  r is Map &&
                  (parseDoubleLoose(r['end']) ?? 0) >
                      (parseDoubleLoose(r['start']) ?? 0),
            )),
    'introSkipping ranges are numeric with end > start',
  );
}

Future<int> _rangeStatus(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    ApiClient.defaultHeaders.forEach(request.headers.set);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } catch (_) {
    return -1;
  } finally {
    client.close(force: true);
  }
}

Future<List<int>?> _download(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    ApiClient.defaultHeaders.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != 200) return null;
    return [for (final chunk in await response.toList()) ...chunk];
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
