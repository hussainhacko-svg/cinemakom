import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/navigation.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/bulb_loader.dart';
import '../../../app/widgets/error_view.dart';
import '../../../data/models/media_details.dart';
import '../../staff/staff_screen.dart' show staffProvider;
import '../../staff/widgets/person_photo.dart';
import '../tv_shell.dart' show tvGutter;
import '../widgets/tv_paged_grid.dart';

/// Dedicated 10-foot Android TV person page: photo, name, role and title
/// count, then an HD poster grid with focus on the first title.
class TvStaffScreen extends ConsumerWidget {
  const TvStaffScreen({super.key, required this.id, this.args});

  final String id;
  final PersonArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final staff = ref.watch(staffProvider(id));
    final page = staff.value;
    final credit = args?.credit;
    final name = page?.name ?? credit?.name;

    final Widget body;
    if (page != null) {
      body = page.items.isEmpty
          ? _Message(l10n.listEmpty)
          : TvPosterGridSliver(items: page.items, autofocusFirst: true);
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

    final role = switch (credit?.role) {
      StaffRole.actor => l10n.roleActor,
      StaffRole.director => l10n.roleDirector,
      StaffRole.writer => l10n.roleWriter,
      StaffRole.other || null => page?.role,
    };

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          if (name != null)
            _Header(
              name: name,
              imageUrl: page?.imageUrl ?? credit?.imageUrl,
              role: role,
              count: page?.items.length,
            ),
          body,
          const SliverToBoxAdapter(child: SizedBox(height: MarqueeSpace.huge)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.imageUrl,
    required this.role,
    required this.count,
  });

  final String name;
  final String? imageUrl;
  final String? role;
  final int? count;

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
        padding: const EdgeInsetsDirectional.fromSTEB(
          tvGutter,
          MarqueeSpace.l,
          tvGutter,
          MarqueeSpace.xl,
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
