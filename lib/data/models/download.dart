import '../../core/network/api_endpoints.dart' show VideoKind;
import 'localized_text.dart';
import 'media_item.dart';
import 'playback_models.dart';
import 'playback_request.dart';

/// Where a download is. Live progress comes from the downloader
/// ([DownloadProgress]), not from here.
enum DownloadStatus {
  /// Waiting for a slot (at most two run at a time).
  queued,
  running,
  paused,

  /// Stopped by an error; [Download.problem] says which. "Try again"
  /// resumes it with a fresh URL.
  failed,
  complete;

  /// Still to finish: in the Downloading section.
  bool get isActive => this != complete;
}

/// Why a download failed.
enum DownloadProblem {
  /// No connection, or it dropped for too long.
  network,

  /// Less than the reserve would be left on the disk.
  noSpace,

  /// The server refused or the title has no stream any more.
  unavailable,

  /// The file can't be written (the folder was removed, no permission).
  storage,
  unknown,
}

/// A subtitle file saved beside a download.
class DownloadedSubtitle {
  const DownloadedSubtitle({
    required this.language,
    required this.fileName,
    required this.format,
  });

  /// "ar" or "en".
  final String language;
  final String fileName;

  /// `SubtitleFormat.name`: "srt", "vtt" or "ass" (styled).
  final String format;

  Map<String, Object?> toJson() => {
    'lang': language,
    'file': fileName,
    'format': format,
  };

  static DownloadedSubtitle? fromJson(Object? json) {
    if (json is! Map) return null;
    final lang = json['lang'];
    final file = json['file'];
    final format = json['format'];
    if (lang is! String || file is! String || format is! String) return null;
    return DownloadedSubtitle(language: lang, fileName: file, format: format);
  }
}

/// A downloaded, or downloading, movie or episode: one row of `downloads`.
class Download {
  const Download({
    required this.videoId,
    required this.titleId,
    required this.title,
    required this.quality,
    required this.baseDirectory,
    required this.directory,
    required this.fileName,
    required this.status,
    required this.addedAt,
    this.season,
    this.episode,
    this.episodeLast,
    this.finale = false,
    this.posterUrl,
    this.kind,
    this.year,
    this.duration,
    this.subtitles = const [],
    this.totalBytes,
    this.problem,
    this.completedAt,
  });

  /// The movie or episode, and the downloader's task ID.
  final String videoId;

  /// The movie, or the series.
  final String titleId;
  final LocalizedText title;
  final int? season;

  /// The server's `episodeNummer`.
  final int? episode;
  final int? episodeLast;
  final bool finale;
  final String? posterUrl;
  final VideoKind? kind;
  final int? year;
  final Duration? duration;

  /// e.g. "1080p".
  final String quality;

  /// Where the file is, as background_downloader names it.
  final String baseDirectory;
  final String directory;
  final String fileName;
  final List<DownloadedSubtitle> subtitles;
  final int? totalBytes;
  final DownloadStatus status;
  final DownloadProblem? problem;
  final DateTime addedAt;
  final DateTime? completedAt;

  bool get isEpisode => season != null && episode != null;

  /// The movie or series, as a list item.
  MediaItem get item => MediaItem(
    id: titleId,
    title: title,
    posterUrl: posterUrl,
    kind: kind ?? (isEpisode ? VideoKind.series : VideoKind.movies),
    year: year,
  );

  /// This episode, for the player and the episode labels.
  Episode? get asEpisode => isEpisode
      ? Episode(
          id: videoId,
          season: season!,
          episode: episode!,
          numbering: EpisodeNumbering(
            episode!,
            last: episodeLast,
            isFinale: finale,
          ),
          duration: duration,
        )
      : null;

  /// What to play: the player finds the downloaded file by itself.
  PlaybackRequest get request =>
      PlaybackRequest(item: item, episode: asEpisode);

  Download copyWith({
    DownloadStatus? status,
    DownloadProblem? problem,
    bool clearProblem = false,
    int? totalBytes,
    DateTime? completedAt,
    String? quality,
  }) => Download(
    videoId: videoId,
    titleId: titleId,
    title: title,
    season: season,
    episode: episode,
    episodeLast: episodeLast,
    finale: finale,
    posterUrl: posterUrl,
    kind: kind,
    year: year,
    duration: duration,
    quality: quality ?? this.quality,
    baseDirectory: baseDirectory,
    directory: directory,
    fileName: fileName,
    subtitles: subtitles,
    totalBytes: totalBytes ?? this.totalBytes,
    status: status ?? this.status,
    problem: clearProblem ? null : (problem ?? this.problem),
    addedAt: addedAt,
    completedAt: completedAt ?? this.completedAt,
  );

  @override
  String toString() => 'Download($videoId, $quality, ${status.name})';
}

/// A running download's progress, from the downloader.
class DownloadProgress {
  const DownloadProgress({
    required this.fraction,
    this.expectedBytes,
    this.bytesPerSecond,
    this.timeLeft,
  });

  /// 0–1.
  final double fraction;
  final int? expectedBytes;
  final double? bytesPerSecond;
  final Duration? timeLeft;
}
