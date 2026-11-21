import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/bulb_loader.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/media_image.dart';
import '../../app/widgets/media_text.dart';
import '../../core/network/api_exception.dart';
import '../../core/platform/platform_info.dart';
import '../../core/player/audio_focus.dart';
import '../../core/storage/preferences.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import '../../features/player/player_controller.dart';
import '../../features/player/player_labels.dart';
import '../../features/player/player_state.dart';
import '../../features/player/quality.dart';
import '../../features/player/up_next.dart';
import '../../features/player/widgets/seek_preview_frame.dart';
import '../../features/player/widgets/subtitle_layer.dart';
import '../focus/tv_back.dart';
import '../focus/tv_focusable.dart';
import '../focus/tv_screen.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import '../tv_keys.dart';
import '../widgets/tv_button.dart';
import '../widgets/tv_choice_panel.dart';
import 'tv_player_controls.dart';
import 'tv_player_panels.dart';
import 'tv_seek.dart';

/// The TV player (docs/TV.md §8, the TV player designs): the same
/// [PlayerController] and engine as the phone, driven by the remote.
///
/// **Controls hidden** (watching): OK pauses (or plays) and shows them;
/// Left and Right seek (held: 10 s steps, then 30 s, then 60 s) with the
/// frame and the time over the bar, playing from there 600 ms after the last
/// key; Up and Down show the controls; Back leaves. Skip intro and Up next
/// take the focus when they appear, so OK acts on them (owner's choice).
///
/// **Controls shown**: the chips at the top (each opens a panel), then the
/// row above the bar (Start over, Skip intro or Up next), the seek bar
/// (Left and Right scrub, OK or 600 ms plays from there, Up and Down leave
/// it without seeking), and the buttons: −10 s, Play/Pause (focus starts
/// here), +10 s, Episodes and Next episode. They hide after 5 s without a
/// key while playing; Back hides them first.
///
/// The media keys always work, over the panels too. The seek bar, the times
/// and the ±10 s buttons keep their physical places in Arabic (PLAYER.md
/// §2); the rest follows start and end.
class TvPlayerScreen extends ConsumerStatefulWidget {
  const TvPlayerScreen({super.key, required this.request});

  final PlaybackRequest request;

  static const hideAfter = Duration(seconds: 5);

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

/// Where the row above the bar (Skip intro, Up next) sits from the bottom:
/// the safe area, the buttons, the seek row and their gaps (the Controls
/// design). The pinned ones sit there too, so they don't jump.
const double _aboveBar = TvSpace.safeV + 64 + 20 + TvSeekTrack.height + 16;

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen> {
  static const _bufferingDelay = Duration(milliseconds: 300);
  static const _noteFor = Duration(seconds: 4);
  static const _resumedFor = Duration(seconds: 5);
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  bool _visible = true;

  /// Counts the times the controls showed: each time they're built afresh,
  /// so Play/Pause takes the focus again.
  int _shows = 0;
  bool _panelOpen = false;
  bool _showBuffering = false;
  String? _note;
  Timer? _hideTimer;
  Timer? _bufferingTimer;
  Timer? _noteTimer;
  Timer? _resumedTimer;
  AudioFocus? _audio;

  late final TvScrub _scrub = TvScrub(
    onCommit: (to) {
      unawaited(_controller.seek(to));
      _scheduleHide();
    },
  );

  PlayerController get _controller =>
      ref.read(playerControllerProvider(widget.request).notifier);
  PlayerState get _state => ref.read(playerControllerProvider(widget.request));

  /// Kept for dispose, where `ref` can't be used.
  late final PlayerController _session;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _session = _controller;
    // Progress survives the app being closed in the background.
    _lifecycle = AppLifecycleListener(
      onInactive: () => _session.saveProgress(),
      onHide: () => _session.saveProgress(),
    );
    if (isMobile) {
      _audio = AudioFocus(
        onPause: () => _session.pause(),
        onResume: () => _session.play(),
      );
      unawaited(_audio!.start());
    }
    TvMedia.handler = _media;
    HardwareKeyboard.instance.addHandler(_anyKey);
  }

