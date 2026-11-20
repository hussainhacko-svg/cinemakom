import 'package:material_ui/material_ui.dart';

import '../theme/tv_space.dart';
import 'tv_nav.dart';
import 'tv_scopes.dart';

/// Scrolling follows focus (docs/TV.md §5.1 R10).
abstract final class TvReveal {
  /// Set while an arrow is held (key repeat): the next reveal jumps instead
  /// of animating, so holding Right through 100 posters doesn't queue 100
  /// animations.
  static bool jump = false;
}

/// Scrolls every scroll view around the focused [item] (index [index] of
/// [zone]) so it's on screen:
/// - a row (any horizontal scroll view) puts the item at the zone's
///   keyline, until the row's end;
/// - the page puts the zone's top at the page keyline (a row, or a grid's
///   first row), or scrolls only as far as the item needs, or back to the top
///   for the first zone;
/// - any other vertical scroll view (a column that scrolls by itself) only as
///   far as needed.
void tvReveal(BuildContext item, TvNavZone zone, int index) {
  final animate =
      !TvReveal.jump && !(MediaQuery.maybeDisableAnimationsOf(item) ?? false);
  TvReveal.jump = false;
  final itemBox = item.findRenderObject();
  if (itemBox is! RenderBox || !itemBox.attached) return;
  final page = TvPageScope.maybeOf(item);
  final pageScroll = page?.scroll;

  var scrollable = Scrollable.maybeOf(item);
  while (scrollable != null) {
    final position = scrollable.position;
    final viewport = scrollable.context.findRenderObject();
    if (viewport is RenderBox && position.hasContentDimensions) {
      final isPage =
          pageScroll != null &&
          pageScroll.hasClients &&
          pageScroll.positions.contains(position);
      double? target;
      if (isPage) {
        if (zone == page!.firstZone) {
          target = position.minScrollExtent;
        } else if (zone.revealsWhole(index)) {
          final zoneBox = zone.context?.findRenderObject();
          if (zoneBox is RenderBox && zoneBox.attached) {
            target = _aligned(position, viewport, zoneBox, page.keylineTop);
          }
        } else {
          target = _minimal(position, viewport, itemBox, TvSpace.revealMargin);
        }
      } else if (position.axis == Axis.horizontal) {
        target = _aligned(position, viewport, itemBox, zone.keyline);
      } else {
        target = _minimal(position, viewport, itemBox, TvSpace.revealMargin);
      }
      if (target != null) _scrollTo(position, target, animate);
    }
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
}

/// Where [box] starts and how long it is along [position]'s axis, in the
/// viewport's visible coordinates (from its leading edge).
(double, double)? _span(
  ScrollPosition position,
  RenderBox viewport,
  RenderBox box,
) {
  if (!box.attached) return null;
  final rect = MatrixUtils.transformRect(
    box.getTransformTo(viewport),
    Offset.zero & box.size,
  );
  final size = viewport.size;
  return switch (position.axisDirection) {
    AxisDirection.right => (rect.left, rect.width),
    AxisDirection.left => (size.width - rect.right, rect.width),
    AxisDirection.down => (rect.top, rect.height),
    AxisDirection.up => (size.height - rect.bottom, rect.height),
  };
}

double? _aligned(
  ScrollPosition position,
  RenderBox viewport,
  RenderBox box,
  double keyline,
) {
  final span = _span(position, viewport, box);
  if (span == null) return null;
  return position.pixels + span.$1 - keyline;
}

double? _minimal(
  ScrollPosition position,
  RenderBox viewport,
  RenderBox box,
  double margin,
) {
  final span = _span(position, viewport, box);
  if (span == null) return null;
  final (lead, extent) = span;
  final visible = position.viewportDimension;
  if (lead < margin) return position.pixels + lead - margin;
  if (lead + extent > visible - margin) {
    return position.pixels + lead + extent - (visible - margin);
  }
  return null;
}

void _scrollTo(ScrollPosition position, double target, bool animate) {
  final to = target.clamp(position.minScrollExtent, position.maxScrollExtent);
  if ((to - position.pixels).abs() < 0.5) return;
  if (animate) {
    position.animateTo(
      to,
      duration: TvFocusStyle.duration,
      curve: TvFocusStyle.curve,
    );
  } else {
    position.jumpTo(to);
  }
}
