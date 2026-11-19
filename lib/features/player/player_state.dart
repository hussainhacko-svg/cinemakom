import '../../data/models/media_details.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import 'subtitles.dart';
import 'up_next.dart';

enum PlayerPhase {
  /// Loading the streams, or opening a file (also after a quality switch).
  loading,

  /// The file is open; [PlayerState.playing] says whether it plays.
  ready,

  /// Getting playback back after the stream failed or stalled.
  recovering,

  /// Gave up; [PlayerState.error] says why. "Try again" calls `retry()`.
  failed,

  /// The video played to its end.
  ended,
}

/// Why playback failed, when it wasn't an API error ([ApiException]).
enum PlayerFailure implements Exception {
  /// The title has no streams.
  unavailable,

  /// The stream kept failing after every recovery attempt.
  playback,
}

/// How the video fills the screen (PLAYER.md §7.4).
enum VideoFit { fit, fill, stretch }

/// Everything the player UI shows, except the position, which changes too
/// often: read it from `PlayerController.position`.
class PlayerState {
  const PlayerState({
    required this.request,
    required this.videoId,
    this.episode,
    this.episodes = const [],
    this.details,
    this.sources = const [],
    this.quality,
    this.subtitles = const [SubtitleOption.off()],
    this.subtitle = const SubtitleOption.off(),
    this.subtitleDelay = Duration.zero,
    this.subtitleFailed = false,
    this.speed = 1,
    this.fit = VideoFit.fit,
    this.phase = PlayerPhase.loading,
    this.error,
    this.playing = false,
    this.buffering = false,
    this.duration = Duration.zero,
    this.seekPreview,
    this.resumedFrom,
    this.upNext = UpNext.none,
    this.intro,
    this.introPinned = false,
    this.aspectRatio,
  });

  factory PlayerState.initial(PlaybackRequest request) => PlayerState(
    request: request,
    videoId: request.videoId,
    episode: request.episode,
  );

  final PlaybackRequest request;

  /// The movie or episode playing now (changes with the episode).
  final String videoId;
  final Episode? episode;

  /// The series' episodes in order. Empty for movies.
  final List<Episode> episodes;
  final MediaDetails? details;
  final List<VideoSource> sources;
  final VideoSource? quality;
  final List<SubtitleOption> subtitles;
  final SubtitleOption subtitle;
  final Duration subtitleDelay;

  /// The chosen subtitle file couldn't be loaded (playback goes on).
  final bool subtitleFailed;
  final double speed;
  final VideoFit fit;
  final PlayerPhase phase;
  final Object? error;
  final bool playing;
  final bool buffering;
  final Duration duration;
  final SeekPreview? seekPreview;

  /// Set when the player resumed a saved position ("Resuming from 14:32 ·
  /// Start over", PLAYER.md §7.6).
  final Duration? resumedFrom;

  /// The "Up next" card and its countdown (PLAYER.md §7.7).
  final UpNext upNext;

  /// The intro range under the playhead, for Skip intro (PLAYER.md §7.5).
  final SkipRange? intro;

  /// Skip intro shows even with the controls hidden: the first seconds in
  /// each range. After that it shows with the controls only.
  final bool introPinned;

  /// The picture's width ÷ height, once known. Seek previews are drawn at
  /// this shape: the server squeezes every frame into a 16:9 cell.
  final double? aspectRatio;

  List<SkipRange> get introRanges => details?.introRanges ?? const [];

  /// The episode after the current one, across seasons. `null` after the
  /// last one, and for movies.
  Episode? get nextEpisode {
    final i = episodes.indexWhere((e) => e.id == videoId);
    return i < 0 || i + 1 >= episodes.length ? null : episodes[i + 1];
  }

  PlayerState copyWith({
    String? videoId,
    Episode? episode,
    List<Episode>? episodes,
    MediaDetails? details,
    bool clearDetails = false,
    List<VideoSource>? sources,
    VideoSource? quality,
    List<SubtitleOption>? subtitles,
    SubtitleOption? subtitle,
    Duration? subtitleDelay,
    bool? subtitleFailed,
    double? speed,
    VideoFit? fit,
    PlayerPhase? phase,
    Object? error,
    bool clearError = false,
    bool? playing,
    bool? buffering,
    Duration? duration,
    SeekPreview? seekPreview,
    bool clearSeekPreview = false,
    Duration? resumedFrom,
    bool clearResumedFrom = false,
    UpNext? upNext,
    SkipRange? intro,
    bool clearIntro = false,
    bool? introPinned,
    double? aspectRatio,
    bool clearAspectRatio = false,
  }) => PlayerState(
    request: request,
    videoId: videoId ?? this.videoId,
    episode: episode ?? this.episode,
    episodes: episodes ?? this.episodes,
    details: clearDetails ? null : (details ?? this.details),
    sources: sources ?? this.sources,
    quality: quality ?? this.quality,
    subtitles: subtitles ?? this.subtitles,
    subtitle: subtitle ?? this.subtitle,
    subtitleDelay: subtitleDelay ?? this.subtitleDelay,
    subtitleFailed: subtitleFailed ?? this.subtitleFailed,
    speed: speed ?? this.speed,
    fit: fit ?? this.fit,
    phase: phase ?? this.phase,
    error: clearError ? null : (error ?? this.error),
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    duration: duration ?? this.duration,
    seekPreview: clearSeekPreview ? null : (seekPreview ?? this.seekPreview),
    resumedFrom: clearResumedFrom ? null : (resumedFrom ?? this.resumedFrom),
    upNext: upNext ?? this.upNext,
    intro: clearIntro ? null : (intro ?? this.intro),
    introPinned: introPinned ?? this.introPinned,
    aspectRatio: clearAspectRatio ? null : (aspectRatio ?? this.aspectRatio),
  );
}
