import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation_args.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/error_view.dart';
import '../../../features/staff/staff_providers.dart';
import '../../focus/tv_screen.dart';
import '../../focus/tv_zone.dart';
import '../../theme/tv_space.dart';
import '../../theme/tv_text.dart';
import '../../tv_navigation.dart';
import '../../widgets/tv_button.dart';
import '../../widgets/tv_paged_grid.dart';
import '../../widgets/tv_poster_card.dart';
import '../details/tv_details_screen.dart';

/// A person's page on TV: their photo, name and role · "31 titles", then
/// every title they're credited on, newest first, as a grid (all at once:
/// the API doesn't page it). Focus starts on the first poster. [args] (the
/// credit that was opened) draws the header at once.
class TvPersonScreen extends ConsumerWidget {
  const TvPersonScreen({super.key, required this.id, this.args});

  final String id;
  final PersonArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final staff = ref.watch(staffProvider(id));
    final page = staff.value;
    final credit = args?.credit;
    final name = page?.name ?? credit?.name ?? '';
    final role = credit != null ? tvRoleLabel(l10n, credit.role) : page?.role;
    final items = page?.items ?? const [];
    final caption = [
      if (role != null && role.isNotEmpty) role,
      if (page != null) l10n.personTitleCount(items.length),
    ].join(' · ');

    final Widget body;
    if (page != null && items.isNotEmpty) {
      body = SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          TvSpace.safeH,
          TvPoster.growRoom,
          TvSpace.safeH,
          TvSpace.safeV,
        ),
        sliver: TvZone.grid(
          order: 0,
          columns: tvGridColumns,
          initial: true,
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
    } else {
      final message = staff.hasError
          ? errorMessage(l10n, staff.error!)
          : page == null && !staff.isLoading
          ? l10n.personUnavailable
          : page != null
          ? l10n.listEmpty
          : null;
      body = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(TvSpace.safeH),
          child: message == null
              ? Center(child: BulbLoader(semanticLabel: l10n.loading))
              : Column(
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: text.body.copyWith(color: context.palette.dust),
                    ),
                    if (staff.hasError) ...[
                      const SizedBox(height: 20),
                      TvZone.row(
                        order: 0,
                        initial: true,
                        keyline: 0,
                        child: TvButton(
                          index: 0,
                          label: l10n.retry,
                          onSelect: () => ref.invalidate(staffProvider(id)),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      );
    }

    return TvScreen(
      order: 1,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                TvSpace.safeH,
                TvSpace.safeV,
                TvSpace.safeH,
                0,
              ),
              child: Row(
                children: [
                  TvPersonPhoto(
                    name: name,
                    url: page?.imageUrl ?? credit?.imageUrl,
                    size: 96,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MarqueeText.hasArabic(name)
                              ? name
                              : name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text
                              .displayLargeFor(name)
                              .copyWith(fontSize: 36),
                        ),
                        if (caption.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(caption, style: text.caption),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body,
        ],
      ),
    );
  }
}
