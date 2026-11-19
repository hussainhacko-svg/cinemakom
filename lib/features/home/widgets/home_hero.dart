import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
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

/// On narrow screens each banner takes this share of the carousel, so the
/// next one peeks in at the end edge.
const _peekFraction = 0.9;

/// The gap between banners in the carousel.
const _gap = MarqueeSpace.s;

/// How long a banner stays before the carousel moves on.
const _advanceAfter = Duration(seconds: 7);

/// The Home hero (DESIGN.md §8): a row of marquee bulbs, one per banner
/// with the current one lit, over a carousel of wide covers where the next
/// one peeks in. Under it "Now showing", the title, metadata and Play,
/// which change with the banner.
///
/// The carousel moves on every [_advanceAfter] on a plain timer (no frames
/// in between). It holds while a finger is on it, while Home is hidden
/// (another tab, a pushed page, the player) and when the system asks for
/// fewer animations.
class HomeHero extends ConsumerStatefulWidget {
  const HomeHero({super.key, required this.gutter});

  final double gutter;

  @override
  ConsumerState<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends ConsumerState<HomeHero> {
  var _pages = PageController(viewportFraction: _peekFraction);
  int _index = 0;
  Timer? _timer;
  bool _held = false;
  bool _shown = true;
  bool _still = false;

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
    // Offstage tabs and routes under a full-screen one have tickers off.
    _shown = TickerMode.valuesOf(context).enabled;
    _still = MediaQuery.disableAnimationsOf(context);
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  int get _count => ref.read(bannersProvider).value?.length ?? 0;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_shown || _still || _held || _count < 2) return;
    _timer = Timer(_advanceAfter, () {
      if (!mounted || !_pages.hasClients) return;
      _goTo((_index + 1) % _count);
    });
  }

  void _goTo(int index) => _pages.animateToPage(
    index,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  void _hold(bool held) {
    _held = held;
    _restartTimer();
  }

  /// The controller for this layout: a peek on narrow screens, whole
  /// pages beside the text on wide ones.
  PageController _controllerFor(double fraction) {
    if (_pages.viewportFraction != fraction) {
      final old = _pages;
      _pages = PageController(viewportFraction: fraction, initialPage: _index);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return _pages;
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(bannersProvider);
    final gutter = widget.gutter;
    return LayoutBuilder(
      builder: (context, box) {
        final items = banners.value ?? const <MediaItem>[];
        if (items.isEmpty && banners.hasError && !banners.isLoading) {
          return Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
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
        final index = items.isEmpty ? 0 : _index.clamp(0, items.length - 1);
        final wide = box.maxWidth - 2 * gutter >= _sideBySide;
        final pager = items.length > 1
            ? _BulbPager(count: items.length, index: index, onTap: _goTo)
            : const SizedBox.shrink();
        // Every banner's text is laid out at once and only the current one
        // shows, so the hero is always as tall as its tallest text and the
        // page below never shifts when the banner changes.
        final info = Stack(
          children: [
            for (var i = 0; i < items.length; i++)
              IgnorePointer(
                ignoring: i != index,
                child: AnimatedOpacity(
                  opacity: i == index ? 1 : 0,
                  duration: _still
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: _HeroInfo(item: items[i]),
                ),
              ),
          ],
        );

        if (wide) {
          final width = (box.maxWidth - 2 * gutter) * 0.6;
          return Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
            child: Row(
              children: [
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      pager,
                      const SizedBox(height: MarqueeSpace.s),
                      _Carousel(
                        items: items,
                        controller: _controllerFor(1),
                        height: width / _coverRatio,
                        gap: 0,
                        clip: Clip.hardEdge,
                        onPageChanged: _onPageChanged,
                        onHold: _hold,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MarqueeSpace.xxxl),
                Expanded(child: info),
              ],
            ),
          );
        }

        // The carousel starts at the gutter and runs to the end edge, so
        // the next banner peeks in and the last one scrolls out past the
        // start gutter.
        final viewport = box.maxWidth - gutter;
        final cover = viewport * _peekFraction - _gap;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              child: pager,
            ),
            const SizedBox(height: MarqueeSpace.s),
            Padding(
              padding: EdgeInsetsDirectional.only(start: gutter),
              child: _Carousel(
                items: items,
                controller: _controllerFor(_peekFraction),
                height: cover / _coverRatio,
                gap: _gap,
                clip: Clip.none,
                onPageChanged: _onPageChanged,
                onHold: _hold,
              ),
            ),
            const SizedBox(height: MarqueeSpace.l),
            Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              child: info,
            ),
          ],
        );
      },
    );
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _restartTimer();
  }
}

class _Carousel extends StatelessWidget {
  const _Carousel({
    required this.items,
    required this.controller,
    required this.height,
    required this.gap,
    required this.clip,
    required this.onPageChanged,
    required this.onHold,
  });

  final List<MediaItem> items;
  final PageController controller;
  final double height;
  final double gap;
  final Clip clip;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<bool> onHold;

  static const _radius = BorderRadius.all(MarqueeRadius.card);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsetsDirectional.only(end: gap),
        child: SizedBox(
          height: height,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: MarqueeColors.boothRaised,
              borderRadius: _radius,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      // A finger on the carousel holds it still.
      child: Listener(
        onPointerDown: (_) => onHold(true),
        onPointerUp: (_) => onHold(false),
        onPointerCancel: (_) => onHold(false),
        // Mouse drag too, so the carousel works on desktop.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: PageView.builder(
            controller: controller,
            padEnds: false,
            clipBehavior: clip,
            itemCount: items.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsetsDirectional.only(end: gap),
              child: Semantics(
                button: true,
                label: context.titleOf(items[i]),
                child: GestureDetector(
                  onTap: () => openTitle(context, items[i]),
                  child: MediaImage(
                    url: items[i].backdropUrl,
                    borderRadius: _radius,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The marquee bulbs, one per banner: the current one lit `bulb`, the rest
/// `velvetStrong`. A tap on a bulb goes to its banner. With many banners
/// only a window of bulbs around the current one is shown.
class _BulbPager extends StatelessWidget {
  const _BulbPager({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  static const _window = 15;
  static const _size = 7.0;

  @override
  Widget build(BuildContext context) {
    final first = (index - _window ~/ 2).clamp(
      0,
      (count - _window).clamp(0, count),
    );
    final last = (first + _window).clamp(0, count);
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = first; i < last; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Padding(
                // The first bulb lines up with the banner's start edge.
                padding: EdgeInsetsDirectional.only(
                  end: MarqueeSpace.m,
                  top: MarqueeSpace.s,
                  bottom: MarqueeSpace.s,
                ),
                child: AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: _size,
                  height: _size,
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
