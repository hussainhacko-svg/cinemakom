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
            _SegmentItem(
              label: label,
              selected: value == selected,
              style: value == selected
                  ? text.label.copyWith(fontSize: 13)
                  : text.label
                        .copyWith(fontSize: 13, color: MarqueeColors.dust)
                        .withWeight(FontWeight.w500),
              onTap: () => onChanged(value),
            ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatefulWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  State<_SegmentItem> createState() => _SegmentItemState();
}

class _SegmentItemState extends State<_SegmentItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    selected: widget.selected,
    button: true,
    child: Material(
      color: widget.selected ? MarqueeColors.boothRaised : Colors.transparent,
      shape: StadiumBorder(
        side: _focused
            ? const BorderSide(color: MarqueeColors.bulb, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
          child: Center(
            widthFactor: 1,
            child: Text(widget.label, style: widget.style),
          ),
        ),
      ),
    ),
  );
}

/// A filter chip (DESIGN.md §5).
class FilterPill extends StatefulWidget {
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
  State<FilterPill> createState() => _FilterPillState();
}

class _FilterPillState extends State<FilterPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    return Semantics(
      selected: widget.selected,
      button: true,
      excludeSemantics: true,
      label: widget.label,
      child: Material(
        color: widget.selected || _focused
            ? MarqueeColors.boothRaised
            : Colors.transparent,
        shape: StadiumBorder(
          side: _focused
              ? const BorderSide(color: MarqueeColors.bulb, width: 2)
              : BorderSide(
                  color: widget.selected
                      ? MarqueeColors.velvetStrong
                      : MarqueeColors.velvet,
                ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          focusColor: Colors.transparent,
          // Sized to its label, also inside a stretching Column or Wrap.
          child: Container(
            height: 36,
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                widget.label,
                style: widget.selected
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
