import 'package:material_ui/material_ui.dart';

import '../theme/tv_space.dart';
import 'tv_nav.dart';
import 'tv_scopes.dart';

/// A row, column or grid of `TvFocusable`s (docs/TV.md §5.2). Arrows move
/// inside it by index; at its edges they go to the next zone of the screen
/// (or the other column of a split). It remembers its last item (R2).
///
/// [order] is its place in the screen (or split): zones are visited in that
/// order, whatever their position on screen. Items are numbered from 0, row
/// by row in a grid.
class TvZone extends StatefulWidget {
  /// A single row: Left and Right move, Up and Down leave the zone.
  const TvZone.row({
    super.key,
    required this.order,
    required this.child,
    this.initialIndex = 0,
    this.initial = false,
    this.keyline = TvSpace.safeH,
    this.onEdge,
    this.remember = true,
  }) : columns = null;

  /// A single column: Up and Down move, Left and Right leave the zone.
  const TvZone.column({
    super.key,
    required this.order,
    required this.child,
    this.initialIndex = 0,
    this.initial = false,
    this.keyline = TvSpace.safeH,
    this.onEdge,
    this.remember = true,
  }) : columns = 1;

  /// A grid of [columns] (also a list of rows of cells: an episode's play
  /// part and download button is a grid of 2, so Down keeps the cell).
  const TvZone.grid({
    super.key,
    required this.order,
    required int this.columns,
    required this.child,
    this.initialIndex = 0,
    this.initial = false,
    this.keyline = TvSpace.safeH,
    this.onEdge,
    this.remember = true,
  });

  final int order;

  /// Items per row; `null` is one row.
  final int? columns;

  /// Where focus enters the first time (later: where it was, R2).
  final int initialIndex;

  /// Focus starts in this zone when the screen opens (R11).
  final bool initial;

  /// Where a horizontal scroll view in this zone puts the focused item (the
  /// row's start padding, R10).
  final double keyline;

  /// A named exception to R3: called on an edge press, true when used.
  final bool Function(TraversalDirection dir)? onEdge;

  /// False: entering always lands on [initialIndex] (the tab bar's current
  /// tab), not where focus was.
  final bool remember;

  final Widget child;

  @override
  State<TvZone> createState() => _TvZoneState();
}

class _TvZoneState extends State<TvZone> {
  final _zone = TvNavZone();
  TvNavGroup? _group;

  @override
  void initState() {
    super.initState();
    TvNavZone.live.add(_zone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = TvGroupScope.maybeOf(context);
    assert(group != null, 'A TvZone must be inside a TvScreen.');
    if (group != _group) {
      _group?.remove(_zone);
      _group = group;
      _apply();
      group?.add(_zone);
    }
  }

  @override
  void didUpdateWidget(TvZone old) {
    super.didUpdateWidget(old);
    final reorder = old.order != widget.order;
    _apply();
    if (reorder) _group?.sort();
  }

  void _apply() {
    _zone
      ..order = widget.order
      ..columns = widget.columns
      ..initialIndex = widget.initialIndex
      ..initial = widget.initial
      ..keyline = widget.keyline
      ..onEdge = widget.onEdge
      ..remember = widget.remember
      ..context = context;
  }

  @override
  void dispose() {
    _group?.remove(_zone);
    TvNavZone.live.remove(_zone);
    _zone.context = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _zone.rtl = Directionality.of(context) == TextDirection.rtl;
    return TvZoneScope(zone: _zone, child: widget.child);
  }
}

/// Zones side by side or one above the other, inside a screen. A split
/// (`TvGroup.split`: the seasons beside the episodes) moves between its
/// columns with Left and Right, and each column keeps its own memory (R1).
class TvGroup extends StatefulWidget {
  const TvGroup({
    super.key,
    required this.order,
    required this.child,
    this.axis = Axis.vertical,
  });

  const TvGroup.split({super.key, required this.order, required this.child})
    : axis = Axis.horizontal;

  final int order;
  final Axis axis;
  final Widget child;

  @override
  State<TvGroup> createState() => _TvGroupState();
}

class _TvGroupState extends State<TvGroup> {
  late final _node = TvNavGroup(axis: widget.axis);
  TvNavGroup? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parent = TvGroupScope.maybeOf(context);
    assert(parent != null, 'A TvGroup must be inside a TvScreen.');
    if (parent != _parent) {
      _parent?.remove(_node);
      _parent = parent;
      _node.order = widget.order;
      parent?.add(_node);
    }
  }

  @override
  void didUpdateWidget(TvGroup old) {
    super.didUpdateWidget(old);
    _node.axis = widget.axis;
    if (old.order != widget.order) {
      _node.order = widget.order;
      _parent?.sort();
    }
  }

  @override
  void dispose() {
    _parent?.remove(_node);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _node.rtl = Directionality.of(context) == TextDirection.rtl;
    return TvGroupScope(group: _node, child: widget.child);
  }
}
