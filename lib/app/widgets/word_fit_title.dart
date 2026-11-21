import 'package:material_ui/material_ui.dart';

/// A display title that never breaks a word across lines: when its longest
/// word is wider than the space, its size steps down until that word fits,
/// to at most [minScale] of the size (past that, the word wraps). Lines
/// still wrap between words.
///
/// The Details header uses it: "SEKAI SAIKOU NO ANSATSUSHA, …" broke as
/// "ANSATSUSH / A" on a phone (2026-11-21).
class WordFitTitle extends StatelessWidget {
  const WordFitTitle(
    this.text, {
    super.key,
    required this.style,
    this.minScale = 0.6,
  });

  final String text;
  final TextStyle style;
  final double minScale;

  @override
  Widget build(BuildContext context) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, box) => Text(
        text,
        style: fitWords(text, merged, box.maxWidth, scaler, direction),
      ),
    );
  }

  /// [style] made small enough that every word of [text] fits [maxWidth]
  /// on its own (a pixel to spare), never under [minScale] of its size.
  TextStyle fitWords(
    String text,
    TextStyle style,
    double maxWidth,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final base = style.fontSize;
    if (base == null || !maxWidth.isFinite) return style;
    final width = maxWidth - 1;
    double widest(TextStyle s) {
      var w = 0.0;
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final p = TextPainter(
          text: TextSpan(text: word, style: s),
          maxLines: 1,
          textDirection: direction,
          textScaler: scaler,
        )..layout();
        if (p.width > w) w = p.width;
        p.dispose();
      }
      return w;
    }

    var size = base;
    var s = style;
    var w = widest(s);
    // Width is close to proportional to the size; letter spacing isn't, so
    // check again and step down until it fits.
    while (w > width && size > base * minScale) {
      final next = size * width / w;
      size = (next < size - 0.5 ? next : size - 0.5);
      if (size < base * minScale) size = base * minScale;
      s = style.copyWith(fontSize: size);
      w = widest(s);
    }
    return s;
  }
}
