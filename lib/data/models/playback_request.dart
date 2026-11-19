import 'media_item.dart';
import 'playback_models.dart';

/// What the player was asked to play: a movie, or an episode of a series.
class PlaybackRequest {
  const PlaybackRequest({required this.item, this.episode, this.start});

  /// The movie, or any item of the series (usually its S1E1 record).
  final MediaItem item;

  /// The episode to play. `null` for a movie, or to play [item] itself.
  final Episode? episode;

  /// Where to start. `null` lets the player decide (resume, from Phase 4 M4).
  final Duration? start;

  /// The ID streams are loaded with: the episode's for a series.
  String get videoId => episode?.id ?? item.id;

  bool get isSeries => episode != null || item.isSeries;

  @override
  bool operator ==(Object other) =>
      other is PlaybackRequest &&
      other.videoId == videoId &&
      other.item.id == item.id &&
      other.start == start;

  @override
  int get hashCode => Object.hash(videoId, item.id, start);

  @override
  String toString() => 'PlaybackRequest($videoId, start: $start)';
}
