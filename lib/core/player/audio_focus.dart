import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// The player's audio focus on phones (PLAYER.md §9.1). The only file that
/// imports audio_session.
///
/// It pauses when headphones are unplugged, for a call, or when another
/// app takes the sound, and resumes after a short interruption (a call)
/// that paused it. A notification sound (a "duck") doesn't pause.
///
/// It owns focus on every platform: ExoPlayer is told not to take focus
/// itself (`mixWithOthers`), because two focus requests from one app take
/// focus from each other, and audio_session only reports unplugged
/// headphones while it holds focus.
class AudioFocus {
  AudioFocus({required this.onPause, required this.onResume});

  final void Function() onPause;
  final void Function() onResume;

  AudioSession? _session;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _playing = false;
  bool _active = false;

  /// Paused by a short interruption: resume when it ends.
  bool _resumeAfter = false;
  bool _disposed = false;

  Future<void> start() async {
    try {
      final session = await AudioSession.instance;
      if (_disposed) return;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionMode: AVAudioSessionMode.moviePlayback,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.movie,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
      _session = session;
      _subscriptions.addAll([
        session.interruptionEventStream.listen(_onInterruption),
        session.becomingNoisyEventStream.listen((_) {
          _resumeAfter = false;
          if (_playing) onPause();
        }),
      ]);
      if (_playing) await _activate();
    } on Object {
      // No audio session here (tests, odd platforms): play without it.
    }
  }

  /// Follows play/pause: focus is taken when playback starts.
  void playing(bool playing) {
    _playing = playing;
    if (playing) {
      _resumeAfter = false;
      unawaited(_activate());
    }
  }

  Future<void> _activate() async {
    final session = _session;
    if (session == null || _active || _disposed) return;
    try {
      _active = await session.setActive(true);
      // Refused (a call is going on): don't play over it.
      if (!_active && _playing) onPause();
    } on Object {
      // Keep playing without focus.
    }
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      if (event.type == AudioInterruptionType.duck) return;
      // A pause can come back (a call); "unknown" is for good (another app).
      _resumeAfter = _playing && event.type == AudioInterruptionType.pause;
      _active = false;
      if (_playing) onPause();
    } else if (_resumeAfter) {
      _resumeAfter = false;
      onResume();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    try {
      if (_active) await _session?.setActive(false);
    } on Object {
      // Nothing to give back.
    }
  }
}