  @override
  void dispose() {
    _session.saveProgress();
    _lifecycle.dispose();
    if (TvMedia.handler == _media) TvMedia.handler = null;
    HardwareKeyboard.instance.removeHandler(_anyKey);
    _hideTimer?.cancel();
    _bufferingTimer?.cancel();
    _noteTimer?.cancel();
    _resumedTimer?.cancel();
    _scrub.dispose();
    unawaited(_audio?.dispose());
    unawaited(_wakelock(on: false));
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Showing and hiding the controls

  /// Any key: someone is watching ("Still watching?" waits), and the
  /// controls stay a while longer.
  bool _anyKey(KeyEvent event) {
    if (event is KeyDownEvent && mounted) {
      _session.noteActivity();
      if (_visible) _scheduleHide();
    }
    return false;
  }

  void _show() {
    if (!_visible) {
      setState(() {
        _visible = true;
        _shows++;
      });
    }
    _scheduleHide();
  }

  void _hide() {
    _hideTimer?.cancel();
    if (_visible) setState(() => _visible = false);
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_state.playing || _panelOpen || _scrub.active) return;
    _hideTimer = Timer(TvPlayerScreen.hideAfter, () {
      if (mounted && _state.playing && !_panelOpen && !_scrub.active) {
        _hide();
      }
    });
  }

  /// Back, before it leaves the player: a seek in progress stays where the
  /// video is, then shown controls hide (docs/TV.md §8.2).
  bool _back() {
    if (_scrub.active) {
      _scrub.cancel();
      _scheduleHide();
      return true;
    }
    if (_visible && _state.phase != PlayerPhase.failed) {
      _hide();
      return true;
    }
    return false;
  }

  void _leave() => Navigator.of(context).maybePop();

  // ---------------------------------------------------------------------------
  // Keys

  void _media(TvMediaKey key) {
    switch (key) {
      case TvMediaKey.playPause:
        unawaited(_controller.togglePlay());
      case TvMediaKey.play:
        unawaited(_controller.play());
      case TvMediaKey.pause:
        unawaited(_controller.pause());
      case TvMediaKey.rewind:
        _seekStep(forward: false, repeat: false);
      case TvMediaKey.fastForward:
        _seekStep(forward: true, repeat: false);
      case TvMediaKey.next:
        if (_state.nextEpisode != null) unawaited(_controller.playNext());
    }
  }

  void _seekStep({required bool forward, required bool repeat}) {
    final state = _state;
    if (state.duration <= Duration.zero || state.phase == PlayerPhase.failed) {
      return;
    }
    _hideTimer?.cancel();
    _scrub.step(
      forward: forward,
      repeat: repeat,
      position: _controller.position.value,
      duration: state.duration,
    );
  }

