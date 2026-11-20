import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/playback_models.dart';
import '../../../data/models/playback_request.dart';
import '../../../data/models/watch_progress.dart';
import '../../../features/details/episode_view.dart';
import '../../focus/tv_focusable.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_downloads.dart';
import '../../widgets/tv_focus_look.dart';
import '../../widgets/tv_row.dart';

/// One entry of the seasons column: a season, or one block of 50 of a long
/// season ("1–50"; [block] set).
typedef _Entry = ({int season, int? block});

/// Details' episodes on TV (docs/TV.md §7.3–7.4, the two-pane design): the
/// seasons column beside the episodes, a split (zone [order]).
/// - Moving onto a season shows its episodes, no OK needed. A long season
///   (over 50 episodes) lists its blocks under it; a one-season show like
///   One Piece lists only the blocks.
/// - Right enters the episodes where they were left (else the one playing or
///   watched last); Left from an episode goes back to the selected season.
/// - Each episode row is two cells, the episode (OK plays it) and its
///   download button, so Up and Down keep the cell: a whole season can be
///   downloaded one by one going down the button column.
/// Both columns scroll by themselves under one heading.
class TvEpisodes extends StatelessWidget {
  const TvEpisodes({
    super.key,
    required this.order,
    required this.series,
    required this.all,
    required this.view,
    required this.watched,
    required this.onSelect,
  });

  final int order;
  final MediaItem series;
  final List<Episode> all;
  final EpisodeView view;
  final Map<String, WatchProgress> watched;
  final void Function(int season, int? block) onSelect;

  static const double height = 360;

  List<_Entry> _entries() {
    final entries = <_Entry>[];
    for (final s in view.seasons) {
      final count = all.where((e) => e.season == s).length;
      final blocks = (count / episodeBlockSize).ceil();
      if (blocks <= 1 || view.seasons.length > 1) {
        entries.add((season: s, block: null));
      }
      if (blocks > 1) {
        for (var b = 0; b < blocks; b++) {
          entries.add((season: s, block: b));
        }
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = _entries();
    var selected = entries.indexWhere(
      (e) => e.season == view.season && e.block == view.block,
    );
    if (selected < 0) {
      selected = entries.indexWhere((e) => e.season == view.season);
    }
    final shown = view.shown;
    final anchorAt = view.anchor == null ? -1 : shown.indexOf(view.anchor!);
    final digits = shown.fold<int>(
      2,
      (w, e) =>
          '${e.numbering.first}'.length > w ? '${e.numbering.first}'.length : w,
    );

    String entryLabel(_Entry e) {
      final block = e.block;
      if (block == null) return l10n.seasonNumber(e.season);
      final (first, last) = EpisodeView(
        all,
        watched,
        season: e.season,
      ).range(block);
      return first == last ? '$first' : l10n.episodeRange(first, last);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvSectionTitle(l10n.episodesHeading),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: TvGroup.split(
            order: order,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: TvSpace.safeH + 210,
                  child: TvZone.column(
                    order: 0,
                    initialIndex: selected < 0 ? 0 : selected,
                    pageWhole: true,
                    keyline: 0,
                    child: ListView.separated(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        TvSpace.safeH,
                        8,
                        0,
                        8,
                      ),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return _SeasonEntry(
                          index: i,
                          label: entryLabel(e),
                          block: e.block != null,
                          selected: i == selected,
                          onFocus: () => onSelect(e.season, e.block),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: TvZone.grid(
                    // A new season or block starts on its anchor episode.
                    key: ValueKey((view.season, view.block)),
                    order: 1,
                    columns: 2,
                    initialIndex: anchorAt < 0 ? 0 : anchorAt * 2,
                    pageWhole: true,
                    keyline: 0,
                    child: ListView.separated(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        0,
                        8,
                        TvSpace.safeH,
                        8,
                      ),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => Row(
                        children: [
                          Expanded(
                            child: _EpisodeCell(
                              index: i * 2,
                              episode: shown[i],
                              progress: watched[shown[i].id],
                              numeralWidth: 18.0 * digits + 16,
                              onSelect: () => tvOpenPlayer(
                                context,
                                PlaybackRequest(
                                  item: series,
                                  episode: shown[i],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          TvEpisodeDownloadButton(
                            index: i * 2 + 1,
                            series: series,
                            episode: shown[i],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SeasonEntry extends StatelessWidget {
  const _SeasonEntry({
    required this.index,
    required this.label,
    required this.block,
    required this.selected,
    required this.onFocus,
  });

  final int index;
  final String label;
  final bool block;
  final bool selected;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: label,
      onFocus: onFocus,
      onSelect: onFocus,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 12,
        child: Container(
          height: 48,
          alignment: AlignmentDirectional.centerStart,
          padding: EdgeInsetsDirectional.only(start: block ? 32 : 16, end: 16),
          decoration: BoxDecoration(
            color: selected || focused ? MarqueeColors.boothRaised : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.body
                .withWeight(selected ? FontWeight.w600 : FontWeight.w500)
                .copyWith(
                  height: 1.2,
                  color: selected ? MarqueeColors.bulb : MarqueeColors.dust,
                ),
          ),
        ),
      ),
    );
  }
}

/// An episode's play cell (the TV episodes design): the numeral (`bulb`
/// when started, `cream` when watched, `dustDim` when new), "Episode 6",
/// its length and how much is left, with a bar while it's under way.
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.index,
    required this.episode,
    required this.numeralWidth,
    required this.onSelect,
    this.progress,
  });

  final int index;
  final Episode episode;
  final WatchProgress? progress;
  final double numeralWidth;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final progress = this.progress;
    final finished = progress?.isFinished ?? false;
    final started = progress != null && !finished;
    final label = episodeLabel(l10n, episode.numbering);
    final meta = context.joinMeta([
      if (episode.duration case final d?) formatDuration(l10n, d),
      if (started)
        minutesLeft(l10n, progress.remaining)
      else if (finished)
        l10n.tvWatched,
    ]);
    return TvFocusable(
      index: index,
      label: meta.isEmpty ? label : '$label, $meta',
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 12,
        child: Container(
          height: 60,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: focused ? MarqueeColors.boothRaised : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: numeralWidth,
                child: Text(
                  '${episode.numbering.first}'.padLeft(2, '0'),
                  maxLines: 1,
                  softWrap: false,
                  style: text.numeral.copyWith(
                    fontSize: 32,
                    color: started
                        ? MarqueeColors.bulb
                        : finished
                        ? MarqueeColors.cream
                        : MarqueeColors.dustDim,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.body
                                .withWeight(FontWeight.w600)
                                .copyWith(
                                  height: 1.2,
                                  color: MarqueeColors.cream,
                                ),
                          ),
                        ),
                        if (episode.numbering.isFinale) ...[
                          const SizedBox(width: 8),
                          Text(
                            l10n.finalEpisode,
                            style: text.caption.copyWith(
                              color: MarqueeColors.bulb,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) Text(meta, style: text.caption),
                    if (started) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 240,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress.fraction,
                            minHeight: 4,
                            color: MarqueeColors.bulb,
                            backgroundColor: MarqueeColors.velvet,
                          ),
                        ),
                      ),
                    ],
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
