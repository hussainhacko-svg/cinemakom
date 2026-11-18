// Captures one real response per endpoint into test/fixtures/.
//
//   fvm dart run tool/capture_fixtures.dart            # capture everything
//   fvm dart run tool/capture_fixtures.dart --max 8    # keep at most 8 items per list
//
// Signed-URL credentials (AWSAccessKeyId, Signature) are redacted before
// writing, so fixtures never contain them.
//
// IDs are discovered from earlier responses (latest movie → its cast → staff
// page, and so on), so the script keeps working as the catalog changes.
// Re-run it when the API seems to have changed and diff the fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:cinemakom/core/network/api_client.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/network/api_exception.dart';

const _encoder = JsonEncoder.withIndent('  ');

Future<void> main(List<String> args) async {
  final maxIndex = args.indexOf('--max');
  final maxItems = maxIndex >= 0 && maxIndex + 1 < args.length
      ? int.parse(args[maxIndex + 1])
      : 6;

  final client = ApiClient();
  final outDir = Directory('test/fixtures')..createSync(recursive: true);
  final failures = <String>[];

  /// Saves one response. With [prefer], matching list items are moved to
  /// the front before trimming, so the fixture keeps them.
  Future<Object?> capture(
    String name,
    ApiRequest request, {
    bool Function(Map<Object?, Object?> item)? prefer,
  }) async {
    try {
      final json = await client.fetch(request);
      final ordered = prefer == null || json is! List
          ? json
          : [
              ...json.where((e) => e is Map && prefer(e)),
              ...json.where((e) => e is! Map || !prefer(e)),
            ];
      final trimmed = _redact(_trim(ordered, maxItems));
      File('${outDir.path}/$name.json')
          .writeAsStringSync('${_encoder.convert(trimmed)}\n');
      stdout.writeln('✓ ${name.padRight(34)} ${_describe(json)}');
      return json;
    } on ApiException catch (e) {
      failures.add('$name: $e');
      stdout.writeln('✗ ${name.padRight(34)} $e');
      return null;
    }
  }

  // Home and catalog.
  await capture('banners', ApiEndpoints.banners());
  final groups = await capture(
    'video_groups_ar',
    ApiEndpoints.videoGroups(ApiLanguage.ar),
  );
  await capture('video_groups_en', ApiEndpoints.videoGroups(ApiLanguage.en));
  final groupId = _firstValue(groups, ['groupsID', 'id', 'nb']);
  if (groupId != null) {
    await capture('video_group_page', ApiEndpoints.videoGroupPage(groupId));
  }
  await capture('featured', ApiEndpoints.featured());
  final latestMovies = await capture(
    'latest_movies',
    ApiEndpoints.latestMovies(),
  );
  final latestSeries = await capture(
    'latest_series',
    ApiEndpoints.latestSeries(),
  );
  await capture('newly_added', ApiEndpoints.newlyAdded());
  await capture(
    'catalog_movies_most_viewed',
    ApiEndpoints.catalog(kind: VideoKind.movies, sort: SortOrder.mostViewed),
  );
  await capture(
    'catalog_series_newest',
    ApiEndpoints.catalog(kind: VideoKind.series, sort: SortOrder.recentlyAdded),
  );

  // Categories and languages.
  await capture('categories', ApiEndpoints.categories());
  await capture(
    'main_categories_ar',
    ApiEndpoints.mainCategories(ApiLanguage.ar),
  );
  final subCategories = await capture(
    'sub_categories_en',
    ApiEndpoints.subCategories(ApiLanguage.en),
  );
  final catLang = await capture(
    'category_languages',
    ApiEndpoints.categoryLanguages(),
  );
  // `category` also holds non-genre entries (e.g. "Program") that return
  // nothing, so use a real genre from `subCategories`.
  final categoryId = _firstValue(subCategories, ['nb', 'id']) ?? '87';
  await capture(
    'videos_by_category',
    ApiEndpoints.videosByCategory(categoryId: categoryId),
  );
  final langEntry = _firstLangEntry(catLang);
  if (langEntry != null) {
    await capture(
      'videos_by_category_and_language',
      ApiEndpoints.videosByCategoryAndLanguage(
        categoryId: langEntry.$1,
        languageId: langEntry.$2,
      ),
    );
  }

  // Search.
  await capture('title_search', ApiEndpoints.titleSearch('batman'));
  await capture(
    'advanced_search_series',
    ApiEndpoints.advancedSearch(videoTitle: 'batman', kind: VideoKind.series),
  );

  // Styled "special" (ass) subtitles exist mostly on Japanese anime.
  final anime = await client.fetch(
    ApiEndpoints.videosByCategoryAndLanguage(
      categoryId: '57',
      languageId: '22',
      kind: VideoKind.series,
    ),
  );
  // List items lack `spTranslationFile`; getVideosByIds records have it.
  final animeIds = [
    if (anime is Map && anime['info'] is List)
      for (final i in anime['info'] as List)
        if (i is Map) '${i['nb']}',
  ];
  final full = animeIds.isEmpty
      ? null
      : await client.fetch(
          ApiEndpoints.videosByIds(
            animeIds.take(ApiEndpoints.maxIdsPerRequest).toList(),
          ),
        );
  final special =
      [
        if (full is List)
          for (final i in full)
            if (i is Map && '${i['spTranslationFile'] ?? ''}'.trim().isNotEmpty)
              '${i['nb']}',
      ].firstOrNull ??
      '279230';
  await capture('subtitles_special', ApiEndpoints.subtitles(special));
  await capture('video_info_special', ApiEndpoints.videoInfo(special));

  // Details and playback, for a movie.
  final movieId = _firstValue(latestMovies, ['nb', 'id']);
  if (movieId != null) {
    final info = await capture(
      'video_info_movie',
      ApiEndpoints.videoInfo(movieId),
    );
    await capture('streams_movie', ApiEndpoints.streams(movieId));
    await capture('subtitles_movie', ApiEndpoints.subtitles(movieId));
    await capture(
      'related_movie',
      ApiEndpoints.related(movieId, VideoKind.movies),
    );
    final movieTitle = latestMovies is List && latestMovies.first is Map
        ? '${(latestMovies.first as Map)['en_title']}'
        : null;
    await capture(
      'recommendations',
      ApiEndpoints.recommendations(movieId, title: movieTitle),
    );

    final staffId = info is Map
        ? _firstValue(info['actorsInfo'], ['nb', 'id']) ??
              _firstValue(info['directorsInfo'], ['nb', 'id'])
        : null;
    if (staffId != null) {
      await capture('staff', ApiEndpoints.staff(staffId, ApiLanguage.en));
    }

    // A person whose page image is the loading.gif placeholder.
    final cast = info is Map ? info['actorsInfo'] : null;
    for (final actor in cast is List ? cast.take(12) : const <Object?>[]) {
      final id = actor is Map ? '${actor['nb']}' : null;
      if (id == null) continue;
      final page = await client.fetch(ApiEndpoints.staff(id, ApiLanguage.en));
      if (page is Map && '${page['imgObjUrl']}'.contains('loading.gif')) {
        await capture('staff_no_photo', ApiEndpoints.staff(id, ApiLanguage.en));
        break;
      }
    }

    final secondId = _valueAt(latestMovies, 1, ['nb', 'id']);
    await capture(
      'videos_by_ids',
      ApiEndpoints.videosByIds([movieId, ?secondId]),
    );
  }

  // Seek previews exist mostly for popular titles.
  final mostViewed = await client.fetch(
    ApiEndpoints.catalog(kind: VideoKind.movies, sort: SortOrder.mostViewed),
  );
  final popularId = _firstValue(mostViewed, ['nb']);
  if (popularId != null) {
    await capture('thumbnails', ApiEndpoints.thumbnails(popularId));
  }
  if (movieId != null) {
    await capture('thumbnails_none', ApiEndpoints.thumbnails(movieId));
  }
  // A title whose only sprite sheet is broken (height 0, error file).
  await capture('thumbnails_broken', ApiEndpoints.thumbnails('816721'));

  // Details and playback, for a series. A series is identified by its first
  // episode (rootSeries == 0). Prefer one with several seasons.
  String? seriesId = _firstValue(latestSeries, ['rootSeries', 'nb', 'id']);
  final seriesCatalog = await client.fetch(
    ApiEndpoints.advancedSearch(videoTitle: 'friends', kind: VideoKind.series),
  );
  for (final id in _ids(seriesCatalog).take(5)) {
    final seasons = await client.fetch(ApiEndpoints.seriesSeasons(id));
    if (seasons is List && seasons.length > 1) {
      seriesId = id;
      break;
    }
  }
  if (seriesId != null) {
    await capture('video_info_series', ApiEndpoints.videoInfo(seriesId));
    final episodes = await capture(
      'series_episodes',
      ApiEndpoints.seriesEpisodes(seriesId),
    );
    await capture('series_seasons', ApiEndpoints.seriesSeasons(seriesId));
    // The second episode, so it has a non-zero rootSeries.
    final episodeId =
        _valueAt(episodes, 1, ['nb', 'id']) ?? _firstValue(episodes, ['nb']);
    if (episodeId != null) {
      await capture('video_info_episode', ApiEndpoints.videoInfo(episodeId));
      await capture('streams_episode', ApiEndpoints.streams(episodeId));
      await capture('subtitles_episode', ApiEndpoints.subtitles(episodeId));
    }
  }

  // episode_flag: Lucifer has season finales (1000), One Piece a double
  // episode (0010). Long-running series, so the IDs are stable.
  bool flagged(Map<Object?, Object?> e) => '${e['episode_flag']}' != '0000';
  await capture(
    'series_episodes_finale',
    ApiEndpoints.seriesEpisodes('36835'),
    prefer: flagged,
  );
  await capture(
    'series_episodes_double',
    ApiEndpoints.seriesEpisodes('38834'),
    prefer: flagged,
  );

  await capture('faq', ApiEndpoints.faq());

  stdout.writeln(
    failures.isEmpty
        ? '\nAll endpoints captured into ${outDir.path}/'
        : '\n${failures.length} failed:\n  ${failures.join('\n  ')}',
  );
  exit(failures.isEmpty ? 0 : 1);
}

