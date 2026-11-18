import '../../core/json/json_utils.dart';
import '../models/media_item.dart';
import '../models/playback_models.dart';
import 'media_parser.dart';

/// `transcoddedFiles`: stream qualities, highest resolution first.
List<VideoSource> parseVideoSources(Object? json) {
  final out = <VideoSource>[];
  final seen = <String>{};
  final list = json is List
      ? json
      : asList(asMap(json)?.values.whereType<List>().firstOrNull);
  for (final entry in list) {
    try {
      final m = asMap(entry);
      if (m == null) continue;
      final url = readUrl(m, ['videoUrl', 'url', 'file', 'src']);
      if (!isHttpUrl(url) || !seen.add(url!)) continue;
      out.add(
        VideoSource(
          url: url,
          name: readString(m['name']),
          resolution: readString(m['resolution']),
          container: readString(m['container']),
          fileName: readString(m['transcoddedFileName']),
        ),
      );
    } catch (_) {
      continue;
    }
  }
  out.sort((a, b) => (b.height ?? -1).compareTo(a.height ?? -1));
  return out;
}

/// The source closest to [preferredHeight]: an exact match, else the best one
/// below it, else the lowest one above it. `null` for an empty list.
VideoSource? pickClosestQuality(
  List<VideoSource> sources,
  int preferredHeight,
) {
  if (sources.isEmpty) return null;
  final withHeight = sources.where((s) => s.height != null).toList();
  if (withHeight.isEmpty) return sources.first;
  final atOrBelow = withHeight.where((s) => s.height! <= preferredHeight);
  if (atOrBelow.isNotEmpty) {
    return atOrBelow.reduce((a, b) => a.height! >= b.height! ? a : b);
  }
  return withHeight.reduce((a, b) => a.height! <= b.height! ? a : b);
}

const _imageExtensions = ['.gif', '.png', '.jpg', '.jpeg', '.webp'];

/// `translationFiles` (and the `translations` inside `allVideoInfo`).
///
/// Reads the `translations` list first, then the `arTranslationFilePath` /
/// `enTranslationFilePath` fields for languages not found yet. Placeholders
/// such as `defaultImages/loading.gif` are rejected.
///
/// Each plain language comes as both `srt` and `vtt`. Some titles add a
/// styled Arabic `ass` track: `{type: "sp", name: "special"}` in
/// `allVideoInfo`, but `{type: "arabic"}` in `translationFiles`. It becomes
/// an `ar` track with [SubtitleFormat.ass].
List<SubtitleTrack> parseSubtitles(Object? json) {
  final tracks = <SubtitleTrack>[];
  final seenPaths = <String>{};

  void add(String? rawUrl, String? language, String? rawFormat, String? name) {
    if (rawUrl == null || language == null) return;
    final url = unescapeUrl(rawUrl);
    if (!isHttpUrl(url)) return;
    final path = Uri.parse(url).path.toLowerCase();
    if (_imageExtensions.any(path.endsWith)) return;
    if (!seenPaths.add(path)) return;
    final format = switch (rawFormat?.toLowerCase().replaceFirst('.', '')) {
      'vtt' => SubtitleFormat.vtt,
      'srt' => SubtitleFormat.srt,
      'ass' || 'ssa' => SubtitleFormat.ass,
      _ =>
        path.endsWith('.vtt')
            ? SubtitleFormat.vtt
            : (path.endsWith('.ass') || path.endsWith('.ssa'))
            ? SubtitleFormat.ass
            : SubtitleFormat.srt,
    };
    tracks.add(
      SubtitleTrack(
        url: url,
        // The styled track is Arabic whatever its `type` says ("sp").
        languageCode: format == SubtitleFormat.ass ? 'ar' : language,
        format: format,
        name: name,
      ),
    );
  }

  try {
    final map = asMap(json);
    final list = json is List
        ? json
        : asList(map?['translations'] ?? map?['files'] ?? map?['data']);
    for (final entry in list) {
      final m = asMap(entry);
      if (m == null) continue;
      final name = firstNonBlank(m, ['name', 'lang', 'language', 'title']);
      add(
        firstNonBlank(m, ['file', 'filePath', 'url', 'subtitleUrl', 'src']),
        _languageCode(readString(m['type'])) ?? _languageCode(name) ?? 'ar',
        firstNonBlank(m, ['extention', 'extension']),
        name,
      );
    }
    if (map != null) {
      final have = {
        for (final t in tracks)
          if (!t.isStyled) t.languageCode,
      };
      for (final (code, keys) in const [
        ('ar', ['arTranslationFilePath', 'arTranslationFile']),
        ('en', ['enTranslationFilePath', 'enTranslationFile']),
      ]) {
        if (!have.contains(code)) {
          add(firstNonBlank(map, keys), code, null, null);
        }
      }
    }
  } catch (_) {
    // Return what was parsed so far.
  }
  return tracks;
}

