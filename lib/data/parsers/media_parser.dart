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
      kind: kind,
      rootSeriesId: readId(map['rootSeries']),
      season: season,
      episode: episode,
      categories: parseLocalizedList(
        map['categories'] ?? map['genres'] ?? map['subCategories'],
      ),
      duration: parseSeconds(map['duration']),
      numbering: kind == VideoKind.series && episode != null
          ? EpisodeNumbering.fromFlag(episode, readString(map['episode_flag']))
          : null,
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

/// `banner/level/0`. Banners are special: `imgObjUrl` is a wide cover
/// (~2.7:1) and `imgMediumThumbObjUrl` is a relative path to the portrait
/// poster. A series banner's `link` can name the episode to open
/// (`?lastEpisodeVideoID=`), which becomes [MediaItem.linkedEpisodeId].
List<MediaItem> parseBanners(Object? json) {
  final links = <String, String>{};
  for (final raw in asList(json)) {
    final m = asMap(raw);
    final id = m == null ? null : readId(m['nb']);
    final episode = id == null ? null : bannerEpisodeId(readString(m!['link']));
    if (id != null && episode != null) links[id] = episode;
  }
  return [
    for (final item in parseMediaItems(json))
      item.copyWith(clearHdPoster: true, linkedEpisodeId: links[item.id]),
  ];
}

/// The `lastEpisodeVideoID` of a banner link such as
/// `https://cinemana.shabakaty.cc/video/ar/797119?lastEpisodeVideoID=3157016`
/// (both `.com` and `.cc` hosts occur).
String? bannerEpisodeId(String? link) {
  final uri = link == null ? null : Uri.tryParse(unescapeUrl(link));
  return readId(uri?.queryParameters['lastEpisodeVideoID']);
}

/// `videosByCategory…`: `{info: [items], offset: 30}`. A bare list also works.
/// Paging ends ([OffsetPage.nextOffset] is `null`) when the server returned
/// fewer than [pageSize] raw items.
OffsetPage parseOffsetPage(
  Object? json, {
  VideoKind? fallbackKind,
  int pageSize = 30,
}) {
  final map = asMap(json);
  final raw = map?['info'] ?? json;
  final rawCount = raw is List ? raw.length : 0;
  final next = map == null ? null : parseIntLoose(map['offset']);
  return OffsetPage(
    items: parseMediaItems(raw, fallbackKind: fallbackKind),
    nextOffset: rawCount < pageSize ? null : next,
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

/// Images are on this host. Some fields (banners' `imgMediumThumbObjUrl`)
/// hold a path like `vascin-poster-images/….jpg` instead of a full URL.
const imageHost = 'https://cnth2.shabakaty.com/';

String? _httpUrl(JsonMap map, List<String> keys) {
  for (final key in keys) {
    final url = resolveImageUrl(readString(map[key]));
    if (url != null) return url;
  }
  return null;
}

/// A full image URL, a `vascin-…` path resolved against [imageHost], or
/// `null` for anything else (bare file names, placeholders such as
/// `loadingImages/loading.gif`).
String? resolveImageUrl(String? raw) {
  if (raw == null) return null;
  final s = unescapeUrl(raw);
  if (isPlaceholderImage(s)) return null;
  if (isHttpUrl(s)) return s;
  final path = s.startsWith('/') ? s.substring(1) : s;
  return path.startsWith('vascin-') ? '$imageHost$path' : null;
}

int? _parseYear(JsonMap map) {
  final year = parseIntLoose(map['year']);
  if (year != null && year > 1800) return year;
  final m = RegExp(r'(1[89]\d\d|2\d\d\d)')
      .firstMatch(firstNonBlank(map, ['releaseYear', 'mDate']) ?? '');
  return m == null ? null : int.parse(m[1]!);
}

int? _positive(int? n) => (n == null || n <= 0) ? null : n;
