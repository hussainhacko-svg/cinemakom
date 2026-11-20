import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_text.dart';
import '../player_controller.dart';
import '../player_state.dart';
import '../quality.dart';
import '../subtitles.dart';
import 'chip_menus.dart' show anchorOf;
import 'seek_bar.dart';

/// Opens a chip's menu under [anchor] (the chip's place on screen).
typedef MenuOpener = void Function(Rect anchor);

/// The player's controls over a 60% `night` scrim (DESIGN.md §8):
/// - top: back, title and episode, then the subtitle, quality, speed and fit
///   chips (one "⋯" chip below [narrowWidth]);
/// - centre: back 10 s, play/pause, forward 10 s;
/// - bottom: elapsed time, the seek bar, remaining time, then Episodes and
///   Next episode for a series.
///
/// The seek row and the centre buttons keep their physical layout in
/// Arabic (PLAYER.md §2); the top bar follows the text direction.
class ControlsOverlay extends StatelessWidget {
  const ControlsOverlay({
    super.key,
    required this.state,
    required this.controller,
    required this.busy,
    required this.onBack,
    required this.onSubtitles,
    required this.onQuality,
    required this.onSpeed,
    required this.onFit,
    required this.onMore,
    required this.onScrub,
    this.onEpisodes,
    this.playPauseFocusNode,
    this.trailing = const [],
  });

  final PlayerState state;
  final PlayerController controller;

  /// Loading or buffering: the play button makes room for the loader.
  final bool busy;
  final VoidCallback onBack;
  final MenuOpener onSubtitles;
  final MenuOpener onQuality;
  final MenuOpener onSpeed;

  /// Cycles Fit → Fill → Stretch (PLAYER.md §7.4).
  final VoidCallback onFit;

  /// The "⋯" chip on narrow screens.
  final MenuOpener onMore;
  final ValueChanged<Duration?> onScrub;

  /// Opens the Episodes panel (series only).
  final VoidCallback? onEpisodes;

  /// Focus node on the centre Play/Pause button (TV D-pad reveal).
  final FocusNode? playPauseFocusNode;

  /// Extra top-bar buttons (fullscreen on desktop, the lock on mobile).
  final List<Widget> trailing;

  static const _seekStep = Duration(seconds: 10);

  /// Below this width the chips fold into one "⋯" chip (PLAYER.md §8).
  static const narrowWidth = 480.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 600 ? MarqueeSpace.xxxl : MarqueeSpace.l;
    final item = state.details?.item ?? state.request.item;
    final episode = state.episode;
    final subtitleLine = episode == null
        ? null
        : '${l10n.seasonNumber(episode.season)} · '
              '${episodeLabel(l10n, episode.numbering)}';
    final quality = state.quality;
    final next = state.nextEpisode;

    final topBar = Row(
      children: [
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, size: 24),
          style: withFocusRing(
            IconButton.styleFrom(
              foregroundColor: MarqueeColors.cream,
              fixedSize: const Size.square(44),
            ),
          ),
        ),
        const SizedBox(width: MarqueeSpace.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.titleOf(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.title.copyWith(fontSize: 18),
              ),
              if (subtitleLine != null) Text(subtitleLine, style: text.caption),
            ],
          ),
        ),
        const SizedBox(width: MarqueeSpace.s),
        if (width < narrowWidth)
          _Chip(
            icon: Icons.more_horiz,
            tooltip: l10n.playerMore,
            onPressed: onMore,
          )
        else ...[
          _Chip(
            icon: Icons.subtitles_outlined,
            label: subtitleLabel(l10n, state.subtitle),
            tooltip: l10n.playerSubtitles,
            onPressed: state.subtitles.length > 1 ? onSubtitles : null,
          ),
          if (quality != null)
            _Chip(
              label: qualityChipLabel(quality),
              tooltip: l10n.playerQuality,
              onPressed: state.sources.length > 1 ? onQuality : null,
            ),
          _Chip(
            label: speedLabel(state.speed),
            tooltip: l10n.playerSpeed,
            onPressed: onSpeed,
          ),
          _Chip(
            icon: fitIcon(state.fit),
            tooltip: l10n.playerScreenFit,
            onPressed: (_) => onFit(),
          ),
        ],
        ...trailing,
      ],
    );

    final ended = state.phase == PlayerPhase.ended;
    final centre = Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SeekButton(
            icon: Icons.replay_10,
            tooltip: l10n.playerSeekBack,
            onPressed: () => controller.seekBy(-_seekStep),
          ),
          const SizedBox(width: 56),
          SizedBox.square(
            dimension: 76,
            child: busy
                ? null
                : IconButton(
                    focusNode: playPauseFocusNode,
                    tooltip: state.playing ? l10n.playerPause : l10n.play,
                    onPressed: controller.togglePlay,
                    style: withFocusRing(
                      IconButton.styleFrom(
                        backgroundColor: MarqueeColors.bulb,
                        foregroundColor: MarqueeColors.onBulb,
                        hoverColor: MarqueeColors.bulbBright,
                        fixedSize: const Size.square(76),
                      ),
                      color: MarqueeColors.cream,
                    ),
                    icon: Icon(
                      ended
                          ? Icons.replay
                          : state.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 40,
                    ),
                  ),
          ),
          const SizedBox(width: 56),
          _SeekButton(
            icon: Icons.forward_10,
            tooltip: l10n.playerSeekForward,
            onPressed: () => controller.seekBy(_seekStep),
          ),
        ],
      ),
    );

    final clockStyle = text.label.copyWith(color: MarqueeColors.cream);
    final bottomBar = Row(
      children: [
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              children: [
                PlayerClock(
                  position: controller.position,
                  duration: state.duration,
                  style: clockStyle,
                ),
                const SizedBox(width: MarqueeSpace.m),
                Expanded(
                  child: SeekBar(
                    position: controller.position,
                    buffered: controller.buffered,
                    duration: state.duration,
                    onSeek: controller.seek,
                    onScrub: onScrub,
                    preview: state.seekPreview,
                    aspectRatio: state.aspectRatio,
                    semanticLabel: l10n.playerSeekBar,
                  ),
                ),
                const SizedBox(width: MarqueeSpace.m),
                PlayerClock(
                  position: controller.position,
                  duration: state.duration,
                  remaining: true,
                  style: clockStyle.copyWith(color: MarqueeColors.dust),
                ),
              ],
            ),
          ),
        ),
        if (onEpisodes case final open? when state.episodes.length > 1) ...[
          const SizedBox(width: MarqueeSpace.l),
          TextButton.icon(
            onPressed: open,
            icon: const Icon(Icons.video_library_outlined, size: 22),
            label: Text(l10n.episodesHeading),
            style: withFocusRing(
              TextButton.styleFrom(
                foregroundColor: MarqueeColors.cream,
                minimumSize: const Size(44, 44),
              ),
            ),
          ),
        ],
        if (next != null) ...[
          const SizedBox(width: MarqueeSpace.s),
          TextButton.icon(
            onPressed: () => controller.playEpisode(next),
            icon: const Icon(Icons.skip_next_outlined, size: 22),
            iconAlignment: IconAlignment.end,
            label: Text(l10n.nextEpisode),
            style: withFocusRing(
              TextButton.styleFrom(
                foregroundColor: MarqueeColors.cream,
                minimumSize: const Size(44, 44),
              ),
            ),
          ),
        ],
      ],
    );

    return ColoredBox(
      color: MarqueeColors.night.withValues(alpha: 0.6),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            gutter,
            MarqueeSpace.m,
            gutter,
            MarqueeSpace.s,
          ),
          child: Column(
            children: [
              topBar,
              Expanded(child: Center(child: centre)),
              bottomBar,
            ],
          ),
        ),
      ),
    );
  }
}

