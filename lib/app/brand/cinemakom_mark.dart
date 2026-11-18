import 'package:material_ui/material_ui.dart';

import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';
import 'brand_paths.g.dart';

/// How much of the ticket's detail to draw (docs/DESIGN.md §7).
enum MarkDetail { full, small, tiny }

/// The Cinemakom ticket mark, drawn from the generated paths: sharp at any
/// size, no image decoding. Detail follows [size] unless [detail] is given.
class CinemakomMark extends StatelessWidget {
  const CinemakomMark({
    super.key,
    this.size = 48,
    this.color = MarqueeColors.bulb,
    this.detail,
    this.semanticLabel = 'Cinemakom',
  });

  /// Width and height of the square box the 100×100 design is scaled into.
  final double size;
  final Color color;
  final MarkDetail? detail;
  final String? semanticLabel;

  static MarkDetail detailFor(double size) => size >= 48
      ? MarkDetail.full
      : size >= 24
      ? MarkDetail.small
      : MarkDetail.tiny;

  @override
  Widget build(BuildContext context) {
    final painter = CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(detail ?? detailFor(size), color),
    );
    return semanticLabel == null
        ? painter
        : Semantics(label: semanticLabel, image: true, child: painter);
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.detail, this.color);

  final MarkDetail detail;
  final Color color;

  static final Map<MarkDetail, Path> _paths = {};

  static Path pathFor(MarkDetail detail) =>
      _paths[detail] ??= buildMarkPath(switch (detail) {
        MarkDetail.full => fullMarkOps,
        MarkDetail.small => smallMarkOps,
        MarkDetail.tiny => tinyMarkOps,
      });

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 100, size.height / 100)
      ..drawPath(pathFor(detail), Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.detail != detail || old.color != color;
}

/// Builds a [Path] from the op list in brand_paths.g.dart.
@visibleForTesting
Path buildMarkPath(List<double> ops) {
  final path = Path()..fillType = PathFillType.evenOdd;
  var i = 0;
  double next() => ops[i++];
  while (i < ops.length) {
    switch (next().toInt()) {
      case 0:
        path.moveTo(next(), next());
      case 1:
        path.lineTo(next(), next());
      case 2:
        path.quadraticBezierTo(next(), next(), next(), next());
      case 3:
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 4:
        final end = Offset(next(), next());
        final r = next();
        path.arcToPoint(
          end,
          radius: Radius.circular(r),
          largeArc: next() == 1,
          clockwise: next() == 1,
        );
      case 5:
        path.close();
      case final op:
        throw StateError('Unknown mark op $op');
    }
  }
  return path;
}

/// Mark plus wordmark. The UI language decides which name leads.
class CinemakomLogo extends StatelessWidget {
  const CinemakomLogo({super.key, this.markSize = 72});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final text = MarqueeText(arabic: arabic);
    TextStyle latin(double size, Color color) => text.sectionTitle.copyWith(
      fontSize: size,
      height: 1.0,
      color: color,
      letterSpacing: size * 0.04,
    );
    TextStyle arabicName(double size, Color color) => text
        .displayLargeFor('سينماكم')
        .copyWith(fontSize: size, color: color)
        .withWeight(FontWeight.w700);
    final lines = arabic
        ? [
            Text(
              'سينماكم',
              style: arabicName(markSize * 0.5, MarqueeColors.cream),
            ),
            Text(
              'CINEMAKOM',
              textDirection: TextDirection.ltr,
              style: latin(markSize * 0.32, MarqueeColors.bulb),
            ),
          ]
        : [
            Text(
              'CINEMAKOM',
              style: latin(markSize * 0.62, MarqueeColors.cream),
            ),
            Text(
              'سينماكم',
              textDirection: TextDirection.rtl,
              style: arabicName(markSize * 0.36, MarqueeColors.bulb),
            ),
          ];
    return Semantics(
      label: 'Cinemakom',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CinemakomMark(size: markSize, semanticLabel: null),
            SizedBox(width: markSize * 0.22),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ],
        ),
      ),
    );
  }
}