final _signedParams = RegExp(r'(AWSAccessKeyId|Signature)=[^&"\s]+');

/// Replaces signed-URL credentials with a placeholder, recursively.
Object? _redact(Object? json) => switch (json) {
  String() => json.replaceAllMapped(_signedParams, (m) => '${m[1]}=REDACTED'),
  List() => json.map(_redact).toList(),
  Map() => json.map((k, v) => MapEntry(k, _redact(v))),
  _ => json,
};

/// Series root IDs (or plain IDs) from a list response.
Iterable<String> _ids(Object? json) sync* {
  if (json is! List) return;
  for (final item in json) {
    if (item is! Map) continue;
    final root = item['rootSeries']?.toString();
    final id = (root != null && root != '0' && root.isNotEmpty)
        ? root
        : item['nb']?.toString();
    if (id != null && id.isNotEmpty) yield id;
  }
}

/// Keeps fixtures small: lists are cut to [max] items, recursively.
Object? _trim(Object? json, int max) => switch (json) {
  List() => json.take(max).map((e) => _trim(e, max)).toList(),
  Map() => json.map((k, v) => MapEntry(k, _trim(v, max))),
  _ => json,
};

String _describe(Object? json) => switch (json) {
  null => 'empty body',
  List() => 'list of ${json.length}',
  Map() =>
    'object {${json.keys.take(6).join(', ')}${json.length > 6 ? ', …' : ''}}',
  _ => '${json.runtimeType}: $json',
};

String? _firstValue(Object? json, List<String> keys) => _valueAt(json, 0, keys);

String? _valueAt(Object? json, int index, List<String> keys) {
  var list = json;
  if (list is Map) {
    list = list.values.firstWhere((v) => v is List, orElse: () => null);
  }
  if (list is! List || list.length <= index) return null;
  final item = list[index];
  if (item is! Map) return null;
  for (final key in keys) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null' && value != '0') {
      return value;
    }
  }
  return null;
}

/// (catNb, langNb) of the `langArray` entry with the most movies.
(String, String)? _firstLangEntry(Object? json) {
  (String, String)? best;
  var bestFreq = 0;
  for (final cat in json is List ? json : const <Object?>[]) {
    final langs = cat is Map ? cat['langArray'] : null;
    if (langs is! List) continue;
    for (final lang in langs) {
      if (lang is! Map) continue;
      final freq = int.tryParse('${lang['langFreq']}') ?? 0;
      if (freq > bestFreq && lang['catNb'] != null && lang['langNb'] != null) {
        bestFreq = freq;
        best = ('${lang['catNb']}', '${lang['langNb']}');
      }
    }
  }
  return best;
}
