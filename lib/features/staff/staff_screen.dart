import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/navigation.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../../app/widgets/bulb_loader.dart';
import '../../app/widgets/error_view.dart';
import '../../app/widgets/paged_grid.dart';
import '../../app/widgets/sub_page.dart';
import '../../data/models/media_details.dart';
import 'staff_providers.dart';
import 'widgets/person_photo.dart';

/// An actor's, director's or writer's page, pushed inside the current tab:
/// photo, name and role, then every title they're credited on (newest
/// first, all at once: the API doesn't page it).
///
/// [args] (the credit that was tapped) lets the header draw at once.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key, required this.id, this.args});

  final String id;
  final PersonArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    final staff = ref.watch(staffProvider(id));
    final page = staff.value;
    final credit = args?.credit;
    final name = page?.name ?? credit?.name;

    final Widget body;
    if (page != null) {
      body = page.items.isEmpty
          ? _Message(l10n.listEmpty)
          : PosterGridSliver(items: page.items, gutter: gutter);
    } else if (staff.hasError) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorView(
          error: staff.error!,
          onRetry: () => ref.invalidate(staffProvider(id)),
        ),
      );
    } else if (staff.isLoading) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: BulbLoader(semanticLabel: l10n.loading)),
      );
    } else {
      body = _Message(l10n.personUnavailable);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  gutter - 4,
                  MarqueeSpace.m,
                  gutter,
                  0,
                ),
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: BackPill(),
                ),
              ),
            ),
            if (name != null)
              _Header(
                name: name,
                imageUrl: page?.imageUrl ?? credit?.imageUrl,
                role: _role(l10n, credit, page),
                count: page?.items.length,
                gutter: gutter,
              ),
            body,
            const SliverToBoxAdapter(
              child: SizedBox(height: MarqueeSpace.huge),
            ),
          ],
        ),
      ),
    );
  }

  /// The role the person was tapped as (from the title's credits, which are
  /// reliable), else the page's own, which the server localizes.
  static String? _role(
    AppLocalizations l10n,
    StaffCredit? credit,
    StaffPage? page,
  ) => switch (credit?.role) {
    StaffRole.actor => l10n.roleActor,
    StaffRole.director => l10n.roleDirector,
    StaffRole.writer => l10n.roleWriter,
    StaffRole.other || null => page?.role,
  };
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.imageUrl,
    required this.role,
    required this.count,
    required this.gutter,
  });

  final String name;
  final String? imageUrl;
  final String? role;
  final int? count;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final arabic = MarqueeText.hasArabic(name);
    final meta = [
      if (role != null && role!.isNotEmpty) role!,
      if (count != null) l10n.personTitleCount(count!),
    ].join(' · ');
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          gutter,
          MarqueeSpace.l,
          gutter,
          MarqueeSpace.xxl,
        ),
        child: Row(
          children: [
            PersonPhoto(name: name, imageUrl: imageUrl, size: 96),
            const SizedBox(width: MarqueeSpace.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      arabic ? name : name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.displayLargeFor(name).copyWith(fontSize: 30),
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: MarqueeSpace.xs),
                    Text(meta, style: text.caption),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: MarqueeText.of(context).body,
      ),
    ),
  );
}
