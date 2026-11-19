import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/controls.dart';
import '../../../app/widgets/error_view.dart';
import '../../../app/widgets/media_text.dart';
import '../../../app/widgets/section_header.dart';
import '../../../data/models/playback_models.dart';
import '../details_providers.dart';
import '../../../app/widgets/progress_line.dart';
import '../../../data/models/watch_progress.dart';
import '../../../data/repositories/library_repository.dart';

/// A season longer than this is split into blocks of this many episodes,
/// picked with range chips ("1–50", "51–100"), so the page below the list
/// (cast, "More like this") stays in reach: One Piece is one season of
/// 1,179 episodes.
const episodeBlockSize = 50;

/// A series' seasons and episodes (DESIGN.md §5): season chips, range chips
/// for a long season, then one row per episode labelled from its numbering
/// ("Episode 7", "Episodes 7 & 8", a Final badge), never from its title.
///
/// It opens on the season and block of [currentId], else of the episode
/// watched last.
class EpisodeList extends ConsumerStatefulWidget {
  const EpisodeList({
    super.key,
    required this.seriesId,
    required this.gutter,
    required this.onPlay,
    this.initialSeason,
    this.currentId,
  });

  final String seriesId;
  final double gutter;

  /// Plays an episode (opens the player).
  final ValueChanged<Episode> onPlay;

  /// The season to open on (the one of the episode the list showed).
  final int? initialSeason;

  /// The episode playing now, marked in `bulb` (the player's panel).
  final String? currentId;

  @override
  ConsumerState<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends ConsumerState<EpisodeList> {
  int? _season;

  /// The picked block of the season; `null` follows the anchor episode.
  int? _block;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = widget.gutter;
    final episodes = ref.watch(episodesProvider(widget.seriesId));
    final all = episodes.value ?? const <Episode>[];
    final watched =
        ref.watch(seriesProgressProvider(widget.seriesId)).value ?? const {};

    final Widget body;
    if (all.isEmpty) {
      body = episodes.hasError && !episodes.isLoading
          ? ErrorView(
              error: episodes.error!,
              onRetry: () => ref.invalidate(episodesProvider(widget.seriesId)),
              compact: true,
            )
          : episodes.isLoading
          ? Padding(
              padding: const EdgeInsets.all(MarqueeSpace.xxl),
              child: Center(child: BulbLoader(semanticLabel: l10n.loading)),
            )
          : const SizedBox.shrink();
    } else {
      // The episode to open on: the one playing, else the one watched last.
      final anchorId =
          widget.currentId ??
          watched.values
              .fold<WatchProgress?>(
                null,
                (a, b) => a == null || b.updatedAt.isAfter(a.updatedAt) ? b : a,
              )
              ?.videoId;
      final anchor = [
        for (final e in all)
          if (e.id == anchorId) e,
      ].firstOrNull;
      final seasons = {for (final e in all) e.season}.toList()..sort();
      final season = seasons.contains(_season)
          ? _season!
          : seasons.contains(widget.initialSeason)
          ? widget.initialSeason!
          : anchor?.season ?? seasons.first;
      final inSeason = [
        for (final e in all)
          if (e.season == season) e,
      ];
      final blocks = (inSeason.length / episodeBlockSize).ceil();
      final anchorAt = anchor == null ? -1 : inSeason.indexOf(anchor);
      final block =
          (_block ?? (anchorAt < 0 ? 0 : anchorAt ~/ episodeBlockSize)).clamp(
            0,
            blocks - 1,
          );
      final shown = inSeason
          .skip(block * episodeBlockSize)
          .take(episodeBlockSize);
      String range(int b) {
        final first = inSeason[b * episodeBlockSize].numbering.first;
        final last =
            inSeason[math.min((b + 1) * episodeBlockSize, inSeason.length) - 1]
                .numbering
                .last;
        return first == last ? '$first' : l10n.episodeRange(first, last);
      }

      Widget chips(int count, Widget Function(int i) chip) => SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: MarqueeSpace.s),
          itemBuilder: (_, i) => chip(i),
        ),
      );

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (seasons.length > 1)
            chips(
              seasons.length,
              (i) => FilterPill(
                label: l10n.seasonNumber(seasons[i]),
                selected: seasons[i] == season,
                onTap: () => setState(() {
                  _season = seasons[i];
                  _block = null;
                }),
              ),
            ),
          if (blocks > 1) ...[
            if (seasons.length > 1) const SizedBox(height: MarqueeSpace.s),
            _BlockChips(
              key: ValueKey(season),
              count: blocks,
              selected: block,
              label: range,
              onSelect: (b) => setState(() => _block = b),
            ),
          ],
          const SizedBox(height: MarqueeSpace.m),
          for (final e in shown)
            _EpisodeRow(
              episode: e,
              progress: watched[e.id],
              current: e.id == widget.currentId,
              onTap: () => widget.onPlay(e),
            ),
        ],
      );
    }
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        gutter,
        MarqueeSpace.xxl,
        gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: l10n.episodesHeading),
          const SizedBox(height: MarqueeSpace.s),
          body,
        ],
      ),
    );
  }
}

