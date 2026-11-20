import 'package:material_ui/material_ui.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../focus/tv_screen.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import '../widgets/tv_button.dart';

/// A screen the TV app doesn't have yet (Details in TV-3, the player in
/// TV-4, the other tabs in TV-5): says so, with Back as a button. As a tab
/// ([tab]) it has nothing to focus, so focus stays on the tab bar.
class TvPendingScreen extends StatelessWidget {
  const TvPendingScreen({super.key, this.tab = false});

  final bool tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    return TvScreen(
      order: 1,
      builder: (context, scroll) => Padding(
        padding: TvSpace.safe,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.tvNotYet,
                textAlign: TextAlign.center,
                style: text.body.copyWith(color: MarqueeColors.dust),
              ),
              if (!tab) ...[
                const SizedBox(height: 24),
                TvZone.row(
                  order: 0,
                  initial: true,
                  keyline: 0,
                  child: TvButton(
                    index: 0,
                    primary: true,
                    icon: Icons.arrow_back,
                    label: l10n.tvBack,
                    onSelect: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