/// `videoSeason`: every episode, de-duplicated and sorted by season, then
/// episode. A missing season becomes 1, a missing episode its list position.
///
/// Episode titles are never used: the server repeats the series name, or a
/// season name ("Attack on Titan Final Season"), in every episode. The label
/// comes from `episode_flag` ([Episode.numbering]).
List<Episode> parseEpisodes(Object? json) {
  final map = asMap(json);
  final list = json is List
      ? json
      : asList(
          map?['data'] ??
              map?['episodes'] ??
              map?['videos'] ??
              map?.values.whereType<List>().firstOrNull,
        );
  final byId = <String, Episode>{};
  for (var i = 0; i < list.length; i++) {
    try {
      final m = asMap(list[i]);
      if (m == null) continue;
      final id = readId(
        firstNonBlank(m, ['nb', 'id', 'video_id', 'episode_id']),
      );
      if (id == null || byId.containsKey(id)) continue;
      final season = parseIntLoose(
        firstNonBlank(m, ['season', 'seasonNumber', 'season_number']),
      );
      final episode = parseIntLoose(
        firstNonBlank(m, [
          'episodeNummer',
          'episodeNumber',
          'episode_number',
          'episode',
        ]),
      );
      final item = parseMediaItem(m);
      final number = (episode ?? i + 1) < 1 ? i + 1 : (episode ?? i + 1);
      byId[id] = Episode(
        id: id,
        season: (season ?? 1) < 1 ? 1 : (season ?? 1),
        episode: number,
        numbering: EpisodeNumbering.fromFlag(
          number,
          readString(m['episode_flag']),
        ),
        imageUrl: item?.posterUrl,
        duration: parseSeconds(m['duration']),
      );
    } catch (_) {
      continue;
    }
  }
  return byId.values.toList()..sort(
    (a, b) => a.season != b.season
        ? a.season.compareTo(b.season)
        : a.episode.compareTo(b.episode),
  );
}

/// `video_thumbnails`:
/// `{videoThumbnails: [{sprite_url, url, order, height, …}], status}`.
///
/// `height` is the sheet's pixel height (68 per row, 680 for a full sheet);
/// a missing height counts as a full sheet, and `0` marks a broken sheet.
/// `null` when the title has no previews (`status` 204, empty list) or every
/// sheet is broken.
SeekPreview? parseSeekPreview(Object? json) {
  final sheets = <(int, SeekSheet)>[];
  for (final entry in asList(asMap(json)?['videoThumbnails'] ?? json)) {
    final m = asMap(entry);
    if (m == null) continue;
    var url = readUrl(m, ['sprite_url']);
    final relative = readString(m['url']);
    if (!isHttpUrl(url)) url = resolveImageUrl(relative);
    if (!isHttpUrl(url)) continue;
    final height = parseIntLoose(m['height']);
    final rows = height == null
        ? SeekPreview.maxRows
        : (height ~/ SeekPreview.frameHeight).clamp(0, SeekPreview.maxRows);
    sheets.add((
      parseIntLoose(m['order']) ?? sheets.length,
      (url: url!, rows: rows),
    ));
  }
  if (sheets.every((s) => s.$2.rows == 0)) return null;
  sheets.sort((a, b) => a.$1.compareTo(b.$1));
  return SeekPreview([for (final s in sheets) s.$2]);
}

/// `videoSeasonNumber`: `[{season: "1"}, …]` → sorted, unique, ≥ 1.
List<int> parseSeasons(Object? json) {
  final seasons = <int>{};
  for (final entry in asList(json)) {
    final n = parseIntLoose(asMap(entry)?['season'] ?? entry);
    if (n != null && n >= 1) seasons.add(n);
  }
  return seasons.toList()..sort();
}

String? _languageCode(String? raw) {
  final s = raw?.trim().toLowerCase();
  if (s == null || s.isEmpty) return null;
  // "sp" / "special" is the styled Arabic track.
  if (s == 'sp' || s == 'special') return 'ar';
  if (s == 'ar' || s.startsWith('arab') || s == 'عربي') return 'ar';
  if (s == 'en' || s.startsWith('engl')) return 'en';
  return s;
}
