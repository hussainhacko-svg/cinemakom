import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../theme/marquee_text.dart';

/// A row heading: `sectionTitle` at the start, an optional "See all" link at
/// the end (DESIGN.md §5). Latin titles are uppercased; Arabic never is.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.focusSeeAll = true,
  });

  final String title;
  final VoidCallback? onSeeAll;
  final bool focusSeeAll;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final arabicTitle = MarqueeText.hasArabic(title);
    final onSeeAll = this.onSeeAll;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              arabicTitle ? title : title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: arabicTitle
                  ? text.sectionTitle.copyWith(letterSpacing: 0, height: 1.4)
                  : text.sectionTitle,
            ),
          ),
        ),
        if (onSeeAll != null)
          ExcludeFocus(
            excluding: !focusSeeAll,
            child: TextButton(
              onPressed: onSeeAll,
              child: Text(AppLocalizations.of(context).seeAll),
            ),
          ),
      ],
    );
  }
}
