import 'package:material_ui/material_ui.dart';

import '../../app/theme/marquee_text.dart';

/// A one-line label that is always as wide as its boldest look ([widest]),
/// with the text centred in it. Selected labels (the current tab, chip or
/// segment) turn 600; with a plain [Text] the bolder label is wider and
/// pushed its neighbours (seen on TV Details, 2026-11-22). Focus never
/// changes a weight at all (docs/TV.md §6.3).
class TvSteadyText extends StatelessWidget {
  const TvSteadyText(
    this.text, {
    super.key,
    required this.style,
    this.widest = FontWeight.w600,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final FontWeight widest;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    final painter = TextPainter(
      text: TextSpan(text: text, style: merged.withWeight(widest)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: width),
      child: Text(
        text,
        maxLines: 1,
        overflow: overflow,
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}
