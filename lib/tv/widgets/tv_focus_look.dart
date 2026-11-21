import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_colors.dart';
import '../theme/tv_space.dart';

/// The focus look of a card (posters, wide cards, cast; docs/TV.md §6.3 and
/// the TV system sheet): it grows 8% from its bottom edge, so the title under
/// it stays clear, with a 3 px `bulb` ring 3 px out from its corners. A
/// `Transform` in its own `RepaintBoundary`, so growing one card doesn't
/// repaint the row, and nothing changes size. With animations off it only
/// shows the ring.
class TvCardFocus extends StatelessWidget {
  const TvCardFocus({
    super.key,
    required this.focused,
    required this.radius,
    this.scale = TvFocusStyle.cardScale,
    required this.child,
  });

  final bool focused;
  final double radius;

  /// How much it grows: [TvFocusStyle.wideCardScale] for wide cards.
  final double scale;
  final Widget child;

  /// How far a focused card of [size], growing by [scale], reaches past its
  /// sides and its top, ring included: the room its row must leave.
  static ({double side, double top}) reach(Size size, double scale) {
    const ring = TvFocusStyle.cardGap + TvFocusStyle.ring;
    return (
      side: size.width * (scale - 1) / 2 + ring,
      top: size.height * (scale - 1) + ring,
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: AnimatedScale(
        scale: focused && !still ? scale : 1,
        alignment: Alignment.bottomCenter,
        duration: still ? Duration.zero : TvFocusStyle.duration,
        curve: TvFocusStyle.curve,
        child: TvRing(
          on: focused,
          radius: radius,
          gap: TvFocusStyle.cardGap,
          child: child,
        ),
      ),
    );
  }
}

/// The 3 px focus ring (§6.3), drawn over [child] [gap] px out from its
/// edge, following its corner [radius] (a large radius makes a pill). `bulb`,
/// or `cream` around the `bulb` primary button. Painted, not a border, so
/// focusing never moves anything.
class TvRing extends StatelessWidget {
  const TvRing({
    super.key,
    required this.on,
    required this.radius,
    this.gap = 0,
    this.color = MarqueeColors.bulb,
    required this.child,
  });

  /// Pills (buttons, chips, tabs): the radius is clamped to half the height.
  static const double pill = 999;

  final bool on;
  final double radius;
  final double gap;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: on ? _RingPainter(radius, gap, color) : null,
    child: child,
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.radius, this.gap, this.color);

  final double radius;
  final double gap;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const w = TvFocusStyle.ring;
    final out = gap + w / 2;
    final rect = (Offset.zero & size).inflate(out);
    final r = (radius + out).clamp(0.0, rect.shortestSide / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.gap != gap || old.color != color;
}
