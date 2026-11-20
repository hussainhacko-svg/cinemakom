import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/catalog_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/error_view.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../data/models/catalog_models.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/playback_request.dart';
import '../../../data/paging/media_sources.dart';
import '../../../data/paging/paged_media.dart';
import '../../home/home_providers.dart';
import '../../home/widgets/hero_title.dart';
import '../../library/library_providers.dart';
import '../../library/widgets/favorite_button.dart';
import '../tv_shell.dart' show tvGutter, tvPrimaryFocusLabel;
import '../widgets/tv_continue_card.dart';
import '../widgets/tv_focus.dart';
import '../widgets/tv_media_row.dart';

const _genreRows = 12;
const _coverRatio = 2.7;
const _loopBase = 10000;
const _advanceAfter = Duration(seconds: 10);

int _bannerAt(int page, int count) => (page - _loopBase) % count;

/// Dedicated 10-foot Android TV Home screen:
/// - side-by-side HD hero banner with D-pad prev/next steppers and landing
///   focus on Play,
/// - Continue watching row with sibling Remove buttons,
/// - curated groups, catalog rows, and genre rows with HD `TvPosterCard`s and
///   end-of-row "See all" cards.
class TvHomeScreen extends ConsumerWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(videoGroupsProvider);
    final genres = ref.watch(genresProvider).value ?? const <Category>[];

    final rows = <Widget>[
      if (groups.isLoading && !groups.hasValue)
        const TvMediaRow(title: '', items: [], loading: true),
      for (final g in groups.value ?? const <VideoGroup>[])
        TvMediaRow(
          title: g.title,
          items: g.items,
          onSeeAll: g.hasPagination
              ? () => openList(
                  context,
                  MediaListArgs(title: g.title, source: GroupSource(g.id)),
                )
              : null,
        ),
      TvSourceRow(title: l10n.rowFeatured, source: const FeaturedSource()),
      TvSourceRow(
        title: l10n.rowLatestMovies,
        source: const LatestSource(VideoKind.movies),
      ),
      TvSourceRow(
        title: l10n.rowLatestSeries,
        source: const LatestSource(VideoKind.series),
      ),
      TvSourceRow(
        title: l10n.rowMostWatched,
        source: const CatalogSource(VideoKind.movies, SortOrder.mostViewed),
      ),
      TvSourceRow(
        title: l10n.rowNewReleases,
        source: const CatalogSource(VideoKind.movies, SortOrder.newestRelease),
      ),
      TvSourceRow(
        title: l10n.rowRecentlyAdded,
        source: const CatalogSource(VideoKind.movies, SortOrder.recentlyAdded),
      ),
      for (final genre in genres.take(_genreRows)) _TvGenreRow(genre: genre),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: MarqueeSpace.l)),
          const SliverToBoxAdapter(child: _TvHero()),
          const SliverToBoxAdapter(child: _TvContinueRow()),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => rows[i],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: MarqueeSpace.huge)),
        ],
      ),
    );
  }
}

class _TvGenreRow extends ConsumerWidget {
  const _TvGenreRow({required this.genre});

  final Category genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = GenreSource(categoryId: genre.id);
    final paged = ref.watch(pagedMediaProvider(source));
    final title = genre.name.resolve(arabic: context.isArabicUi) ?? '';
    return TvMediaRow(
      title: title,
      items: paged.items,
      loading: paged.isFirstLoad,
      error: paged.failedFirstPage ? paged.error : null,
      onRetry: () => ref.read(pagedMediaProvider(source).notifier).retry(),
      onSeeAll: () => openGenre(context, genre),
    );
  }
}

class _TvContinueRow extends ConsumerWidget {
  const _TvContinueRow();

