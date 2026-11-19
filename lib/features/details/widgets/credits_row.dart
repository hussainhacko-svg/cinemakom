import 'package:material_ui/material_ui.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';
import '../../../app/widgets/media_image.dart';
import '../../../app/widgets/section_header.dart';
import '../../../data/models/media_details.dart';

/// "Cast and crew": round photos (or initials) with name and role. Actor
/// pages come in Phase 7, so the people aren't tappable yet.
class CreditsRow extends StatelessWidget {
  const CreditsRow({super.key, required this.details, required this.gutter});

  final MediaDetails details;
  final double gutter;

  static const _maxPeople = 16;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seen = <String>{};
    final people = [
      for (final p in [
        ...details.directors,
        ...details.actors,
        ...details.writers,
      ])
        if (seen.add(p.id)) p,
    ].take(_maxPeople).toList();
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: MarqueeSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
            child: SectionHeader(title: l10n.castAndCrew),
          ),
          const SizedBox(height: MarqueeSpace.m),
          SizedBox(
            height: 144,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _Person(credit: people[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.credit});

  final StaffCredit credit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeText.of(context);
    final role = switch (credit.role) {
      StaffRole.actor => l10n.roleActor,
      StaffRole.director => l10n.roleDirector,
      StaffRole.writer => l10n.roleWriter,
      StaffRole.other => '',
    };
    final initials = credit.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    return Semantics(
      label: role.isEmpty ? credit.name : '${credit.name}, $role',
      excludeSemantics: true,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: MarqueeColors.booth,
                border: Border.fromBorderSide(
                  BorderSide(color: MarqueeColors.velvet),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: credit.imageUrl == null
                  ? Text(
                      initials,
                      style: text.label.copyWith(color: MarqueeColors.dust),
                    )
                  : MediaImage(url: credit.imageUrl),
            ),
            const SizedBox(height: 6),
            Text(
              credit.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: text.caption
                  .copyWith(color: MarqueeColors.cream)
                  .withWeight(FontWeight.w600),
            ),
            if (role.isNotEmpty)
              Text(role, style: text.caption.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
