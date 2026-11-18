import '../../core/json/json_utils.dart';
import '../../core/network/api_endpoints.dart';
import '../models/catalog_models.dart';
import '../models/localized_text.dart';
import '../models/media_item.dart';

const _idKeys = ['nb', 'id', 'video_id', 'target_id', 'itemId'];
const _enTitleKeys = ['en_title', 'title_en', 'title', 'name', 'videoTitle'];
const _arTitleKeys = ['ar_title', 'title_ar', 'arabicTitle'];
const _cardImageKeys = [
  'imgMediumThumbObjUrl',
  'imgMediumObjUrl',
  'imgObjUrl',
  'imgThumbObjUrl',
  'poster',
  'posterUrl',
  'image',
];
const _hdImageKeys = [
  'imgObjUrl',
  'imgMediumThumbObjUrl',
  'imgMediumObjUrl',
  'imgThumbObjUrl',
  'poster',
  'posterUrl',
  'image',
];
const _backdropKeys = [
  'backgroundImageObjUrl',
  'backdropUrl',
  'coverUrl',
  'imgObjUrl',
  'imgMediumThumbObjUrl',
  'imgMediumObjUrl',
  'imgThumbObjUrl',
];

/// Keys that wrap a list of items in object responses.
const _wrapperKeys = [
  'data',
  'info',
  'videos',
  'items',
  'results',
  'content',
  'list',
  'movies',
  'series',
  'groups',
];

/// One media item, or `null` when [json] has no ID or no title.
MediaItem? parseMediaItem(Object? json, {VideoKind? fallbackKind}) {
  try {
    final map = asMap(json);
    if (map == null) return null;
    final id = readId(firstNonBlank(map, _idKeys));
    if (id == null) return null;

    final other = firstNonBlank(map, ['other_title', 'otherTitle']);
    var title = LocalizedText(
      en: firstNonBlank(map, _enTitleKeys),
      ar: firstNonBlank(map, _arTitleKeys),
    );
    if (title.isEmpty && other != null) title = LocalizedText(en: other);
    if (title.isEmpty) return null;

    final season = _positive(parseIntLoose(map['season']));
    final episode = _positive(
      parseIntLoose(
        firstNonBlank(map, [
          'episodeNummer',
          'episodeNumber',
          'episode_number',
        ]),
      ),
    );
    final kind =
        parseVideoKind(firstNonBlank(map, ['kind', 'videoKind', 'type'])) ??
        fallbackKind ??
        (episode != null ? VideoKind.series : null);

    final card = _httpUrl(map, _cardImageKeys);
    final hd = _httpUrl(map, _hdImageKeys);
    return MediaItem(
      id: id,
      title: title,
      otherTitle: other,
      description: LocalizedText(
        en: firstNonBlank(map, ['en_content', 'description', 'story']),
        ar: firstNonBlank(map, ['ar_content']),
      ),
      posterUrl: card ?? hd,
      hdPosterUrl: hd ?? card,
      backdropUrl: _httpUrl(map, _backdropKeys) ?? hd ?? card,
      year: _parseYear(map),
      rating: _parseRating(map),
      kind: kind,
      rootSeriesId: readId(map['rootSeries']),
      season: season,
      episode: episode,
      categories: parseLocalizedList(
        map['categories'] ?? map['genres'] ?? map['subCategories'],
      ),
      duration: parseSeconds(map['duration']),
    );
  } catch (_) {
    return null;
  }
}

/// Every media item in [json], wherever it is nested: a root list, an object
/// wrapping a list (`info`, `data`, `content`, …), or video groups. Items are
/// de-duplicated by ID, keeping the first.
List<MediaItem> parseMediaItems(Object? json, {VideoKind? fallbackKind}) {
  final results = <MediaItem>[];
  final seen = <String>{};

  void traverse(Object? node, int depth) {
    if (depth > 6) return;
    if (node is List) {
      for (final child in node) {
        traverse(child, depth + 1);
      }
      return;
    }
    final map = asMap(node);
    if (map == null) return;
    final item = parseMediaItem(map, fallbackKind: fallbackKind);
    if (item != null) {
      if (seen.add(item.id)) results.add(item);
      return;
    }
    var foundWrapper = false;
    for (final key in _wrapperKeys) {
      final value = map[key];
      if (value is List || value is Map) {
        foundWrapper = true;
        traverse(value, depth + 1);
      }
    }
    if (!foundWrapper) {
      final firstList = map.values.whereType<List>().firstOrNull;
      if (firstList != null) traverse(firstList, depth + 1);
    }
  }

  try {
    traverse(json, 0);
  } catch (_) {
    // Keep whatever was parsed before the failure.
  }
  return results;
}

