import 'package:material_ui/material_ui.dart';

import 'tv_nav.dart';

/// The group items and zones below register with (a screen or a split).
class TvGroupScope extends InheritedWidget {
  const TvGroupScope({super.key, required this.group, required super.child});

  final TvNavGroup group;

  static TvNavGroup? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvGroupScope>()?.group;

  @override
  bool updateShouldNotify(TvGroupScope old) => group != old.group;
}

/// The zone items below register with.
class TvZoneScope extends InheritedWidget {
  const TvZoneScope({super.key, required this.zone, required super.child});

  final TvNavZone zone;

  static TvNavZone? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvZoneScope>()?.zone;

  @override
  bool updateShouldNotify(TvZoneScope old) => zone != old.zone;
}

/// What the screen tells its items for scrolling (R10).
abstract interface class TvPage {
  /// The page's own scroll view, if it has one.
  ScrollController get scroll;

  /// Where a focused zone's top goes.
  double get keylineTop;

  /// The first zone: focusing it scrolls the page to the top.
  TvNavZone? get firstZone;
}

class TvPageScope extends InheritedWidget {
  const TvPageScope({super.key, required this.page, required super.child});

  final TvPage page;

  static TvPage? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvPageScope>()?.page;

  @override
  bool updateShouldNotify(TvPageScope old) => page != old.page;
}
