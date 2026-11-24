import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/marquee_colors.dart';

/// What a part of a screen that failed to build shows in release builds:
/// the background, so the rest of the screen still reads, instead of
/// Flutter's grey box. The error itself is in the log
/// (`installErrorCapture`). Debug builds keep the red screen.
class BrokenPart extends StatelessWidget {
  const BrokenPart({super.key});

  static void install() {
    if (!kDebugMode) ErrorWidget.builder = (_) => const BrokenPart();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: MarqueeColors.booth, child: SizedBox.expand());
}