/// `videoGroups`: `{groups: [{groupsID, title, content: [items]}]}`.
/// Groups with no items are skipped.
List<VideoGroup> parseVideoGroups(Object? json) {
  final map = asMap(json);
  final raw = map != null
      ? asList(
          map['groups'] ??
              map['data'] ??
              map.values.whereType<List>().firstOrNull,
        )
      : asList(json);
  final groups = <VideoGroup>[];
  for (final entry in raw) {
    try {
      final g = asMap(entry);
      if (g == null) continue;
      final title = firstNonBlank(g, ['title', 'en_title', 'ar_title', 'name']);
      final items = parseMediaItems(
        g['content'] ?? g['videos'] ?? g['data'] ?? g['items'],
      );
      if (title == null || items.isEmpty) continue;
      final id = readId(firstNonBlank(g, ['groupsID', 'id', 'nb', 'groupId']));
      groups.add(
        VideoGroup(
          id: id ?? title,
          title: title,
          items: items,
          hasPagination:
              id != null && (parseBoolLoose(g['hasPagination']) ?? false),
        ),
      );
    } catch (_) {
      continue;
    }
  }
  return groups;
}

/// `videosByCategory…`: `{info: [items], offset: 30}`. A bare list also works.
OffsetPage parseOffsetPage(Object? json, {VideoKind? fallbackKind}) {
  final map = asMap(json);
  return OffsetPage(
    items: parseMediaItems(map?['info'] ?? json, fallbackKind: fallbackKind),
    nextOffset: map == null ? null : parseIntLoose(map['offset']),
  );
}

/// "1"/"movies" → movies, "2"/"series" → series.
VideoKind? parseVideoKind(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case '1' || 'movie' || 'movies' || 'film':
      return VideoKind.movies;
    case '2' || 'series' || 'show' || 'tv':
      return VideoKind.series;
    default:
      return null;
  }
}

/// `[{en_title, ar_title}]`, a single such object, or `["Action", …]`.
List<LocalizedText> parseLocalizedList(Object? json) {
  final out = <LocalizedText>[];
  final list = json is List ? json : (json == null ? const [] : [json]);
  for (final entry in list) {
    final map = asMap(entry);
    final text = map == null
        ? LocalizedText(en: readString(entry))
        : LocalizedText(
            en: firstNonBlank(map, ['en_title', 'title_en', 'title', 'name']),
            ar: firstNonBlank(map, ['ar_title', 'title_ar']),
          );
    if (!text.isEmpty && !out.contains(text)) out.add(text);
  }
  return out;
}

/// A duration given in (fractional) seconds.
Duration? parseSeconds(Object? value) {
  final seconds = parseDoubleLoose(value);
  if (seconds == null || seconds <= 0) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}

String? _httpUrl(JsonMap map, List<String> keys) {
  for (final key in keys) {
    final s = readString(map[key]);
    if (s != null && isHttpUrl(unescapeUrl(s))) return unescapeUrl(s);
  }
  return null;
}

int? _parseYear(JsonMap map) {
  final year = parseIntLoose(map['year']);
  if (year != null && year > 1800) return year;
  final m = RegExp(r'(1[89]\d\d|2\d\d\d)')
      .firstMatch(firstNonBlank(map, ['releaseYear', 'mDate']) ?? '');
  return m == null ? null : int.parse(m[1]!);
}

/// `stars` is the real rating. `rate` is usually "0".
double? _parseRating(JsonMap map) {
  for (final key in ['stars', 'imdbRating', 'rating', 'rate']) {
    final r = parseDoubleLoose(map[key]);
    if (r != null && r > 0) return r;
  }
  return null;
}

int? _positive(int? n) => (n == null || n <= 0) ? null : n;
