import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/error_view.dart';
import '../../data/models/media_item.dart';
import '../../data/paging/media_sources.dart';
import '../../data/paging/paged_media.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_button.dart';
import 'tv_poster_card.dart';

/// Posters per row in a TV grid (the Genre design: 6 at 960 dp).
const tvGridColumns = 6;

/// A [source]'s titles as an infinitely paged grid of posters (docs/TV.md
/// §7.2), zone [order], as slivers for the page's scroll view. The next
/// page loads when focus gets within 2 rows of the end (R10). While a page
/// loads a row of `booth` blocks shows (not focusable, R5); a failed page
/// shows Try again in place of the next row, as its own zone ([order] + 1).
class TvPagedGrid extends ConsumerWidget {
  const TvPagedGrid({
    super.key,
    required this.order,
    required this.source,
    required this.onOpen,
    this.initial = false,
    this.filter,
    this.emptyMessage,
  });

  final int order;
  final MediaSource source;
  final void Function(MediaItem item) onOpen;
  final bool initial;

  /// Shows only the items it keeps (Search's kind chips); paging goes on
  /// underneath.
  final bool Function(MediaItem item)? filter;

  /// What an empty list says ("Nothing found for …").
  final String? emptyMessage;

  static const double _rowGap = 22;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final paged = ref.watch(pagedMediaProvider(source));
    final notifier = ref.read(pagedMediaProvider(source).notifier);
    final filter = this.filter;
    final items = filter == null
        ? paged.items
        : paged.items.where(filter).toList();
    // A filter can leave too few to scroll to the end, where loading more
    // starts: load on until there are two rows (or no more pages).
    final starved =
        filter != null &&
        items.length < 2 * tvGridColumns &&
        paged.hasMore &&
        paged.error == null;
    if (starved && !paged.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.loadMore());
    }

    Widget retry() => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TvSpace.safeH,
        TvPoster.growRoom,
        TvSpace.safeH,
        TvSpace.safeV,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              errorMessage(l10n, paged.error!),
              style: text.body.copyWith(color: context.palette.dust),
            ),
          ),
          const SizedBox(width: 20),
          TvZone.row(
            order: items.isEmpty ? order : order + 1,
            initial: items.isEmpty && initial,
            keyline: 0,
            child: TvButton(
              index: 0,
              label: l10n.retry,
              onSelect: notifier.retry,
            ),
          ),
        ],
      ),
    );

    Widget placeholders() => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TvSpace.safeH,
        TvPoster.growRoom,
        TvSpace.safeH,
        TvSpace.safeV,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < tvGridColumns; i++) const TvPosterPlaceholder(),
        ],
      ),
    );

    if (paged.failedFirstPage) return SliverToBoxAdapter(child: retry());
    if (paged.isFirstLoad || (items.isEmpty && starved)) {
      return SliverToBoxAdapter(child: placeholders());
    }
    if (items.isEmpty &&
        paged.started &&
        !paged.hasMore &&
        paged.error == null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(TvSpace.safeH),
          child: Center(
            child: Text(
              emptyMessage ?? l10n.listEmpty,
              style: text.body.copyWith(color: context.palette.dust),
            ),
          ),
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            TvSpace.safeH,
            TvPoster.growRoom,
            TvSpace.safeH,
            0,
          ),
          sliver: TvZone.grid(
            order: order,
            columns: tvGridColumns,
            initial: initial,
            child: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: tvGridColumns,
                mainAxisSpacing: _rowGap,
                crossAxisSpacing: 28,
                mainAxisExtent: TvPoster.cardHeight,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => Align(
                alignment: AlignmentDirectional.topStart,
                child: TvPosterCard(
                  index: i,
                  item: items[i],
                  onSelect: () => onOpen(items[i]),
                  onFocus: () {
                    if (i >= items.length - 2 * tvGridColumns) {
                      notifier.loadMore();
                    }
                  },
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: paged.error != null
              ? retry()
              : paged.isLoading
              ? placeholders()
              : const SizedBox(height: TvSpace.safeV),
        ),
      ],
    );
  }
}
