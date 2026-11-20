import 'dart:math' as math;

import '../../data/models/playback_models.dart';
import '../../data/models/watch_progress.dart';

/// A season longer than this is split into blocks of this many episodes
/// ("1–50", "51–100"), so at most 50 rows sit on screen (DESIGN.md §5).
const episodeBlockSize = 50;

/// Which part of a series' episode list to show, without any UI: the phone's
/// season and range chips and the TV's seasons column share it.
///
/// It opens on the season and block of the anchor: the episode playing
/// ([currentId]), else the one watched last. [season] and [block] are what
/// the user picked (`null` follows the anchor); [initialSeason] is the
/// season of the episode a list showed.
class EpisodeView {
  factory EpisodeView(
    List<Episode> all,
    Map<String, WatchProgress> watched, {
    String? currentId,
    int? initialSeason,
    int? season,
    int? block,
  }) {
    final anchorId =
        currentId ??
        watched.values
            .fold<WatchProgress?>(
              null,
              (a, b) => a == null || b.updatedAt.isAfter(a.updatedAt) ? b : a,
            )
            ?.videoId;
    final anchor = all.where((e) => e.id == anchorId).firstOrNull;
    final seasons = {for (final e in all) e.season}.toList()..sort();
    final shownSeason = seasons.contains(season)
        ? season!
        : seasons.contains(initialSeason)
        ? initialSeason!
        : anchor?.season ?? (seasons.isEmpty ? 0 : seasons.first);
    final inSeason = [
      for (final e in all)
        if (e.season == shownSeason) e,
    ];
    final blocks = math.max(1, (inSeason.length / episodeBlockSize).ceil());
    final anchorAt = anchor == null ? -1 : inSeason.indexOf(anchor);
    final shownBlock =
        (block ?? (anchorAt < 0 ? 0 : anchorAt ~/ episodeBlockSize)).clamp(
          0,
          blocks - 1,
        );
    return EpisodeView._(
      seasons: seasons,
      season: shownSeason,
      inSeason: inSeason,
      blocks: blocks,
      block: shownBlock,
      anchor: anchor,
    );
  }

  const EpisodeView._({
    required this.seasons,
    required this.season,
    required this.inSeason,
    required this.blocks,
    required this.block,
    required this.anchor,
  });

  final List<int> seasons;

  /// The season shown, and all its episodes.
  final int season;
  final List<Episode> inSeason;

  /// How many blocks the season has (1 when it's short), and the one shown.
  final int blocks;
  final int block;

  /// The episode the list opens on, if any.
  final Episode? anchor;

  /// The episodes on screen: the shown block of the season.
  List<Episode> get shown =>
      inSeason.skip(block * episodeBlockSize).take(episodeBlockSize).toList();

  /// The block [b] of the season as its first and last episode numbers.
  (int, int) range(int b) {
    final first = inSeason[b * episodeBlockSize].numbering.first;
    final last =
        inSeason[math.min((b + 1) * episodeBlockSize, inSeason.length) - 1]
            .numbering
            .last;
    return (first, last);
  }

  /// The block of [season] that [anchor] is in (0 when it's elsewhere).
  int anchorBlockOf(int season, List<Episode> all) {
    final a = anchor;
    if (a == null || a.season != season) return 0;
    final list = [
      for (final e in all)
        if (e.season == season) e,
    ];
    return list.indexOf(a) ~/ episodeBlockSize;
  }
}
