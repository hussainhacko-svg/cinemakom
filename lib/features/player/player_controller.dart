import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/player/media_kit_engine.dart';
import '../../core/player/player_engine.dart';
import '../../core/storage/preferences.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import '../../data/repositories/media_repository.dart';
import 'player_state.dart';
import 'quality.dart';
import 'subtitles.dart';

/// Makes the engine for each player session. Tests override it with a fake.
final playerEngineFactoryProvider = Provider<PlayerEngine Function()>(
  (ref) => MediaKitEngine.new,
);

/// One playback session: opened by the player screen, closed with it.
final playerControllerProvider = NotifierProvider.autoDispose
    .family<PlayerController, PlayerState, PlaybackRequest>(
      PlayerController.new,
    );

/// The playback session (docs/PLAYER.md §4 and §6). The UI calls the
/// intents (`togglePlay`, `seekBy`, `selectQuality`…); the controller also
/// recovers from stream failures by itself.
class PlayerController extends Notifier<PlayerState> {
  PlayerController(this.request);

  final PlaybackRequest request;

  /// A file "completes" this close to its duration, or it was a stream
  /// failure (a failed reconnect ends the file early, PLAYER.md §6).
  static const endTolerance = Duration(seconds: 5);

  /// Watchdog: no progress for this many seconds while playing, or while
  /// opening, means the stream is stuck.
  static const stallLimitPlaying = 15;
  static const stallLimitLoading = 20;

