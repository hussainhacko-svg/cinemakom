import '../../core/network/api_endpoints.dart';
import 'localized_text.dart';

/// A movie, a series or an episode as it appears in lists.
///
/// A series is represented by its first episode (S1E1): that item has no
/// [rootSeriesId], and every other episode points to it. Use [seriesId] to
/// load episodes.
class MediaItem {
  const MediaItem({
    required this.id,
    this.title = const LocalizedText(),
    this.otherTitle,
    this.description = const LocalizedText(),
    this.posterUrl,
    this.hdPosterUrl,
    this.backdropUrl,
    this.year,
    this.kind,
    this.rootSeriesId,
    this.season,
    this.episode,
    this.categories = const [],
    this.duration,
  });

  final String id;
  final LocalizedText title;

  /// Original-language title (`other_title`), when different.
  final String? otherTitle;
  final LocalizedText description;

  /// For cards and grids: the medium thumbnail first.
  final String? posterUrl;

  /// For the hero banner and details: the full-size image first.
  final String? hdPosterUrl;
  final String? backdropUrl;
  final int? year;
  final VideoKind? kind;

  /// The first episode's ID when this item is a later episode of a series.
  final String? rootSeriesId;
  final int? season;
  final int? episode;
  final List<LocalizedText> categories;
  final Duration? duration;

  bool get isSeries => kind == VideoKind.series;

  /// The ID to load a series' episodes with.
  String get seriesId => rootSeriesId ?? id;

  MediaItem copyWith({VideoKind? kind}) => MediaItem(
    id: id,
    title: title,
    otherTitle: otherTitle,
    description: description,
    posterUrl: posterUrl,
    hdPosterUrl: hdPosterUrl,
    backdropUrl: backdropUrl,
    year: year,
    kind: kind ?? this.kind,
    rootSeriesId: rootSeriesId,
    season: season,
    episode: episode,
    categories: categories,
    duration: duration,
  );

  @override
  String toString() => 'MediaItem($id, ${title.en ?? title.ar}, $kind)';
}
