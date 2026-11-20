import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/catalog_providers.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/bulb_loader.dart';
import '../../app/widgets/controls.dart';
import '../../app/widgets/media_text.dart';
import '../../app/widgets/paged_grid.dart';
import '../../app/widgets/section_header.dart';
import '../../core/network/api_endpoints.dart';
import '../../data/models/catalog_models.dart';
import '../../data/paging/media_sources.dart';
import 'search_history.dart';

/// How long typing must pause before searching (PLAN.md §4.1).
const searchDebounce = Duration(milliseconds: 400);

/// Search (DESIGN.md §8). Before typing: recent searches and the genre
/// grid. After: the title grid, infinitely scrolling, filtered by the kind chips. Titles match by
/// name and by cast or crew name. An empty query is never sent.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
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
    _debounce = Timer(searchDebounce, () => _submit(value));
    setState(() {}); // The clear button follows the text.
  }

  void _submit(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q != _query) setState(() => _query = q);
  }

  /// A search the user meant (the keyboard's search key, a recent search,
  /// or a title opened from the results), so it is remembered. Searches
  /// made while typing are not, or half-typed words would fill the list.
  void _remember(String value) {
    _submit(value);
    ref.read(searchHistoryProvider.notifier).add(value);
  }

  void _searchAgain(String query) {
    _field.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    _remember(query);
  }

  void _clear() {
    _field.clear();
    _submit('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final kind = _kind;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  gutter,
                  MarqueeSpace.xl,
                  gutter,
                  MarqueeSpace.m,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        text.arabic
                            ? l10n.navSearch
                            : l10n.navSearch.toUpperCase(),
                        style: text.displayLarge,
                      ),
                    ),
                    const SizedBox(height: MarqueeSpace.m),
                    TextField(
                      controller: _field,
                      onChanged: _onChanged,
                      onSubmitted: _remember,
                      textInputAction: TextInputAction.search,
                      style: text.body.copyWith(color: MarqueeColors.cream),
                      decoration: InputDecoration(
                        hintText: l10n.searchHint,
                        prefixIcon: const Icon(
                          Icons.search,
                          color: MarqueeColors.dust,
                          size: 20,
                        ),
                        suffixIcon: _field.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: l10n.clearSearch,
                                onPressed: _clear,
                                icon: const Icon(
                                  Icons.close,
                                  color: MarqueeColors.dust,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: MarqueeSpace.m),
                    Wrap(
                      spacing: MarqueeSpace.s,
                      children: [
                        for (final (value, label) in [
                          (null, l10n.kindAll),
                          (VideoKind.movies, l10n.kindMovies),
                          (VideoKind.series, l10n.kindSeries),
                        ])
                          FilterPill(
                            label: label,
                            selected: kind == value,
                            onTap: () => setState(() => _kind = value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_query.isEmpty) ...[
              ..._recentSearches(context, gutter),
              ..._genreGrid(context, gutter),
            ] else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    gutter,
                    MarqueeSpace.m,
                    gutter,
                    MarqueeSpace.m,
                  ),
                  child: SectionHeader(title: l10n.searchTitles),
                ),
              ),
              PagedGridSlivers(
                source: SearchSource(_query),
                gutter: gutter,
                filter: kind == null ? null : (i) => i.kind == kind,
                emptyMessage: l10n.searchNoResults(_query),
                onOpen: (_) =>
                    ref.read(searchHistoryProvider.notifier).add(_query),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Recent searches, newest first: a tap searches again, ✕ removes one,
  /// and "Clear all" removes every one. Nothing shows when there are none.
  List<Widget> _recentSearches(BuildContext context, double gutter) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final history = ref.watch(searchHistoryProvider);
    final notifier = ref.read(searchHistoryProvider.notifier);
    if (history.isEmpty) return const [];
    return [
      SliverPadding(
        padding: EdgeInsetsDirectional.fromSTEB(
          gutter,
          MarqueeSpace.m,
          gutter,
          MarqueeSpace.l,
        ),
        sliver: SliverList.list(
          children: [
            Row(
              children: [
                Expanded(child: SectionHeader(title: l10n.recentSearches)),
                TextButton(
                  onPressed: notifier.clear,
                  child: Text(l10n.clearSearchHistory),
                ),
              ],
            ),
            for (final query in history)
              InkWell(
                onTap: () => _searchAgain(query),
                borderRadius: const BorderRadius.all(MarqueeRadius.card),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.history,
                        size: 20,
                        color: MarqueeColors.dust,
                      ),
                      const SizedBox(width: MarqueeSpace.m),
                      Expanded(
                        child: Text(
                          query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.body.copyWith(color: MarqueeColors.cream),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.removeSearch(query),
                        onPressed: () => notifier.remove(query),
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: MarqueeColors.dust,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _genreGrid(BuildContext context, double gutter) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final arabic = context.isArabicUi;
    final genres = ref.watch(genresProvider);
    final list = genres.value ?? const <Category>[];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            gutter,
            MarqueeSpace.m,
            gutter,
            MarqueeSpace.m,
          ),
          child: SectionHeader(title: l10n.browseGenres),
        ),
      ),
      if (list.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(MarqueeSpace.huge),
            child: Center(child: BulbLoader(semanticLabel: l10n.loading)),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(
            gutter,
            0,
            gutter,
            MarqueeSpace.huge,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisExtent: 64,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => Material(
              color: MarqueeColors.booth,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(MarqueeRadius.card),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openGenre(context, list[i]),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 14,
                  ),
                  child: Row(
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          color: MarqueeColors.velvetStrong,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: 6),
                      ),
                      const SizedBox(width: MarqueeSpace.m),
                      Expanded(
                        child: Text(
                          list[i].name.resolve(arabic: arabic) ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.label.copyWith(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
