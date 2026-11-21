import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';

/// A 44 px round back button (`booth` fill, `velvet` border), mirrored in
/// RTL. Pops the current page of the tab.
class BackPill extends StatelessWidget {
  const BackPill({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: () => context.pop(),
    style: IconButton.styleFrom(
      backgroundColor: context.palette.booth,
      side: BorderSide(color: context.palette.velvet),
      fixedSize: const Size.square(44),
    ),
    icon: const Icon(Icons.arrow_back, size: 20),
  );
}

/// The header of a page pushed inside a tab: back button and title
/// (`displayLarge`, Latin uppercased), as a sliver.
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, required this.gutter});

  final String title;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final arabic = MarqueeText.hasArabic(title);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          gutter - 4,
          MarqueeSpace.m,
          gutter,
          MarqueeSpace.m,
        ),
        child: Row(
          children: [
            const BackPill(),
            const SizedBox(width: MarqueeSpace.m),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  arabic ? title : title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.displayLargeFor(title).copyWith(fontSize: 34),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
