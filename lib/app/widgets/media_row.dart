import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/media_item.dart';
import '../../data/paging/media_sources.dart';
import '../../data/paging/paged_media.dart';
import '../navigation.dart';
import '../shell/app_shell.dart';
import '../theme/marquee_colors.dart';
import 'error_view.dart';
import 'poster_card.dart';
import 'section_header.dart';

/// Poster width in horizontal rows.
double rowPosterWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.rail ? 140 : 112;

/// A titled horizontal row of posters (DESIGN.md §5).
///
/// It shows [items]; while [loading] with nothing to show, plain `booth`
/// blocks; on [error], a compact retry. An empty, finished row hides itself.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onSeeAll,
  });

  final String title;
  final List<MediaItem> items;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    if (items.isEmpty && !loading && error == null) {
      return const SizedBox.shrink();
    }
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final width = rowPosterWidth(context);
    final height = PosterCard.heightFor(width);
    final Widget body;
    if (items.isEmpty && error != null) {
      body = SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
          child: ErrorView(
            error: error,
            onRetry: onRetry ?? () {},
            compact: true,
          ),
        ),
      );
    } else {
      final placeholders = items.isEmpty;
      body = SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
          itemCount: placeholders ? 6 : items.length,
          separatorBuilder: (_, _) => const SizedBox(width: MarqueeSpace.m),
          itemBuilder: (context, i) => SizedBox(
            width: width,
            child: placeholders
                ? const _PosterPlaceholder()
                : PosterCard(
                    item: items[i],
                    onTap: () => openTitle(context, items[i]),
                  ),
          ),
        ),
      );
    }
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
            child: SectionHeader(title: title, onSeeAll: onSeeAll),
          ),
          body,
        ],
      ),
    );
  }
}

/// A [MediaRow] showing the first page of [source], with "See all" opening
/// the whole list.
class SourceRow extends ConsumerWidget {
  const SourceRow({
    super.key,
    required this.title,
    required this.source,
    this.seeAll = true,
  });

  final String title;
  final MediaSource source;
  final bool seeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paged = ref.watch(pagedMediaProvider(source));
    return MediaRow(
      title: title,
      items: paged.items,
      loading: paged.isFirstLoad,
      error: paged.failedFirstPage ? paged.error : null,
      onRetry: () => ref.read(pagedMediaProvider(source).notifier).retry(),
      onSeeAll: seeAll && paged.items.isNotEmpty
          ? () => openList(context, MediaListArgs(title: title, source: source))
          : null,
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: 2 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MarqueeColors.booth,
            borderRadius: BorderRadius.all(MarqueeRadius.poster),
          ),
        ),
      ),
    ],
  );
}
