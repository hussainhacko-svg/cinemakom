import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/error_view.dart';
import '../../../app/widgets/media_text.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/playback_request.dart';
import '../../../data/repositories/library_repository.dart';
import '../../../features/home/home_providers.dart';
import '../../../features/home/widgets/hero_title.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_image.dart';

/// The Home hero on TV (the TV Home design, "side by side"): "NOW SHOWING",
/// the fitted title, the meta and Play · Favorite at the start; the banner
/// at its real 2.7:1 beside it, with the bulb pager under it.
///
/// Its buttons are zone [order], where Home's focus starts (Play, R11).
/// Left from Play shows the previous banner and Right from Favorite the
/// next one (R3's named exception), round the loop like the phone's. It
/// moves on by itself every 10 s, except while it has focus, while hidden,
/// and with animations off. The next and previous banners load hidden, so
/// a change shows at once.
class TvHomeHero extends ConsumerStatefulWidget {
  const TvHomeHero({super.key, required this.order});

  final int order;

  /// Tall enough for the longest title step, so the rows below never move.
  static const double height = 226;

  @override
  ConsumerState<TvHomeHero> createState() => _TvHomeHeroState();
}

class _TvHomeHeroState extends ConsumerState<TvHomeHero> {
  static const _advanceAfter = Duration(seconds: 10);

  int _index = 0;
  Timer? _timer;
  bool _held = false;
  bool _shown = true;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(bannersProvider, (_, _) => _restart());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    _still = MediaQuery.disableAnimationsOf(context);
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _count => ref.read(bannersProvider).value?.length ?? 0;

  void _restart() {
    _timer?.cancel();
    _timer = null;
    if (!_shown || _still || _held || _count < 2) return;
    _timer = Timer(_advanceAfter, () {
      if (mounted) _step(1);
    });
  }

  void _step(int delta) {
    final count = _count;
    if (count < 2) return;
    setState(() => _index = (_index + delta) % count);
    _restart();
  }

  /// Left past Play, Right past Favorite: the banner before or after.
  bool _edge(TraversalDirection dir) {
    if (dir != TraversalDirection.left && dir != TraversalDirection.right) {
      return false;
    }
    if (_count < 2) return false;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final towardsStart = (dir == TraversalDirection.left) != rtl;
    _step(towardsStart ? -1 : 1);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bannersProvider);
    final banners = async.value ?? const <MediaItem>[];
    if (banners.isEmpty) {
      final error = async.hasError ? async.error : null;
      // Loading (or none): a quiet `booth` block where the banner goes.
      // Failed (offline): why, and Try again where Play would be (R11).
      return SizedBox(
        height: TvHomeHero.height,
        child: Row(
          children: [
            SizedBox(
              width: 340 + 32,
              child: error == null
                  ? null
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          errorMessage(AppLocalizations.of(context), error),
                          style: MarqueeTvText.of(context).body
                              .copyWith(color: MarqueeColors.creamSoft),
                        ),
                        const SizedBox(height: 18),
                        TvZone.row(
                          order: widget.order,
                          initial: true,
                          keyline: 0,
                          child: TvButton(
                            index: 0,
                            primary: true,
                            label: AppLocalizations.of(context).retry,
                            onSelect: () => ref.invalidate(bannersProvider),
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AspectRatio(
                  aspectRatio: 2.7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: MarqueeColors.booth,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final i = _index % banners.length;
    final item = banners[i];
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        _held = focused;
        _restart();
      },
      child: SizedBox(
        height: TvHomeHero.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 340,
              child: _HeroText(item: item, order: widget.order, onEdge: _edge),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AspectRatio(
                    aspectRatio: 2.7,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (final d in [-1, 1])
                          if (banners.length > 1)
                            Offstage(
                              child: TvImage(
                                url: banners[(i + d) % banners.length]
                                    .backdropUrl,
                                radius: 12,
                              ),
                            ),
                        TvImage(
                          key: ValueKey(item.id),
                          url: item.backdropUrl,
                          radius: 12,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Bulbs(count: banners.length, current: i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroText extends ConsumerWidget {
  const _HeroText({
    required this.item,
    required this.order,
    required this.onEdge,
  });

  final MediaItem item;
  final int order;
  final bool Function(TraversalDirection) onEdge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final title = context.titleOf(item);
    final arabicTitle = MarqueeText.hasArabic(title);
    final meta = context.joinMeta(
      [
        context.cardMeta(item),
        if (item.duration case final d? when !item.isSeries)
          formatDuration(l10n, d),
      ].where((s) => s.isNotEmpty),
    );
    final saved = ref.watch(isFavoriteProvider(item.seriesId)).value ?? false;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.arabic ? l10n.nowShowing : l10n.nowShowing.toUpperCase(),
          style: text.eyebrow,
        ),
        const SizedBox(height: 10),
        HeroTitle(
          key: ValueKey(item.id),
          title: arabicTitle ? title : title.toUpperCase(),
          style: text.heroTitleFor(title),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(meta, style: text.caption),
        ],
        const SizedBox(height: 18),
        TvZone.row(
          order: order,
          initial: true,
          onEdge: onEdge,
          keyline: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A series banner plays the episode it links to (the newest).
              TvButton(
                index: 0,
                primary: true,
                icon: Icons.play_arrow_rounded,
                label: l10n.play,
                onSelect: () => tvOpenPlayer(
                  context,
                  PlaybackRequest(item: item, episodeId: item.linkedEpisodeId),
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: TvButton(
                  index: 1,
                  icon: saved ? Icons.bookmark : Icons.bookmark_border,
                  label: saved ? l10n.inFavorites : l10n.favorite,
                  onSelect: () {
                    final library = ref.read(libraryRepositoryProvider);
                    saved
                        ? library.removeFavorite(item.seriesId)
                        : library.addFavorite(item);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bulb pager under the banner: one bulb per banner, the current one
/// lit (DESIGN.md §4).
class _Bulbs extends StatelessWidget {
  const _Bulbs({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: 7);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == current
                  ? MarqueeColors.bulb
                  : MarqueeColors.velvetStrong,
            ),
          ),
        ],
      ],
    );
  }
}
