import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/catalog_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_text.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../data/models/catalog_models.dart';
import '../../../data/paging/media_sources.dart';
import '../../../features/search/search_history.dart';
import '../../focus/tv_focusable.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_chip.dart';
import '../../widgets/tv_focus_look.dart';
import '../../widgets/tv_paged_grid.dart';
import '../../widgets/tv_row.dart';
import '../../widgets/tv_shelf.dart';
import '../../widgets/tv_text_entry.dart';

/// How long typing pauses before the results follow (as on the phone).
const tvSearchDebounce = Duration(milliseconds: 400);

/// Search on TV (docs/TV.md §7.6, the TV Search designs), zones top to
/// bottom: the search box (0; OK opens the TV's keyboard, R8), the kind
/// chips (1), then before anything is typed the recent searches (2, each a
/// row of cells: the search · ✕), Clear all (3) and the genres (4); once
/// typed, the results (2), updating as you type. There's no People row: the
/// API has no people search, and titles match by cast and crew already.
///
/// A search is remembered only when meant, as on the phone: the keyboard's
/// search key, a recent search again, or a title opened from the results.
class TvSearchScreen extends ConsumerStatefulWidget {
  const TvSearchScreen({super.key});

  @override
  ConsumerState<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends ConsumerState<TvSearchScreen> {
  final _field = TextEditingController();
  Timer? _debounce;
  String _query = '';
  VideoKind? _kind;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(tvSearchDebounce, () => _submit(value));
  }

  void _submit(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q != _query) setState(() => _query = q);
  }

  void _remember(String value) {
    _submit(value);
    ref.read(searchHistoryProvider.notifier).add(value);
  }

  void _searchAgain(String query) {
    _field.text = query;
    _remember(query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query;
    final kind = _kind;
    return TvScreen(
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverPadding(
            // The box's ring at the top, which the scroll view clips.
            padding: const EdgeInsetsDirectional.fromSTEB(
              TvSpace.safeH,
              TvFocusStyle.buttonOutset,
              TvSpace.safeH,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvZone.row(
                    order: 0,
                    keyline: 0,
                    child: TvTextEntry(
                      index: 0,
                      controller: _field,
                      label: l10n.searchHint,
                      onChanged: _onChanged,
                      onSubmitted: _remember,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TvZone.row(
                    order: 1,
                    keyline: 0,
                    child: Row(
                      children: [
                        for (final (i, (value, label)) in [
                          (null, l10n.kindAll),
                          (VideoKind.movies, l10n.kindMovies),
                          (VideoKind.series, l10n.kindSeries),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: 10),
                          TvChip(
                            index: i,
                            label: label,
                            selected: kind == value,
                            onSelect: () => setState(() => _kind = value),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (query.isEmpty) ...[
            _RecentSearches(onSearch: _searchAgain),
            const _Genres(),
          ] else
            TvPagedGrid(
              order: 2,
              source: SearchSource(query),
              filter: kind == null ? null : (i) => i.kind == kind,
              emptyMessage: l10n.searchNoResults(query),
              onOpen: (item) {
                ref.read(searchHistoryProvider.notifier).add(query);
                tvOpenTitle(context, item);
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: TvSpace.safeV)),
        ],
      ),
    );
  }
}

/// Up to 10 recent searches (zone 2: the search · ✕ on each row), then
/// Clear all (zone 3). Nothing when there are none.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(searchHistoryProvider);
    final notifier = ref.read(searchHistoryProvider.notifier);
    if (history.isEmpty) return const SliverToBoxAdapter();
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvSectionTitle(l10n.recentSearches),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
            child: TvZone.grid(
              order: 2,
              columns: 2,
              keyline: 0,
              child: Column(
                children: [
                  for (final (i, q) in history.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: _RecentRow(
                              index: i * 2,
                              query: q,
                              onSelect: () => onSearch(q),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _RemoveButton(
                            index: i * 2 + 1,
                            label: l10n.removeSearch(q),
                            onSelect: () => notifier.remove(q),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TvZone.row(
                order: 3,
                keyline: 0,
                child: _TextButton(
                  index: 0,
                  label: l10n.clearSearchHistory,
                  onSelect: notifier.clear,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.index,
    required this.query,
    required this.onSelect,
  });

  final int index;
  final String query;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: query,
      onSelect: onSelect,
      builder: (context, focused) => TvRing(
        on: focused,
        radius: 12,
        child: Container(
          height: 48,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: focused ? context.palette.boothRaised : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.history, size: 20, color: context.palette.dust),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.body
                      .withWeight(FontWeight.w400)
                      .copyWith(height: 1.2, color: context.palette.cream),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✕: a 44 `booth` circle with a `velvet` edge.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({
    required this.index,
    required this.label,
    required this.onSelect,
  });

  final int index;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => TvFocusable(
    index: index,
    label: label,
    onSelect: onSelect,
    builder: (context, focused) => TvRing(
      on: focused,
      radius: TvRing.pill,
      gap: TvFocusStyle.buttonGap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: focused ? context.palette.boothRaised : context.palette.booth,
          border: Border.all(color: context.palette.velvet),
        ),
        child: Icon(
          Icons.close,
          size: 18,
          color: focused ? context.palette.cream : context.palette.dust,
        ),
      ),
    ),
  );
}

/// A `bulb` text button ("Clear all").
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.index,
    required this.label,
    required this.onSelect,
  });

  final int index;
  final String label;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => TvFocusable(
    index: index,
    label: label,
    onSelect: onSelect,
    builder: (context, focused) => TvRing(
      on: focused,
      radius: TvRing.pill,
      gap: TvFocusStyle.buttonGap,
      child: Container(
        height: 44,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        decoration: ShapeDecoration(
          color: focused ? context.palette.boothRaised : null,
          shape: const StadiumBorder(),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: MarqueeTvText.of(context).label
                .copyWith(color: context.palette.bulb),
          ),
        ),
      ),
    ),
  );
}

/// The genres, five to a row (zone 4): a tile opens that genre's page.
class _Genres extends ConsumerWidget {
  const _Genres();

  static const _columns = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final genres = ref.watch(genresProvider).value ?? const <Category>[];
    if (genres.isEmpty) return const SliverToBoxAdapter();
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: TvSectionTitle(l10n.browseGenres)),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: TvSpace.safeH),
          sliver: TvZone.grid(
            order: 4,
            columns: _columns,
            keyline: 0,
            child: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columns,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: TvTile.height,
              ),
              itemCount: genres.length,
              itemBuilder: (context, i) => TvTile(
                index: i,
                label: genres[i].name.resolve(arabic: context.isArabicUi) ?? '',
                onSelect: () => tvOpenGenre(context, genres[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
