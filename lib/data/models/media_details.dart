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

  /// Usually a YouTube watch URL; see [trailerYoutubeId].
  final String? trailerUrl;

  /// An IMDb title page, or for anime a MyAnimeList page (about 8% of
  /// titles). Check [imdbUrlIsImdb] before labelling it "IMDb".
  final String? imdbUrl;

  /// From `introSkipping`. Use for the "Skip intro" button. Sometimes two
  /// ranges: a cold open, then the intro.
  final List<SkipRange> introRanges;
  final bool castable;

  /// Every subtitle file, including styled ASS tracks.
  final List<SubtitleTrack> subtitles;

  /// The YouTube video ID of [trailerUrl], or `null` when the trailer isn't
  /// on YouTube.
  String? get trailerYoutubeId => youtubeVideoId(trailerUrl);

  bool get imdbUrlIsImdb =>
      Uri.tryParse(imdbUrl ?? '')?.host.endsWith('imdb.com') ?? false;
}

/// The `v=` ID of a YouTube watch URL, or the path of a youtu.be link.
/// Tolerates the HTML-escaped junk some trailers carry (`&ab;_channel=…`).
String? youtubeVideoId(String? url) {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if (host.endsWith('youtube.com')) {
    id =
        RegExp(r'[?&]v=([\w-]+)').firstMatch(url!)?.group(1) ??
        (uri.pathSegments.length >= 2 &&
                const {'embed', 'shorts', 'v'}.contains(uri.pathSegments[0])
            ? uri.pathSegments[1]
            : null);
  }
  return (id != null && RegExp(r'^[\w-]{6,}$').hasMatch(id)) ? id : null;
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

  /// As sent by the server, localized: "Actor" / "الممثل", "Director",
  /// "Writers". Unreliable: one person can have several staff IDs, each with
  /// a different role.
  final String? role;
  final String? imageUrl;
  final List<MediaItem> items;
}
