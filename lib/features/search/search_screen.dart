import 'dart:async';

import 'package:flutter/services.dart';
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
import '../../core/platform/platform_info.dart';
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
  final _boxFocus = FocusNode(debugLabel: 'searchBox');
  final _inputFocus = FocusNode(debugLabel: 'searchInput');
  Timer? _debounce;
  String _query = '';
  VideoKind? _kind;

  /// On Android TV, D-pad focuses the search box without immediately opening
  /// the virtual keyboard; pressing OK/Select enters editing mode.
  bool _tvEditing = false;
  bool _boxFocused = false;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus && _tvEditing && mounted) {
        setState(() => _tvEditing = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _boxFocus.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _enterTvEdit() {
    if (_tvEditing) return;
    setState(() => _tvEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tvEditing) _inputFocus.requestFocus();
    });
  }

  void _exitTvEdit() {
    if (!_tvEditing) return;
    setState(() => _tvEditing = false);
    _boxFocus.requestFocus();
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
                    _buildSearchField(l10n, text),
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

  Widget _buildSearchField(AppLocalizations l10n, MarqueeText text) {
    final field = TextField(
      controller: _field,
      focusNode: isTv ? _inputFocus : null,
      readOnly: isTv && !_tvEditing,
      onChanged: _onChanged,
      onSubmitted: (value) {
        _remember(value);
        if (isTv) _exitTvEdit();
      },
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
                icon: const Icon(Icons.close, color: MarqueeColors.dust),
              ),
      ),
    );
    if (!isTv) return field;
    // On TV, wrap the field so D-pad can pass across it without popping the
    // on-screen keyboard or trapping arrow keys in the cursor.
    return Focus(
      focusNode: _boxFocus,
      onFocusChange: (f) => setState(() => _boxFocused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (!_tvEditing &&
            (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter)) {
          _enterTvEdit();
          return KeyEventResult.handled;
        }
        if (_tvEditing &&
            (key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.escape)) {
          _exitTvEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          border: _boxFocused && !_tvEditing
              ? Border.all(color: MarqueeColors.bulb, width: 2)
              : null,
        ),
        child: ExcludeFocus(
          excluding: !_tvEditing,
          child: GestureDetector(
            onTap: _enterTvEdit,
            child: field,
          ),
        ),
      ),
    );
  }

  /// Recent searches, newest first: a tap searches again, ✕ removes one,
  /// and "Clear all" removes every one. Nothing shows when there are none.
  List<Widget> _recentSearches(BuildContext context, double gutter) {
    final l10n = AppLocalizations.of(context);
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
              _RecentSearchRow(
                query: query,
                onTap: () => _searchAgain(query),
                onRemove: () => notifier.remove(query),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _genreGrid(BuildContext context, double gutter) {
    final l10n = AppLocalizations.of(context);
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
            itemBuilder: (context, i) => _GenreTile(
              label: list[i].name.resolve(arabic: arabic) ?? '',
              onTap: () => openGenre(context, list[i]),
            ),
          ),
        ),
    ];
  }
}

class _RecentSearchRow extends StatefulWidget {
  const _RecentSearchRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_RecentSearchRow> createState() => _RecentSearchRowState();
}

class _RecentSearchRowState extends State<_RecentSearchRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _focused ? MarqueeColors.boothRaised : null,
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        border: _focused
            ? Border.all(color: MarqueeColors.bulb, width: 2)
            : null,
      ),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: Colors.transparent,
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Row(
            children: [
              const Icon(Icons.history, size: 20, color: MarqueeColors.dust),
              const SizedBox(width: MarqueeSpace.m),
              Expanded(
                child: Text(
                  widget.query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.body.copyWith(color: MarqueeColors.cream),
                ),
              ),
              IconButton(
                tooltip: l10n.removeSearch(widget.query),
                onPressed: widget.onRemove,
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
    );
  }
}

class _GenreTile extends StatefulWidget {
  const _GenreTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_GenreTile> createState() => _GenreTileState();
}

class _GenreTileState extends State<_GenreTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Material(
      color: _focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(MarqueeRadius.card),
        side: _focused
            ? const BorderSide(color: MarqueeColors.bulb, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _focused
                      ? MarqueeColors.bulb
                      : MarqueeColors.velvetStrong,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 6),
              ),
              const SizedBox(width: MarqueeSpace.m),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
