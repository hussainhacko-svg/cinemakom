import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/media_text.dart';
import '../../data/models/playback_models.dart';
import '../../data/models/playback_request.dart';
import '../../data/models/watch_progress.dart';
import '../../data/repositories/library_repository.dart';
import '../../features/details/details_providers.dart';
import '../../features/details/episode_view.dart';
import '../../features/player/player_controller.dart';
import '../../features/player/player_labels.dart';
import '../focus/tv_focusable.dart';
import '../focus/tv_panel.dart';
import '../focus/tv_zone.dart';
import '../screens/details/tv_episodes.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import '../widgets/tv_focus_look.dart';
import '../widgets/tv_list_row.dart';

/// The player's panels sit over the video, which keeps playing: a 50%
/// veil (the Subtitles design).
const double tvPlayerScrim = 0.5;

/// The pickers' width (the Subtitles design).
const double tvPlayerPanelWidth = 360;

/// One Sync step (PLAYER.md §7.2).
const _syncStep = Duration(milliseconds: 500);

/// Subtitles (the TV Subtitles design, plus Sync, owner's choice 2026-11-20):
/// one row per track with the current one checked, then with a track on a
/// Sync row (−, the delay, +, Reset). It follows the session live: Sync
/// changes in place and the panel stays; picking a track closes it. The
/// size is in Settings. Returns true when a track was picked.
Future<bool?> showTvSubtitlePanel(
  BuildContext context,
  PlaybackRequest request,
) => showTvSidePanel<bool>(
  context,
  width: tvPlayerPanelWidth,
  scrim: tvPlayerScrim,
  builder: (context, scroll) =>
      _SubtitlePanel(request: request, scroll: scroll),
);

class _SubtitlePanel extends ConsumerWidget {
  const _SubtitlePanel({required this.request, required this.scroll});

  final PlaybackRequest request;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final provider = playerControllerProvider(request);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final options = state.subtitles;
    final current = options.indexOf(state.subtitle);
    final delay = state.subtitleDelay;
    final title = l10n.playerSubtitles;
    // The tracks take what they need, Sync follows them, and "Back closes"
    // stays at the bottom.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text.arabic ? title : title.toUpperCase(), style: text.panelTitle),
        const SizedBox(height: 22),
        Flexible(
          child: TvZone.column(
            order: 0,
            initial: true,
            initialIndex: current < 0 ? 0 : current,
            keyline: 0,
            child: ListView.separated(
              controller: scroll,
              shrinkWrap: true,
              // Room for the rows' ring, which the list clips.
              padding: const EdgeInsets.symmetric(
                vertical: 4,
                horizontal: TvFocusStyle.ring,
              ),
              itemCount: options.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => TvListRow(
                index: i,
                label: subtitleLabel(l10n, options[i]),
                selected: i == current,
                onSelect: () {
                  controller.selectSubtitle(options[i]);
                  Navigator.of(context).pop(true);
                },
              ),
            ),
          ),
        ),
        if (!state.subtitle.isOff) ...[
          const SizedBox(height: 20),
          Text(
            l10n.playerSubtitleSync,
            style: text.caption.withWeight(FontWeight.w600),
          ),
          const SizedBox(height: 10),
          // A number line: earlier on the left in both languages, like the
          // seek bar (PLAYER.md §2).
          Directionality(
            textDirection: TextDirection.ltr,
            child: TvZone.row(
              order: 1,
              keyline: 0,
              child: Row(
                children: [
                  _StepButton(
                    index: 0,
                    icon: Icons.remove,
                    label: l10n.playerSyncEarlier,
                    onSelect: () => controller.nudgeSubtitleDelay(-_syncStep),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      l10n.playerSyncSeconds(delayLabel(delay)),
                      textAlign: TextAlign.center,
                      textDirection: Directionality.of(context),
                      style: text.label.copyWith(
                        color: delay == Duration.zero
                            ? MarqueeColors.cream
                            : MarqueeColors.bulb,
                      ),
                    ),
                  ),
                  _StepButton(
                    index: 1,
                    icon: Icons.add,
                    label: l10n.playerSyncLater,
                    onSelect: () => controller.nudgeSubtitleDelay(_syncStep),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _TextButton(
                        index: 2,
                        label: l10n.playerSyncReset,
                        enabled: delay != Duration.zero,
                        onSelect: () =>
                            controller.setSubtitleDelay(Duration.zero),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Align(alignment: Alignment.topCenter, child: content),
        ),
        Text(l10n.tvBackCloses, style: text.caption),
      ],
    );
  }
}

/// − or + of the Sync row: a 48 `boothRaised` circle.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.index,
    required this.icon,
    required this.label,
    required this.onSelect,
  });

  final int index;
  final IconData icon;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => TvFocusable(
    index: index,
    label: label,
    onSelect: onSelect,
    builder: (context, focused) => TvRing(
      on: focused,
      radius: TvRing.pill,
      gap: TvFocusStyle.buttonGap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: MarqueeColors.boothRaised,
          border: Border.all(
            color: focused ? MarqueeColors.velvetStrong : MarqueeColors.velvet,
          ),
        ),
        child: Icon(icon, size: 22, color: MarqueeColors.cream),
      ),
    ),
  );
}