  /// Waits before each recovery attempt. After the last, playback fails.
  static const recoveryDelays = [
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Playing this far past a recovery resets the attempt count.
  static const recoveredAfter = Duration(seconds: 30);

  late final PlayerEngine engine;

  /// The playhead. Kept out of [state] so only the seek bar and the clock
  /// repaint every tick.
  final position = ValueNotifier<Duration>(Duration.zero);

  /// The end of the buffered range.
  final buffered = ValueNotifier<Duration>(Duration.zero);

  /// The current lines of a plain subtitle track (empty for styled tracks,
  /// which libass draws into the frame).
  final subtitleLines = ValueNotifier<List<String>>(const []);

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _watchdog;

  /// Bumped by every load; async work from an older load is dropped.
  int _session = 0;
  bool _userPaused = false;
  int _stallTicks = 0;
  Duration _lastTickPosition = Duration.zero;
  int _attempt = 0;
  Duration? _recoveredAt;
  bool _recovering = false;

  /// The last position known to play, for reopening after a failure.
  Duration _resumeAt = Duration.zero;

  /// Session choices: they win over Settings for the next episodes.
  int? _chosenHeight;
  SubtitleOption? _chosenSubtitle;

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  @override
  PlayerState build() {
    engine = ref.read(playerEngineFactoryProvider)();
    _subscriptions.addAll([
      engine.position.listen(_onPosition),
      engine.buffered.listen((b) => buffered.value = b),
      engine.duration.listen(_onDuration),
      engine.playing.listen(_onPlaying),
      engine.buffering.listen(_onBuffering),
      engine.completed.listen(_onCompleted),
      engine.errors.listen(_onError),
      engine.subtitleErrors.listen((_) => _onSubtitleError()),
      engine.subtitleText.listen(_onSubtitleText),
    ]);
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    ref.onDispose(_dispose);
    Future.microtask(
      () => _load(
        request.videoId,
        episode: request.episode,
        start: request.start,
      ),
    );
    return PlayerState.initial(request);
  }

  void _dispose() {
    _session++;
    _watchdog?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    unawaited(engine.dispose());
    position.dispose();
    buffered.dispose();
    subtitleLines.dispose();
  }

  bool _isCurrent(int session) => ref.mounted && session == _session;

  // ---------------------------------------------------------------------------
  // Loading

  Future<void> _load(
    String videoId, {
    Episode? episode,
    Duration? start,
  }) async {
    final session = ++_session;
    _recovering = false;
    _attempt = 0;
    _recoveredAt = null;
    _stallTicks = 0;
    _resumeAt = start ?? Duration.zero;
    position.value = _resumeAt;
    buffered.value = Duration.zero;
    subtitleLines.value = const [];
    state = state.copyWith(
      videoId: videoId,
      episode: episode,
      phase: PlayerPhase.loading,
      clearError: true,
      clearDetails: true,
      clearSeekPreview: true,
      subtitleFailed: false,
      duration: Duration.zero,
      playing: false,
    );

    final repo = _repo;
    final streams = repo.streams(videoId);
    final details = _quietly(repo.details(videoId), null);
    final tracks = _quietly(repo.subtitles(videoId), const <SubtitleTrack>[]);
    final preview = _quietly(repo.seekPreview(videoId), null);
    final episodes = request.isSeries && state.episodes.isEmpty
        ? _quietly(repo.episodes(request.item.seriesId), const <Episode>[])
        : Future.value(state.episodes);

    final List<VideoSource> sources;
    try {
      sources = await streams;
    } on Object catch (e) {
      // Stop the other requests' results from landing later.
      if (_isCurrent(session)) _fail(e);
      return;
    }
    final (loadedDetails, loadedTracks, loadedPreview, loadedEpisodes) = (
      await details,
      await tracks,
      await preview,
      await episodes,
    );
    if (!_isCurrent(session)) return;
    if (sources.isEmpty) {
      _fail(PlayerFailure.unavailable);
      return;
    }

    final settings = ref.read(settingsProvider);
    final quality = pickQuality(
      sources,
      _chosenHeight ?? settings.defaultQuality.height,
    )!;
    final options = subtitleOptions(
      loadedTracks.isNotEmpty ? loadedTracks : loadedDetails?.subtitles ?? [],
    );
    final chosen = _chosenSubtitle;
    final subtitle =
        (chosen == null ? null : carryOver(options, chosen)) ??
        pickSubtitle(options, settings.defaultSubtitle);

    state = state.copyWith(
      episode:
          episode ?? loadedEpisodes.where((e) => e.id == videoId).firstOrNull,
      episodes: loadedEpisodes,
      details: loadedDetails,
      sources: sources,
      quality: quality,
      subtitles: options,
      subtitle: subtitle,
      seekPreview: loadedPreview,
    );
    await _openCurrent(session, start: _resumeAt);
  }

  /// Opens [PlayerState.quality] at [start] and sets the subtitle again
  /// (opening a file drops external subtitles).
  Future<void> _openCurrent(int session, {required Duration start}) async {
    final source = state.quality;
    if (source == null) return;
    _stallTicks = 0;
    await engine.open(
      EngineSource(source.url, headers: ApiClient.defaultHeaders),
      start: start,
      play: !_userPaused,
    );
    if (!_isCurrent(session)) return;
    await _applySubtitle();
  }

  Future<T> _quietly<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } on Object {
      return fallback;
    }
  }

  void _fail(Object error) {
    _recovering = false;
    state = state.copyWith(phase: PlayerPhase.failed, error: error);
  }

  // ---------------------------------------------------------------------------
  // Engine events

  void _onPosition(Duration p) {
    position.value = p;
    if (state.phase == PlayerPhase.loading && p > _resumeAt) {
      state = state.copyWith(phase: PlayerPhase.ready);
    }
    if (state.phase == PlayerPhase.ready) {
      _resumeAt = p;
      final recoveredAt = _recoveredAt;
      if (recoveredAt != null && p - recoveredAt >= recoveredAfter) {
        _attempt = 0;
        _recoveredAt = null;
      }
    }
  }

  void _onDuration(Duration d) {
    if (d != state.duration) state = state.copyWith(duration: d);
  }

  void _onPlaying(bool playing) {
    if (playing != state.playing) state = state.copyWith(playing: playing);
  }

  void _onBuffering(bool buffering) {
    if (buffering != state.buffering) {
      state = state.copyWith(buffering: buffering);
    }
    // Opened and buffered, though maybe paused. (A failed open stays
    // buffering, PLAYER.md §13.)
    if (!buffering &&
        state.phase == PlayerPhase.loading &&
        state.quality != null &&
        engine.currentDuration > Duration.zero) {
      state = state.copyWith(phase: PlayerPhase.ready);
    }
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    if (state.phase == PlayerPhase.failed || _recovering) return;
    final duration = engine.currentDuration;
    final at = position.value;
    if (duration > Duration.zero && at >= duration - endTolerance) {
      state = state.copyWith(phase: PlayerPhase.ended, playing: false);
    } else {
      unawaited(_recover());
    }
  }

  void _onError(String _) {
    // Mid-play errors are often blips the native player gets over by itself;
    // the watchdog and the early-completion check catch the real failures.
    if (state.phase == PlayerPhase.loading && state.quality != null) {
      unawaited(_recover());
    }
  }

  void _onSubtitleError() {
    subtitleLines.value = const [];
    state = state.copyWith(
      subtitle: const SubtitleOption.off(),
      subtitleFailed: true,
    );
  }

  void _onSubtitleText(List<String> lines) {
    final shown = state.subtitle.isOff || state.subtitle.isStyled
        ? const <String>[]
        : [
            for (final l in lines)
              if (l.trim().isNotEmpty) l.trim(),
          ];
    if (!listEquals(shown, subtitleLines.value)) subtitleLines.value = shown;
  }

  void _tick() {
    if (_recovering || !ref.mounted) return;
    final phase = state.phase;
    // A file opened paused (a quality switch while paused) never moves, so
    // it isn't watched; its open errors still trigger recovery.
    final expectsProgress =
        !_userPaused &&
        ((phase == PlayerPhase.loading && state.quality != null) ||
            phase == PlayerPhase.ready);
    final p = position.value;
    if (!expectsProgress || p != _lastTickPosition) {
      _stallTicks = 0;
    } else {
      _stallTicks++;
    }
    _lastTickPosition = p;
    final limit = phase == PlayerPhase.loading
        ? stallLimitLoading
        : stallLimitPlaying;
    if (_stallTicks >= limit) {
      _stallTicks = 0;
      unawaited(_recover());
    }
  }

  // ---------------------------------------------------------------------------
  // Recovery (PLAYER.md §6)

  Future<void> _recover() async {
    if (_recovering || !ref.mounted) return;
    if (state.phase == PlayerPhase.failed || state.phase == PlayerPhase.ended) {
      return;
    }
    if (_attempt >= recoveryDelays.length) {
      _fail(PlayerFailure.playback);
      return;
    }
    final session = _session;
    _recovering = true;
    final at = _resumeAt;
    state = state.copyWith(phase: PlayerPhase.recovering);
    await Future<void>.delayed(recoveryDelays[_attempt++]);
    if (!_isCurrent(session)) return;

    // Any open failure may be an expired URL (mpv doesn't say), so always
    // get fresh ones.
    final List<VideoSource> sources;
    try {
      sources = await _repo.streams(state.videoId, fresh: true);
    } on Object catch (e) {
      if (_isCurrent(session)) _fail(e);
      return;
    }
    if (!_isCurrent(session)) return;
    if (sources.isEmpty) {
      _fail(PlayerFailure.unavailable);
      return;
    }
    final quality = pickQuality(
      sources,
      state.quality?.height ?? ref.read(settingsProvider).defaultQuality.height,
    );
    state = state.copyWith(
      sources: sources,
      quality: quality,
      phase: PlayerPhase.loading,
    );
    _recoveredAt = at;
    _recovering = false;
    await _openCurrent(session, start: at);
  }

  // ---------------------------------------------------------------------------
  // Intents

  Future<void> togglePlay() => state.playing ? pause() : play();

  Future<void> play() async {
    _userPaused = false;
    if (state.phase == PlayerPhase.ended) {
      state = state.copyWith(phase: PlayerPhase.ready);
      await seek(Duration.zero);
    }
    await engine.play();
  }

  Future<void> pause() async {
    _userPaused = true;
    await engine.pause();
  }

  Future<void> seek(Duration to) async {
    final duration = state.duration;
    final clamped = to < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && to > duration ? duration : to);
    position.value = clamped;
    _resumeAt = clamped;
    _stallTicks = 0;
    if (state.phase == PlayerPhase.ended && clamped < duration) {
      state = state.copyWith(phase: PlayerPhase.ready);
    }
    await engine.seek(clamped);
  }

  Future<void> seekBy(Duration delta) => seek(position.value + delta);

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await engine.setRate(speed);
  }

  void setFit(VideoFit fit) => state = state.copyWith(fit: fit);

  /// Switches quality at the current position, keeping play/pause, speed and
  /// the subtitle. The choice holds for the next episodes too.
  Future<void> selectQuality(VideoSource source) async {
    if (source.url == state.quality?.url) return;
    _chosenHeight = source.height;
    final at = position.value;
    _resumeAt = at;
    state = state.copyWith(quality: source, phase: PlayerPhase.loading);
    await _openCurrent(_session, start: at);
  }

  Future<void> selectSubtitle(SubtitleOption option) async {
    _chosenSubtitle = option;
    state = state.copyWith(subtitle: option, subtitleFailed: false);
    await _applySubtitle();
  }

  Future<void> _applySubtitle() async {
    final option = state.subtitle;
    subtitleLines.value = const [];
    final track = option.track;
    await engine.setSubtitle(
      track == null
          ? null
          : EngineSubtitle(
              uri: track.url,
              language: track.languageCode,
              title: track.name,
              styled: track.isStyled,
            ),
    );
  }

  /// Positive values show subtitles later. Kept for the session.
  Future<void> setSubtitleDelay(Duration delay) async {
    const limit = Duration(seconds: 60);
    final clamped = delay > limit ? limit : (delay < -limit ? -limit : delay);
    state = state.copyWith(subtitleDelay: clamped);
    await engine.setSubtitleDelay(clamped);
  }

  /// After a failure: load again from where playback stopped.
  Future<void> retry() =>
      _load(state.videoId, episode: state.episode, start: _resumeAt);

  /// Switches to [episode], keeping quality, subtitle choice and speed.
  Future<void> playEpisode(Episode episode) =>
      _load(episode.id, episode: episode);
}
