import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// One native player the fake made.
class FakeVideo {
  FakeVideo(this.id, this.options);

  final int id;
  final VideoCreationOptions options;
  final events = StreamController<VideoEvent>();
  final calls = <String>[];
  Duration position = Duration.zero;
  bool disposed = false;

  DataSource get source => options.dataSource;

  /// What video_player sends once the file is open.
  void initialize({
    Duration duration = const Duration(minutes: 90),
    Size size = const Size(1920, 1080),
  }) => events.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: duration,
      size: size,
    ),
  );

  /// ExoPlayer stopping with [message] (video_player reports it as an
  /// error on the event stream).
  void fail(String message) =>
      events.addError(PlatformException(code: 'VideoError', message: message));

  void send(
    VideoEventType type, {
    List<DurationRange>? buffered,
    bool? playing,
  }) => events.add(
    VideoEvent(eventType: type, buffered: buffered, isPlaying: playing),
  );
}

/// A [VideoPlayerPlatform] that keeps every player it makes, so tests can
/// drive ExoPlayer's events and see what the engine asked for. Each step a
/// test may want to race against can be held with a completer.
class FakeVideoPlatform extends VideoPlayerPlatform {
  final videos = <FakeVideo>[];
  var _nextId = 1;
  bool? mixWithOthers;

  /// Answers `initialized` on its own for each new player.
  bool autoInitialize = true;
  Duration autoDuration = const Duration(minutes: 90);

  /// Held platform steps: dispose of a player, and its volume being set
  /// (the engine's first call once the file is open, before it's shown;
  /// video_player only sends the speed once playback starts).
  Completer<void>? holdDispose;
  Completer<void>? holdVolume;

  FakeVideo get last => videos.last;

  /// Players made and not disposed.
  List<FakeVideo> get alive => [
    for (final v in videos)
      if (!v.disposed) v,
  ];

  FakeVideo _byId(int id) => videos.firstWhere((v) => v.id == id);

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final video = FakeVideo(_nextId++, options);
    videos.add(video);
    if (autoInitialize) {
      scheduleMicrotask(() => video.initialize(duration: autoDuration));
    }
    return video.id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _byId(playerId).events.stream;

  @override
  Future<void> dispose(int playerId) async {
    final hold = holdDispose;
    if (hold != null) await hold.future;
    final v = _byId(playerId);
    v.disposed = true;
    v.calls.add('dispose');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => _byId(playerId).calls.add('play');

  @override
  Future<void> pause(int playerId) async => _byId(playerId).calls.add('pause');

  @override
  Future<void> setVolume(int playerId, double volume) async {
    final hold = holdVolume;
    if (hold != null) await hold.future;
    _byId(playerId).calls.add('volume $volume');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    final v = _byId(playerId)..calls.add('seek ${position.inSeconds}');
    v.position = position;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      _byId(playerId).calls.add('speed $speed');

  @override
  Future<Duration> getPosition(int playerId) async => _byId(playerId).position;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Text('video ${options.playerId}', textDirection: TextDirection.ltr);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async =>
      this.mixWithOthers = mixWithOthers;
}
