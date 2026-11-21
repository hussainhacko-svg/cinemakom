import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/media_text.dart';
import '../../data/models/media_item.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';
import 'tv_image.dart';

/// Poster card sizes on TV (the Home rows and Genre designs).
abstract final class TvPoster {
  static const double width = 120;
  static const double height = 180;
  static const double radius = 10;

  /// The gap between cards in a row.
  static const double gap = 18;

  /// The card with its title and meta.
  static const double cardHeight = 230;

  /// Room above a row for a focused card's grow and ring (180 × 0.08, plus
  /// the 3 px ring 3 px out).
  static const double growRoom = 22;
}

/// A poster with its title and "2023 · Drama" under it, item [index] of its
/// zone. Focused: it grows from its bottom edge (so the title stays clear)
/// with the ring, and the title goes from `creamSoft` 500 to `cream` 600.
class TvPosterCard extends StatelessWidget {
  const TvPosterCard({
    super.key,
    required this.index,
    required this.item,
    required this.onSelect,
    this.onFocus,
  });

  final int index;
  final MediaItem item;
  final VoidCallback onSelect;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    final title = context.titleOf(item);
    final meta = context.cardMeta(item);
    return TvFocusable(
      index: index,
      label: title,
      onSelect: onSelect,
      onFocus: onFocus,
      builder: (context, focused) => SizedBox(
        width: TvPoster.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: TvPoster.width,
              height: TvPoster.height,
              child: TvCardFocus(
                focused: focused,
                radius: TvPoster.radius,
                child: TvImage(
                  url: item.posterUrl,
                  hdUrl: item.hdPosterUrl,
                  radius: TvPoster.radius,
                  grows: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.label
                  .withWeight(FontWeight.w500)
                  .copyWith(
                    height: 1.3,
                    color: focused
                        ? MarqueeColors.cream
                        : MarqueeColors.creamSoft,
                  ),
            ),
            if (meta.isNotEmpty)
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.caption,
              ),
          ],
        ),
      ),
    );
  }
}

/// The last card of a row: "See all", poster-sized (the Home rows design).
class TvSeeAllCard extends StatelessWidget {
  const TvSeeAllCard({super.key, required this.index, required this.onSelect});

  final int index;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: l10n.seeAll,
      onSelect: onSelect,
      builder: (context, focused) => Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: TvPoster.width,
          height: TvPoster.height,
          child: TvCardFocus(
            focused: focused,
            radius: TvPoster.radius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: focused
                    ? MarqueeColors.boothRaised
                    : MarqueeColors.booth,
                borderRadius: BorderRadius.circular(TvPoster.radius),
                border: Border.all(color: MarqueeColors.velvet),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.arrow_forward,
                    size: 28,
                    color: MarqueeColors.bulb,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.seeAll,
                    style: text.label.copyWith(color: MarqueeColors.bulb),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A poster-sized `booth` block for a row or grid that's still loading. Not
/// focusable (R5).
class TvPosterPlaceholder extends StatelessWidget {
  const TvPosterPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: Container(
      width: TvPoster.width,
      height: TvPoster.height,
      decoration: BoxDecoration(
        color: MarqueeColors.booth,
        borderRadius: BorderRadius.circular(TvPoster.radius),
      ),
    ),
  );
}
