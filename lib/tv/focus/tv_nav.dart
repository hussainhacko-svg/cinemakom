import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

// The TV's navigation model (docs/TV.md §5.1). Items sit in zones, zones in
// groups, and the root group is a screen. An arrow press goes to the focused
// item's zone; at the zone's edge it goes up to the group, which moves to its
// next child or passes it further up. Nothing here looks at pixel positions:
// where focus goes depends only on the declared order (R1).

/// A focusable item as its zone sees it (implemented by `TvFocusable`).
abstract interface class TvItem {
  FocusNode get node;

  /// Zones skip items that are disabled (they stay visible) or hidden
  /// (inside an `ExcludeFocus`), R5.
  bool get enabled;

  void focus();
}

/// The FocusNode of a `TvFocusable`, so focus checks can tell a TV item from
/// a route's scope or a stray Flutter widget.
class TvItemNode extends FocusNode {
  TvItemNode({super.debugLabel});

  TvNavZone? zone;
}

/// A zone or a group: something arrows can move into.
abstract class TvNavNode {
  TvNavGroup? _parent;
  bool _attached = false;

  /// The position among the parent's children (declared by the screen).
  int order = 0;

  /// The group this node is (or was, after removal) in.
  TvNavGroup? get parent => _parent;

  /// Whether the node is in the tree. A removed node keeps its [parent], so
  /// focus can recover next to where it was (R7).
  bool get attached => _attached;

  /// Every group above is active (its route is current, its tab shown).
  bool get isActive {
    for (TvNavGroup? g = _parent; g != null; g = g._parent) {
      if (!g._selfActive) return false;
    }
    return true;
  }

  /// Whether arrows can move into this node now.
  bool get canEnter;

  bool get containsFocus;

  /// Focuses the remembered item, else the initial one. Returns false when
  /// nothing can take focus.
  bool enter();

  /// The first zone focus would reach going down from the top.
  TvNavZone? get firstZone;
}

/// Zones and groups in [order], one after the other along [axis]: a screen
/// (vertical) or a split (horizontal, docs/TV.md §5.1 R1).
class TvNavGroup extends TvNavNode {
  TvNavGroup({this.axis = Axis.vertical});

  Axis axis;

  /// Right means "towards the start" in RTL (R12).
  bool rtl = false;

  /// A screen's group is active only while its route is current.
  bool Function()? activeCheck;

  /// Called when an item joins somewhere below (a screen takes focus if
  /// nothing has it, R11).
  VoidCallback? onContentAdded;

  /// A screen's group: scrolls its page back to the top (Back to the tab
  /// bar, R4).
  VoidCallback? scrollToTop;

  final _children = <TvNavNode>[];
  TvNavNode? _last;

  bool get _selfActive => activeCheck?.call() ?? true;

  List<TvNavNode> get children => List.unmodifiable(_children);

  /// The child that had focus last (R2).
  TvNavNode? get remembered => _last;

  /// Marks a group without a parent (a screen's root) as in the tree.
  set rootAttached(bool value) => _attached = value;

  void add(TvNavNode child) {
    child._parent = this;
    child._attached = true;
    _children.add(child);
    sort();
  }

  void remove(TvNavNode child) {
    _children.remove(child);
    child._attached = false;
    if (_last == child) _last = null;
  }

  /// Puts the children back in [order] after one changed.
  void sort() => _children.sort((a, b) => a.order.compareTo(b.order));

  @override
  bool get canEnter =>
      _selfActive && _children.any((c) => c.attached && c.canEnter);

  @override
  bool get containsFocus => _children.any((c) => c.containsFocus);

  @override
  bool enter() {
    if (!_selfActive) return false;
    for (final c in [?_last, ..._children]) {
      if (c.attached && c.canEnter && c.enter()) return true;
    }
    return false;
  }

  @override
  TvNavZone? get firstZone {
    for (final c in _children) {
      if (c.canEnter) return c.firstZone;
    }
    return null;
  }

  /// The zone marked initial (R11), if it can take focus.
  TvNavZone? get initialZone {
    for (final c in _children) {
      if (!c.canEnter) continue;
      if (c is TvNavZone && c.initial) return c;
      if (c is TvNavGroup) {
        final z = c.initialZone;
        if (z != null) return z;
      }
    }
    return null;
  }

