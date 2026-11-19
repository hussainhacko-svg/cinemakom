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

/// A series' seasons and episodes (DESIGN.md §5): season chips, then one row
/// per episode labelled from its numbering ("Episode 7", "Episodes 7 & 8",
/// a Final badge), never from its title.
class EpisodeList extends ConsumerStatefulWidget {
  const EpisodeList({
    super.key,
    required this.seriesId,
    required this.gutter,
    required this.onPlay,
    this.initialSeason,
  });

  final String seriesId;
  final double gutter;

  /// Plays an episode (opens the player).
  final ValueChanged<Episode> onPlay;

  /// The season to open on (the one of the episode the list showed).
  final int? initialSeason;

  @override
  ConsumerState<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends ConsumerState<EpisodeList> {
  int? _season;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gutter = widget.gutter;
    final episodes = ref.watch(episodesProvider(widget.seriesId));
    final all = episodes.value ?? const <Episode>[];

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
      final seasons = {for (final e in all) e.season}.toList()..sort();
      final season = seasons.contains(_season)
          ? _season!
          : seasons.contains(widget.initialSeason)
          ? widget.initialSeason!
          : seasons.first;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (seasons.length > 1)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: MarqueeSpace.s),
                itemBuilder: (_, i) => FilterPill(
                  label: l10n.seasonNumber(seasons[i]),
                  selected: seasons[i] == season,
                  onTap: () => setState(() => _season = seasons[i]),
                ),
              ),
            ),
          const SizedBox(height: MarqueeSpace.m),
          for (final e in all)
            if (e.season == season)
              _EpisodeRow(episode: e, onTap: () => widget.onPlay(e)),
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

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.onTap});

  final Episode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final numbering = episode.numbering;
    final duration = episode.duration;
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
                    style: text.numeral.copyWith(color: MarqueeColors.dustDim),
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
                              style: text.label,
                            ),
                          ),
                          if (numbering.isFinale) ...[
                            const SizedBox(width: MarqueeSpace.s),
                            _Badge(l10n.finalEpisode),
                          ],
                        ],
                      ),
                      if (duration != null)
                        Text(
                          formatDuration(l10n, duration),
                          style: text.caption,
                        ),
                    ],
                  ),
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
