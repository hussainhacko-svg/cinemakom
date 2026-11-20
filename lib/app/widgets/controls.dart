import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';

/// A segmented control (DESIGN.md §5): `booth` track, the selected segment
/// a `boothRaised` pill.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: const ShapeDecoration(
        color: MarqueeColors.booth,
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in segments)
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: value == selected,
              button: true,
              child: Material(
                color: value == selected
                    ? MarqueeColors.boothRaised
                    : Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onChanged(value),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 14,
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        label,
                        style: value == selected
                            ? text.label.copyWith(fontSize: 13)
                            : text.label
                                  .copyWith(
                                    fontSize: 13,
                                    color: MarqueeColors.dust,
                                  )
                                  .withWeight(FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A filter chip (DESIGN.md §5).
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Semantics(
      selected: selected,
      button: true,
      excludeSemantics: true,
      label: label,
      child: Material(
        color: selected ? MarqueeColors.boothRaised : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? MarqueeColors.velvetStrong : MarqueeColors.velvet,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Sized to its label, also inside a stretching Column or Wrap.
          child: Container(
            height: 36,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: selected
                    ? text.label.copyWith(fontSize: 13)
                    : text.label
                          .copyWith(fontSize: 13, color: MarqueeColors.dust)
                          .withWeight(FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