  int? _step(TraversalDirection dir) => switch ((axis, dir)) {
    (Axis.vertical, TraversalDirection.up) => -1,
    (Axis.vertical, TraversalDirection.down) => 1,
    (Axis.horizontal, TraversalDirection.right) => rtl ? -1 : 1,
    (Axis.horizontal, TraversalDirection.left) => rtl ? 1 : -1,
    _ => null,
  };

  /// [child] is at its edge in [dir]: move to the next child that way, else
  /// pass it up. False means nothing moves (R3: no wrap, no jump).
  bool moveFrom(TvNavNode child, TraversalDirection dir) {
    final step = _step(dir);
    final i = _children.indexOf(child);
    if (step != null && i >= 0) {
      for (var j = i + step; j >= 0 && j < _children.length; j += step) {
        final c = _children[j];
        if (c.canEnter && c.enter()) return true;
      }
    }
    return _parent?.moveFrom(this, dir) ?? false;
  }

  void noteFocus(TvNavNode child) {
    _last = child;
    _parent?.noteFocus(this);
  }

  /// [child], at [childOrder], went away while it had focus: focus the next
  /// child, then the previous one, else ask the parent (R7).
  void recoverFrom(TvNavNode child, int childOrder) {
    for (final c in _children) {
      if (c != child && c.order >= childOrder && c.canEnter && c.enter()) {
        return;
      }
    }
    for (final c in _children.reversed) {
      if (c != child && c.order < childOrder && c.canEnter && c.enter()) {
        return;
      }
    }
    _parent?.recoverFrom(this, order);
  }

  void contentAdded() {
    for (TvNavGroup? g = this; g != null; g = g._parent) {
      g.onContentAdded?.call();
    }
  }
}

/// A row, a column or a grid of items, moved through by index (R1). A row
/// of cells (an episode's play part and download button) is a grid, so Up and
/// Down keep the cell (§7.4).
class TvNavZone extends TvNavNode {
  TvNavZone();

  /// Every zone in the tree, for the debug watchdog (R7).
  static final Set<TvNavZone> live = {};

  /// Items per row; `null` is a single row.
  int? columns;
  bool rtl = false;
  int initialIndex = 0;

  /// Where the screen's focus starts (R11).
  bool initial = false;

  /// False: entering always lands on [initialIndex] (the tab bar lands on
  /// the current tab, wherever focus left it).
  bool remember = true;

  /// A named exception to R3 (the Home hero changes banners at its ends):
  /// return true when it used the edge press.
  bool Function(TraversalDirection dir)? onEdge;

  /// Where the zone's own row scrolls the focused item to (R10).
  double keyline = 0;

  /// The zone's widget, for scrolling it into view.
  BuildContext? context;

  final _items = <int, TvItem>{};
  int? _last;

  /// The index that had focus last (R2).
  int? get remembered => _last;

  Iterable<int> get indexes => _items.keys;

  TvItem? itemAt(int index) => _items[index];

  bool _enabledAt(int i) => _items[i]?.enabled ?? false;

  @override
  bool get canEnter => isActive && _items.values.any((i) => i.enabled);

  @override
  bool get containsFocus => _items.values.any((i) => i.node.hasPrimaryFocus);

  @override
  TvNavZone? get firstZone => canEnter ? this : null;

  /// Whether the page scrolls the whole zone into view for [index] (a row,
  /// or a grid's first row: its header stays visible), or only that item.
  bool revealsWhole(int index) =>
      pageWhole ?? (columns == null || index < columns!);

  /// True: the page always aligns the whole zone (the split's columns,
  /// which scroll by themselves under one heading).
  bool? pageWhole;

  void register(int index, TvItem item) {
    _items[index] = item;
    parent?.contentAdded();
  }

  void unregister(int index, TvItem item) {
    if (_items[index] == item) _items.remove(index);
  }

  @override
  bool enter() {
    if (!isActive) return false;
    final target = _nearestEnabled(
      remember ? (_last ?? initialIndex) : initialIndex,
    );
    if (target == null) return false;
    _items[target]!.focus();
    return true;
  }

