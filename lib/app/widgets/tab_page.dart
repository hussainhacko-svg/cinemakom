import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';

/// The frame of a tab's first screen: the screen name in `displayLarge` at
/// the start edge (DESIGN.md §8), the responsive gutter, and [child] below.
/// With no [child], it shows a "Coming soon" note (screens built in later
/// phases).
class TabPage extends StatelessWidget {
  const TabPage({super.key, this.title, this.header, this.child});

  /// The screen name. Ignored when [header] is given.
  final String? title;

  /// Replaces the title (Home shows the logo instead).
  final Widget? header;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final gutter = MarqueeSpace.gutter(MediaQuery.sizeOf(context).width);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                gutter,
                MarqueeSpace.xl,
                gutter,
                MarqueeSpace.l,
              ),
              child:
                  header ??
                  Semantics(
                    header: true,
                    child: Text(
                      text.arabic ? title! : title!.toUpperCase(),
                      style: text.displayLarge,
                    ),
                  ),
            ),
            Expanded(
              child:
                  child ??
                  Center(
                    child: Text(
                      AppLocalizations.of(context).comingSoon,
                      style: text.caption,
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
