import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/error_view.dart';
import '../../../data/models/media_item.dart';
import '../../../data/paging/media_sources.dart';
import '../../../data/paging/paged_media.dart';
import '../tv_shell.dart' show tvGutter;
import 'tv_poster_card.dart';

const _prefetchItems = 12;

/// TV grid columns: ~150 dp wide posters (5 across a 960 dp TV).
int tvGridColumns(double width) => (width / 155).floor().clamp(3, 8);

/// Infinitely scrolling HD poster grid for TV screens.
class TvPagedGridSlivers extends ConsumerWidget {
  const TvPagedGridSlivers({
    super.key,
    required this.source,
    this.filter,
    this.emptyMessage,
    this.onOpen,
    this.autofocusFirst = false,
  });

  final MediaSource source;
  final bool Function(MediaItem)? filter;
  final String? emptyMessage;
  final ValueChanged<MediaItem>? onOpen;
  final bool autofocusFirst;

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
        TvPosterGridSliver(
          items: items,
          autofocusFirst: autofocusFirst,
          onOpen: onOpen,
          onBuild: (i) {
            if (i >= items.length - _prefetchItems) prefetch();
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              tvGutter,
              MarqueeSpace.xl,
              tvGutter,
              MarqueeSpace.huge,
            ),
            child: error != null
                ? ErrorView(
                    error: error,
                    onRetry: notifier.retry,
                    compact: true,
                  )
                : paged.isLoading
                ? Center(child: BulbLoader(semanticLabel: l10n.loading))
                : const SizedBox(height: 6),
          ),
        ),
      ],
    );
  }
}

/// Poster grid sliver of HD [TvPosterCard]s.
class TvPosterGridSliver extends StatelessWidget {
  const TvPosterGridSliver({
    super.key,
    required this.items,
    this.onBuild,
    this.onOpen,
    this.autofocusFirst = false,
  });

  final List<MediaItem> items;
  final void Function(int index)? onBuild;
  final ValueChanged<MediaItem>? onOpen;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: tvGutter),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = tvGridColumns(constraints.crossAxisExtent);
        const spacing = MarqueeSpace.m;
        final cellWidth =
            (constraints.crossAxisExtent - (columns - 1) * spacing) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: MarqueeSpace.l,
            mainAxisExtent: TvPosterCard.heightFor(cellWidth),
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            onBuild?.call(i);
            return TvPosterCard(
              item: items[i],
              autofocus: autofocusFirst && i == 0,
              onTap: () {
                onOpen?.call(items[i]);
                openTitle(context, items[i]);
              },
            );
          },
        );
      },
    ),
  );
}
