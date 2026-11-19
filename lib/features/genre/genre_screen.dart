import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/catalog_providers.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/widgets/choice_picker.dart';
import '../../app/widgets/controls.dart';
import '../../app/widgets/media_text.dart';
import '../../app/widgets/paged_grid.dart';
import '../../app/widgets/sub_page.dart';
import '../../core/network/api_endpoints.dart';
import '../../data/models/catalog_models.dart';
import '../../data/paging/media_sources.dart';

/// How many audio-language chips a genre shows at most (the most common).
const _maxLanguages = 8;

/// One genre (DESIGN.md §8): Movies | Series, a sort, the genre × language
/// chips, and the infinitely scrolling grid.
class GenreScreen extends ConsumerStatefulWidget {
  const GenreScreen({super.key, required this.categoryId, this.genre});

  final String categoryId;

  /// The genre as the list showed it; looked up by ID when missing.
  final Category? genre;

  @override
  ConsumerState<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends ConsumerState<GenreScreen> {
  VideoKind _kind = VideoKind.movies;
  SortOrder _sort = SortOrder.recentlyAdded;
  String? _languageId;

  String _sortLabel(AppLocalizations l10n, SortOrder s) => switch (s) {
    SortOrder.recentlyAdded => l10n.sortRecentlyAdded,
    SortOrder.oldestAdded => l10n.sortOldestAdded,
    SortOrder.newestRelease => l10n.sortNewestRelease,
    SortOrder.oldestRelease => l10n.sortOldestRelease,
    SortOrder.mostViewed => l10n.sortMostWatched,
    SortOrder.titleAscending => l10n.sortTitleAscending,
    SortOrder.titleDescending => l10n.sortTitleDescending,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final arabic = context.isArabicUi;
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final genre =
        widget.genre ??
        ref
            .watch(genresProvider)
            .value
            ?.where((g) => g.id == widget.categoryId)
            .firstOrNull;
    final title = genre?.name.resolve(arabic: arabic) ?? '';

    // The languages this genre has for the chosen kind, most titles first.
    final languages =
        [
          for (final l
              in ref.watch(categoryLanguagesProvider).value ??
                  const <CategoryLanguage>[])
            if (l.categoryId == widget.categoryId &&
                (_kind == VideoKind.series ? l.seriesCount : l.movieCount) > 0)
              l,
        ]..sort(
          (a, b) => _kind == VideoKind.series
              ? b.seriesCount.compareTo(a.seriesCount)
              : b.movieCount.compareTo(a.movieCount),
        );
    final shown = languages.take(_maxLanguages).toList();
    // A chosen language that this kind doesn't have falls back to all.
    final languageId = shown.any((l) => l.languageId == _languageId)
        ? _languageId
        : null;

    final source = GenreSource(
      categoryId: widget.categoryId,
      kind: _kind,
      sort: _sort,
      languageId: languageId,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SubPageHeader(title: title, gutter: gutter),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  gutter,
                  MarqueeSpace.xs,
                  gutter,
                  MarqueeSpace.m,
                ),
                child: Row(
                  children: [
                    Segmented(
                      segments: [
                        (VideoKind.movies, l10n.kindMovies),
                        (VideoKind.series, l10n.kindSeries),
                      ],
                      selected: _kind,
                      onChanged: (k) => setState(() => _kind = k),
                    ),
                    const SizedBox(width: MarqueeSpace.m),
                    const Spacer(),
                    // Shrinks (and ellipsizes) before the row overflows.
                    Flexible(
                      flex: 1000,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final sort = await showChoicePicker(
                            context,
                            title: l10n.sortTitle,
                            selected: _sort,
                            choices: [
                              for (final s in SortOrder.values)
                                Choice(s, _sortLabel(l10n, s)),
                            ],
                          );
                          if (sort != null) setState(() => _sort = sort);
                        },
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.expand_more, size: 18),
                        label: Text(
                          _sortLabel(l10n, _sort),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 40),
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (shown.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: gutter,
                    ),
                    children: [
                      for (final l in [null, ...shown]) ...[
                        FilterPill(
                          label: l == null
                              ? l10n.allLanguages
                              : l.name.resolve(arabic: arabic) ?? '',
                          selected: l?.languageId == languageId,
                          onTap: () =>
                              setState(() => _languageId = l?.languageId),
                        ),
                        const SizedBox(width: MarqueeSpace.s),
                      ],
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: MarqueeSpace.l)),
            PagedGridSlivers(source: source, gutter: gutter),
          ],
        ),
      ),
    );
  }
}
