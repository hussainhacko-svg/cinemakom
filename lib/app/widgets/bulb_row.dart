import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';

/// A still row of marquee bulbs spread across the available width, with an
/// occasional dimmed bulb (DESIGN.md §4): the frame above the hero banner.
class BulbRow extends StatelessWidget {
  const BulbRow({super.key, this.dotSize = 5, this.spacing = 22});

  final double dotSize;

  /// The target distance between bulb centres.
  final double spacing;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: dotSize,
      width: double.infinity,
      child: CustomPaint(painter: _BulbRowPainter(dotSize, spacing)),
    ),
  );
}

class _BulbRowPainter extends CustomPainter {
  const _BulbRowPainter(this.dotSize, this.spacing);

  final double dotSize;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final r = dotSize / 2;
    final count = ((size.width - dotSize) / spacing).floor() + 1;
    if (count < 2) return;
    final step = (size.width - dotSize) / (count - 1);
    final lit = Paint()..color = MarqueeColors.bulb;
    final dim = Paint()..color = MarqueeColors.velvetStrong;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(Offset(r + i * step, r), r, i % 8 == 3 ? dim : lit);
    }
  }

  @override
  bool shouldRepaint(_BulbRowPainter old) =>
      old.dotSize != dotSize || old.spacing != spacing;
}
