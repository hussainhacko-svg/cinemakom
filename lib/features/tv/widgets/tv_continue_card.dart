import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/choice_picker.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../app/widgets/progress_line.dart';
import '../../../data/repositories/library_repository.dart';
import '../../library/library_providers.dart';
import '../../library/widgets/continue_card.dart' show playContinue;
import 'tv_focus.dart';

/// A 10-foot TV continue card with clean sibling focus targets:
/// - the main card (D-pad OK plays or opens [onTap]),
/// - optional [trailing] button (e.g. Library's Play button),
/// - a Remove (`close`) button reachable with D-pad Right.
class TvContinueCard extends ConsumerStatefulWidget {
  const TvContinueCard({
    super.key,
    required this.entry,
    this.onTap,
    this.trailing,
  });

  final ContinueEntry entry;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  ConsumerState<TvContinueCard> createState() => _TvContinueCardState();
}

class _TvContinueCardState extends ConsumerState<TvContinueCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final entry = widget.entry;
    final p = entry.progress;
    final next = entry.upNext;
    final item = p.item;
    final title = context.titleOf(item);

    Future<void> offerRemove() async {
      final remove = await showChoicePicker(
        context,
        title: title,
        choices: [Choice(true, l10n.removeFromContinue)],
        selected: false,
      );
      if (remove ?? false) {
        await ref.read(libraryRepositoryProvider).hideFromContinue(p.titleId);
      }
    }

    final Widget where;
    final double? progress;
    final String? left;
    if (next != null) {
      where = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l10n.playerUpNext,
              style: const TextStyle(color: MarqueeColors.bulb),
            ),
            TextSpan(
              text:
                  ' · ${l10n.seasonNumber(next.season)}'
                  ' · ${episodeLabel(l10n, next.numbering)}',
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.caption,
      );
      progress = null;
      left = next.duration == null
          ? null
          : formatDuration(l10n, next.duration!);
    } else {
      final season = p.season;
      final episode = p.episode;
      where = season != null && episode != null
          ? Text(
              '${l10n.seasonNumber(season)} · ${l10n.episodeNumber(episode)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.caption,
            )
          : const SizedBox.shrink();
      progress = p.fraction;
      left = minutesLeft(l10n, p.remaining);
    }

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l10n.removeFromContinue): offerRemove,
      },
      child: Material(
        color: MarqueeColors.booth,
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: _focused
                    ? MarqueeColors.boothRaised
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(MarqueeRadius.card),
                  side: _focused
                      ? const BorderSide(color: MarqueeColors.bulb, width: 2)
                      : BorderSide.none,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: const BorderRadius.all(MarqueeRadius.card),
                  onTap: widget.onTap ?? () => playContinue(context, entry),
                  onFocusChange: (f) {
                    setState(() => _focused = f);
                    if (f) tvEnsureVisible(context, alignment: 0.35);
                  },
                  focusColor: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.all(MarqueeSpace.s),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 84,
                          child: MediaImage(
                            url: item.hdPosterUrl ?? item.posterUrl,
                            borderRadius: const BorderRadius.all(
                              MarqueeRadius.thumb,
                            ),
                            decodeScale: 2.0,
                            filterQuality: FilterQuality.medium,
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
                              where,
                              if (progress != null) ...[
                                const SizedBox(height: MarqueeSpace.s),
                                ProgressLine(value: progress),
                              ],
                              if (left != null) ...[
                                const SizedBox(height: MarqueeSpace.xs),
                                Text(left, style: text.caption),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.trailing case final trailing?)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: MarqueeSpace.xs),
                child: trailing,
              ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: MarqueeSpace.xs),
              child: IconButton(
                tooltip: l10n.removeFromContinue,
                onPressed: offerRemove,
                icon: const Icon(
                  Icons.more_vert,
                  size: 20,
                  color: MarqueeColors.dust,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
