import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/media_text.dart';
import '../../features/library/library_providers.dart';
import '../focus/tv_focusable.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';
import 'tv_image.dart';
import 'tv_poster_card.dart';
import 'tv_row.dart';

/// Home's Continue watching row (the TV Home design), zone [order]: the
/// same list as the Library's. OK plays where it was left, or the next
/// episode. Hidden when empty. Removing one is in the Library (docs/TV.md
/// §7.5), so every action stays a visible control (R6).
///
/// The design draws 16:9 artwork, but history only keeps the poster, so the
/// card is the poster beside its text (TV.md §7.1 allows this).
class TvContinueRow extends ConsumerWidget {
  const TvContinueRow({super.key, required this.order, required this.onPlay});

  final int order;
  final void Function(ContinueEntry entry) onPlay;

  static const double cardWidth = 300;
  static const double cardHeight = 117;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(continueEntriesProvider).value ?? const [];
    if (entries.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvSectionTitle(l10n.rowContinueWatching),
        SizedBox(
          height: TvPoster.growRoom - 8 + cardHeight + 16,
          child: TvZone.row(
            order: order,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.fromSTEB(
                TvSpace.safeH,
                TvPoster.growRoom - 8,
                TvSpace.safeH,
                0,
              ),
              itemExtent: cardWidth + 16,
              itemCount: entries.length,
              itemBuilder: (context, i) => Align(
                alignment: AlignmentDirectional.topStart,
                child: _ContinueCard(
                  index: i,
                  entry: entries[i],
                  onSelect: () => onPlay(entries[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.index,
    required this.entry,
    required this.onSelect,
  });

  final int index;
  final ContinueEntry entry;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final p = entry.progress;
    final next = entry.upNext;
    final title = context.titleOf(p.item);
    final String where;
    final String? left;
    if (next != null) {
      where = context.joinMeta([
        l10n.playerUpNext,
        l10n.seasonEpisodeShort(next.season, next.numbering.first),
      ]);
      left = next.duration == null
          ? null
          : formatDuration(l10n, next.duration!);
    } else {
      where = p.season != null && p.episode != null
          ? l10n.seasonEpisodeShort(p.season!, p.episode!)
          : '';
      left = minutesLeft(l10n, p.remaining);
    }
    final meta = context.joinMeta([where, ?left].where((s) => s.isNotEmpty));
    return TvFocusable(
      index: index,
      label: '$title, $meta',
      onSelect: onSelect,
      builder: (context, focused) => SizedBox(
        width: TvContinueRow.cardWidth,
        height: TvContinueRow.cardHeight,
        child: TvCardFocus(
          focused: focused,
          radius: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: focused ? context.palette.boothRaised : context.palette.booth,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: TvContinueRow.cardHeight,
                  child: TvImage(url: p.posterUrl, radius: 12, grows: true),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      14,
                      12,
                      14,
                      14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.label.copyWith(height: 1.25),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.caption.copyWith(
                            color: next != null
                                ? context.palette.bulb
                                : context.palette.dust,
                          ),
                        ),
                        const Spacer(),
                        if (next == null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: p.fraction,
                              minHeight: 4,
                              color: context.palette.bulb,
                              backgroundColor: context.palette.velvet,
                            ),
                          ),
                      ],
                    ),
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
