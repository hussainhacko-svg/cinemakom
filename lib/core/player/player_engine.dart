import 'package:flutter/widgets.dart';

/// What to play: a URL (with the shared headers) or, from Phase 6, a local
/// file path.
class EngineSource {
  const EngineSource(this.uri, {this.headers = const {}});

  final String uri;
  final Map<String, String> headers;

  @override
  String toString() => 'EngineSource(${Uri.tryParse(uri)?.path ?? uri})';
}

/// An external subtitle file. [styled] ASS tracks are drawn by libass inside
/// the frame; plain ones are drawn by Flutter from [PlayerEngine.subtitleText]
/// (docs/PLAYER.md §7.2).
class EngineSubtitle {
  const EngineSubtitle({
    required this.uri,
    required this.language,
    this.title,
    this.styled = false,
  });

  final String uri;
  final String language;
  final String? title;
  final bool styled;
}

/// The video player, without any UI. `MediaKitEngine` (mpv) runs on desktop
/// and iOS, `ExoPlayerEngine` on Android; tests use a fake. Only the engine
/// implementations know about their packages.
///
/// The streams are broadcast streams that survive [open], even when the
/// implementation recreates its native player for a new file.
abstract interface class PlayerEngine {
  /// Whether styled (ASS) subtitles can be drawn. When not, the player
  /// doesn't offer them.
  bool get supportsStyledSubtitles;

  /// Whether every error on [errors] means playback stopped for good, so
  /// the file must be reopened. True for ExoPlayer; mpv also reports blips
  /// it gets over by itself.
  bool get errorsStopPlayback;

  Stream<Duration> get position;
  Stream<Duration> get duration;

  /// The picture's width ÷ height, once the file shows it.
  Stream<double> get aspectRatio;

  /// The end of the buffered range.
  Stream<Duration> get buffered;
  Stream<bool> get playing;
  Stream<bool> get buffering;

  /// `true` when the file ended. A failed reconnect also ends the file, so
  /// check the position before treating it as finished (PLAYER.md §6).
  Stream<bool> get completed;

  /// Errors from the native player, as text. They are not reliable enough to
  /// tell an expired URL from a network failure (PLAYER.md §13). Unless
  /// [errorsStopPlayback], some come from blips the player recovers from by
  /// itself, so only act on them while a file is opening.
  Stream<String> get errors;

  /// An external subtitle file couldn't be loaded.
  Stream<String> get subtitleErrors;

  /// The current lines of a plain subtitle track, for the Flutter layer.
  Stream<List<String>> get subtitleText;

  Duration get currentPosition;
  Duration get currentDuration;

  /// Opens [source] at [start]. Playback starts unless [play] is false.
  /// External subtitles are dropped: set them again after opening.
  Future<void> open(
    EngineSource source, {
    Duration start = Duration.zero,
    bool play = true,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 1.0 is normal speed.
  Future<void> setRate(double rate);

  /// 0–100.
  Future<void> setVolume(double volume);

  /// `null` turns subtitles off.
  Future<void> setSubtitle(EngineSubtitle? track);

  /// Positive values show subtitles later.
  Future<void> setSubtitleDelay(Duration delay);

  /// Size of styled (libass) subtitles; 1.0 is the file's own size.
  Future<void> setSubtitleScale(double scale);

  /// The video surface, scaled with [fit]. Rebuilds itself if the native
  /// player is recreated.
  Widget buildVideo({BoxFit fit = BoxFit.contain});

  Future<void> dispose();
}
