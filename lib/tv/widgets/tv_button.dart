import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';

/// A TV pill button, item [index] of its zone (the TV system sheet; docs/
/// TV.md §6.3). 48 tall.
/// - [primary]: the `bulb` button (one per screen). Focused, it keeps its
///   fill and gets a `cream` ring, so the ring shows against it.
/// - Otherwise outlined (`velvetStrong`), label at 500. Focused: a
///   `boothRaised` fill, the label at 600 and a `bulb` ring.
/// The ring sits 2 px out. Disabled ones stay visible in `dustDim`; the zone
/// skips them.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.index,
    required this.label,
    this.icon,
    this.onSelect,
    this.onLongSelect,
    this.primary = false,
    this.enabled = true,
  });

  final int index;
  final String label;
  final IconData? icon;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    return TvFocusable(
      index: index,
      label: label,
      enabled: enabled,
      onSelect: onSelect,
      onLongSelect: onLongSelect,
      builder: (context, focused) {
        final color = primary
            ? MarqueeColors.onBulb
            : enabled
            ? MarqueeColors.cream
            : MarqueeColors.dustDim;
        final weight = primary || focused ? FontWeight.w600 : FontWeight.w500;
        return TvRing(
          on: focused,
          radius: TvRing.pill,
          gap: TvFocusStyle.buttonGap,
          color: primary ? MarqueeColors.cream : MarqueeColors.bulb,
          child: Container(
            height: TvSpace.minTarget,
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: primary ? 24 : 22,
            ),
            decoration: ShapeDecoration(
              color: primary
                  ? MarqueeColors.bulb
                  : focused
                  ? MarqueeColors.boothRaised
                  : null,
              shape: StadiumBorder(
                side: primary
                    ? BorderSide.none
                    : const BorderSide(color: MarqueeColors.velvetStrong),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: text.label.withWeight(weight).copyWith(color: color),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
