import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/catalog_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/media_text.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../data/models/catalog_models.dart';
import '../../../data/paging/media_sources.dart';
import '../../search/search_history.dart';
import '../../search/search_screen.dart' show searchDebounce;
import '../tv_shell.dart' show tvGutter, tvPrimaryFocusLabel;
import '../widgets/tv_focus.dart';
import '../widgets/tv_paged_grid.dart';

/// Dedicated 10-foot Android TV Search screen:
/// - D-pad focuses the search box with a crisp `bulb` ring without popping
///   the on-screen keyboard; pressing OK/Select enters editing mode and Back
///   exits back to D-pad navigation.
/// - Recent searches have sibling Remove buttons (D-pad Right to reach).
/// - Genre grid tiles and HD poster results all use 2 px `bulb` focus rings.
class TvSearchScreen extends ConsumerStatefulWidget {
  const TvSearchScreen({super.key});

  @override
  ConsumerState<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends ConsumerState<TvSearchScreen> {
  final _field = TextEditingController();
  final _boxFocus = FocusNode(debugLabel: tvPrimaryFocusLabel);
  final _inputFocus = FocusNode(debugLabel: 'tvSearchInput');
  Timer? _debounce;
  String _query = '';
  VideoKind? _kind;
  bool _editing = false;
  bool _boxFocused = false;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus && _editing && mounted) {
        setState(() => _editing = false);
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

  void _enterEdit() {
    if (_editing) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _inputFocus.requestFocus();
    });
  }

  void _exitEdit() {
    if (!_editing) return;
    setState(() => _editing = false);
    _boxFocus.requestFocus();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => _submit(value));
    setState(() {});
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
    _field.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
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
    final kind = _kind;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: TvPageHeader(title: l10n.navSearch)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                tvGutter,
                0,
                tvGutter,
                MarqueeSpace.m,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildSearchBox(l10n, text)),
                      if (_field.text.isNotEmpty) ...[
                        const SizedBox(width: MarqueeSpace.s),
                        IconButton(
                          tooltip: l10n.clearSearch,
                          onPressed: _clear,
                          icon: const Icon(
                            Icons.close,
                            color: MarqueeColors.dust,
                          ),
                        ),
                      ],
                    ],
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
                        TvPill(
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
            ..._recentSearches(context),
            ..._genreGrid(context),
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  tvGutter,
                  MarqueeSpace.m,
                  tvGutter,
                  MarqueeSpace.m,
                ),
                child: TvSectionHeader(title: l10n.searchTitles),
              ),
            ),
            TvPagedGridSlivers(
              source: SearchSource(_query),
              filter: kind == null ? null : (i) => i.kind == kind,
              emptyMessage: l10n.searchNoResults(_query),
              onOpen: (_) =>
                  ref.read(searchHistoryProvider.notifier).add(_query),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBox(AppLocalizations l10n, MarqueeText text) {
    final field = TextField(
      controller: _field,
      focusNode: _inputFocus,
      readOnly: !_editing,
      onChanged: _onChanged,
      onSubmitted: (value) {
        _remember(value);
        _exitEdit();
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
      ),
    );
    return Focus(
      focusNode: _boxFocus,
      onFocusChange: (f) => setState(() => _boxFocused = f),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (!_editing &&
            (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter)) {
          _enterEdit();
          return KeyEventResult.handled;
        }
        if (_editing &&
            (key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.escape)) {
          _exitEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          border: _boxFocused && !_editing
              ? Border.all(color: MarqueeColors.bulb, width: 2)
              : null,
        ),
        child: ExcludeFocus(
          excluding: !_editing,
          child: GestureDetector(onTap: _enterEdit, child: field),
        ),
      ),
    );
  }

  List<Widget> _recentSearches(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(searchHistoryProvider);
    final notifier = ref.read(searchHistoryProvider.notifier);
    if (history.isEmpty) return const [];
    return [
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          tvGutter,
          MarqueeSpace.m,
          tvGutter,
          MarqueeSpace.l,
        ),
        sliver: SliverList.list(
          children: [
            Row(
              children: [
                Expanded(child: TvSectionHeader(title: l10n.recentSearches)),
                TextButton(
                  onPressed: notifier.clear,
                  child: Text(l10n.clearSearchHistory),
                ),
              ],
            ),
            const SizedBox(height: MarqueeSpace.xs),
            for (final query in history)
              _TvRecentSearchRow(
                query: query,
                onTap: () => _searchAgain(query),
                onRemove: () => notifier.remove(query),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _genreGrid(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final arabic = context.isArabicUi;
    final genres = ref.watch(genresProvider);
    final list = genres.value ?? const <Category>[];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            tvGutter,
            MarqueeSpace.m,
            tvGutter,
            MarqueeSpace.m,
          ),
          child: TvSectionHeader(title: l10n.browseGenres),
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
          padding: const EdgeInsetsDirectional.fromSTEB(
            tvGutter,
            0,
            tvGutter,
            MarqueeSpace.huge,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisExtent: 64,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => _TvGenreTile(
              label: list[i].name.resolve(arabic: arabic) ?? '',
              onTap: () => openGenre(context, list[i]),
            ),
          ),
        ),
    ];
  }
}

class _TvRecentSearchRow extends StatefulWidget {
  const _TvRecentSearchRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_TvRecentSearchRow> createState() => _TvRecentSearchRowState();
}

class _TvRecentSearchRowState extends State<_TvRecentSearchRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _focused ? MarqueeColors.boothRaised : null,
                borderRadius: const BorderRadius.all(MarqueeRadius.card),
                border: _focused
                    ? Border.all(color: MarqueeColors.bulb, width: 2)
                    : null,
              ),
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (f) {
                  setState(() => _focused = f);
                  if (f) tvEnsureVisible(context, alignment: 0.4);
                },
                focusColor: Colors.transparent,
                borderRadius: const BorderRadius.all(MarqueeRadius.card),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                          widget.query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.body.copyWith(color: MarqueeColors.cream),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: MarqueeSpace.xs),
          IconButton(
            tooltip: l10n.removeSearch(widget.query),
            onPressed: widget.onRemove,
            icon: const Icon(
              Icons.close,
              size: 20,
              color: MarqueeColors.dust,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvGenreTile extends StatefulWidget {
  const _TvGenreTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_TvGenreTile> createState() => _TvGenreTileState();
}

class _TvGenreTileState extends State<_TvGenreTile> {
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
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) tvEnsureVisible(context, alignment: 0.4);
        },
        focusColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _focused
                      ? MarqueeColors.bulb
                      : MarqueeColors.velvetStrong,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 7),
              ),
              const SizedBox(width: MarqueeSpace.m),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(
                    fontSize: 15,
                    color: _focused ? MarqueeColors.bulb : MarqueeColors.cream,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
