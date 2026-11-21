import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';

/// The Marquee loading indicator: a row of bulb dots that light in sequence
/// (DESIGN.md §4). It replaces spinners and shimmer everywhere.
///
/// One [CustomPaint] repaints per frame; nothing rebuilds. When the platform
/// asks for reduced motion, the dots are drawn lit and still.
class BulbLoader extends StatefulWidget {
  const BulbLoader({
    super.key,
    this.count = 7,
    this.dotSize = 6,
    this.gap = 6,
    this.semanticLabel,
  });

  final int count;
  final double dotSize;
  final double gap;

  /// Read by screen readers. Null hides the loader from them (use that when
  /// the surrounding UI already says something is loading).
  final String? semanticLabel;

  @override
  State<BulbLoader> createState() => _BulbLoaderState();
}

class _BulbLoaderState extends State<BulbLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final p = context.palette;
    final painter = CustomPaint(
      size: Size(w.count * w.dotSize + (w.count - 1) * w.gap, w.dotSize),
      painter: _BulbPainter(
        progress: _controller,
        still: MediaQuery.disableAnimationsOf(context),
        count: w.count,
        dotSize: w.dotSize,
        gap: w.gap,
        rtl: Directionality.of(context) == TextDirection.rtl,
        dimColor: p.velvetStrong,
        litColor: p.bulb,
      ),
    );
    final label = w.semanticLabel;
    return label == null
        ? ExcludeSemantics(child: painter)
        : Semantics(label: label, liveRegion: true, child: painter);
  }
}

class _BulbPainter extends CustomPainter {
  _BulbPainter({
    required this.progress,
    required this.still,
    required this.count,
    required this.dotSize,
    required this.gap,
    required this.rtl,
    required this.dimColor,
    required this.litColor,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final bool still;
  final int count;
  final double dotSize;
  final double gap;
  final bool rtl;
  final Color dimColor;
  final Color litColor;

  static final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    // A lit "head" travels along the row with a short fading tail, like a
    // chasing marquee. The light moves in reading direction.
    final head = progress.value * (count + 2) - 1;
    final r = dotSize / 2;
    for (var i = 0; i < count; i++) {
      final distance = head - i;
      final glow = still
          ? 1.0
          : distance >= 0 && distance < 3
          ? 1 - distance / 3
          : 0.0;
      _paint.color = Color.lerp(dimColor, litColor, glow)!;
      final slot = rtl ? count - 1 - i : i;
      canvas.drawCircle(Offset(r + slot * (dotSize + gap), r), r, _paint);
    }
  }

  @override
  bool shouldRepaint(_BulbPainter old) =>
      old.still != still ||
      old.count != count ||
      old.dotSize != dotSize ||
      old.gap != gap ||
      old.rtl != rtl ||
      old.dimColor != dimColor ||
      old.litColor != litColor;
}
