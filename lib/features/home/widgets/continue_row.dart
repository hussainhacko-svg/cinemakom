import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../app/widgets/progress_line.dart';
import '../../../app/widgets/section_header.dart';
import '../../../data/models/playback_request.dart';
import '../../../data/models/watch_progress.dart';
import '../../../data/repositories/library_repository.dart';

/// Home's Continue watching row (DESIGN.md §5 continue cards): the latest
/// unfinished movie or episode of each title. A tap plays it where it was
/// left. Hidden when empty.
class ContinueRow extends ConsumerWidget {
  const ContinueRow({super.key});

  static const _cardWidth = 300.0;
  static const _cardHeight = 100.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueWatchingProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: gutter,
              end: gutter - MarqueeSpace.s,
              bottom: MarqueeSpace.s,
            ),
            child: SectionHeader(
              title: AppLocalizations.of(context).rowContinueWatching,
            ),
          ),
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: MarqueeSpace.m),
              itemBuilder: (_, i) => SizedBox(
                width: _cardWidth,
                child: ContinueCard(progress: items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `booth` row (radius 12, padding 8): poster, title, "Season 2 · Episode
/// 5", a progress bar and "14 min left".
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.progress});

  final WatchProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final p = progress;
    final item = p.item;
    final season = p.season;
    final episode = p.episode;
    final title = context.titleOf(item);
    return Material(
      color: MarqueeColors.booth,
      borderRadius: const BorderRadius.all(MarqueeRadius.card),
      child: InkWell(
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        // The player resumes the saved position by itself.
        onTap: () => openPlayer(
          context,
          PlaybackRequest(
            item: item,
            episodeId: p.isSeries ? p.videoId : null,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(MarqueeSpace.s),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 84,
                child: MediaImage(
                  url: item.posterUrl,
                  borderRadius: const BorderRadius.all(MarqueeRadius.thumb),
                ),
              ),
              const SizedBox(width: MarqueeSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.label,
                    ),
                    if (season != null && episode != null)
                      Text(
                        '${l10n.seasonNumber(season)} · '
                        '${l10n.episodeNumber(episode)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption,
                      ),
                    const SizedBox(height: MarqueeSpace.s),
                    ProgressLine(value: p.fraction),
                    const SizedBox(height: MarqueeSpace.xs),
                    Text(minutesLeft(l10n, p.remaining), style: text.caption),
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
