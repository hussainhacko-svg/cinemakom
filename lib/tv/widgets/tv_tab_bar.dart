import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../focus/tv_focusable.dart';
import '../focus/tv_zone.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';
import 'tv_steady_text.dart';

/// The TV's top tabs (docs/TV.md §6.4, the TvTabs design): the mark, then
/// Home · Search · Library · Downloads · Settings as 40 dp pills. The current
/// tab is a `boothRaised` pill with a `bulb` label at 600; the others are
/// `dust` at 500; focus adds the ring. Moving onto a tab switches to it, as
/// on Google TV's own home screen, and entering the bar always lands on the
/// current tab.
class TvTabBar extends StatelessWidget {
  const TvTabBar({super.key, required this.current, required this.onTab});

  final int current;
  final ValueChanged<int> onTab;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = MarqueeTvText.of(context);
    final labels = [
      l10n.navHome,
      l10n.navSearch,
      l10n.navLibrary,
      l10n.navDownloads,
      l10n.navSettings,
    ];
    return SizedBox(
      height: height,
      child: Row(
        children: [
          const CinemakomMark(size: 40, semanticLabel: null),
          const SizedBox(width: 18),
          TvZone.row(
            order: 0,
            initialIndex: current,
            remember: false,
            keyline: 0,
            child: Row(
              children: [
                for (final (i, label) in labels.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  TvFocusable(
                    index: i,
                    label: label,
                    onFocus: () {
                      if (i != current) onTab(i);
                    },
                    onSelect: () => onTab(i),
                    builder: (context, focused) {
                      final on = i == current;
                      return TvRing(
                        on: focused,
                        radius: TvRing.pill,
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 18,
                          ),
                          decoration: BoxDecoration(
                            color: on ? MarqueeColors.boothRaised : null,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: TvSteadyText(
                            label,
                            style: text.navLabel
                                .withWeight(
                                  on ? FontWeight.w600 : FontWeight.w500,
                                )
                                .copyWith(
                                  color: on
                                      ? MarqueeColors.bulb
                                      : MarqueeColors.dust,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
