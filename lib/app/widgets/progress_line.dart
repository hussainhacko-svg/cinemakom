import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';

/// How much was watched: a 3 px `bulb` bar on a `velvet` track (DESIGN.md
/// §5). [value] is 0–1. It fills from the start edge.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 3,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: MarqueeColors.velvet,
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: value.clamp(0.0, 1.0),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: MarqueeColors.bulb,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    ),
  );
}
