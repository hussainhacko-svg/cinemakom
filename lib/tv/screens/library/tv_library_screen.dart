import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../features/library/library_providers.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_paged_grid.dart' show tvGridColumns;
import '../../widgets/tv_poster_card.dart';
import '../../widgets/tv_shelf.dart';

/// The Library on TV (docs/TV.md §7.5, the TV Library design): the segment
/// (zone 0: Continue watching · Favorites; moving onto one shows it), then
/// - Continue watching: a list of rows, each a row of cells (zone 1): the
///   title (OK resumes, or plays the next episode) · Details · Remove.
///   Remove hides the title as the phone does; focus stays on the row that
///   moves up into its place (R7).
/// - Favorites: a grid of posters (zone 1); OK opens Details, where the
///   Favorite button removes it.
class TvLibraryScreen extends ConsumerStatefulWidget {
  const TvLibraryScreen({super.key});

  @override
  ConsumerState<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends ConsumerState<TvLibraryScreen> {
  bool _favorites = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TvScreen(
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverPadding(
            // The segment's ring at the top, which the scroll view clips.
            padding: const EdgeInsetsDirectional.fromSTEB(
              TvSpace.safeH,
              TvFocusStyle.buttonOutset,
              TvSpace.safeH,
              20,
            ),
            sliver: SliverToBoxAdapter(
              child: TvZone.row(
                order: 0,
                keyline: 0,
                child: TvSegmentTrack(
                  children: [
                    TvSegment(
                      index: 0,
                      label: l10n.rowContinueWatching,
                      selected: !_favorites,
                      onFocus: () => setState(() => _favorites = false),
                    ),
                    TvSegment(
                      index: 1,
                      label: l10n.libraryFavorites,
                      selected: _favorites,
                      onFocus: () => setState(() => _favorites = true),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_favorites) const _Favorites() else const _Continue(),
          const SliverToBoxAdapter(child: SizedBox(height: TvSpace.safeV)),
        ],
      ),
    );
  }
}

class _Continue extends ConsumerWidget {
  const _Continue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(continueEntriesProvider).value;
    if (entries == null) return const SliverToBoxAdapter();
    if (entries.isEmpty) {
      return SliverToBoxAdapter(child: TvEmpty(l10n.continueEmpty));
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
      sliver: TvZone.grid(
        order: 1,
        columns: 3,
        keyline: 0,
        child: SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) =>
              _ContinueRow(index: i * 3, entry: entries[i]),
        ),
      ),
    );
  }
}

/// One title: its card, Details and Remove (cells [index] to [index] + 2).
class _ContinueRow extends ConsumerWidget {
  const _ContinueRow({required this.index, required this.entry});

  final int index;
  final ContinueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = entry.progress;
    final next = entry.upNext;
    final title = context.titleOf(p.item);
    final String where;
    final String left;
    if (next != null) {
      where = context.joinMeta([
        l10n.playerUpNext,
        '${l10n.seasonNumber(next.season)} · '
            '${episodeLabel(l10n, next.numbering)}',
      ]);
      left = next.duration == null ? '' : formatDuration(l10n, next.duration!);
    } else {
      // "Season 2 · Episode 5", or "Movie" (the Library design).
      where = p.season != null && p.episode != null
          ? '${l10n.seasonNumber(p.season!)} · '
                '${l10n.episodeNumber(p.episode!)}'
          : l10n.tvMovie;
      left = minutesLeft(l10n, p.remaining);
    }
    return Row(
      children: [
        Expanded(
          child: TvShelfRow(
            index: index,
            label: context.joinMeta(
              [title, where, left].where((s) => s.isNotEmpty),
            ),
            title: title,
            posterUrl: p.posterUrl,
            lines: [where, left],
            bar: next == null ? p.fraction : null,
            onSelect: () => tvOpenPlayer(context, continueRequest(entry)),
          ),
        ),
        const SizedBox(width: 14),
        TvButton(
          index: index + 1,
          label: l10n.tvDetails,
          onSelect: () => tvOpenTitle(context, p.item),
        ),
        const SizedBox(width: 14),
        TvButton(
          index: index + 2,
          icon: Icons.close,
          label: l10n.tvRemove,
          onSelect: () =>
              ref.read(libraryRepositoryProvider).hideFromContinue(p.titleId),
        ),
      ],
    );
  }
}

class _Favorites extends ConsumerWidget {
  const _Favorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(favoritesProvider).value;
    if (items == null) return const SliverToBoxAdapter();
    if (items.isEmpty) {
      return SliverToBoxAdapter(child: TvEmpty(l10n.tvFavoritesEmpty));
    }
    return SliverPadding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TvSpace.safeH,
        TvPoster.growRoom - 20,
        TvSpace.safeH,
        0,
      ),
      sliver: TvZone.grid(
        order: 1,
        columns: tvGridColumns,
        child: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: tvGridColumns,
            mainAxisSpacing: 22,
            crossAxisSpacing: 28,
            mainAxisExtent: TvPoster.cardHeight,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => Align(
            alignment: AlignmentDirectional.topStart,
            child: TvPosterCard(
              index: i,
              item: items[i],
              onSelect: () => tvOpenTitle(context, items[i]),
            ),
          ),
        ),
      ),
    );
  }
}
