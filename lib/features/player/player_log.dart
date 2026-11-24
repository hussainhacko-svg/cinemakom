import 'player_labels.dart' show formatClock;
import 'player_state.dart';
import 'subtitles.dart';

// What the player writes in the flight recorder (lib/core/diagnostics):
// one line per state change, naming only what changed. Shared by the
// phone and TV players through PlayerController.

/// The fields that differ between [before] and [after], as one line
/// ("phase loading → ready · playing false → true"), or `null` when none
/// the log cares about did. The position isn't in the state (it would be a
/// line per frame); the caller adds where playback was.
String? describePlayerChange(PlayerState? before, PlayerState after) {
  if (before == null) return null;
  final parts = <String>[];
  void diff(String name, Object? a, Object? b) {
    if (a != b) parts.add('$name $a → $b');
  }

  diff('video', before.videoId, after.videoId);
  diff('phase', before.phase.name, after.phase.name);
  if (after.error != null && after.error != before.error) {
    parts.add('error ${after.error}');
  }
  diff('playing', before.playing, after.playing);
  diff('buffering', before.buffering, after.buffering);
  diff('quality', before.quality?.label, after.quality?.label);
  if (after.loweredFrom != null && after.loweredFrom != before.loweredFrom) {
    parts.add('lowered from ${after.loweredFrom!.label}');
  }
  diff('subtitle', subtitleName(before.subtitle), subtitleName(after.subtitle));
  if (after.subtitleFailed && !before.subtitleFailed) {
    parts.add('subtitle failed');
  }
  diff('speed', before.speed, after.speed);
  diff('fit', before.fit.name, after.fit.name);
  diff('up next', before.upNext.name, after.upNext.name);
  diff(
    'skip intro',
    before.intro == null ? 'hidden' : 'shown',
    after.intro == null ? 'hidden' : 'shown',
  );
  diff('muted', before.muted, after.muted);
  if (before.duration == Duration.zero && after.duration > Duration.zero) {
    parts.add('length ${formatClock(after.duration)}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "off", "ar", "ar styled".
String subtitleName(SubtitleOption s) =>
    s.isOff ? 'off' : '${s.languageCode ?? '?'}${s.isStyled ? ' styled' : ''}';
