import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_row.dart';
import '../../../app/widgets/error_view.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/playback_request.dart';
import '../home_providers.dart';

/// Wide covers are about 2.7:1 (docs/API.md §Images).
const _coverRatio = 2.7;

/// From this content width the hero puts its text beside the banner.
const _sideBySide = 900.0;

/// The Home hero (DESIGN.md §5): the banners in a `booth` panel with a bulb
/// row and page bars, then "Now showing", the title, metadata and Play.
/// The carousel never moves by itself (nothing loops but the loader).
class HomeHero extends ConsumerStatefulWidget {
  const HomeHero({super.key, required this.gutter});

  final double gutter;

  @override
  ConsumerState<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends ConsumerState<HomeHero> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int index) => _pages.animateToPage(
    index,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(bannersProvider);
    final gutter = widget.gutter;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _sideBySide;
          final panelWidth = wide ? box.maxWidth * 0.6 : box.maxWidth;
          final items = banners.value ?? const <MediaItem>[];
          if (items.isEmpty && banners.hasError && !banners.isLoading) {
            return ErrorView(
              error: banners.error!,
              onRetry: () => ref.invalidate(bannersProvider),
              compact: true,
            );
          }
          if (items.isEmpty && !banners.isLoading) {
            return const SizedBox.shrink();
          }
          final current = items.isEmpty
              ? null
              : items[_index.clamp(0, items.length - 1)];
          final panel = SizedBox(
            width: panelWidth,
            child: _Panel(
              items: items,
              controller: _pages,
              index: _index,
              onPageChanged: (i) => setState(() => _index = i),
              onDot: _goTo,
            ),
          );
          final info = current == null
              ? const SizedBox.shrink()
              : _HeroInfo(item: current);
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                panel,
                const SizedBox(width: MarqueeSpace.xxxl),
                Expanded(child: info),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panel,
              const SizedBox(height: MarqueeSpace.l),
              info,
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.items,
    required this.controller,
    required this.index,
    required this.onPageChanged,
    required this.onDot,
  });

  final List<MediaItem> items;
  final PageController controller;
  final int index;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onDot;

  static const _coverRadius = BorderRadius.all(Radius.circular(8));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MarqueeColors.booth,
        borderRadius: BorderRadius.all(MarqueeRadius.panel),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 4),
              child: BulbRow(),
            ),
            const SizedBox(height: MarqueeSpace.s),
            AspectRatio(
              aspectRatio: _coverRatio,
              child: items.isEmpty
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: MarqueeColors.boothRaised,
                        borderRadius: _coverRadius,
                      ),
                    )
                  // Mouse drag too, so the carousel works on desktop.
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                      child: PageView.builder(
                        controller: controller,
                        itemCount: items.length,
                        onPageChanged: onPageChanged,
                        itemBuilder: (context, i) => Semantics(
                          button: true,
                          label: context.titleOf(items[i]),
                          child: GestureDetector(
                            onTap: () => openTitle(context, items[i]),
                            child: MediaImage(
                              url: items[i].backdropUrl,
                              borderRadius: _coverRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            if (items.length > 1) ...[
              const SizedBox(height: MarqueeSpace.s),
              _PageBars(count: items.length, index: index, onTap: onDot),
            ],
          ],
        ),
      ),
    );
  }
}

/// The carousel position: a wide `bulb` bar for the current page, short
/// `velvetStrong` bars for the rest. With many banners only a window of
/// bars around the current one is shown.
class _PageBars extends StatelessWidget {
  const _PageBars({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  static const _window = 9;

  @override
  Widget build(BuildContext context) {
    final first = (index - _window ~/ 2).clamp(
      0,
      (count - _window).clamp(0, count),
    );
    final last = (first + _window).clamp(0, count);
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = first; i < last; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: i == index ? 18 : 6,
                  height: 3,
                  decoration: BoxDecoration(
                    color: i == index
                        ? MarqueeColors.bulb
                        : MarqueeColors.velvetStrong,
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({required this.item});

  final MediaItem item;

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
        Text(
          arabicTitle ? title : title.toUpperCase(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: text.heroTitleFor(title),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(meta, style: text.caption),
        ],
        const SizedBox(height: MarqueeSpace.l),
        // A series banner plays the episode it links to (usually the newest).
        FilledButton.icon(
          onPressed: () => openPlayer(
            context,
            PlaybackRequest(item: item, episodeId: item.linkedEpisodeId),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(l10n.play),
          style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
        ),
      ],
    );
  }
}
