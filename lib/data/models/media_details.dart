import 'localized_text.dart';
import 'media_item.dart';
import 'playback_models.dart';

enum StaffRole { director, actor, writer, other }

/// A person in a title's cast or crew.
class StaffCredit {
  const StaffCredit({
    required this.id,
    required this.name,
    required this.role,
    this.imageUrl,
  });

  final String id;
  final String name;
  final StaffRole role;
  final String? imageUrl;
}

/// A time range in a video.
class SkipRange {
  const SkipRange(this.start, this.end);

  final Duration start;
  final Duration end;

  Duration get length => end - start;

  bool contains(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is SkipRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SkipRange($start – $end)';
}

/// The full record from `allVideoInfo`.
class MediaDetails {
  const MediaDetails({
    required this.item,
    this.directors = const [],
    this.actors = const [],
    this.writers = const [],
    this.audioLanguages = const [],
    this.trailerUrl,
    this.imdbUrl,
    this.introRanges = const [],
    this.castable = false,
    this.subtitles = const [],
  });

  final MediaItem item;
  final List<StaffCredit> directors;
  final List<StaffCredit> actors;
  final List<StaffCredit> writers;
  final List<LocalizedText> audioLanguages;
  final String? trailerUrl;
  final String? imdbUrl;

  /// From `introSkipping`. Use for the "Skip intro" button. Sometimes two
  /// ranges: a cold open, then the intro.
  final List<SkipRange> introRanges;
  final bool castable;
  final List<SubtitleTrack> subtitles;
}

/// An actor or director page from `staff/actorID/…`.
class StaffPage {
  const StaffPage({
    required this.name,
    this.role,
    this.imageUrl,
    this.items = const [],
  });

  final String name;

  /// As sent by the server, e.g. "Actor".
  final String? role;
  final String? imageUrl;
  final List<MediaItem> items;
}
