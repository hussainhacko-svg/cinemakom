import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../../data/paging/media_sources.dart';
import '../../data/paging/paged_media.dart';
import '../l10n/app_localizations.dart';
import '../navigation.dart';
import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';
import 'bulb_loader.dart';
import 'error_view.dart';
import 'poster_card.dart';

/// How many items before the end the next page starts loading: about two
/// screens of posters, so scrolling rarely has to wait.
const _prefetchItems = 12;

/// Grid columns for a content width: at least 3, posters about 160 wide.
int gridColumns(double width) => (width / 160).floor().clamp(3, 12);

/// An infinitely scrolling poster grid over [source], as slivers to place
/// in a [CustomScrollView] (after a header, for example).
///
/// The next page loads when the grid builds an item near its end, which
/// also covers lists shorter than the screen. The end of the list shows the
/// bulb loader while a page loads, or a "Try again" row when one failed;
/// everything loaded stays. [filter] hides items (the search kind chips).
class PagedGridSlivers extends ConsumerWidget {
  const PagedGridSlivers({
    super.key,
    required this.source,
    required this.gutter,
    this.filter,
    this.emptyMessage,
  });

  final MediaSource source;
  final double gutter;
  final bool Function(MediaItem)? filter;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = pagedMediaProvider(source);
    final paged = ref.watch(provider);
    final notifier = ref.read(provider.notifier);
    final filter = this.filter;
    final items = filter == null
        ? paged.items
        : paged.items.where(filter).toList();
    final l10n = AppLocalizations.of(context);

    void prefetch() {
      if (paged.hasMore && !paged.isLoading && paged.error == null) {
        Future.microtask(notifier.loadMore);
      }
    }

    // A filter can hide a whole page: keep loading until something shows.
    if (items.length < _prefetchItems && paged.started) prefetch();

    final error = paged.error;
    if (items.isEmpty) {
      final Widget body;
      if (error != null && !paged.isLoading) {
        body = ErrorView(error: error, onRetry: notifier.retry);
      } else if (paged.hasMore || paged.isLoading || !paged.started) {
        body = Center(child: BulbLoader(semanticLabel: l10n.loading));
      } else {
        body = Center(
          child: Text(
            emptyMessage ?? l10n.listEmpty,
            textAlign: TextAlign.center,
            style: MarqueeText.of(context).body,
          ),
        );
      }
      return SliverFillRemaining(hasScrollBody: false, child: body);
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final columns = gridColumns(constraints.crossAxisExtent);
              const spacing = MarqueeSpace.m;
              final cellWidth =
                  (constraints.crossAxisExtent - (columns - 1) * spacing) /
                  columns;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: MarqueeSpace.l,
                  mainAxisExtent: PosterCard.heightFor(cellWidth),
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  if (i >= items.length - _prefetchItems) prefetch();
                  return PosterCard(
                    item: items[i],
                    onTap: () => openTitle(context, items[i]),
                  );
                },
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              gutter,
              MarqueeSpace.xxl,
              gutter,
              MarqueeSpace.huge,
            ),
            child: error != null
                ? ErrorView(
                    error: error,
                    onRetry: notifier.retry,
                    compact: true,
                  )
                // The loader only while a page is on its way (it animates,
                // and an idle list should be still).
                : paged.isLoading
                ? Center(child: BulbLoader(semanticLabel: l10n.loading))
                : const SizedBox(height: 6),
          ),
        ),
      ],
    );
  }
}
