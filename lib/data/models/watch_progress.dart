import 'localized_text.dart';
import '../../core/network/api_endpoints.dart' show VideoKind;
import 'media_item.dart';

/// How far a movie or episode was watched: one row of `watch_history`
/// (PLAYER.md §7.6). Carries enough display data for Continue watching,
/// and never a stream URL.
class WatchProgress {
  const WatchProgress({
    required this.videoId,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.title,
    this.seriesId,
    this.season,
    this.episode,
    this.posterUrl,
    this.kind,
    this.finished,
  });

  /// The movie or episode.
  final String videoId;

  /// The series (its first episode's ID); `null` for movies.
  final String? seriesId;
  final int? season;
  final int? episode;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  /// The movie's or series' title, both languages.
  final LocalizedText title;
  final String? posterUrl;
  final VideoKind? kind;

  /// Stored "finished"; when null it follows from the position.
  final bool? finished;

  /// Watched to the end: 95%, or less than 2 minutes left.
  static const finishedShare = 0.95;
  static const finishedLeft = Duration(minutes: 2);

  /// Resume is offered after this much.
  static const resumeAfter = Duration(seconds: 30);

  static bool finishedAt(Duration position, Duration duration) =>
      duration > Duration.zero &&
      (position.inMilliseconds >= duration.inMilliseconds * finishedShare ||
          duration - position < finishedLeft);

  bool get isFinished => finished ?? finishedAt(position, duration);

  bool get isSeries => seriesId != null;

  /// The movie, or the series this episode belongs to.
  String get titleId => seriesId ?? videoId;

  /// Where to start again, or `null` (barely started, or finished).
  Duration? get resumeAt =>
      !isFinished && position >= resumeAfter ? position : null;

  Duration get remaining =>
      duration > position ? duration - position : Duration.zero;

  /// 0–1, for progress bars.
  double get fraction => duration > Duration.zero
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0;

  /// The movie, or the series, as a list item (to open or play it).
  MediaItem get item => MediaItem(
    id: seriesId ?? videoId,
    title: title,
    posterUrl: posterUrl,
    kind: kind ?? (isSeries ? VideoKind.series : VideoKind.movies),
  );

  @override
  String toString() =>
      'WatchProgress($videoId, $position / $duration, finished: $isFinished)';
}
