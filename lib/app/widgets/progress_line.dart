import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';

/// How much was watched: a 3 px `bulb` bar on a `velvet` track (DESIGN.md
/// §5). [value] is 0–1. It fills from the start edge.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    this.track,
  });

  final double value;

  /// The unfilled part; defaults to `velvet`, use `velvetStrong` on a `booth`
  /// row.
  final Color? track;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 3,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: track ?? context.palette.velvet,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: value.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.palette.bulb,
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    ),
  );
}
