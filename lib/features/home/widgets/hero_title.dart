import 'package:material_ui/material_ui.dart';

/// How a hero title is set: a size, one or two lines, and the width to wrap
/// at (narrower than the space for two balanced lines).
@immutable
class HeroTitleFit {
  const HeroTitleFit({
    required this.style,
    required this.maxLines,
    required this.width,
    required this.fits,
  });

  final TextStyle style;
  final int maxLines;
  final double width;

  /// False when even the smallest step needs an ellipsis.
  final bool fits;
}

/// The steps a hero title tries, biggest first: the share of the hero size
/// and how many lines it may take. Fewer lines win over a bigger size (they
/// keep the hero short); three lines are only for really long titles. Only a
/// title that fits none of them (a single absurdly long word) gets an
/// ellipsis.
const heroTitleSteps = <(double, int)>[
  (1, 1),
  (0.85, 1),
  (0.72, 2),
  (0.6, 2),
  (0.5, 2),
  (0.5, 3),
  (0.42, 3),
];

/// Picks the biggest step at which [title] fits in [maxWidth] without an
/// ellipsis and without breaking a word in half, then balances two-line
/// titles so both lines are about the same length.
///
/// [style] must be the style the text is really drawn with (the default
/// text style merged in), or the measure and the render disagree.
HeroTitleFit fitHeroTitle({
  required String title,
  required TextStyle style,
  required double maxWidth,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  // A pixel to spare, so a measured fit never rounds into an ellipsis.
  final width = maxWidth - 1;
  final base = style.fontSize ?? 58;

  TextPainter painter(TextStyle s, int lines) => TextPainter(
    text: TextSpan(text: title, style: s),
    maxLines: lines,
    textDirection: textDirection,
    textScaler: textScaler,
  );

  bool fitsAt(TextStyle s, int lines, double at) {
    final p = painter(s, lines)..layout(maxWidth: at);
    final ok = !p.didExceedMaxLines;
    p.dispose();
    return ok;
  }

  for (final (scale, lines) in heroTitleSteps) {
    final s = scale == 1 ? style : style.copyWith(fontSize: base * scale);
    if (!fitsAt(s, lines, width)) continue;
    if (lines == 1) {
      return HeroTitleFit(style: s, maxLines: 1, width: maxWidth, fits: true);
    }
    if (!_wordsWithin(title, s, width, textDirection, textScaler)) continue;
    // Balance: the narrowest width that still fits in that many lines.
    var lo = width / lines, hi = width;
    for (var i = 0; i < 12; i++) {
      final mid = (lo + hi) / 2;
      if (fitsAt(s, lines, mid) &&
          _wordsWithin(title, s, mid, textDirection, textScaler)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return HeroTitleFit(
      style: s,
      maxLines: lines,
      width: (hi + 1).clamp(0, maxWidth),
      fits: true,
    );
  }
  // Nothing fits: the smallest size with an ellipsis. Three lines, unless a
  // word is wider than the hero, which would break mid-word: then one.
  final (scale, lines) = heroTitleSteps.last;
  final s = style.copyWith(fontSize: base * scale);
  return HeroTitleFit(
    style: s,
    maxLines: _wordsWithin(title, s, width, textDirection, textScaler)
        ? lines
        : 1,
    width: maxWidth,
    fits: false,
  );
}

bool _wordsWithin(
  String title,
  TextStyle style,
  double width,
  TextDirection textDirection,
  TextScaler textScaler,
) {
  for (final word in title.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final p = TextPainter(
      text: TextSpan(text: word, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    final w = p.width;
    p.dispose();
    if (w > width) return false;
  }
  return true;
}

/// The Home hero title, set by [fitHeroTitle]. The fit is measured once per
/// title, style and width, not on every rebuild (the hero rebuilds all its
/// titles whenever the banner changes).
class HeroTitle extends StatefulWidget {
  const HeroTitle({super.key, required this.title, required this.style});

  final String title;
  final TextStyle style;

  @override
  State<HeroTitle> createState() => _HeroTitleState();
}

class _HeroTitleState extends State<HeroTitle> {
  Object? _key;
  HeroTitleFit? _fit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final key = (widget.title, style, box.maxWidth, scaler, direction);
      if (key != _key) {
        _key = key;
        _fit = fitHeroTitle(
          title: widget.title,
          style: style,
          maxWidth: box.maxWidth,
          textScaler: scaler,
          textDirection: direction,
        );
      }
      final fit = _fit!;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: fit.width),
        child: Text(
          widget.title,
          maxLines: fit.maxLines,
          overflow: TextOverflow.ellipsis,
          style: fit.style,
        ),
      );
    },
  );
}
