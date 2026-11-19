import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/playback_models.dart';
import '../../data/models/watch_progress.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../details/details_providers.dart';

/// One Continue watching card: where a title was left, and for a series
/// whose newest episode is finished, the episode to watch next.
class ContinueEntry {
  const ContinueEntry(this.progress, {this.upNext});

  final WatchProgress progress;

  /// Set when [progress] is a finished episode.
  final Episode? upNext;
}

/// The episode after [videoId] in a sorted episode list (across seasons),
/// or `null` when it is the last one or unknown.
Episode? episodeAfter(List<Episode> episodes, String videoId) {
  final i = episodes.indexWhere((e) => e.id == videoId);
  return i < 0 || i + 1 >= episodes.length ? null : episodes[i + 1];
}

/// Continue watching for Home and the Library (DESIGN.md §8): unfinished
/// movies and episodes resume; a finished episode offers the next one
/// ("Up next"). A series shows up once its episode list is in, and not at
/// all after its last episode (or when the list can't be loaded).
final continueEntriesProvider =
    Provider.autoDispose<AsyncValue<List<ContinueEntry>>>((ref) {
      final rows = ref.watch(continueWatchingProvider);
      return rows.whenData(
        (list) => [
          for (final p in list)
            if (!p.isFinished)
              ContinueEntry(p)
            else if (p.seriesId case final series?)
              if (ref.watch(episodesProvider(series)).value case final eps?)
                if (episodeAfter(eps, p.videoId) case final next?)
                  ContinueEntry(p, upNext: next),
        ],
      );
    });

/// Refreshes the stored titles and posters of favorites and history from
/// `getVideosByIds`, once per session (PLAN.md §4.2 Library refresh). It
/// runs in the background: a failure keeps what is stored.
final libraryRefreshProvider = FutureProvider<void>((ref) async {
  final library = ref.read(libraryRepositoryProvider);
  try {
    final ids = await library.titleIds();
    if (ids.isEmpty) return;
    final fresh = await ref.read(mediaRepositoryProvider).byIds(ids);
    if (fresh.isNotEmpty) await library.updateTitles(fresh);
  } on Object {
    // Offline or the API failed: the stored metadata stays.
  }
});
