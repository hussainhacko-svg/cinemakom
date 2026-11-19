import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/choice_picker.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../app/widgets/progress_line.dart';
import '../../../data/models/playback_request.dart';
import '../../../data/repositories/library_repository.dart';
import '../library_providers.dart';

/// Plays [entry]: the next episode when it offers one, otherwise the movie
/// or episode where it was left (the player resumes by itself).
void playContinue(BuildContext context, ContinueEntry entry) {
  final p = entry.progress;
  openPlayer(
    context,
    entry.upNext != null
        ? PlaybackRequest(item: p.item, episode: entry.upNext)
        : PlaybackRequest(
            item: p.item,
            episodeId: p.isSeries ? p.videoId : null,
          ),
  );
}

/// A continue card (DESIGN.md §5): `booth` row (radius 12, padding 8), a
/// 56 × 84 poster, the title, "Season 2 · Episode 5", a progress bar and
/// "14 min left". A finished episode shows the next one instead: "Up next"
/// in `bulb`, its number and its length, without a bar.
///
/// A tap runs [onTap] (default: [playContinue]). A long press, or a right
/// click, offers "Remove from Continue watching", which hides the title
/// until it is watched again.
class ContinueCard extends ConsumerWidget {
  const ContinueCard({
    super.key,
    required this.entry,
    this.onTap,
    this.trailing,
  });

  final ContinueEntry entry;
  final VoidCallback? onTap;

  /// Shown at the end edge (the Library's play button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
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
      progress = null; // Not started: no bar.
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
        child: InkWell(
          borderRadius: const BorderRadius.all(MarqueeRadius.card),
          onTap: onTap ?? () => playContinue(context, entry),
          onLongPress: offerRemove,
          onSecondaryTap: offerRemove,
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
                if (trailing case final trailing?) ...[
                  const SizedBox(width: MarqueeSpace.m),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
