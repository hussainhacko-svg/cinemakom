import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/marquee_colors.dart';
import '../../../app/theme/marquee_text.dart';

/// Plain subtitles, drawn by Flutter (PLAYER.md §7.2): cream text with a
/// dark outline (no shadows, DESIGN.md §1), IBM Plex Sans / IBM Plex Sans
/// Arabic. It sits near the bottom and [lifted] moves it above the
/// controls. Styled tracks are drawn by libass instead, so [lines] is empty
/// for them.
class SubtitleLayer extends StatelessWidget {
  const SubtitleLayer({
    super.key,
    required this.lines,
    required this.lifted,
    this.scale = 1,
  });

  final ValueListenable<List<String>> lines;
  final bool lifted;

  /// The size setting: 1 is Medium (PLAYER.md §7.2).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // About 5% of the screen height, readable on phones and TVs alike.
    final fontSize = (size.shortestSide * 0.05).clamp(16.0, 44.0) * scale;
    final base = MarqueeText.of(context).body
        .copyWith(fontSize: fontSize, height: 1.3, fontWeight: FontWeight.w500);
    return IgnorePointer(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(
          MarqueeSpace.xxl,
          0,
          MarqueeSpace.xxl,
          lifted ? 120 : MarqueeSpace.xxxl,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder<List<String>>(
            valueListenable: lines,
            builder: (context, lines, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [for (final line in lines) _Line(line, style: base)],
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final direction = MarqueeText.hasArabic(text)
        ? TextDirection.rtl
        : TextDirection.ltr;
    final outline = style.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (style.fontSize ?? 20) / 7
        ..strokeJoin = StrokeJoin.round
        ..color = MarqueeColors.night,
    );
    return Stack(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          textDirection: direction,
          style: outline,
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          textDirection: direction,
          style: style.copyWith(color: MarqueeColors.cream),
        ),
      ],
    );
  }
}
