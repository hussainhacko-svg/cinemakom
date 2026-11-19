import '../../data/models/watch_progress.dart';

/// The "Up next" card (PLAYER.md §7.7).
enum UpNext {
  /// Not shown: not near the end, no next episode, or hidden.
  none,

  /// From the "finished" point: Play now and Hide.
  card,

  /// The last [upNextCountdown] (or after the file ended): a ring fills,
  /// then the next episode starts.
  countdown,

  /// After [autoEpisodesBeforeAsking] automatic episodes with no input:
  /// paused, asking "Still watching?" instead of going on.
  stillWatching,
}

/// How long the countdown runs before the next episode starts.
const upNextCountdown = Duration(seconds: 10);

/// Automatic episodes in a row, with no input, before "Still watching?".
const autoEpisodesBeforeAsking = 3;

/// The card shows from the point the episode counts as watched: 95%, or
/// less than 2 minutes left (the same rule as the history).
bool upNextDue(Duration position, Duration duration) =>
    WatchProgress.finishedAt(position, duration);

/// The countdown runs in the last [upNextCountdown] while playing.
bool countdownDue(Duration position, Duration duration) =>
    duration > Duration.zero && duration - position <= upNextCountdown;