  int? _nearestEnabled(int index) {
    if (_items.isEmpty) return null;
    if (_enabledAt(index)) return index;
    final keys = _items.keys;
    final lo = keys.reduce((a, b) => a < b ? a : b);
    final hi = keys.reduce((a, b) => a > b ? a : b);
    for (var d = 1; index - d >= lo || index + d <= hi; d++) {
      if (_enabledAt(index + d)) return index + d;
      if (_enabledAt(index - d)) return index - d;
    }
    return null;
  }

  /// Moves from [from] in [dir]: inside the zone, else at its edge
  /// [onEdge], else the parent. False when nothing moved.
  bool move(int from, TraversalDirection dir) {
    final target = _target(from, dir);
    if (target != null) {
      _items[target]!.focus();
      return true;
    }
    if (onEdge?.call(dir) ?? false) return true;
    return parent?.moveFrom(this, dir) ?? false;
  }

  int? _target(int from, TraversalDirection dir) {
    if (_items.isEmpty) return null;
    final hi = _items.keys.reduce((a, b) => a > b ? a : b);
    final cols = columns ?? hi + 1;
    final row = from ~/ cols;
    final col = from % cols;
    switch (dir) {
      case TraversalDirection.left || TraversalDirection.right:
        final forward = (dir == TraversalDirection.right) != rtl;
        final step = forward ? 1 : -1;
        for (var c = col + step; c >= 0 && c < cols; c += step) {
          final i = row * cols + c;
          if (i > hi) break;
          if (_enabledAt(i)) return i;
        }
        return null;
      case TraversalDirection.up || TraversalDirection.down:
        if (columns == null) return null;
        final step = dir == TraversalDirection.down ? 1 : -1;
        for (var r = row + step; r >= 0 && r * cols <= hi; r += step) {
          // The same column, else the nearest one in that row (a short last
          // row, or a row without that cell).
          for (var d = 0; d < cols; d++) {
            for (final c in {col - d, col + d}) {
              if (c < 0 || c >= cols) continue;
              if (_enabledAt(r * cols + c)) return r * cols + c;
            }
          }
        }
        return null;
    }
  }

  void noteFocus(int index) {
    _last = index;
    parent?.noteFocus(this);
  }

  /// The focused item at [index] went away: focus the next item, then the
  /// previous one, then the next zone (R7).
  void recover(int index) {
    final keys = _items.keys.toList()..sort();
    for (final k in keys) {
      if (k >= index && _enabledAt(k)) return _items[k]!.focus();
    }
    for (final k in keys.reversed) {
      if (k < index && _enabledAt(k)) return _items[k]!.focus();
    }
    parent?.recoverFrom(this, order);
  }
}

/// Focus is on nothing useful: no item, no text field, or an item of a
/// screen that isn't shown any more.
bool tvFocusIsLost() {
  // A `TvFocusable(autofocus: true)` was just built and is taking focus:
  // nothing should move focus elsewhere meanwhile (the removed item's
  // recovery, the screen's initial focus).
  if (tvAutofocusPending > 0) return false;
  final focus = FocusManager.instance.primaryFocus;
  if (focus == null || focus.context == null) return true;
  if (focus is TvItemNode) return !(focus.zone?.isActive ?? false);
  return !tvIsEditingText(focus);
}

/// How many autofocus requests are on their way (see [tvFocusIsLost]).
int tvAutofocusPending = 0;

/// Whether [focus] is a text field (R8: it keeps the arrows while typing).
bool tvIsEditingText(FocusNode? focus) =>
    focus?.context?.findAncestorStateOfType<EditableTextState>() != null;

/// After the frame, if the item at [index] of [zone] took focus with it,
/// moves focus next to where it was (R7).
void tvRecoverAfterRemoval(TvNavZone zone, int index) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!tvFocusIsLost()) return;
    if (zone.attached) return zone.recover(index);
    TvNavNode child = zone;
    var group = zone.parent;
    while (group != null && !group.attached) {
      child = group;
      group = group.parent;
    }
    group?.recoverFrom(child, child.order);
  });
  SchedulerBinding.instance.ensureVisualUpdate();
}
