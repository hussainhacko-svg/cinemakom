import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/error_view.dart';
import '../../data/models/media_item.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_button.dart';
import 'tv_poster_card.dart';

/// A section title ("LATEST MOVIES"): uppercase in Latin only.
class TvSectionTitle extends StatelessWidget {
  const TvSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: TvSpace.safeH,
        end: TvSpace.safeH,
      ),
      child: Text(
        text.arabic ? title : title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.sectionTitle,
      ),
    );
  }
}

/// A row of posters (the Home rows design), zone [order] of its screen: the
/// header (not focusable), the cards, and "See all" as the last card when
/// [onSeeAll] is set. Loading shows `booth` blocks (not focusable, R5); a
/// failed load shows the error with Try again in place of the cards; an
/// empty row shows nothing.
class TvPosterRow extends StatelessWidget {
  const TvPosterRow({
    super.key,
    required this.order,
    required this.title,
    required this.items,
    required this.onOpen,
    this.onSeeAll,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final int order;
  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item) onOpen;
  final VoidCallback? onSeeAll;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  static const double height =
      TvPoster.growRoom + TvPoster.cardHeight + TvSpace.safeV / 3;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && !loading && error == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final Widget body;
    if (items.isEmpty && error != null) {
      body = Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          TvSpace.safeH,
          TvPoster.growRoom,
          TvSpace.safeH,
          0,
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                errorMessage(l10n, error!),
                style: text.body.copyWith(color: context.palette.dust),
              ),
            ),
            const SizedBox(width: 20),
            TvZone.row(
              order: order,
              child: TvButton(index: 0, label: l10n.retry, onSelect: onRetry),
            ),
          ],
        ),
      );
    } else {
      final count = loading && items.isEmpty
          ? 7
          : items.length + (onSeeAll != null ? 1 : 0);
      body = SizedBox(
        height: height,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.fromSTEB(
            TvSpace.safeH,
            TvPoster.growRoom,
            TvSpace.safeH,
            0,
          ),
          itemExtent: TvPoster.width + TvPoster.gap,
          itemCount: count,
          itemBuilder: (context, i) {
            if (items.isEmpty) return const TvPosterPlaceholder();
            final card = i < items.length
                ? TvPosterCard(
                    index: i,
                    item: items[i],
                    onSelect: () => onOpen(items[i]),
                  )
                : TvSeeAllCard(index: i, onSelect: onSeeAll!);
            return Align(alignment: AlignmentDirectional.topStart, child: card);
          },
        ),
      );
      // The title is inside the zone, so the page scrolls it, not the
      // posters, to the top keyline (R10) and it isn't pushed against the
      // screen edge.
      return TvZone.row(
        order: order,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [TvSectionTitle(title), body],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [TvSectionTitle(title), body],
    );
  }
}
