import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart'
    show Caption, ClosedCaptionFile, SubRipCaptionFile, WebVTTCaptionFile;

import 'player_engine.dart';

/// [PlayerEngine] on Apple TV's native HDR `AVPlayer` + `AVPlayerLayer`
/// (hosted in `tvos/Runner/AppleTvHdrPlayer.swift`).
///
/// Unlike `video_player`'s texture mode (which forces an 8-bit `32BGRA`
/// `AVPlayerItemVideoOutput` into a Flutter texture), this engine embeds a
/// native `AVPlayerLayer` via `UiKitView` with **no** `AVPlayerItemVideoOutput`
/// attached and drives `UIWindow.avDisplayManager.preferredDisplayCriteria`
/// from the playing `AVAsset`. That preserves 10-bit/12-bit hardware decoding
/// and engages Apple TV's Match Dynamic Range (HDR10, HLG, Dolby Vision) and
/// Match Frame Rate while Flutter composites `SubtitleLayer` and player
/// controls above the video.
///
/// Plain SRT/VTT subtitles are downloaded with [loadText] (carrying Cinemana's
/// shared headers), parsed in Dart, and drawn by the Flutter `SubtitleLayer`
/// (with Arabic RTL and sync delay). Styled ASS tracks require libass and are
/// not offered ([supportsStyledSubtitles] is `false`).
class AvPlayerEngine implements PlayerEngine {
  AvPlayerEngine({
    required this.loadText,
    MethodChannel? channel,
    EventChannel Function(int playerId)? eventChannelFactory,
  }) : _channel = channel ?? const MethodChannel(methodChannelName),
       _eventChannelFactory =
           eventChannelFactory ??
           ((id) => EventChannel('$eventChannelPrefix$id'));

  static const methodChannelName =
      'io.github.sharon_xa.cinemakom/apple_tv_player';
  static const eventChannelPrefix =
      'io.github.sharon_xa.cinemakom/apple_tv_player/events/';
  static const viewType = 'io.github.sharon_xa.cinemakom/apple_tv_player_view';

  /// Downloads a subtitle file (`ApiClient.fetchText`).
  final Future<String> Function(String url) loadText;

  final MethodChannel _channel;
  final EventChannel Function(int playerId) _eventChannelFactory;

  final _playerId = ValueNotifier<int?>(null);
  final _hdrFormat = ValueNotifier<String>('sdr');
  StreamSubscription<dynamic>? _eventSubscription;

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
  BoxFit _fit = BoxFit.contain;
  Duration _subtitleDelay = Duration.zero;
  List<Caption> _captions = const [];
  List<String> _shownLines = const [];

  Duration _currentPosition = Duration.zero;
  Duration _currentDuration = Duration.zero;
  String? _lastError;

  int _openId = 0;
  int _subtitleId = 0;
  bool _disposed = false;

  /// The dynamic range detected on the active video track (`sdr`, `hdr10`,
  /// `hlg`, or `dolbyVision`).
  ValueListenable<String> get hdrFormat => _hdrFormat;

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
  Duration get currentPosition => _currentPosition;
  @override
  Duration get currentDuration => _currentDuration;

  Future<int?> _ensureSession() async {
    final existing = _playerId.value;
    if (existing != null) return existing;

    final id = await _channel.invokeMethod<int>('create');
    if (id == null) {
      throw StateError('Apple TV HDR player failed to create a native session');
    }
    if (_disposed) {
      unawaited(_safeInvoke('dispose', {'playerId': id}));
      return null;
    }

    _eventSubscription = _eventChannelFactory(id)
        .receiveBroadcastStream()
        .listen(_onEvent, onError: _onEventError);
    _playerId.value = id;
    return id;
  }

