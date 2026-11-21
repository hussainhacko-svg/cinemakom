import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';
import '../focus/tv_focusable.dart';
import '../theme/tv_space.dart';
import '../theme/tv_text.dart';
import 'tv_focus_look.dart';

/// A TV filter chip, item [index] of its zone (the TV system sheet and Genre
/// design): a 40 dp pill.
/// - A picker chip ([name] set: "Sort · Recently added ▾") opens a panel:
///   `velvetStrong` border, the name in `dust`, the value in `cream`.
/// - A toggle chip ([selected]: Movies | Series, seasons): selected is a
///   `boothRaised` fill with a `velvetStrong` border and a `cream` label at
///   600; unselected is a `velvet` border and a `dust` label at 500.
/// Focus adds a `boothRaised` fill and the ring 2 px out, so selected and
/// focused never look the same.
class TvChip extends StatelessWidget {
  const TvChip({
    super.key,
    required this.index,
    required this.label,
    this.name,
    this.selected = false,
    this.onSelect,
    this.onFocus,
  });

  final int index;
  final String label;
  final String? name;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeTvText.of(context);
    final picker = name != null;
    return TvFocusable(
      index: index,
      label: picker ? '$name: $label' : label,
      onSelect: onSelect,
      onFocus: onFocus,
      builder: (context, focused) {
        final strong = picker || selected;
        return TvRing(
          on: focused,
          radius: TvRing.pill,
          gap: TvFocusStyle.buttonGap,
          child: Container(
            height: 40,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: focused || selected ? MarqueeColors.boothRaised : null,
              shape: StadiumBorder(
                side: BorderSide(
                  color: strong
                      ? MarqueeColors.velvetStrong
                      : MarqueeColors.velvet,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (picker) ...[
                  Text(name!, style: text.caption.copyWith(fontSize: 15)),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: text.label
                      .copyWith(fontSize: 15)
                      .withWeight(FontWeight.w500)
                      .copyWith(
                        color: picker || selected || focused
                            ? MarqueeColors.cream
                            : MarqueeColors.dust,
                      ),
                ),
                if (picker) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.expand_more,
                    size: 18,
                    color: MarqueeColors.cream,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
