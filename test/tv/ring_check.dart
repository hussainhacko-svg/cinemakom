import 'package:cinemakom/tv/theme/tv_space.dart';
import 'package:cinemakom/tv/widgets/tv_focus_look.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The focus ring that's on is drawn whole: inside the screen and inside
/// every scroll view and clip above it. A ring cut by its list's edge was
/// seen on the TV (the search box, the Sort panel, 2026-11-21/22).
void expectRingVisible(WidgetTester tester, {String reason = ''}) {
  final rings = find.byWidgetPredicate((w) => w is TvRing && w.on);
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final element in rings.evaluate()) {
    final ring = element.widget as TvRing;
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    final out = ring.gap + TvFocusStyle.ring;
    final drawn = MatrixUtils.transformRect(
      box.getTransformTo(null),
      (Offset.zero & box.size).inflate(out),
    );
    bool inside(Rect clip) =>
        drawn.left >= clip.left - 0.5 &&
        drawn.top >= clip.top - 0.5 &&
        drawn.right <= clip.right + 0.5 &&
        drawn.bottom <= clip.bottom + 0.5;
    expect(inside(screen), isTrue, reason: 'ring off screen $reason: $drawn');
    for (RenderObject? o = box.parent; o != null; o = o.parent) {
      final clips = switch (o) {
        RenderViewportBase(:final clipBehavior) => clipBehavior != Clip.none,
        RenderClipRect(:final clipBehavior) ||
        RenderClipRRect(:final clipBehavior) ||
        RenderClipPath(:final clipBehavior) => clipBehavior != Clip.none,
        _ => false,
      };
      if (!clips || o is! RenderBox) continue;
      final clip = MatrixUtils.transformRect(
        o.getTransformTo(null),
        Offset.zero & o.size,
      );
      expect(
        inside(clip),
        isTrue,
        reason:
            'ring cut by ${o.runtimeType} (${o.debugCreator}) $reason: '
            'ring $drawn, clip $clip',
      );
    }
  }
}
