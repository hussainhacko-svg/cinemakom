import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/error_view.dart';
import '../../../data/models/media_item.dart';
import '../../../data/paging/media_sources.dart';
import '../../../data/paging/paged_media.dart';
import '../tv_shell.dart' show tvGutter;
import 'tv_focus.dart';
import 'tv_poster_card.dart';

/// Poster width in TV horizontal rows (~5 posters visible across 960 dp).
const double tvRowPosterWidth = 142;

/// A TV horizontal poster carousel: non-focusable header so D-pad Down jumps
/// straight from poster row to poster row, with a focusable "See all" card at
/// the end of the row.
class TvMediaRow extends StatelessWidget {
  const TvMediaRow({
    super.key,
    required this.title,
    required this.items,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onSeeAll,
  });

  final String title;
  final List<MediaItem> items;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    if (items.isEmpty && !loading && error == null) {
      return const SizedBox.shrink();
    }
    final height = TvPosterCard.heightFor(tvRowPosterWidth);
    final Widget body;
    if (items.isEmpty && error != null) {
      body = SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: tvGutter),
          child: ErrorView(
            error: error,
            onRetry: onRetry ?? () {},
            compact: true,
          ),
        ),
      );
    } else {
      final placeholders = items.isEmpty;
      final hasSeeAll = !placeholders && onSeeAll != null;
      body = SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: tvGutter),
          itemCount: placeholders ? 6 : items.length + (hasSeeAll ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(width: MarqueeSpace.m),
          itemBuilder: (context, i) => SizedBox(
            width: tvRowPosterWidth,
            child: placeholders
                ? const _TvPosterPlaceholder()
                : hasSeeAll && i == items.length
                ? _TvSeeAllCard(onTap: onSeeAll!)
                : TvPosterCard(
                    item: items[i],
                    onTap: () => openTitle(context, items[i]),
                  ),
          ),
        ),
      );
    }

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
            child: TvSectionHeader(title: title),
          ),
          body,
        ],
      ),
    );
  }
}

/// A [TvMediaRow] backed by [pagedMediaProvider].
class TvSourceRow extends ConsumerWidget {
  const TvSourceRow({
    super.key,
    required this.title,
    required this.source,
    this.seeAll = true,
  });

  final String title;
  final MediaSource source;
  final bool seeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paged = ref.watch(pagedMediaProvider(source));
    return TvMediaRow(
      title: title,
      items: paged.items,
      loading: paged.isFirstLoad,
      error: paged.failedFirstPage ? paged.error : null,
      onRetry: () => ref.read(pagedMediaProvider(source).notifier).retry(),
      onSeeAll: seeAll && paged.items.isNotEmpty
          ? () => openList(context, MediaListArgs(title: title, source: source))
          : null,
    );
  }
}

class _TvSeeAllCard extends StatefulWidget {
  const _TvSeeAllCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TvSeeAllCard> createState() => _TvSeeAllCardState();
}

class _TvSeeAllCardState extends State<_TvSeeAllCard> {
  bool _focused = false;
  static const _radius = BorderRadius.all(MarqueeRadius.poster);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    return Semantics(
      button: true,
      label: l10n.seeAll,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Material(
              color: _focused ? MarqueeColors.boothRaised : MarqueeColors.booth,
              shape: RoundedRectangleBorder(
                borderRadius: _radius,
                side: _focused
                    ? const BorderSide(color: MarqueeColors.bulb, width: 2.5)
                    : const BorderSide(color: MarqueeColors.velvet),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (f) {
                  setState(() => _focused = f);
                  if (f) tvEnsureVisible(context, alignment: 0.5);
                },
                focusColor: Colors.transparent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: MarqueeColors.bulb,
                      size: 30,
                    ),
                    const SizedBox(height: MarqueeSpace.s),
                    Text(
                      l10n.seeAll,
                      style: text.label.copyWith(color: MarqueeColors.bulb),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvPosterPlaceholder extends StatelessWidget {
  const _TvPosterPlaceholder();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: 2 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MarqueeColors.booth,
            borderRadius: BorderRadius.all(MarqueeRadius.poster),
          ),
        ),
      ),
    ],
  );
}
