import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/catalog_providers.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/shell/app_shell.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/media_row.dart';
import '../../app/widgets/media_text.dart';
import '../../core/network/api_endpoints.dart';
import '../../data/models/catalog_models.dart';
import '../../data/paging/media_sources.dart';
import '../../data/paging/paged_media.dart';
import 'home_providers.dart';
import 'widgets/home_hero.dart';
import 'widgets/continue_row.dart';

/// How many genres get a row of their own at the end of Home.
const _genreRows = 12;

/// Home (PLAN.md §4.1): the hero, the curated groups, the catalog rows and
/// one row per genre. Rows load as they scroll into view, so the sections
/// above the fold come first. Pull down to refresh.
///
/// On phones it opens with the logo lockup (DESIGN.md §8); with a rail, the
/// rail already carries the brand.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = MarqueeSpace.gutter(width);
    final withBar = navLayoutFor(width) == NavLayout.bar;
    final groups = ref.watch(videoGroupsProvider);
    final genres = ref.watch(genresProvider).value ?? const <Category>[];

    final rows = <Widget>[
      if (groups.isLoading && !groups.hasValue)
        const MediaRow(title: '', items: [], loading: true),
      for (final g in groups.value ?? const <VideoGroup>[])
        MediaRow(
          title: g.title,
          items: g.items,
          onSeeAll: g.hasPagination
              ? () => openList(
                  context,
                  MediaListArgs(title: g.title, source: GroupSource(g.id)),
                )
              : null,
        ),
      SourceRow(title: l10n.rowFeatured, source: const FeaturedSource()),
      SourceRow(
        title: l10n.rowLatestMovies,
        source: const LatestSource(VideoKind.movies),
      ),
      SourceRow(
        title: l10n.rowLatestSeries,
        source: const LatestSource(VideoKind.series),
      ),
      SourceRow(
        title: l10n.rowMostWatched,
        source: const CatalogSource(VideoKind.movies, SortOrder.mostViewed),
      ),
      SourceRow(
        title: l10n.rowNewReleases,
        source: const CatalogSource(VideoKind.movies, SortOrder.newestRelease),
      ),
      SourceRow(
        title: l10n.rowRecentlyAdded,
        source: const CatalogSource(VideoKind.movies, SortOrder.recentlyAdded),
      ),
      for (final genre in genres.take(_genreRows)) _GenreRow(genre: genre),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.palette.bulb,
          backgroundColor: context.palette.booth,
          onRefresh: () async {
            refreshHome(ref);
            // Keep the spinner until the hero is back (or has failed).
            try {
              await ref.read(bannersProvider.future);
            } catch (_) {}
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    gutter,
                    MarqueeSpace.xl,
                    gutter,
                    MarqueeSpace.l,
                  ),
                  child: withBar
                      ? const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: CinemakomLogo(markSize: 36),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              SliverToBoxAdapter(child: HomeHero(gutter: gutter)),
              const SliverToBoxAdapter(child: ContinueRow()),
              SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => rows[i],
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: MarqueeSpace.huge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A genre's newest movies; "See all" opens the genre page.
class _GenreRow extends ConsumerWidget {
  const _GenreRow({required this.genre});

  final Category genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = GenreSource(categoryId: genre.id);
    final paged = ref.watch(pagedMediaProvider(source));
    final title = genre.name.resolve(arabic: context.isArabicUi) ?? '';
    return MediaRow(
      title: title,
      items: paged.items,
      loading: paged.isFirstLoad,
      error: paged.failedFirstPage ? paged.error : null,
      onRetry: () => ref.read(pagedMediaProvider(source).notifier).retry(),
      onSeeAll: () => openGenre(context, genre),
    );
  }
}
