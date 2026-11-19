import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/bulb_loader.dart';
import '../../app/widgets/error_view.dart';
import '../../core/network/api_exception.dart';
import '../../core/platform/orientation.dart';
import '../../core/platform/platform_info.dart';
import '../../core/storage/preferences.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import 'player_controller.dart';
import 'player_state.dart';
import 'quality.dart';
import 'widgets/chip_menus.dart';
import 'widgets/controls_overlay.dart';
import 'widgets/seek_bar.dart' show formatClock;
import 'widgets/subtitle_layer.dart';

/// The full-screen player (docs/PLAYER.md §8). It owns what only the screen
/// knows about: whether the controls show, the menus, orientation, the
/// wakelock. Playback itself is [PlayerController].
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.request});

  final PlaybackRequest request;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _hideAfter = Duration(seconds: 3);
  static const _bufferingDelay = Duration(milliseconds: 300);
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _toastFor = Duration(milliseconds: 1200);
  static const _resumedFor = Duration(seconds: 5);

  bool _visible = true;
  bool _menuOpen = false;
  bool _scrubbing = false;
  bool _showBuffering = false;
  Timer? _hideTimer;
  Timer? _bufferingTimer;
  Timer? _toastTimer;
  Timer? _resumedTimer;

  /// A short note in the middle of the screen ("Fill" after the fit chip).
  ({IconData icon, String label})? _toast;

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.request).notifier);

  /// Kept for dispose, where `ref` can't be used.
  late final PlayerController _session;
  late final AppLifecycleListener _lifecycle;

  /// The browsing orientation to return to (Settings can't change while
  /// the player is open).
  late final ScreenRotation _rotation;
  PlayerState get _state => ref.read(playerControllerProvider(widget.request));

  @override
  void initState() {
    super.initState();
    _session = _controller;
    _rotation = ref.read(settingsProvider).screenRotation;
    // Progress survives the app being killed in the background.
    _lifecycle = AppLifecycleListener(
      onInactive: () => _session.saveProgress(),
      onHide: () => _session.saveProgress(),
    );
    if (isMobile) {
      // Either landscape side; Android and iOS only flip between them when
      // the device's auto-rotate allows it.
      setPlayerOrientation();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _session.saveProgress();
    _lifecycle.dispose();
    _hideTimer?.cancel();
    _bufferingTimer?.cancel();
    _toastTimer?.cancel();
    _resumedTimer?.cancel();
    unawaited(_wakelock(on: false));
    if (isMobile) {
      setBrowseOrientation(_rotation);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls visibility (PLAYER.md §8)

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_state.playing || _menuOpen || _scrubbing) return;
    _hideTimer = Timer(_hideAfter, () {
      if (mounted && _state.playing && !_menuOpen && !_scrubbing) {
        setState(() => _visible = false);
      }
    });
  }

  /// A tap on the video: hides the controls (paused too), or brings them back.
  void _toggle() {
    if (_visible) {
      _hide();
    } else {
      _show();
    }
  }

  void _hide() {
    _hideTimer?.cancel();
    if (_visible) setState(() => _visible = false);
  }

  /// Opens a menu; the controls stay up while it's open. Closing it without
  /// a pick (a tap on the video, back, a swipe down) hides them too.
  Future<T?> _menu<T>(
    Rect anchor,
    WidgetBuilder builder, {
    double width = 340,
  }) async {
    _menuOpen = true;
    _show();
    final picked = await showPlayerMenu<T>(
      context,
      anchor: anchor,
      builder: builder,
      width: width,
    );
    _menuOpen = false;
    if (!mounted) return picked;
    if (picked == null) {
      _hide();
    } else {
      _scheduleHide();
    }
    return picked;
  }

  void _back() {
    if (context.canPop()) context.pop();
  }

  void _showToast(IconData icon, String label) {
    _toastTimer?.cancel();
    setState(() => _toast = (icon: icon, label: label));
    _toastTimer = Timer(_toastFor, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Menus (PLAYER.md §8)

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

  Future<void> _fitMenu(AppLocalizations l10n, Rect anchor) async {
    final picked = await _menu<VideoFit>(
      anchor,
      (_) => ChoiceMenu(
        title: l10n.playerScreenFit,
        selected: _state.fit,
        choices: [
          for (final f in VideoFit.values) MenuChoice(f, fitLabel(l10n, f)),
        ],
      ),
    );
    if (picked != null) _controller.setFit(picked);
  }

  void _cycleFit(AppLocalizations l10n) {
    final fit = _controller.cycleFit();
    _showToast(fitIcon(fit), fitLabel(l10n, fit));
    _show();
  }

  /// Narrow screens: one menu with each chip and its value; a pick opens
  /// that chip's menu in the same place.
  Future<void> _moreMenu(AppLocalizations l10n, Rect anchor) async {
    final state = _state;
    final quality = state.quality;
    final picked = await _menu<_ChipMenu>(
      anchor,
      (_) => ChoiceMenu(
        title: l10n.playerMore,
        choices: [
          if (state.subtitles.length > 1)
            MenuChoice(
              _ChipMenu.subtitles,
              l10n.playerSubtitles,
              trailing: subtitleLabel(l10n, state.subtitle),
            ),
          if (quality != null && state.sources.length > 1)
            MenuChoice(
              _ChipMenu.quality,
              l10n.playerQuality,
              trailing: qualityChipLabel(quality),
            ),
          MenuChoice(
            _ChipMenu.speed,
            l10n.playerSpeed,
            trailing: speedLabel(state.speed),
          ),
          MenuChoice(
            _ChipMenu.fit,
            l10n.playerScreenFit,
            trailing: fitLabel(l10n, state.fit),
          ),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case _ChipMenu.subtitles:
        _subtitleMenu(anchor);
      case _ChipMenu.quality:
        await _qualityMenu(l10n, anchor);
      case _ChipMenu.speed:
        await _speedMenu(l10n, anchor);
      case _ChipMenu.fit:
        await _fitMenu(l10n, anchor);
    }
  }

  // ---------------------------------------------------------------------------

  void _listen(AppLocalizations l10n) {
    final provider = playerControllerProvider(widget.request);
    ref
      ..listen(provider.select((s) => s.playing), (_, playing) {
        unawaited(_wakelock(on: playing));
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
        // Short stalls don't flash the loader.
        _bufferingTimer = Timer(_bufferingDelay, () {
          if (mounted && _state.buffering) {
            setState(() => _showBuffering = true);
          }
        });
      })
      ..listen(provider.select((s) => s.subtitleFailed), (_, failed) {
        if (!failed) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.playerSubtitlesFailed)));
      })
      ..listen(provider.select((s) => s.phase), (_, phase) {
        if (phase == PlayerPhase.failed || phase == PlayerPhase.ended) {
          _show();
        }
        // "Resuming from …" stays 5 s once the video plays.
        if (phase == PlayerPhase.ready && _state.resumedFrom != null) {
          _resumedTimer?.cancel();
          _resumedTimer = Timer(_resumedFor, () {
            if (mounted) _controller.dismissResumed();
          });
        }
      });
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.space): () {
      _show();
      _controller.togglePlay();
    },
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
      _show();
      _controller.seekBy(const Duration(seconds: -10));
    },
    const SingleActivator(LogicalKeyboardKey.arrowRight): () {
      _show();
      _controller.seekBy(const Duration(seconds: 10));
    },
    const SingleActivator(LogicalKeyboardKey.escape): _back,
  };

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

    return Scaffold(
      backgroundColor: MarqueeColors.screen,
      body: CallbackShortcuts(
        bindings: _shortcuts,
        child: Focus(
          autofocus: true,
          child: MouseRegion(
            cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
            onHover: (_) => _show(),
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
                // Wraps the controls: the scrim takes every hit, so a tap
                // detector under it would never fire. Buttons inside still
                // win their own taps.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
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
                        onMore: (anchor) => _moreMenu(l10n, anchor),
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
                    child: _Busy(
                      label: phase == PlayerPhase.recovering
                          ? l10n.playerReconnecting
                          : null,
                    ),
                  ),
                if (failed)
                  _Failure(error: state.error, onRetry: controller.retry),
                if (state.resumedFrom case final from?
                    when phase == PlayerPhase.ready)
                  _Resumed(from: from, onStartOver: controller.startOver),
                if (toast != null && !busy && !failed)
                  IgnorePointer(
                    child: _Toast(icon: toast.icon, label: toast.label),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ChipMenu { subtitles, quality, speed, fit }

/// Keeps the screen on while playing. A missing plugin (tests, odd
/// platforms) just means no wakelock.
Future<void> _wakelock({required bool on}) async {
  try {
    await (on ? WakelockPlus.enable() : WakelockPlus.disable());
  } on Object {
    // Not available here.
  }
}

class _Busy extends StatelessWidget {
  const _Busy({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BulbLoader(semanticLabel: AppLocalizations.of(context).loading),
          if (label != null) ...[
            const SizedBox(height: MarqueeSpace.m),
            Text(label, style: MarqueeText.of(context).label),
          ],
        ],
      ),
    );
  }
}

/// "Resuming from 14:32 · Start over", above the seek bar at the start
/// edge. It shows even when the controls are hidden.
class _Resumed extends StatelessWidget {
  const _Resumed({required this.from, required this.onStartOver});

  final Duration from;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Align(
        alignment: AlignmentDirectional.bottomStart,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: width >= 600 ? MarqueeSpace.xxxl : MarqueeSpace.l,
            bottom: 72,
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
                    style: TextButton.styleFrom(
                      foregroundColor: MarqueeColors.bulb,
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(l10n.playerStartOver),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short note above the centre buttons, e.g. "Fill" after the fit chip.
class _Toast extends StatelessWidget {
  const _Toast({required this.icon, required this.label});

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
            Icon(icon, size: 18, color: MarqueeColors.cream),
            const SizedBox(width: MarqueeSpace.s),
            Text(label, style: MarqueeText.of(context).label),
          ],
        ),
      ),
    ),
  );
}

/// API errors go through [ErrorView] (it asks the status page once); stream
/// failures say so in the player's own words.
class _Failure extends StatelessWidget {
  const _Failure({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = this.error;
    final Widget body = error is ApiException
        ? ErrorView(error: error, onRetry: onRetry)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error == PlayerFailure.unavailable
                    ? l10n.playerUnavailable
                    : l10n.playerFailed,
                textAlign: TextAlign.center,
                style: MarqueeText.of(context).body
                    .copyWith(color: MarqueeColors.creamSoft),
              ),
              const SizedBox(height: MarqueeSpace.l),
              OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
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
