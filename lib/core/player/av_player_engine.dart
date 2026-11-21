import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'player_engine.dart';

/// [PlayerEngine] on Apple TV's native AVPlayer (through `video_player` +
/// `video_player_tvos`). Kept separate from `ExoPlayerEngine` so Android
/// behavior stays untouched.
///
/// AVPlayer hardware-decodes 4K H.264/HEVC directly into a Metal texture with
/// no CPU copyback. Plain SRT/VTT subtitles are downloaded with [loadText]
/// (carrying Cinemana's shared headers), parsed in Dart, and drawn by the
/// Flutter `SubtitleLayer` (with Arabic RTL and sync delay). Styled ASS tracks
/// require libass and are not offered ([supportsStyledSubtitles] is `false`).
class AvPlayerEngine implements PlayerEngine {
  AvPlayerEngine({required this.loadText});

  /// Downloads a subtitle file (`ApiClient.fetchText`).
  final Future<String> Function(String url) loadText;

  final _controller = ValueNotifier<VideoPlayerController?>(null);

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _aspectRatio = StreamController<double>.broadcast();
  final _buffered = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _subtitleErrors = StreamController<String>.broadcast();
  final _subtitleText = StreamController<List<String>>.broadcast();

  double _rate = 1;
  double _volume = 100;
  Duration _subtitleDelay = Duration.zero;
  List<Caption> _captions = const [];
  List<String> _shownLines = const [];

  VideoPlayerValue? _last;
  String? _lastError;

  int _openId = 0;
  int _subtitleId = 0;
  bool _disposed = false;

  @override
  bool get supportsStyledSubtitles => false;

  /// AVPlayerItem moves to `.failed` and stops playback on fatal stream errors,
  /// so the controller reopens the stream at the last known position.
  @override
  bool get errorsStopPlayback => true;

  @override
  bool isDecoderError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('cannot decode') ||
        lower.contains('format not supported') ||
        lower.contains('unsupported codec') ||
        lower.contains('kcmformatdescriptionerror') ||
        lower.contains('averrordecoder');
  }

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
  Duration get currentPosition => _last?.position ?? Duration.zero;
  @override
  Duration get currentDuration => _last?.duration ?? Duration.zero;

  @override
  Future<void> open(
    EngineSource source, {
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    if (_disposed) return;
    final id = ++_openId;
    await _release();
    _last = null;
    _lastError = null;
    _completed.add(false);
    _buffering.add(true);
    _playing.add(false);
    _subtitleId++;
    _setCaptions(const []);

    final options = VideoPlayerOptions(mixWithOthers: true);
    final uri = Uri.parse(source.uri);
    final controller = uri.isScheme('file')
        ? VideoPlayerController.file(
            File.fromUri(uri),
            viewType: VideoViewType.textureView,
            videoPlayerOptions: options,
          )
        : VideoPlayerController.networkUrl(
            uri,
            httpHeaders: source.headers,
            viewType: VideoViewType.textureView,
            videoPlayerOptions: options,
          );
    try {
      await controller.initialize();
      if (id != _openId || _disposed) {
        await controller.dispose();
        return;
      }
      await controller.setPlaybackSpeed(_rate);
      await controller.setVolume(_volume / 100);
      if (start > Duration.zero) await controller.seekTo(start);
    } on Object catch (e) {
      await controller.dispose();
      if (id == _openId && !_disposed) _errors.add('$e');
      return;
    }
    controller.addListener(() => _onValue(controller));
    _controller.value = controller;
    _onValue(controller);
    if (play) await controller.play();
  }

  void _onValue(VideoPlayerController controller) {
    if (!identical(controller, _controller.value) || _disposed) return;
    final v = controller.value;
    final error = v.errorDescription;
    if (error != null) {
      if (error != _lastError) {
        _lastError = error;
        _errors.add(error);
      }
      return;
    }
    final last = _last;
    _last = v;
    if (last == null || v.position != last.position) {
      _position.add(v.position);
      _updateSubtitle(v.position);
    }
    if (last == null || v.duration != last.duration) _duration.add(v.duration);
    if ((last == null || v.size != last.size) &&
        v.size.width > 0 &&
        v.size.height > 0) {
      _aspectRatio.add(v.size.aspectRatio);
    }
    final end = _bufferedEnd(v);
    if (last == null || end != _bufferedEnd(last)) _buffered.add(end);
    if (last == null || v.isPlaying != last.isPlaying) {
      _playing.add(v.isPlaying);
    }
    if (last == null || v.isBuffering != last.isBuffering) {
      _buffering.add(v.isBuffering);
    }
    if (last == null || v.isCompleted != last.isCompleted) {
      _completed.add(v.isCompleted);
    }
  }

  static Duration _bufferedEnd(VideoPlayerValue v) {
    var end = Duration.zero;
    for (final r in v.buffered) {
      if (r.start <= v.position && r.end > end) end = r.end;
    }
    return end;
  }

  @override
  Future<void> play() async => _controller.value?.play();

  @override
  Future<void> pause() async => _controller.value?.pause();

  @override
  Future<void> seek(Duration position) async =>
      _controller.value?.seekTo(position);

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _controller.value?.setPlaybackSpeed(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100).toDouble();
    await _controller.value?.setVolume(_volume / 100);
  }

  @override
  Future<void> setSubtitle(EngineSubtitle? track) async {
    final id = ++_subtitleId;
    _setCaptions(const []);
    if (track == null) return;
    if (track.styled) {
      _subtitleErrors.add('Styled subtitles need libass: ${track.uri}');
      return;
    }
    try {
      final text = await loadText(track.uri);
      if (id != _subtitleId || _disposed) return;
      final ClosedCaptionFile file = text.trimLeft().startsWith('WEBVTT')
          ? WebVTTCaptionFile(text)
          : SubRipCaptionFile(text);
      final captions = file.captions;
      if (captions.isEmpty) throw const FormatException('No captions');
      _setCaptions(captions);
    } on Object catch (e) {
      if (id == _subtitleId && !_disposed) _subtitleErrors.add('$e');
    }
  }

  void _setCaptions(List<Caption> captions) {
    _captions = captions;
    _updateSubtitle(currentPosition);
  }

  void _updateSubtitle(Duration at) {
    final t = at - _subtitleDelay;
    final lines = <String>[
      for (final c in _captions)
        if (c.start <= t && t < c.end) ...c.text.split('\n'),
    ];
    if (listEquals(lines, _shownLines)) return;
    _shownLines = lines;
    if (!_disposed) _subtitleText.add(lines);
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    _subtitleDelay = delay;
    _updateSubtitle(currentPosition);
  }

  @override
  Future<void> setSubtitleScale(double scale) async {}

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) =>
      ValueListenableBuilder<VideoPlayerController?>(
        valueListenable: _controller,
        builder: (context, controller, _) {
          if (controller == null) return const SizedBox.expand();
          final size = controller.value.size;
          return SizedBox.expand(
            child: FittedBox(
              fit: fit,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: size.width > 0 ? size.width : 16,
                height: size.height > 0 ? size.height : 9,
                child: VideoPlayer(controller, key: ObjectKey(controller)),
              ),
            ),
          );
        },
      );

  Future<void> _release() async {
    final old = _controller.value;
    if (old == null) return;
    _controller.value = null;
    await old.dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _openId++;
    await _release();
    _controller.dispose();
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
}