  /// Keys on the video (and on Skip intro while the controls are hidden):
  /// Left and Right seek, Up and Down show the controls.
  KeyEventResult _watchingKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (event is! KeyUpEvent) {
        _seekStep(
          forward: key == LogicalKeyboardKey.arrowRight,
          repeat: event is KeyRepeatEvent,
        );
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) _showFromWatching();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Keys on the Up next card while the controls are hidden: Left and Right
  /// move between its buttons, Up and Down show the controls.
  KeyEventResult _cardKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) _showFromWatching();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showFromWatching() {
    if (_scrub.active) _scrub.commit();
    _show();
  }

  /// OK on the video: plays from the seek target, else pauses (or plays)
  /// and shows the controls.
  void _watchingOk() {
    if (_scrub.active) return _scrub.commit();
    unawaited(_controller.togglePlay());
    _show();
  }

  /// Keys on the seek bar: Left and Right scrub; Up and Down leave it
  /// without seeking (the zone moves on).
  KeyEventResult _barKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (event is! KeyUpEvent) {
        _seekStep(
          forward: key == LogicalKeyboardKey.arrowRight,
          repeat: event is KeyRepeatEvent,
        );
      }
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown) &&
        event is KeyDownEvent &&
        _scrub.active) {
      _scrub.cancel();
      _scheduleHide();
    }
    return KeyEventResult.ignored;
  }

  /// OK on the seek bar: plays from the target, else plays or pauses.
  void _barOk() {
    if (_scrub.active) return _scrub.commit();
    unawaited(_controller.togglePlay());
  }

  // ---------------------------------------------------------------------------
  // Panels (each chip opens one; the controls stay while it's open)

  Future<void> _panel(Future<void> Function() open) async {
    _panelOpen = true;
    _hideTimer?.cancel();
    await open();
    _panelOpen = false;
    if (mounted) _scheduleHide();
  }

  Future<void> _subtitles() =>
      _panel(() => showTvSubtitlePanel(context, widget.request));

  Future<void> _quality(AppLocalizations l10n) => _panel(() async {
    final state = _state;
    final picked = await showTvChoicePanel<VideoSource>(
      context,
      title: l10n.playerQuality,
      width: tvPlayerPanelWidth,
      scrim: tvPlayerScrim,
      selected: state.quality,
      choices: [
        for (final s in state.sources)
          TvChoice(
            s,
            s.label,
            detail: s.height == 2160 ? l10n.quality4kCaption : null,
          ),
      ],
    );
    if (picked != null) await _controller.selectQuality(picked);
  });

  Future<void> _speed(AppLocalizations l10n) => _panel(() async {
    final picked = await showTvChoicePanel<double>(
      context,
      title: l10n.playerSpeed,
      width: tvPlayerPanelWidth,
      scrim: tvPlayerScrim,
      selected: _state.speed,
      choices: [for (final s in _speeds) TvChoice(s, speedLabel(s))],
    );
    if (picked != null) await _controller.setSpeed(picked);
  });

  Future<void> _fit(AppLocalizations l10n) => _panel(() async {
    final picked = await showTvChoicePanel<VideoFit>(
      context,
      title: l10n.playerScreenFit,
      width: tvPlayerPanelWidth,
      scrim: tvPlayerScrim,
      selected: _state.fit,
      choices: [
        for (final f in VideoFit.values) TvChoice(f, fitLabel(l10n, f)),
      ],
    );
    if (picked != null) _controller.setFit(picked);
  });

  Future<void> _episodes() => _panel(() async {
    final state = _state;
    final picked = await showTvEpisodesPanel(
      context,
      request: widget.request,
      currentId: state.videoId,
      episodes: state.episodes,
    );
    if (picked != null && picked.id != _state.videoId) {
      await _controller.playEpisode(picked);
    }
  });

  // ---------------------------------------------------------------------------

  void _showNote(String text) {
    _noteTimer?.cancel();
    setState(() => _note = text);
    _noteTimer = Timer(_noteFor, () {
      if (mounted) setState(() => _note = null);
    });
  }

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
        // Short stalls don't flash the loader.
        _bufferingTimer = Timer(_bufferingDelay, () {
          if (mounted && _state.buffering) {
            setState(() => _showBuffering = true);
          }
        });
      })
      ..listen(provider.select((s) => s.upNext), (_, upNext) {
        // "Still watching?" needs an answer: the controls, with Play now
        // focused.
        if (upNext == UpNext.stillWatching) {
          setState(() {
            _visible = true;
            _shows++;
          });
        }
      })
      ..listen(provider.select((s) => s.seekPreview), (_, preview) {
        if (preview != null) _prefetch(preview);
      })
      ..listen(provider.select((s) => s.loweredFrom), (_, from) {
        final to = _state.quality;
        if (from == null || to == null) return;
        _showNote(
          l10n.playerQualityLowered(
            qualityChipLabel(from),
            qualityChipLabel(to),
          ),
        );
      })
      ..listen(provider.select((s) => s.subtitleFailed), (_, failed) {
        if (failed) _showNote(l10n.playerSubtitlesFailed);
      })
      ..listen(provider.select((s) => s.phase), (_, phase) {
        if (phase == PlayerPhase.failed) {
          _scrub.cancel();
          _hide();
        }
        if (phase == PlayerPhase.ended) _show();
        // "Resuming from …" stays 5 s once the video plays.
        if (phase == PlayerPhase.ready && _state.resumedFrom != null) {
          _resumedTimer?.cancel();
          _resumedTimer = Timer(_resumedFor, () {
            if (mounted) _controller.dismissResumed();
          });
        }
      });
  }

  /// The sprite sheet under the playhead and the next one, so the first
  /// seek shows frames at once (PLAYER.md §7.8).
  void _prefetch(SeekPreview preview) {
    if (!ref.read(networkImagesProvider)) return;
    final urls = preview.sheetUrls;
    final here = preview.frameAt(_controller.position.value)?.url;
    final from = here == null ? 0 : urls.indexOf(here).clamp(0, urls.length);
    for (final url in urls.skip(from).take(2)) {
      unawaited(
        precacheImage(seekSheetImage(url), context, onError: (_, _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(playerControllerProvider(widget.request));
    final subtitleScale = ref.watch(
      settingsProvider.select((s) => s.subtitleSize.scale),
    );
    final controller = _controller;
    _listen(l10n);

    final phase = state.phase;
    final failed = phase == PlayerPhase.failed;
    final busy =
        !failed &&
        (phase == PlayerPhase.loading ||
            phase == PlayerPhase.recovering ||
            (_showBuffering && state.buffering));
    final next = state.nextEpisode;
    // On TV the card waits for the countdown (the last 10 s, or the end of
    // the file), so it doesn't cover the credits' last minutes; the earlier
    // "card" stage shows nothing here (owner's call, 2026-11-21). Next
    // episode in the controls still works.
    final upNext =
        next != null &&
        (state.upNext == UpNext.countdown ||
            state.upNext == UpNext.stillWatching) &&
        !failed;
    final intro = state.intro != null && phase == PlayerPhase.ready && !upNext;
    final resumed = state.resumedFrom != null && phase == PlayerPhase.ready;
    final watching = !_visible && !failed;
    // With the controls hidden, a pinned Skip intro or the Up next card
    // takes the focus from the video.
    final pinned = watching && (upNext || (intro && state.introPinned));

    return TvScreen(
      builder: (context, scroll) => TvBack(
        onBack: _back,
        child: ColoredBox(
          color: MarqueeColors.screen,
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
                lifted: _visible && !failed,
                liftedBy: _aboveBar + 8,
                scale: subtitleScale,
              ),
              if (watching)
                TvZone.row(
                  order: 0,
                  keyline: 0,
                  child: TvFocusable(
                    index: 0,
                    label: l10n.tvPlayerVideo,
                    autofocus: !pinned,
                    onKey: _watchingKey,
                    onSelect: _watchingOk,
                    builder: (_, _) => const SizedBox.expand(),
                  ),
                ),
              // The controls fade; hidden, nothing in them can take focus
              // (R5). Each showing builds them afresh, focused on Play/Pause.
              // Keyed: hiding them adds the Video target before them, and an
              // unkeyed fade would be rebuilt at its end value, never fading.
              ExcludeFocus(
                key: const ValueKey('controls'),
                excluding: !_visible || failed,
                child: AnimatedOpacity(
                  opacity: _visible && !failed ? 1 : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : _visible && !failed
                      ? controlsFadeIn
                      : controlsFadeOut,
                  curve: TvFocusStyle.curve,
                  child: KeyedSubtree(
                    key: ValueKey(_shows),
                    child: _controls(
                      l10n,
                      state,
                      upNext: upNext,
                      intro: intro,
                      resumed: resumed,
                    ),
                  ),
                ),
              ),
              if (watching)
                ListenableBuilder(
                  listenable: _scrub,
                  builder: (context, _) => _scrub.active
                      ? _watchingSeek(state)
                      : const SizedBox.shrink(),
                ),
              if (watching && upNext)
                _UpNextCard(
                  order: 1,
                  next: next,
                  upNext: state.upNext,
                  autofocus: true,
                  onKey: _cardKey,
                  onPlayNow: controller.playNext,
                  onHide: controller.hideUpNext,
                )
              else if (watching && intro && state.introPinned)
                PositionedDirectional(
                  end: TvSpace.safeH,
                  bottom: _aboveBar,
                  child: TvZone.row(
                    order: 1,
                    keyline: 0,
                    child: TvPlayerPill(
                      index: 0,
                      label: l10n.playerSkipIntro,
                      outline: true,
                      autofocus: true,
                      onKey: _watchingKey,
                      onSelect: controller.skipIntro,
                    ),
                  ),
                ),
              if (watching && resumed && !_scrub.active)
                PositionedDirectional(
                  start: TvSpace.safeH,
                  bottom: _aboveBar,
                  child: _ResumedNote(from: state.resumedFrom!),
                ),
              if (busy)
                _Busy(
                  label: phase == PlayerPhase.recovering
                      ? l10n.playerReconnecting
                      : null,
                ),
              if (failed)
                _Failure(
                  error: state.error,
                  onRetry: controller.retry,
                  onBack: _leave,
                ),
              if (_note case final note?) TvPlayerNote(text: note),
            ],
          ),
        ),
      ),
    );
  }

  /// Seeking with the controls hidden (the Watching design): no veil, the
  /// frame over the bar, the times under it.
  Widget _watchingSeek(PlayerState state) => PositionedDirectional(
    start: TvSpace.safeH,
    end: TvSpace.safeH,
    bottom: TvSpace.safeV,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvSeekBar(
          position: _controller.position,
          buffered: _controller.buffered,
          duration: state.duration,
          scrub: _scrub,
          preview: state.seekPreview,
          aspectRatio: state.aspectRatio,
          overVideo: true,
        ),
        const SizedBox(height: 10),
        TvSeekTimes(scrub: _scrub, duration: state.duration),
      ],
    ),
  );

  /// The controls (the Controls design) over a 62% `night` veil, inside the
  /// safe area: zones 10 (chips), 11 (the row above the bar), 12 (the seek
  /// bar) and 13 (the buttons, a split).
  Widget _controls(
    AppLocalizations l10n,
    PlayerState state, {
    required bool upNext,
    required bool intro,
    required bool resumed,
  }) {
    final text = MarqueeTvText.of(context);
    final controller = _controller;
    final episode = state.episode;
    final stillWatching = state.upNext == UpNext.stillWatching && upNext;
    final quality = state.quality;
    final series = widget.request.isSeries;
    final next = state.nextEpisode;
    final timeStyle = text.caption
        .copyWith(fontSize: 15, color: MarqueeColors.cream)
        .withWeight(FontWeight.w500);
    return ColoredBox(
      color: MarqueeColors.night.withValues(alpha: 0.62),
      child: Padding(
        padding: TvSpace.safe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.titleOf(
                          state.details?.item ?? widget.request.item,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.title.copyWith(fontSize: 20, height: 1.25),
                      ),
                      if (episode != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.seasonNumber(episode.season)} · '
                          '${episodeLabel(l10n, episode.numbering)}',
                          style: text.caption.copyWith(
                            fontSize: 15,
                            color: MarqueeColors.creamSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TvZone.row(
                  order: 10,
                  keyline: 0,
                  child: Row(
                    children: [
                      if (state.subtitles.length > 1)
                        TvPlayerChip(
                          index: 0,
                          icon: Icons.subtitles_outlined,
                          label: subtitleLabel(l10n, state.subtitle),
                          name: l10n.tvPlayerChip(
                            l10n.playerSubtitles,
                            subtitleLabel(l10n, state.subtitle),
                          ),
                          onSelect: _subtitles,
                        ),
                      if (quality != null) ...[
                        const SizedBox(width: 10),
                        TvPlayerChip(
                          index: 1,
                          label: qualityChipLabel(quality),
                          name: l10n.tvPlayerChip(
                            l10n.playerQuality,
                            qualityChipLabel(quality),
                          ),
                          enabled: state.sources.length > 1,
                          onSelect: () => _quality(l10n),
                        ),
                      ],
                      const SizedBox(width: 10),
                      TvPlayerChip(
                        index: 2,
                        label: speedLabel(state.speed),
                        name: l10n.tvPlayerChip(
                          l10n.playerSpeed,
                          speedLabel(state.speed),
                        ),
                        onSelect: () => _speed(l10n),
                      ),
                      const SizedBox(width: 10),
                      TvPlayerChip(
                        index: 3,
                        icon: fitIcon(state.fit),
                        label: fitLabel(l10n, state.fit),
                        name: l10n.tvPlayerChip(
                          l10n.playerScreenFit,
                          fitLabel(l10n, state.fit),
                        ),
                        onSelect: () => _fit(l10n),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Above the bar: Start over at the start, Skip intro or Up next
            // at the end.
            TvZone.row(
              order: 11,
              keyline: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (resumed)
                    _ResumedNote(
                      from: state.resumedFrom!,
                      onStartOver: controller.startOver,
                    ),
                  const Spacer(),
                  if (upNext)
                    _UpNextCard(
                      next: next!,
                      upNext: state.upNext,
                      autofocus: stillWatching,
                      onPlayNow: controller.playNext,
                      onHide: controller.hideUpNext,
                    )
                  else if (intro)
                    TvPlayerPill(
                      index: 1,
                      label: l10n.playerSkipIntro,
                      outline: true,
                      onSelect: controller.skipIntro,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  _Clock(
                    position: controller.position,
                    scrub: _scrub,
                    style: timeStyle,
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _seekBar(l10n, state)),
                  const SizedBox(width: 16),
                  _Clock(
                    position: controller.position,
                    scrub: _scrub,
                    remainingOf: state.duration,
                    style: timeStyle.copyWith(color: MarqueeColors.creamSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TvGroup.split(
              order: 13,
              child: Row(
                children: [
                  // A number line in both languages (PLAYER.md §2).
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: TvZone.row(
                      order: 0,
                      initialIndex: 1,
                      keyline: 0,
                      child: Row(
                        children: [
                          TvRoundButton(
                            index: 0,
                            label: l10n.playerSeekBack,
                            icon: Icons.replay,
                            caption: '10',
                            onSelect: () =>
                                controller.seekBy(const Duration(seconds: -10)),
                          ),
                          const SizedBox(width: 18),
                          TvRoundButton(
                            index: 1,
                            primary: true,
                            autofocus: !stillWatching,
                            label: state.playing ? l10n.playerPause : l10n.play,
                            icon: state.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onSelect: controller.togglePlay,
                          ),
                          const SizedBox(width: 18),
                          TvRoundButton(
                            index: 2,
                            label: l10n.playerSeekForward,
                            icon: Icons.replay,
                            flip: true,
                            caption: '10',
                            onSelect: () =>
                                controller.seekBy(const Duration(seconds: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (series)
                    TvZone.row(
                      order: 1,
                      keyline: 0,
                      child: Row(
                        children: [
                          TvPlayerPill(
                            index: 0,
                            icon: Icons.notes_rounded,
                            label: l10n.episodesHeading,
                            onSelect: _episodes,
                          ),
                          const SizedBox(width: 18),
                          TvPlayerPill(
                            index: 1,
                            icon: Icons.skip_next_outlined,
                            iconAtEnd: true,
                            label: l10n.nextEpisode,
                            enabled: next != null,
                            onSelect: controller.playNext,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seekBar(AppLocalizations l10n, PlayerState state) => TvZone.row(
    order: 12,
    keyline: 0,
    child: TvFocusable(
      index: 0,
      label: l10n.playerSeekBar,
      onKey: _barKey,
      onSelect: _barOk,
      builder: (context, focused) => TvSeekBar(
        position: _controller.position,
        buffered: _controller.buffered,
        duration: state.duration,
        scrub: _scrub,
        preview: state.seekPreview,
        aspectRatio: state.aspectRatio,
        focused: focused,
        bubble: _visible,
      ),
    ),
  );
}

/// The time beside the bar: where the video is (or the seek target), or
/// what's left ("−28:18") with [remainingOf]. Only this rebuilds as the
/// video plays.
class _Clock extends StatelessWidget {
  const _Clock({
    required this.position,
    required this.scrub,
    required this.style,
    this.remainingOf,
  });

  final ValueListenable<Duration> position;
  final TvScrub scrub;
  final TextStyle style;
  final Duration? remainingOf;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([position, scrub]),
    builder: (context, _) {
      final at = scrub.target ?? position.value;
      final total = remainingOf;
      return Text(formatClock(total == null ? at : at - total), style: style);
    },
  );
}

/// "Up next · Season 2 · Episode 6" with Play now and Hide (PLAYER.md §7.7;
/// no TV artboard: built from the system sheet's pieces). During the
/// countdown a `bulb` line fills under the text; after 3 automatic episodes
/// it asks "Still watching?". Over the video (controls hidden) it's its own
/// zone [order] in the bottom end corner and takes the focus.
class _UpNextCard extends StatelessWidget {
  const _UpNextCard({
    required this.next,
    required this.upNext,
    required this.onPlayNow,
    required this.onHide,
    this.order,
    this.autofocus = false,
    this.onKey,
  });

  final Episode next;
  final UpNext upNext;
  final VoidCallback onPlayNow;
  final VoidCallback onHide;

  /// Set over the video: the card is a zone of its own there.
  final int? order;
  final bool autofocus;
  final KeyEventResult Function(KeyEvent event)? onKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final asking = upNext == UpNext.stillWatching;
    final still = MediaQuery.disableAnimationsOf(context);
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvButton(
          index: order == null ? 1 : 0,
          primary: true,
          icon: Icons.play_arrow_rounded,
          label: l10n.playerPlayNow,
          autofocus: autofocus,
          onKey: onKey,
          onSelect: onPlayNow,
        ),
        const SizedBox(width: 10),
        TvButton(
          index: order == null ? 2 : 1,
          label: l10n.playerHide,
          onKey: onKey,
          onSelect: onHide,
        ),
      ],
    );
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarqueeColors.booth,
        border: Border.all(color: MarqueeColors.velvet),
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 88,
            height: 50,
            child: MediaImage(
              url: next.imageUrl,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  asking ? l10n.playerStillWatching : l10n.playerUpNext,
                  style: asking
                      ? text.title
                      : text.eyebrow.copyWith(
                          letterSpacing: text.arabic ? 0 : null,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.seasonNumber(next.season)} · '
                  '${episodeLabel(l10n, next.numbering)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: asking ? text.caption : text.label,
                ),
                if (upNext == UpNext.countdown) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 160,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: still ? Duration.zero : upNextCountdown,
                      builder: (context, value, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 3,
                          color: MarqueeColors.bulb,
                          backgroundColor: MarqueeColors.velvet,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                buttons,
              ],
            ),
          ),
        ],
      ),
    );
    final zone = order;
    if (zone == null) return card;
    return PositionedDirectional(
      end: TvSpace.safeH,
      bottom: _aboveBar,
      child: TvZone.row(order: zone, keyline: 0, child: card),
    );
  }
}

/// "Resuming from 14:32", and with the controls Start over (PLAYER.md §7.6).
class _ResumedNote extends StatelessWidget {
  const _ResumedNote({required this.from, this.onStartOver});

  final Duration from;
  final VoidCallback? onStartOver;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final onStartOver = this.onStartOver;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: tvVeil,
            shape: const StadiumBorder(),
          ),
          child: Text(
            l10n.playerResumingFrom(formatClock(from)),
            style: text.label.withWeight(FontWeight.w500),
          ),
        ),
        if (onStartOver != null) ...[
          const SizedBox(width: 10),
          TvPlayerPill(
            index: 0,
            label: l10n.playerStartOver,
            onSelect: onStartOver,
          ),
        ],
      ],
    );
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
            const SizedBox(height: 16),
            Text(label, style: MarqueeTvText.of(context).label),
          ],
        ],
      ),
    );
  }
}

/// Why it can't play, with Try again (focused) and Back; a title with no
/// streams has Back alone, since trying again can't help (PLAYER.md §6).
class _Failure extends StatelessWidget {
  const _Failure({
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
    final message = error is ApiException
        ? errorMessage(l10n, error)
        : unavailable
        ? l10n.playerUnavailable
        : l10n.playerFailed;
    return ColoredBox(
      color: MarqueeColors.night.withValues(alpha: 0.72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: MarqueeTvText.of(context).body
                    .copyWith(color: MarqueeColors.creamSoft),
              ),
              const SizedBox(height: 24),
              TvZone.row(
                order: 20,
                keyline: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!unavailable) ...[
                      TvButton(
                        index: 0,
                        primary: true,
                        autofocus: true,
                        label: l10n.retry,
                        onSelect: onRetry,
                      ),
                      const SizedBox(width: 12),
                    ],
                    TvButton(
                      index: 1,
                      autofocus: unavailable,
                      label: l10n.tvBack,
                      onSelect: onBack,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the screen on while playing. A missing plugin (tests, Linux) just
/// means no wakelock.
Future<void> _wakelock({required bool on}) async {
  try {
    await (on ? WakelockPlus.enable() : WakelockPlus.disable());
  } on Object {
    // Not available here.
  }
}
