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
    this.numbering,
    this.linkedEpisodeId,
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

  /// How to label this episode (from `episode_flag`). `null` for movies.
  final EpisodeNumbering? numbering;

  /// Banners only: the episode the banner opens (`lastEpisodeVideoID` in its
  /// link), usually the newest one.
  final String? linkedEpisodeId;

  bool get isSeries => kind == VideoKind.series;

  /// The ID to load a series' episodes with.
  String get seriesId => rootSeriesId ?? id;

  MediaItem copyWith({
    VideoKind? kind,
    String? hdPosterUrl,
    bool clearHdPoster = false,
    String? linkedEpisodeId,
  }) => MediaItem(
    id: id,
    title: title,
    otherTitle: otherTitle,
    description: description,
    posterUrl: posterUrl,
    hdPosterUrl: clearHdPoster ? null : (hdPosterUrl ?? this.hdPosterUrl),
    backdropUrl: backdropUrl,
    year: year,
    kind: kind ?? this.kind,
    rootSeriesId: rootSeriesId,
    season: season,
    episode: episode,
    categories: categories,
    duration: duration,
    numbering: numbering,
    linkedEpisodeId: linkedEpisodeId ?? this.linkedEpisodeId,
  );

  @override
  String toString() => 'MediaItem($id, ${title.en ?? title.ar}, $kind)';
}

/// The episode number(s) to show, decoded from `episode_flag` the way the
/// website does:
///
/// | flag | shown as |
/// |---|---|
/// | `0000` | N |
/// | `1000` | N, final episode |
/// | `0001` | N − 1 |
/// | `1001` | N − 1, final episode |
/// | `0010` | N & N + 1 (double episode) |
/// | `0020`, `0100` | N & N + 1 & N + 2 (triple episode) |
///
/// Any other flag is shown as N.
class EpisodeNumbering {
  const EpisodeNumbering(this.first, {int? last, this.isFinale = false})
    : last = last ?? first;

  /// [episodeNummer] with the server's [flag].
  factory EpisodeNumbering.fromFlag(int episodeNummer, String? flag) =>
      switch (flag?.trim()) {
        '1000' => EpisodeNumbering(episodeNummer, isFinale: true),
        '0001' => EpisodeNumbering(episodeNummer - 1),
        '1001' => EpisodeNumbering(episodeNummer - 1, isFinale: true),
        '0010' => EpisodeNumbering(episodeNummer, last: episodeNummer + 1),
        '0020' ||
        '0100' => EpisodeNumbering(episodeNummer, last: episodeNummer + 2),
        _ => EpisodeNumbering(episodeNummer),
      };

  final int first;

  /// Equal to [first] unless this file holds several episodes.
  final int last;

  /// The season's final episode.
  final bool isFinale;

  /// Every number this file covers, e.g. `[7, 8]` for a double episode.
  List<int> get numbers => [for (var n = first; n <= last; n++) n];

  @override
  bool operator ==(Object other) =>
      other is EpisodeNumbering &&
      other.first == first &&
      other.last == last &&
      other.isFinale == isFinale;

  @override
  int get hashCode => Object.hash(first, last, isFinale);

  @override
  String toString() =>
      'EpisodeNumbering(${numbers.join(' & ')}${isFinale ? ', final' : ''})';
}
