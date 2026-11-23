import '../../core/json/json_utils.dart' show signedUrlExpiry;
import 'media_item.dart';

/// One stream quality from `transcoddedFiles`.
class VideoSource {
  const VideoSource({
    required this.url,
    this.name,
    this.resolution,
    this.container,
    this.fileName,
  });

  final String url;

  /// e.g. "mp4-240".
  final String? name;

  /// e.g. "240p".
  final String? resolution;

  /// e.g. "mp4".
  final String? container;
  final String? fileName;

  /// When the signed URL stops working, from its `Expires` parameter.
  /// `null` when the URL isn't signed.
  DateTime? get expiresAt => signedUrlExpiry(url);

  /// Whether the URL is still valid for at least [margin] after [now].
  bool isValidFor(Duration margin, {required DateTime now}) {
    final expires = expiresAt;
    return expires == null || expires.isAfter(now.add(margin));
  }

  /// The quality class in pixels (240, 360, 480, 720, 1080, 2160), parsed
  /// from [resolution] or [name] ("mp4-4k" is 2160). The real frame height
  /// can be smaller for wide films (a "2160p" file can be 3840×1820).
  int? get height {
    for (final s in [resolution, name]) {
      if (s == null) continue;
      // "1080p" first, then the height of "1920x1080", then any number.
      final m =
          RegExp(r'(\d{3,4})p', caseSensitive: false).firstMatch(s) ??
          RegExp(r'\d{3,4}\s*[x×]\s*(\d{3,4})').firstMatch(s) ??
          RegExp(r'(\d{3,4})').firstMatch(s);
      if (m != null) return int.parse(m[1]!);
    }
    return (name?.toLowerCase().contains('4k') ?? false) ? 2160 : null;
  }

  String get label => resolution ?? name ?? 'Auto';

  @override
  String toString() => 'VideoSource($label)';
}

/// `ass` files are the "special" styled Arabic subtitles (mostly anime
/// fansubs): UTF-8 with a BOM, sometimes several MB of karaoke effects.
enum SubtitleFormat { srt, vtt, ass }

/// One subtitle file.
class SubtitleTrack {
  const SubtitleTrack({
    required this.url,
    required this.languageCode,
    this.format = SubtitleFormat.srt,
    this.name,
  });

  final String url;

  /// "ar", "en", or another code the server sent. Styled ([isStyled])
  /// tracks are Arabic.
  final String languageCode;
  final SubtitleFormat format;

  /// The server's name for the track, e.g. "arabic" or "special".
  final String? name;

  /// A styled ASS track (the server's "special" subtitle). Offer it as its
  /// own choice next to the plain track of the same language.
  bool get isStyled => format == SubtitleFormat.ass;

  @override
  String toString() => 'SubtitleTrack($languageCode, ${format.name})';
}

/// One episode of a series.
///
/// Episodes have no titles of their own (the server repeats the series or
/// season name), so the UI labels them from [numbering]: "Episode 7",
/// "Episodes 7 & 8", "Episode 10 (final)".
class Episode {
  Episode({
    required this.id,
    required this.season,
    required this.episode,
    EpisodeNumbering? numbering,
    this.imageUrl,
    this.duration,
  }) : numbering = numbering ?? EpisodeNumbering(episode);

  final String id;
  final int season;

  /// The server's `episodeNummer`, used for ordering.
  final int episode;

  /// What to show, from `episode_flag` (double episodes, finales).
  final EpisodeNumbering numbering;
  final String? imageUrl;
  final Duration? duration;

  @override
  String toString() => 'Episode($id, S${season}E$episode)';
}

/// One plain track per language, in first-seen order, preferring [prefer]
/// when a language comes in several formats (the API sends both srt and
/// vtt). Styled ASS tracks are kept as extra entries, after the plain ones.
List<SubtitleTrack> oneTrackPerLanguage(
  List<SubtitleTrack> tracks, {
  SubtitleFormat prefer = SubtitleFormat.srt,
}) {
  final byLanguage = <String, SubtitleTrack>{};
  final styled = <String, SubtitleTrack>{};
  for (final t in tracks) {
    if (t.isStyled) {
      styled.putIfAbsent(t.languageCode, () => t);
      continue;
    }
    final current = byLanguage[t.languageCode];
    if (current == null || (current.format != prefer && t.format == prefer)) {
      byLanguage[t.languageCode] = t;
    }
  }
  return [...byLanguage.values, ...styled.values];
}

/// One frame of a seek-bar preview: a [width]×[height] cell at ([x], [y])
/// inside the sprite sheet at [url].
typedef SeekFrame = ({String url, int x, int y, int width, int height});

/// One sprite sheet of a [SeekPreview].
typedef SeekSheet = ({String url, int rows});

/// Seek-bar previews from `video_thumbnails`: PNG sprite sheets 1200 px
/// wide, each a grid of 10 columns × up to 10 rows of 120×68 frames, one
/// frame every 10 s, in row-major order.
///
/// The last sheet usually has fewer rows. A sheet can also be broken (the
/// server reports height 0 and the file is an error page): it keeps its
/// place with 0 rows. Some titles have fewer sheets than their duration
/// needs, so previews can stop before the end.
class SeekPreview {
  const SeekPreview(this.sheets);

  static const int columns = 10;
  static const int maxRows = 10;
  static const int framesPerSheet = columns * maxRows;
  static const int frameWidth = 120;
  static const int frameHeight = 68;
  static const Duration interval = Duration(seconds: 10);

  /// Sheets in order. Broken sheets have 0 rows.
  final List<SeekSheet> sheets;

  /// URLs of the usable sheets, in order (for prefetching).
  List<String> get sheetUrls => [
    for (final s in sheets)
      if (s.rows > 0) s.url,
  ];

  /// The frame to show at [position], or `null` when there is none (past the
  /// last frame, or on a broken sheet).
  SeekFrame? frameAt(Duration position) {
    if (sheets.isEmpty || position.isNegative) return null;
    final index = position.inMilliseconds ~/ interval.inMilliseconds;
    final sheetIndex = index ~/ framesPerSheet;
    if (sheetIndex >= sheets.length) return null;
    final sheet = sheets[sheetIndex];
    final cell = index % framesPerSheet;
    final row = cell ~/ columns;
    if (row >= sheet.rows) return null;
    return (
      url: sheet.url,
      x: (cell % columns) * frameWidth,
      y: row * frameHeight,
      width: frameWidth,
      height: frameHeight,
    );
  }
}