/// An outlined pill in the top bar (subtitles, quality, speed, fit).
class _Chip extends StatelessWidget {
  const _Chip({this.icon, this.label, required this.tooltip, this.onPressed});

  final IconData? icon;
  final String? label;
  final String tooltip;
  final MenuOpener? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = withFocusRing(
      TextButton.styleFrom(
        backgroundColor: MarqueeColors.booth,
        foregroundColor: MarqueeColors.cream,
        disabledForegroundColor: MarqueeColors.dust,
        side: const BorderSide(color: MarqueeColors.velvet),
        shape: const StadiumBorder(),
        minimumSize: const Size(44, 44),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: label == null ? 0 : MarqueeSpace.l,
        ),
        textStyle: MarqueeText.of(context).label.copyWith(fontSize: 15),
      ),
    );
    final text = label;
    final glyph = icon;
    final open = onPressed;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: MarqueeSpace.s),
      child: Tooltip(
        message: tooltip,
        child: Builder(
          builder: (context) {
            final onPressed = open == null
                ? null
                : () => open(anchorOf(context));
            return text == null
                ? TextButton(
                    onPressed: onPressed,
                    style: style,
                    child: Icon(glyph, size: 20),
                  )
                : glyph == null
                ? TextButton(
                    onPressed: onPressed,
                    style: style,
                    child: Text(text),
                  )
                : TextButton.icon(
                    onPressed: onPressed,
                    style: style,
                    icon: Icon(glyph, size: 18),
                    label: Text(text),
                  );
          },
        ),
      ),
    );
  }
}

class _SeekButton extends StatelessWidget {
  const _SeekButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 36),
    style: withFocusRing(
      IconButton.styleFrom(
        foregroundColor: MarqueeColors.cream,
        fixedSize: const Size.square(56),
      ),
    ),
  );
}

/// A 2 px ring (default `bulb`) while the button has keyboard/D-pad focus
/// (DESIGN.md §5), over the button's own border otherwise.
ButtonStyle withFocusRing(
  ButtonStyle style, {
  Color color = MarqueeColors.bulb,
}) {
  final rest = style.side;
  return style.copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: color, width: 2)
          : rest?.resolve(states),
    ),
  );
}

IconData fitIcon(VideoFit fit) => switch (fit) {
  VideoFit.fit => Icons.fit_screen_outlined,
  VideoFit.fill => Icons.crop_free,
  VideoFit.stretch => Icons.aspect_ratio,
};

/// "Fit", "Fill", "Stretch".
String fitLabel(AppLocalizations l10n, VideoFit fit) => switch (fit) {
  VideoFit.fit => l10n.playerFit,
  VideoFit.fill => l10n.playerFill,
  VideoFit.stretch => l10n.playerStretch,
};

/// "1×", "1.25×". Wrapped in a left-to-right isolate, or Arabic text
/// shows "×1".
String speedLabel(double speed) {
  final s = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '\u2066$s×\u2069';
}

/// The subtitle menu and chip label for [option].
String subtitleLabel(AppLocalizations l10n, SubtitleOption option) {
  if (option.isOff) return l10n.subtitleOff;
  if (option.isStyled) return l10n.subtitleStyledArabic;
  return switch (option.languageCode) {
    'ar' => l10n.subtitleArabic,
    'en' => l10n.subtitleEnglish,
    final code => code?.toUpperCase() ?? l10n.subtitleOff,
  };
}
