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
import 'package:cinemakom/data/parsers/playback_parser.dart';

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
    await _get(ApiEndpoints.advancedSearch(staffTitle: 'Christopher Nolan')),
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
