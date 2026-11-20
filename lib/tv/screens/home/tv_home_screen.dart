import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/catalog_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation_args.dart';
import '../../../app/widgets/media_text.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../data/models/catalog_models.dart';
import '../../../data/paging/media_sources.dart';
import '../../../data/paging/paged_media.dart';
import '../../../features/home/home_providers.dart';
import '../../../features/library/library_providers.dart';
import '../../focus/tv_screen.dart';
import '../../theme/tv_space.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_continue_row.dart';
import '../../widgets/tv_row.dart';
import 'tv_home_hero.dart';

/// How many genres get a row of their own at the end of Home (as on the
/// phone).
const _genreRows = 12;

/// Home on TV (docs/TV.md §7.1, the TV Home designs): the hero, Continue
/// watching, then the same rows as the phone's Home, one zone each, top to
/// bottom. Focus starts on Play. Rows build as they come near the screen;
/// the next row is always built before focus can move to it.
class TvHomeScreen extends ConsumerWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(videoGroupsProvider);
    final genres = ref.watch(genresProvider).value ?? const <Category>[];

    // Each row: its builder, given its zone order.
    final rows = <Widget Function(int order)>[
      if (groups.isLoading && !groups.hasValue)
        (order) => TvPosterRow(
          order: order,
          title: '',
          items: const [],
          onOpen: (_) {},
          loading: true,
        ),
      for (final g in groups.value ?? const <VideoGroup>[])
        (order) => TvPosterRow(
          order: order,
          title: g.title,
          items: g.items,
          onOpen: (item) => tvOpenTitle(context, item),
          onSeeAll: g.hasPagination
              ? () => tvOpenList(
                  context,
                  MediaListArgs(title: g.title, source: GroupSource(g.id)),
                )
              : null,
        ),
      for (final (title, source) in <(String, MediaSource)>[
        (l10n.rowFeatured, const FeaturedSource()),
        (l10n.rowLatestMovies, const LatestSource(VideoKind.movies)),
        (l10n.rowLatestSeries, const LatestSource(VideoKind.series)),
        (
          l10n.rowMostWatched,
          const CatalogSource(VideoKind.movies, SortOrder.mostViewed),
        ),
        (
          l10n.rowNewReleases,
          const CatalogSource(VideoKind.movies, SortOrder.newestRelease),
        ),
        (
          l10n.rowRecentlyAdded,
          const CatalogSource(VideoKind.movies, SortOrder.recentlyAdded),
        ),
      ])
        (order) => _SourceRow(order: order, title: title, source: source),
      for (final genre in genres.take(_genreRows))
        (order) => _SourceRow(
          order: order,
          title: genre.name.resolve(arabic: context.isArabicUi) ?? '',
          source: GenreSource(categoryId: genre.id),
          onSeeAll: () => tvOpenGenre(context, genre),
        ),
    ];

    return TvScreen(
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: TvSpace.safeH),
            sliver: SliverToBoxAdapter(child: TvHomeHero(order: 0)),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
          SliverToBoxAdapter(
            child: TvContinueRow(
              order: 1,
              onPlay: (entry) => tvOpenPlayer(context, continueRequest(entry)),
            ),
          ),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(top: 18),
              child: rows[i](2 + i),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: TvSpace.safeV)),
        ],
      ),
    );
  }
}

/// A row showing the first page of [source]; "See all" opens the whole list
/// (or [onSeeAll]).
class _SourceRow extends ConsumerWidget {
  const _SourceRow({
    required this.order,
    required this.title,
    required this.source,
    this.onSeeAll,
  });

  final int order;
  final String title;
  final MediaSource source;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paged = ref.watch(pagedMediaProvider(source));
    return TvPosterRow(
      order: order,
      title: title,
      items: paged.items,
      loading: paged.isFirstLoad,
      error: paged.failedFirstPage ? paged.error : null,
      onRetry: () => ref.read(pagedMediaProvider(source).notifier).retry(),
      onOpen: (item) => tvOpenTitle(context, item),
      onSeeAll:
          onSeeAll ??
          () =>
              tvOpenList(context, MediaListArgs(title: title, source: source)),
    );
  }
}
