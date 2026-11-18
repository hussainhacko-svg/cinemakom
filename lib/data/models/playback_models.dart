import 'localized_text.dart';

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

  /// Vertical resolution in pixels, parsed from [resolution] or [name].
  int? get height {
    for (final s in [resolution, name]) {
      final m = s == null ? null : RegExp(r'(\d{3,4})').firstMatch(s);
      if (m != null) return int.parse(m[1]!);
    }
    return null;
  }

  String get label => resolution ?? name ?? 'Auto';

  @override
  String toString() => 'VideoSource($label)';
}

enum SubtitleFormat { srt, vtt }

/// One subtitle file.
class SubtitleTrack {
  const SubtitleTrack({
    required this.url,
    required this.languageCode,
    this.format = SubtitleFormat.srt,
    this.name,
  });

  final String url;

  /// "ar", "en", or another code the server sent.
  final String languageCode;
  final SubtitleFormat format;

  /// The server's name for the track, e.g. "arabic".
  final String? name;

  @override
  String toString() => 'SubtitleTrack($languageCode, ${format.name})';
}

/// One episode of a series.
class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.episode,
    this.title = const LocalizedText(),
    this.imageUrl,
    this.duration,
  });

  final String id;
  final int season;
  final int episode;

  /// Empty when the server only sent a number. The UI shows "Episode N".
  final LocalizedText title;
  final String? imageUrl;
  final Duration? duration;

  @override
  String toString() => 'Episode($id, S${season}E$episode)';
}

/// One track per language, in first-seen order, preferring [prefer] when a
/// language comes in several formats (the API sends both srt and vtt).
List<SubtitleTrack> oneTrackPerLanguage(
  List<SubtitleTrack> tracks, {
  SubtitleFormat prefer = SubtitleFormat.srt,
}) {
  final byLanguage = <String, SubtitleTrack>{};
  for (final t in tracks) {
    final current = byLanguage[t.languageCode];
    if (current == null || (current.format != prefer && t.format == prefer)) {
      byLanguage[t.languageCode] = t;
    }
  }
  return byLanguage.values.toList();
}

/// One frame of a seek-bar preview: a [width]×[height] cell at ([x], [y])
/// inside the sprite sheet at [url].
typedef SeekFrame = ({String url, int x, int y, int width, int height});

/// Seek-bar previews from `video_thumbnails`: PNG sprite sheets, each a
/// 10×10 grid of 120×68 frames, about one frame every 10 s, in row-major
/// order. The last sheet is shorter.
class SeekPreview {
  const SeekPreview(this.sheetUrls);

  static const int columns = 10;
  static const int framesPerSheet = 100;
  static const int frameWidth = 120;
  static const int frameHeight = 68;
  static const Duration interval = Duration(seconds: 10);

  /// Sheet URLs in order.
  final List<String> sheetUrls;

  /// The frame to show at [position], or `null` past the last sheet.
  SeekFrame? frameAt(Duration position) {
    if (sheetUrls.isEmpty || position.isNegative) return null;
    final index = position.inMilliseconds ~/ interval.inMilliseconds;
    final sheet = index ~/ framesPerSheet;
    if (sheet >= sheetUrls.length) return null;
    final cell = index % framesPerSheet;
    return (
      url: sheetUrls[sheet],
      x: (cell % columns) * frameWidth,
      y: (cell ~/ columns) * frameHeight,
      width: frameWidth,
      height: frameHeight,
    );
  }
}