/// The range chips of a long season, built at once (a few dozen at most) so
/// the picked one can be scrolled into view: it can be far along (episode
/// 1,100 of One Piece).
class _BlockChips extends StatefulWidget {
  const _BlockChips({
    super.key,
    required this.count,
    required this.selected,
    required this.label,
    required this.onSelect,
  });

  final int count;
  final int selected;
  final String Function(int block) label;
  final ValueChanged<int> onSelect;

  @override
  State<_BlockChips> createState() => _BlockChipsState();
}

class _BlockChipsState extends State<_BlockChips> {
  final _selected = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(_BlockChips old) {
    super.didUpdateWidget(old);
    // The anchor can arrive after the first frame (watch progress loads).
    if (old.selected != widget.selected) _reveal(animate: true);
  }

  void _reveal({required bool animate}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final chip = _selected.currentContext;
        if (!mounted || chip == null) return;
        Scrollable.ensureVisible(
          chip,
          alignment: 0.5,
          duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
        );
      });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < widget.count; i++) ...[
          if (i > 0) const SizedBox(width: MarqueeSpace.s),
          FilterPill(
            key: i == widget.selected ? _selected : null,
            label: widget.label(i),
            selected: i == widget.selected,
            onTap: () => widget.onSelect(i),
          ),
        ],
      ],
    ),
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.onTap,
    this.progress,
    this.current = false,
  });

  final Episode episode;
  final WatchProgress? progress;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final numbering = episode.numbering;
    final duration = episode.duration;
    final progress = this.progress;
    final finished = progress?.isFinished ?? false;
    final started = progress != null && !finished;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '${numbering.first}'.padLeft(2, '0'),
                    style: text.numeral.copyWith(
                      color: started
                          ? MarqueeColors.bulb
                          : finished
                          ? MarqueeColors.cream
                          : MarqueeColors.dustDim,
                    ),
                  ),
                ),
                const SizedBox(width: MarqueeSpace.s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              episodeLabel(l10n, numbering),
                              style: current
                                  ? text.label.copyWith(
                                      color: MarqueeColors.bulb,
                                    )
                                  : text.label,
                            ),
                          ),
                          if (numbering.isFinale) ...[
                            const SizedBox(width: MarqueeSpace.s),
                            _Badge(l10n.finalEpisode),
                          ],
                        ],
                      ),
                      if (started)
                        Text(
                          minutesLeft(l10n, progress.remaining),
                          style: text.caption,
                        )
                      else if (duration != null)
                        Text(
                          formatDuration(l10n, duration),
                          style: text.caption,
                        ),
                      if (started) ...[
                        const SizedBox(height: MarqueeSpace.xs),
                        ProgressLine(value: progress.fraction),
                      ],
                    ],
                  ),
                ),
                if (current)
                  const Icon(
                    Icons.play_arrow,
                    size: 22,
                    color: MarqueeColors.bulb,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 5,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: MarqueeColors.velvetStrong),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(
        text.arabic ? label : label.toUpperCase(),
        style: text.caption.copyWith(
          fontSize: 10,
          color: MarqueeColors.cream,
          letterSpacing: text.arabic ? 0 : 0.6,
        ),
      ),
    );
  }
}
