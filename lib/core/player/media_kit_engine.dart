import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../platform/platform_info.dart';
import 'player_engine.dart';
import 'subtitle_fonts.dart';

/// [PlayerEngine] on media_kit (libmpv). The only file that imports
/// media_kit. Options and their reasons: docs/PLAYER.md §5 and §13.
class MediaKitEngine implements PlayerEngine {
  MediaKitEngine({bool? recreatePerFile})
    : recreatePerFile =
          recreatePerFile ?? defaultTargetPlatform == TargetPlatform.android;

  /// Create a new native player for every [open]. On the Android emulator a
  /// second `open()` on the same player never brought the picture back,
  /// while a new player per file worked (PLAYER.md §13). Until a real phone
  /// shows the same player can be reused, Android recreates it.
  final bool recreatePerFile;

  static int get _bufferBytes => (isDesktop ? 192 : 64) * 1024 * 1024;

  static Map<String, String> get _options => {
    'ytdl': 'no',
    'network-timeout': '20',
    'demuxer-readahead-secs': '20',
    'cache-secs': isDesktop ? '60' : '30',
    // The disk cache fails on Android ("Failed to create file cache").
    'cache-on-disk': isDesktop ? 'yes' : 'no',
    // mpv's frame dropping misjudges 4K on phones: it dropped about 1 frame
    // in 40 that wasn't late, a visible stutter. With it off: 0 dropped,
    // 0 late, full frame rate (PLAYER.md §13).
    if (!isDesktop) 'framedrop': 'no',
  };

  Player? _player;
  final _video = ValueNotifier<VideoController?>(null);
  final _subscriptions = <StreamSubscription<Object?>>[];

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _aspectRatio = StreamController<double>.broadcast();
  int? _width;
  int? _height;
  final _buffered = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _subtitleErrors = StreamController<String>.broadcast();
  final _subtitleText = StreamController<List<String>>.broadcast();

  double _rate = 1;
  double _volume = 100;
  double _subtitleScale = 1;
  Duration _subtitleDelay = Duration.zero;
  bool _disposed = false;

  @override
  bool get supportsStyledSubtitles => true;

  /// mpv reports blips it gets over by itself (PLAYER.md §13).
  @override
  bool get errorsStopPlayback => false;

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<double> get aspectRatio => _aspectRatio.stream;
  @override
  Stream<Duration> get buffered => _buffered.stream;
  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<bool> get buffering => _buffering.stream;
  @override
  Stream<bool> get completed => _completed.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<String> get subtitleErrors => _subtitleErrors.stream;
  @override
  Stream<List<String>> get subtitleText => _subtitleText.stream;

  @override
  Duration get currentPosition => _player?.state.position ?? Duration.zero;
  @override
  Duration get currentDuration => _player?.state.duration ?? Duration.zero;

  NativePlayer? get _native => _player?.platform as NativePlayer?;

  Future<Player> _ensurePlayer({required bool fresh}) async {
    final existing = _player;
    if (existing != null && !fresh) return existing;
    if (existing != null) await _release(existing);

    final player = Player(
      configuration: PlayerConfiguration(
        bufferSize: _bufferBytes,
        libass: true,
        libassAndroidFont: isAndroid ? libassFontAsset : null,
        libassAndroidFontName: isAndroid ? libassFontFamily : null,
      ),
    );
    _player = player;
    final native = player.platform! as NativePlayer;
    for (final MapEntry(:key, :value) in _options.entries) {
      await native.setProperty(key, value);
    }
    if (!isAndroid) {
      final fonts = await libassFontsDir();
      if (fonts != null) {
        await native.setProperty('sub-fonts-dir', fonts);
        await native.setProperty('sub-font', libassFontFamily);
      }
    }
    // Settings the user picked survive a new native player.
    await player.setRate(_rate);
    await player.setVolume(_volume);
    await native.setProperty('sub-scale', '$_subtitleScale');
    await native.setProperty('sub-delay', _seconds(_subtitleDelay));

    final s = player.stream;
    _subscriptions.addAll([
      s.position.listen(_position.add),
      s.duration.listen(_duration.add),
      s.buffer.listen(_buffered.add),
      s.playing.listen(_playing.add),
      s.buffering.listen(_buffering.add),
      s.completed.listen(_completed.add),
      s.error.listen(_onError),
      s.subtitle.listen(_subtitleText.add),
      s.width.listen((w) => _onSize(w, _height)),
      s.height.listen((h) => _onSize(_width, h)),
    ]);
    _video.value = VideoController(player);
    return player;
  }

  String? _subtitleUri;

  void _onError(String text) {
    final sub = _subtitleUri;
    // mpv: "Can not open external file <url>." for a subtitle it can't load.
    if (text.contains('external file') || (sub != null && text.contains(sub))) {
      _subtitleErrors.add(text);
    } else {
      _errors.add(text);
    }
  }

  Future<void> _release(Player player) async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    _video.value = null;
    if (identical(_player, player)) _player = null;
    await player.dispose();
  }

  @override
  Future<void> open(
    EngineSource source, {
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    if (_disposed) return;
    final player = await _ensurePlayer(
      fresh: recreatePerFile && _player != null,
    );
    await player.open(
      Media(source.uri, httpHeaders: source.headers, start: start),
      play: play,
    );
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _player?.setRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100).toDouble();
    await _player?.setVolume(_volume);
  }

  @override
  Future<void> setSubtitle(EngineSubtitle? track) async {
    final player = _player;
    if (player == null) return;
    _subtitleUri = track?.uri;
    if (track == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    // Plain tracks: mpv still parses them and sends the text, but Flutter
    // draws it. Styled tracks: libass draws them into the frame.
    await _native?.setProperty('sub-visibility', track.styled ? 'yes' : 'no');
    await player.setSubtitleTrack(
      SubtitleTrack.uri(
        track.uri,
        title: track.title,
        language: track.language,
      ),
    );
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    _subtitleDelay = delay;
    await _native?.setProperty('sub-delay', _seconds(delay));
  }

  @override
  Future<void> setSubtitleScale(double scale) async {
    _subtitleScale = scale;
    await _native?.setProperty('sub-scale', '$scale');
  }

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) =>
      ValueListenableBuilder<VideoController?>(
        valueListenable: _video,
        builder: (context, controller, _) => controller == null
            ? const SizedBox.expand()
            : Video(
                // A new native player gets a new texture.
                key: ObjectKey(controller),
                controller: controller,
                fit: fit,
                fill: const Color(0x00000000),
                controls: NoVideoControls,
                // Plain subtitles are drawn by the player screen.
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: false,
                ),
              ),
      );

  void _onSize(int? width, int? height) {
    _width = width;
    _height = height;
    if (width != null && height != null && width > 0 && height > 0) {
      _aspectRatio.add(width / height);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final player = _player;
    if (player != null) await _release(player);
    _video.dispose();
    for (final c in [
      _position,
      _duration,
      _aspectRatio,
      _buffered,
      _playing,
      _buffering,
      _completed,
      _errors,
      _subtitleErrors,
      _subtitleText,
    ]) {
      await c.close();
    }
  }

  static String _seconds(Duration d) => (d.inMilliseconds / 1000).toString();
}