  static const _cardWidth = 340.0;
  static const _cardHeight = 104.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(continueEntriesProvider).value ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              tvGutter,
              0,
              tvGutter,
              MarqueeSpace.s,
            ),
            child: TvSectionHeader(
              title: AppLocalizations.of(context).rowContinueWatching,
            ),
          ),
          SizedBox(
            height: _cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: tvGutter,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: MarqueeSpace.m),
              itemBuilder: (_, i) => SizedBox(
                width: _cardWidth,
                child: TvContinueCard(entry: items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvHero extends ConsumerStatefulWidget {
  const _TvHero();

  @override
  ConsumerState<_TvHero> createState() => _TvHeroState();
}

class _TvHeroState extends ConsumerState<_TvHero> {
  final _pages = PageController(initialPage: _loopBase);
  final Map<int, FocusNode> _playNodes = {};
  int _index = 0;
  Timer? _timer;
  bool _held = false;
  bool _shown = true;
  bool _still = false;
  bool _initialFocusRequested = false;

  FocusNode _playNodeFor(int i) => _playNodes.putIfAbsent(
    i,
    () => FocusNode(debugLabel: tvPrimaryFocusLabel),
  );

  void _maybeRequestInitialFocus(int count) {
    if (_initialFocusRequested || count == 0 || !_shown) return;
    _initialFocusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shown) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null || primary is FocusScopeNode) {
        final safe = _index.clamp(0, count - 1);
        _playNodeFor(safe).requestFocus();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      bannersProvider,
      (_, _) => _restartTimer(),
      fireImmediately: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    _still = MediaQuery.disableAnimationsOf(context);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    for (final node in _playNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  int get _count => ref.read(bannersProvider).value?.length ?? 0;

  int get _currentPage => _pages.hasClients
      ? (_pages.page ?? _pages.initialPage.toDouble()).round()
      : _pages.initialPage;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_shown || _still || _held || _count < 2) return;
    _timer = Timer(_advanceAfter, () {
      if (!mounted || !_pages.hasClients) return;
      _toPage(_currentPage + 1);
    });
  }

  void _toPage(int page) => _pages.animateToPage(
    page,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  void _hold(bool held) {
    _held = held;
    _restartTimer();
  }

  void _onPageChanged(int page) {
    final count = _count;
    if (count == 0) return;
    setState(() => _index = _bannerAt(page, count));
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(bannersProvider);
    return LayoutBuilder(
      builder: (context, box) {
        final items = banners.value ?? const <MediaItem>[];
        if (items.isEmpty && banners.hasError && !banners.isLoading) {
          return Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: tvGutter,
            ),
            child: ErrorView(
              error: banners.error!,
              onRetry: () => ref.invalidate(bannersProvider),
              compact: true,
            ),
          );
        }
        if (items.isEmpty && !banners.isLoading) {
          return const SizedBox.shrink();
        }
        _maybeRequestInitialFocus(items.length);
        final index = items.isEmpty ? 0 : _index.clamp(0, items.length - 1);
        final coverWidth = (box.maxWidth - 2 * tvGutter) * 0.54;

        final pager = items.length > 1
            ? _TvBulbPager(
                count: items.length,
                index: index,
                onStep: (delta) => _toPage(_currentPage + delta),
              )
            : const SizedBox.shrink();

        final info = Stack(
          alignment: AlignmentDirectional.bottomStart,
          children: [
            for (var i = 0; i < items.length; i++)
              ExcludeFocus(
                excluding: i != index,
                child: IgnorePointer(
                  ignoring: i != index,
                  child: AnimatedOpacity(
                    opacity: i == index ? 1 : 0,
                    duration: _still
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    child: _TvHeroInfo(
                      item: items[i],
                      playFocusNode: _playNodeFor(i),
                    ),
                  ),
                ),
              ),
          ],
        );

        return Focus(
          skipTraversal: true,
          canRequestFocus: false,
          onFocusChange: _hold,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: tvGutter,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: coverWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      pager,
                      const SizedBox(height: MarqueeSpace.s),
                      _TvHeroCoverCarousel(
                        items: items,
                        controller: _pages,
                        height: coverWidth / _coverRatio,
                        onPageChanged: _onPageChanged,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MarqueeSpace.xxxl),
                Expanded(child: info),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TvHeroCoverCarousel extends StatelessWidget {
  const _TvHeroCoverCarousel({
    required this.items,
    required this.controller,
    required this.height,
    required this.onPageChanged,
  });

  final List<MediaItem> items;
  final PageController controller;
  final double height;
  final ValueChanged<int> onPageChanged;

  static const _radius = BorderRadius.all(MarqueeRadius.card);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SizedBox(
        height: height,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: MarqueeColors.boothRaised,
            borderRadius: _radius,
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: controller,
        itemCount: items.length > 1 ? null : 1,
        onPageChanged: onPageChanged,
        itemBuilder: (context, i) {
          final item = items[items.length > 1 ? _bannerAt(i, items.length) : 0];
          return _TvHeroCover(
            item: item,
            radius: _radius,
            onTap: () => openTitle(context, item),
          );
        },
      ),
    );
  }
}

class _TvHeroCover extends StatefulWidget {
  const _TvHeroCover({
    required this.item,
    required this.radius,
    required this.onTap,
  });

  final MediaItem item;
  final BorderRadius radius;
  final VoidCallback onTap;

  @override
  State<_TvHeroCover> createState() => _TvHeroCoverState();
}

class _TvHeroCoverState extends State<_TvHeroCover> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.titleOf(widget.item),
    child: InkWell(
      onTap: widget.onTap,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) tvEnsureVisible(context, alignment: 0.2);
      },
      borderRadius: widget.radius,
      focusColor: Colors.transparent,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          border: _focused
              ? Border.all(color: MarqueeColors.bulb, width: 2.5)
              : null,
        ),
        child: MediaImage(
          url: widget.item.backdropUrl,
          borderRadius: widget.radius,
          decodeScale: 2.0,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}

class _TvBulbPager extends StatelessWidget {
  const _TvBulbPager({
    required this.count,
    required this.index,
    required this.onStep,
  });

  final int count;
  final int index;
  final ValueChanged<int> onStep;

  static const _widePitch = 19.0;
  static const _tightPitch = 12.0;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final bulbs = ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final pitch = (box.maxWidth / count).clamp(_tightPitch, _widePitch);
          final size = (pitch * 0.37).clamp(5.0, 7.0);
          final perPage = (box.maxWidth / pitch).floor().clamp(1, count);
          final first = index ~/ perPage * perPage;
          final last = (first + perPage).clamp(0, count);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = first; i < last; i++)
                SizedBox(
                  width: pitch,
                  height: size + 2 * MarqueeSpace.s,
                  child: Align(
                    child: AnimatedContainer(
                      duration: still
                          ? Duration.zero
                          : const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: i == index
                            ? MarqueeColors.bulb
                            : MarqueeColors.velvetStrong,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
    return Row(
      children: [
        IconButton(
          onPressed: () => onStep(-1),
          icon: const Icon(Icons.chevron_left, size: 22),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            fixedSize: const Size.square(36),
            padding: EdgeInsets.zero,
          ),
        ),
        Expanded(child: bulbs),
        IconButton(
          onPressed: () => onStep(1),
          icon: const Icon(Icons.chevron_right, size: 22),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            fixedSize: const Size.square(36),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _TvHeroInfo extends StatelessWidget {
  const _TvHeroInfo({required this.item, required this.playFocusNode});

  final MediaItem item;
  final FocusNode playFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final title = context.titleOf(item);
    final arabicTitle = MarqueeText.hasArabic(title);
    final meta = [
      context.cardMeta(item),
      if (item.duration case final d? when !item.isSeries)
        formatDuration(l10n, d),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text.arabic ? l10n.nowShowing : l10n.nowShowing.toUpperCase(),
          style: text.eyebrow,
        ),
        const SizedBox(height: 6),
        HeroTitle(
          title: arabicTitle ? title : title.toUpperCase(),
          style: text.heroTitleFor(title),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(meta, style: text.caption),
        ],
        const SizedBox(height: MarqueeSpace.l),
        Wrap(
          spacing: MarqueeSpace.m,
          runSpacing: MarqueeSpace.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              focusNode: playFocusNode,
              onPressed: () => openPlayer(
                context,
                PlaybackRequest(item: item, episodeId: item.linkedEpisodeId),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: Text(l10n.play),
              style: FilledButton.styleFrom(minimumSize: const Size(156, 48)),
            ),
            FavoriteIconButton(item: item),
          ],
        ),
      ],
    );
  }
}