  @override
  Future<void> open(
    EngineSource source, {
    Duration start = Duration.zero,
    bool play = true,
  }) async {
    if (_disposed) return;
    final id = ++_openId;
    _currentPosition = start;
    _currentDuration = Duration.zero;
    _lastError = null;
    _hdrFormat.value = 'sdr';
    _completed.add(false);
    _buffering.add(true);
    _playing.add(false);
    _subtitleId++;
    _setCaptions(const []);

    try {
      final playerId = await _ensureSession();
      if (playerId == null || id != _openId || _disposed) return;
      await _channel.invokeMethod<void>('open', <String, Object>{
        'playerId': playerId,
        'uri': source.uri,
        'headers': source.headers,
        'startMs': start.inMilliseconds,
        'play': play,
        'rate': _rate,
        'volume': _volume,
        'fit': _fitName(_fit),
      });
    } on Object catch (e) {
      if (id == _openId && !_disposed) {
        final msg = '$e';
        if (msg != _lastError) {
          _lastError = msg;
          _errors.add(msg);
        }
      }
    }
  }

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    switch (raw['type']) {
      case 'position':
        final ms = (raw['ms'] as num?)?.toInt();
        if (ms == null) return;
        final pos = Duration(milliseconds: ms < 0 ? 0 : ms);
        _currentPosition = pos;
        _position.add(pos);
        _updateSubtitle(pos);
      case 'duration':
        final ms = (raw['ms'] as num?)?.toInt();
        if (ms == null || ms <= 0) return;
        final dur = Duration(milliseconds: ms);
        _currentDuration = dur;
        _duration.add(dur);
      case 'size':
        final w = (raw['width'] as num?)?.toDouble() ?? 0;
        final h = (raw['height'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) _aspectRatio.add(w / h);
      case 'buffered':
        final ms = (raw['ms'] as num?)?.toInt();
        if (ms == null) return;
        _buffered.add(Duration(milliseconds: ms < 0 ? 0 : ms));
      case 'playing':
        final value = raw['value'] as bool?;
        if (value != null) _playing.add(value);
      case 'buffering':
        final value = raw['value'] as bool?;
        if (value != null) _buffering.add(value);
      case 'completed':
        final value = raw['value'] as bool?;
        if (value != null) _completed.add(value);
      case 'hdr':
        final format = raw['format'] as String?;
        if (format != null && format.isNotEmpty) _hdrFormat.value = format;
      case 'error':
        final message = raw['message'] as String?;
        if (message != null && message != _lastError) {
          _lastError = message;
          _errors.add(message);
        }
    }
  }

  void _onEventError(Object error) {
    if (_disposed) return;
    final msg = '$error';
    if (msg != _lastError) {
      _lastError = msg;
      _errors.add(msg);
    }
  }

  @override
  Future<void> play() async {
    final id = _playerId.value;
    if (id == null || _disposed) return;
    await _safeInvoke('play', {'playerId': id});
  }

  @override
  Future<void> pause() async {
    final id = _playerId.value;
    if (id == null || _disposed) return;
    await _safeInvoke('pause', {'playerId': id});
  }

  @override
  Future<void> seek(Duration position) async {
    final id = _playerId.value;
    if (id == null || _disposed) return;
    await _safeInvoke('seek', {
      'playerId': id,
      'positionMs': position.inMilliseconds < 0 ? 0 : position.inMilliseconds,
    });
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    final id = _playerId.value;
    if (id == null || _disposed) return;
    await _safeInvoke('setRate', {'playerId': id, 'rate': rate});
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100).toDouble();
    final id = _playerId.value;
    if (id == null || _disposed) return;
    await _safeInvoke('setVolume', {'playerId': id, 'volume': _volume});
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
    _updateSubtitle(_currentPosition);
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
    _updateSubtitle(_currentPosition);
  }

  @override
  Future<void> setSubtitleScale(double scale) async {}

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) {
    if (_fit != fit) {
      _fit = fit;
      final id = _playerId.value;
      if (id != null && !_disposed) {
        unawaited(
          _safeInvoke('setFit', {'playerId': id, 'fit': _fitName(fit)}),
        );
      }
    }
    return ValueListenableBuilder<int?>(
      valueListenable: _playerId,
      builder: (context, playerId, _) {
        if (playerId == null) return const SizedBox.expand();
        return SizedBox.expand(
          child: IgnorePointer(
            child: UiKitView(
              key: ValueKey<int>(playerId),
              viewType: viewType,
              creationParams: <String, Object>{
                'playerId': playerId,
                'fit': _fitName(_fit),
              },
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _safeInvoke(String method, Map<String, Object> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on Object {
      // Ignored during teardown or when native channels aren't attached.
    }
  }

  static String _fitName(BoxFit fit) => switch (fit) {
    BoxFit.cover => 'cover',
    BoxFit.fill => 'fill',
    _ => 'contain',
  };

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _openId++;
    final sub = _eventSubscription;
    _eventSubscription = null;
    await sub?.cancel();

    final id = _playerId.value;
    _playerId.value = null;
    if (id != null) {
      await _safeInvoke('dispose', {'playerId': id});
    }

    _playerId.dispose();
    _hdrFormat.dispose();
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
