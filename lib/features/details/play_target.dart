import '../../data/models/media_item.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import '../../data/models/watch_progress.dart';

/// What Details' main button does (DESIGN.md §8, PLAYER.md §7.6), without
/// any UI: play from the start, resume where it was left, or play the next
/// episode after a finished one.
class PlayTarget {
  const PlayTarget(
    this.request, {
    this.resume = false,
    this.episode,
    this.left,
  });

  final PlaybackRequest request;

  /// "Resume" rather than "Play".
  final bool resume;

  /// The episode it plays (series), for "S2 E5".
  final Episode? episode;

  /// How much is left, when resuming.
  final Duration? left;
}

/// [item]'s play target from its saved progress: for a series, [watched]
/// (its episodes' progress) and [episodes]; for a movie, [saved].
PlayTarget playTarget(
  MediaItem item, {
  Map<String, WatchProgress> watched = const {},
  List<Episode> episodes = const [],
  WatchProgress? saved,
}) {
  if (!item.isSeries) {
    return saved?.resumeAt != null
        ? PlayTarget(
            PlaybackRequest(item: item),
            resume: true,
            left: saved!.remaining,
          )
        : PlayTarget(PlaybackRequest(item: item));
  }
  final latest = watched.values.fold<WatchProgress?>(
    null,
    (a, b) => a == null || b.updatedAt.isAfter(a.updatedAt) ? b : a,
  );
  if (latest == null) return PlayTarget(PlaybackRequest(item: item));
  final i = episodes.indexWhere((e) => e.id == latest.videoId);
  final current = i < 0 ? null : episodes[i];
  if (!latest.isFinished && current != null) {
    return PlayTarget(
      PlaybackRequest(item: item, episode: current),
      resume: latest.resumeAt != null,
      episode: current,
      left: latest.resumeAt != null ? latest.remaining : null,
    );
  }
  if (latest.isFinished && i >= 0 && i + 1 < episodes.length) {
    final next = episodes[i + 1];
    return PlayTarget(
      PlaybackRequest(item: item, episode: next),
      episode: next,
    );
  }
  return PlayTarget(PlaybackRequest(item: item));
}
