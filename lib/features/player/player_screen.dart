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
import '../../app/widgets/choice_picker.dart';
import '../../app/widgets/error_view.dart';
import '../../core/network/api_exception.dart';
import '../../core/platform/platform_info.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import 'player_controller.dart';
import 'player_state.dart';
import 'subtitles.dart';
import 'widgets/controls_overlay.dart';
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

  bool _visible = true;
  bool _menuOpen = false;
  bool _scrubbing = false;
  bool _showBuffering = false;
  Timer? _hideTimer;
  Timer? _bufferingTimer;

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.request).notifier);
  PlayerState get _state => ref.read(playerControllerProvider(widget.request));

  @override
  void initState() {
    super.initState();
    if (isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _bufferingTimer?.cancel();
    unawaited(_wakelock(on: false));
    if (isMobile) {
      SystemChrome.setPreferredOrientations(const []);
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

  void _toggle() {
    if (_visible && _state.playing) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  Future<void> _menu<T>(
    String title,
    List<Choice<T>> choices,
    T selected,
    ValueChanged<T> onPick,
  ) async {
    _menuOpen = true;
    _show();
    final picked = await showChoicePicker<T>(
      context,
      title: title,
      choices: choices,
      selected: selected,
    );
    _menuOpen = false;
    if (picked != null) onPick(picked);
    _scheduleHide();
  }

  void _back() {
    if (context.canPop()) context.pop();
  }

  // ---------------------------------------------------------------------------
  // Menus

  void _subtitleMenu(AppLocalizations l10n) => _menu<SubtitleOption>(
    l10n.playerSubtitles,
    [for (final o in _state.subtitles) Choice(o, subtitleLabel(l10n, o))],
    _state.subtitle,
    _controller.selectSubtitle,
  );

  void _qualityMenu(AppLocalizations l10n) {
    final current = _state.quality;
    if (current == null) return;
    _menu<VideoSource>(
      l10n.playerQuality,
      [
        for (final s in _state.sources)
          Choice(s, s.height == 2160 ? l10n.quality4kCaption : s.label),
      ],
      current,
      _controller.selectQuality,
    );
  }

  void _speedMenu(AppLocalizations l10n) => _menu<double>(
    l10n.playerSpeed,
    [for (final s in _speeds) Choice(s, speedLabel(s))],
    _state.speed,
    _controller.setSpeed,
  );

  void _fitMenu(AppLocalizations l10n) => _menu<VideoFit>(
    l10n.playerScreenFit,
    [
      Choice(VideoFit.fit, l10n.playerFit),
      Choice(VideoFit.fill, l10n.playerFill),
      Choice(VideoFit.stretch, l10n.playerStretch),
    ],
    _state.fit,
    _controller.setFit,
  );

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
    final controller = _controller;
    _listen(l10n);

    final phase = state.phase;
    final busy =
        phase == PlayerPhase.loading ||
        phase == PlayerPhase.recovering ||
        (_showBuffering && state.buffering);
    final failed = phase == PlayerPhase.failed;

    return Scaffold(
      backgroundColor: MarqueeColors.night,
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
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                ),
                IgnorePointer(
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
                      onSubtitles: () => _subtitleMenu(l10n),
                      onQuality: () => _qualityMenu(l10n),
                      onSpeed: () => _speedMenu(l10n),
                      onFit: () => _fitMenu(l10n),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
