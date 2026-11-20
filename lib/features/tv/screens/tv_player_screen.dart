import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/error_view.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/player/audio_focus.dart';
import '../../../core/storage/preferences.dart';
import '../../../data/models/playback_models.dart';
import '../../../data/models/playback_request.dart';
import '../../player/player_controller.dart';
import '../../player/player_state.dart';
import '../../player/up_next.dart';
import '../../player/widgets/chip_menus.dart';
import '../../player/widgets/controls_overlay.dart';
import '../../player/widgets/episodes_panel.dart';
import '../../player/widgets/seek_bar.dart' show formatClock;
import '../../player/widgets/skip_intro_button.dart';
import '../../player/widgets/subtitle_layer.dart';
import '../../player/widgets/up_next_card.dart';

/// Dedicated Android TV player (docs/ANDROID_TV.md, PLAYER.md). Playback is
/// the shared [PlayerController]; this screen only owns remote handling:
/// - media keys always work;
/// - controls hidden: Left/Right quick-seek (10 → 30 → 60 s), Up/Down reveal
///   the controls on Play/Pause, OK activates Up next / Skip intro or toggles
///   play, Back exits;
/// - controls visible: the D-pad moves between controls, Back hides them.
///
/// No touch gestures, lock or full-screen buttons.
class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({super.key, required this.request});

  final PlaybackRequest request;

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen> {
  static const _hideAfter = Duration(seconds: 5);
  static const _bufferingDelay = Duration(milliseconds: 300);
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _toastFor = Duration(milliseconds: 1200);
  static const _resumedFor = Duration(seconds: 5);

  final _rootFocus = FocusNode(debugLabel: 'tvPlayerRoot');
  final _playPauseFocus = FocusNode(debugLabel: 'tvPlayerPlayPause');

  bool _visible = true;
  bool _menuOpen = false;
  bool _scrubbing = false;
  bool _showBuffering = false;
  int _quickSeekDir = 0;
  int _quickSeekSteps = 0;

  AudioFocus? _audio;
  Timer? _hideTimer;
  Timer? _bufferingTimer;
  Timer? _toastTimer;
  Timer? _resumedTimer;
  Timer? _quickSeekReset;
  ({IconData icon, String label})? _toast;

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.request).notifier);
  PlayerState get _state => ref.read(playerControllerProvider(widget.request));

  late final PlayerController _session;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _session = _controller;
    _lifecycle = AppLifecycleListener(
      onInactive: () => _session.saveProgress(),
      onHide: () => _session.saveProgress(),
    );
    _audio = AudioFocus(
      onPause: () => _session.pause(),
      onResume: () => _session.play(),
    );
    unawaited(_audio!.start());
  }

  @override
  void dispose() {
    _session.saveProgress();
    _lifecycle.dispose();
    _hideTimer?.cancel();
    _bufferingTimer?.cancel();
    _toastTimer?.cancel();
    _resumedTimer?.cancel();
    _quickSeekReset?.cancel();
    _rootFocus.dispose();
    _playPauseFocus.dispose();
    unawaited(_audio?.dispose());
    unawaited(_wakelock(on: false));
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls visibility

  void _show({bool focusPlayPause = false}) {
    if (!_visible) setState(() => _visible = true);
    if (focusPlayPause) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible && !_menuOpen) {
          _playPauseFocus.requestFocus();
        }
      });
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_state.playing || _menuOpen || _scrubbing) return;
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && _state.playing && !_menuOpen && !_scrubbing) _hide();
    });
  }

  void _hide() {
    _hideTimer?.cancel();
    if (_visible) setState(() => _visible = false);
    if (!_menuOpen) _rootFocus.requestFocus();
  }

  void _back() {
    if (context.canPop()) context.pop();
  }

  void _togglePlay() => unawaited(_controller.togglePlay());

  void _showToast(IconData icon, String label) {
    _toastTimer?.cancel();
    setState(() => _toast = (icon: icon, label: label));
    _toastTimer = Timer(_toastFor, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  /// Accelerating quick-seek: 10 s, then 30 s, then 60 s steps.
  void _quickSeek(int direction) {
    if (_quickSeekDir == direction) {
      _quickSeekSteps++;
    } else {
      _quickSeekDir = direction;
      _quickSeekSteps = 1;
    }
    _quickSeekReset?.cancel();
    _quickSeekReset = Timer(_toastFor, () {
      _quickSeekDir = 0;
      _quickSeekSteps = 0;
    });
    final seconds = _quickSeekSteps >= 9
        ? 60
        : _quickSeekSteps >= 4
        ? 30
        : 10;
    unawaited(_controller.seekBy(Duration(seconds: seconds * direction)));
    _showToast(
      direction > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      AppLocalizations.of(
        context,
      ).playerSeekAmount('${direction > 0 ? '+' : '−'}$seconds'),
    );
  }

  // ---------------------------------------------------------------------------
  // Menus

  Future<T?> _open<T>(Future<T?> Function() show) async {
    _controller.noteActivity();
    _menuOpen = true;
    _show();
    final picked = await show();
    _menuOpen = false;
    if (!mounted) return picked;
    _scheduleHide();
    return picked;
  }

  Future<T?> _menu<T>(Rect anchor, WidgetBuilder builder, {double width = 340}) =>
      _open(
        () => showPlayerMenu<T>(
          context,
          anchor: anchor,
          builder: builder,
          width: width,
        ),
      );

  void _subtitleMenu(Rect anchor) => _menu<bool>(
    anchor,
    (_) => SubtitleMenu(request: widget.request),
    width: SubtitleMenu.popoverWidth,
  );

  Future<void> _qualityMenu(AppLocalizations l10n, Rect anchor) async {
    final current = _state.quality;
    if (current == null) return;
    final picked = await _menu<VideoSource>(
      anchor,
      (_) => ChoiceMenu(
        title: l10n.playerQuality,
        selected: current,
        choices: [
          for (final s in _state.sources)
            MenuChoice(
              s,
              s.label,
              caption: s.height == 2160 ? l10n.quality4kCaption : null,
            ),
        ],
      ),
    );
    if (picked != null) await _controller.selectQuality(picked);
  }

  Future<void> _speedMenu(AppLocalizations l10n, Rect anchor) async {
    final picked = await _menu<double>(
      anchor,
      (_) => ChoiceMenu(
        title: l10n.playerSpeed,
        selected: _state.speed,
        choices: [for (final s in _speeds) MenuChoice(s, speedLabel(s))],
      ),
    );
    if (picked != null) await _controller.setSpeed(picked);
  }

  void _cycleFit(AppLocalizations l10n) {
    final fit = _controller.cycleFit();
    _showToast(fitIcon(fit), fitLabel(l10n, fit));
    _show();
  }

  Future<void> _episodesPanel() async {
    final picked = await _open(
      () => showEpisodesPanel(
        context,
        seriesId: widget.request.item.seriesId,
        current: _state.episode,
      ),
    );
    if (picked != null && picked.id != _state.videoId) {
      await _controller.playEpisode(picked);
    }
  }

  // ---------------------------------------------------------------------------
  // Remote keys

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_menuOpen) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    _controller.noteActivity();

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
      _show(focusPlayPause: !_visible);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      unawaited(_controller.play());
      _show();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(_controller.pause());
      _show(focusPlayPause: !_visible);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _quickSeek(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _quickSeek(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaTrackNext) {
      unawaited(_controller.playNext());
      _show();
      return KeyEventResult.handled;
    }

    final isBack =
        key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape;
    final isSelect =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;

    if (!_visible) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _quickSeek(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _quickSeek(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _show(focusPlayPause: true);
        return KeyEventResult.handled;
      }
      if (isSelect) {
        final s = _state;
        if (s.nextEpisode != null &&
            s.upNext != UpNext.none &&
            s.phase != PlayerPhase.failed) {
          unawaited(_controller.playNext());
        } else if (s.intro != null &&
            s.introPinned &&
            s.phase == PlayerPhase.ready) {
          unawaited(_controller.skipIntro());
        } else {
          _togglePlay();
          _show(focusPlayPause: true);
        }
        return KeyEventResult.handled;
      }
      if (isBack && event is KeyDownEvent) {
        _back();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    _scheduleHide();
    if (isBack && event is KeyDownEvent) {
      _hide();
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) &&
        _rootFocus.hasPrimaryFocus) {
      _playPauseFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------

  void _listen(AppLocalizations l10n) {
    final provider = playerControllerProvider(widget.request);
    ref
      ..listen(provider.select((s) => s.playing), (_, playing) {
        unawaited(_wakelock(on: playing));
        _audio?.playing(playing);
        if (playing) {
          _scheduleHide();
        } else {
          _show();
        }
      })
      ..listen(provider.select((s) => s.buffering), (_, buffering) {
        _bufferingTimer?.cancel();
        if (!buffering) {
          if (_showBuffering) setState(() => _showBuffering = false);
          return;
        }
        _bufferingTimer = Timer(_bufferingDelay, () {
          if (mounted && _state.buffering) {
            setState(() => _showBuffering = true);
          }
        });
      })
      ..listen(provider.select((s) => s.loweredFrom), (_, from) {
        final to = _state.quality;
        if (from == null || to == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.playerQualityLowered(
                qualityChipLabel(from),
                qualityChipLabel(to),
              ),
            ),
          ),
        );
      })
      ..listen(provider.select((s) => s.subtitleFailed), (_, failed) {
        if (!failed) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.playerSubtitlesFailed)));
      })
      ..listen(provider.select((s) => s.phase), (_, phase) {
        if (phase == PlayerPhase.failed || phase == PlayerPhase.ended) {
          _show();
        }
        if (phase == PlayerPhase.ready && _state.resumedFrom != null) {
          _resumedTimer?.cancel();
          _resumedTimer = Timer(_resumedFor, () {
            if (mounted) _controller.dismissResumed();
          });
        }
      });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playerControllerProvider(widget.request));
    final subtitleScale = ref.watch(
      settingsProvider.select((s) => s.subtitleSize.scale),
    );
    final controller = _controller;
    final toast = _toast;
    _listen(l10n);

    final phase = state.phase;
    final busy =
        phase == PlayerPhase.loading ||
        phase == PlayerPhase.recovering ||
        (_showBuffering && state.buffering);
    final failed = phase == PlayerPhase.failed;

    return PopScope(
      canPop: !(_visible && !failed),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _visible) _hide();
      },
      child: Scaffold(
        backgroundColor: MarqueeColors.screen,
        body: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              controller.engine.buildVideo(
                fit: switch (state.fit) {
                  VideoFit.fit => BoxFit.contain,
                  VideoFit.fill => BoxFit.cover,
                  VideoFit.stretch => BoxFit.fill,
                },
              ),
              SubtitleLayer(
                lines: controller.subtitleLines,
                lifted: _visible,
                scale: subtitleScale,
              ),
              ExcludeFocus(
                excluding: !_visible,
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: ControlsOverlay(
                      state: state,
                      controller: controller,
                      busy: busy || failed,
                      onBack: _back,
                      onSubtitles: _subtitleMenu,
                      onQuality: (anchor) => _qualityMenu(l10n, anchor),
                      onSpeed: (anchor) => _speedMenu(l10n, anchor),
                      onFit: () => _cycleFit(l10n),
                      onMore: (anchor) => _speedMenu(l10n, anchor),
                      onEpisodes: widget.request.isSeries
                          ? _episodesPanel
                          : null,
                      playPauseFocusNode: _playPauseFocus,
                      onScrub: (at) {
                        _scrubbing = at != null;
                        if (_scrubbing) {
                          _hideTimer?.cancel();
                        } else {
                          _scheduleHide();
                        }
                      },
                    ),
                  ),
                ),
              ),
              if (busy && !failed)
                IgnorePointer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BulbLoader(semanticLabel: l10n.loading),
                        if (phase == PlayerPhase.recovering) ...[
                          const SizedBox(height: MarqueeSpace.m),
                          Text(
                            l10n.playerReconnecting,
                            style: MarqueeText.of(context).label,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (failed)
                _TvFailure(
                  error: state.error,
                  onRetry: controller.retry,
                  onBack: _back,
                ),
              if (state.resumedFrom case final from?
                  when phase == PlayerPhase.ready)
                _TvResumed(from: from, onStartOver: controller.startOver),
              if (state.nextEpisode case final next?
                  when state.upNext != UpNext.none && !failed)
                UpNextCard(
                  next: next,
                  upNext: state.upNext,
                  onPlayNow: controller.playNext,
                  onHide: controller.hideUpNext,
                )
              else if (state.intro != null &&
                  phase == PlayerPhase.ready &&
                  !failed)
                SkipIntroButton(
                  visible: state.introPinned || _visible,
                  onPressed: () {
                    _controller.noteActivity();
                    _controller.skipIntro();
                  },
                ),
              if (toast != null && !busy && !failed)
                IgnorePointer(
                  child: _TvToast(icon: toast.icon, label: toast.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _wakelock({required bool on}) async {
  try {
    await (on ? WakelockPlus.enable() : WakelockPlus.disable());
  } on Object {
    // Not available here.
  }
}

class _TvResumed extends StatelessWidget {
  const _TvResumed({required this.from, required this.onStartOver});

  final Duration from;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: MarqueeSpace.xxxl,
          bottom: 88,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MarqueeColors.booth,
            border: Border.all(color: MarqueeColors.velvet),
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: MarqueeSpace.l),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.playerResumingFrom(formatClock(from)),
                  style: MarqueeText.of(context).label,
                ),
                const SizedBox(width: MarqueeSpace.xs),
                TextButton(
                  onPressed: onStartOver,
                  style: withFocusRing(
                    TextButton.styleFrom(
                      foregroundColor: MarqueeColors.bulb,
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                  child: Text(l10n.playerStartOver),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvToast extends StatelessWidget {
  const _TvToast({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.45),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: MarqueeColors.booth,
        border: Border.all(color: MarqueeColors.velvet),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: MarqueeSpace.l,
          vertical: MarqueeSpace.s,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: MarqueeColors.cream),
            const SizedBox(width: MarqueeSpace.s),
            Text(label, style: MarqueeText.of(context).label),
          ],
        ),
      ),
    ),
  );
}

class _TvFailure extends StatelessWidget {
  const _TvFailure({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = this.error;
    final unavailable = error == PlayerFailure.unavailable;
    final Widget body = error is ApiException
        ? ErrorView(error: error, onRetry: onRetry)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                unavailable ? l10n.playerUnavailable : l10n.playerFailed,
                textAlign: TextAlign.center,
                style: MarqueeText.of(
                  context,
                ).body.copyWith(color: MarqueeColors.creamSoft),
              ),
              const SizedBox(height: MarqueeSpace.l),
              unavailable
                  ? OutlinedButton(
                      autofocus: true,
                      onPressed: onBack,
                      child: Text(
                        MaterialLocalizations.of(context).backButtonTooltip,
                      ),
                    )
                  : OutlinedButton(
                      autofocus: true,
                      onPressed: onRetry,
                      child: Text(l10n.retry),
                    ),
            ],
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(MarqueeSpace.xxl),
          child: body,
        ),
      ),
    );
  }
}
