import '../../data/models/playback_models.dart';

/// The source closest to [preferredHeight] (PLAYER.md §7.1): the exact
/// quality, else the nearest lower one, else the lowest one above it.
/// 2160p counts like any other quality. Sources without a known height are
/// a last resort. `null` only when [sources] is empty.
VideoSource? pickQuality(List<VideoSource> sources, int preferredHeight) {
  VideoSource? lower;
  VideoSource? higher;
  for (final s in sources) {
    final h = s.height;
    if (h == null) continue;
    if (h == preferredHeight) return s;
    if (h < preferredHeight) {
      if (lower == null || h > lower.height!) lower = s;
    } else {
      if (higher == null || h < higher.height!) higher = s;
    }
  }
  return lower ?? higher ?? (sources.isEmpty ? null : sources.first);
}

/// What the quality chip shows: "4K" for 2160p, else "1080p".
String qualityChipLabel(VideoSource source) =>
    source.height == 2160 ? '4K' : source.label;