/// Reset: a `bulb` text button, `dustDim` (and skipped) at 0.
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.index,
    required this.label,
    required this.enabled,
    required this.onSelect,
  });

  final int index;
  final String label;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => TvFocusable(
    index: index,
    label: label,
    enabled: enabled,
    onSelect: onSelect,
    builder: (context, focused) => TvRing(
      on: focused,
      radius: TvRing.pill,
      gap: TvFocusStyle.buttonGap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: focused ? MarqueeColors.boothRaised : null,
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MarqueeTvText.of(context).label.copyWith(
            color: enabled ? MarqueeColors.bulb : MarqueeColors.dustDim,
          ),
        ),
      ),
    ),
  );
}

/// The series' episodes without leaving the player (PLAYER.md §7.7): the
/// Details panes (seasons beside episodes, blocks of 50) in a wide panel,
/// opened on the episode playing. Returns the episode picked.
Future<Episode?> showTvEpisodesPanel(
  BuildContext context, {
  required PlaybackRequest request,
  required String currentId,
  required List<Episode> episodes,
}) => showTvSidePanel<Episode>(
  context,
  width: 620,
  scrim: tvPlayerScrim,
  builder: (context, scroll) => _EpisodesPanel(
    request: request,
    currentId: currentId,
    episodes: episodes,
  ),
);

class _EpisodesPanel extends ConsumerStatefulWidget {
  const _EpisodesPanel({
    required this.request,
    required this.currentId,
    required this.episodes,
  });

  final PlaybackRequest request;
  final String currentId;
  final List<Episode> episodes;

  @override
  ConsumerState<_EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends ConsumerState<_EpisodesPanel> {
  int? _season;
  int? _block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final series = widget.request.item;
    final id = series.seriesId;
    // Offline, the player's list (the downloaded episodes) stands in.
    final all = ref.watch(episodesProvider(id)).value ?? widget.episodes;
    final watched =
        ref.watch(seriesProgressProvider(id)).value ??
        const <String, WatchProgress>{};
    final view = EpisodeView(
      all,
      watched,
      currentId: widget.currentId,
      season: _season,
      block: _block,
    );
    final title = l10n.episodesHeading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text.arabic ? title : title.toUpperCase(), style: text.panelTitle),
        const SizedBox(height: 6),
        Text(
          context.titleOf(series),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.caption,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: all.isEmpty
              ? const SizedBox.shrink()
              : TvEpisodes(
                  order: 0,
                  series: series,
                  all: all,
                  view: view,
                  watched: watched,
                  downloads: false,
                  initial: true,
                  heading: false,
                  edge: 0,
                  seasonsWidth: 150,
                  height: double.infinity,
                  currentId: widget.currentId,
                  onPlay: (e) => Navigator.of(context).pop(e),
                  onSelect: (season, block) {
                    if (season == view.season && block == view.block) return;
                    setState(() {
                      _season = season;
                      _block = block;
                    });
                  },
                ),
        ),
        const SizedBox(height: 12),
        Text(l10n.tvBackCloses, style: text.caption),
      ],
    );
  }
}
