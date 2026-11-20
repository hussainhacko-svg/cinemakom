import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../tv_keys.dart';
import 'tv_nav.dart';
import 'tv_reveal.dart';
import 'tv_scopes.dart';

/// One focusable item at [index] of its zone (docs/TV.md §5.2). Every TV
/// control is one: the zone moves between them, so nothing guesses (R1).
///
/// [builder] draws it, focused or not (the focus look is in
/// `widgets/tv_focus_look.dart`). OK fires [onSelect] when the key comes back
/// up, as Android TV buttons do; held for half a second it fires
/// [onLongSelect] instead, which is only ever a shortcut (R6). [label] is the
/// control's accessible name, and how tests find it.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.index,
    required this.label,
    required this.builder,
    this.onSelect,
    this.onLongSelect,
    this.enabled = true,
  });

  final int index;
  final String label;
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;

  /// Disabled items stay visible but their zone skips them (R5).
  final bool enabled;

  static const longPress = Duration(milliseconds: 500);

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> implements TvItem {
  final _node = TvItemNode(debugLabel: 'TvFocusable');
  TvNavZone? _zone;
  int? _index;
  bool _focused = false;
  bool _hadFocus = false;
  bool _pressed = false;
  bool _longFired = false;
  Timer? _longTimer;

  @override
  FocusNode get node => _node;

  /// Disabled, or hidden inside an `ExcludeFocus` (R5): the zone skips it.
  @override
  bool get enabled => widget.enabled && _node.canRequestFocus;

  @override
  void focus() => _node.requestFocus();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(TvFocusable old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _register();
  }

  void _register() {
    final zone = TvZoneScope.maybeOf(context);
    assert(zone != null, 'A TvFocusable must be inside a TvZone.');
    if (zone == _zone && widget.index == _index) return;
    if (_zone != null && _index != null) _zone!.unregister(_index!, this);
    _zone = zone;
    _index = widget.index;
    _node.zone = zone;
    zone?.register(widget.index, this);
  }

  @override
  void deactivate() {
    // Children deactivate after their parents, so the node still knows.
    _hadFocus = _node.hasPrimaryFocus;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _hadFocus = false;
  }

  @override
  void dispose() {
    _longTimer?.cancel();
    final zone = _zone;
    final index = _index;
    if (zone != null && index != null) {
      zone.unregister(index, this);
      if (_hadFocus) tvRecoverAfterRemoval(zone, index);
    }
    _node.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (!focused) {
      _pressed = false;
      _longTimer?.cancel();
      return;
    }
    final zone = _zone;
    if (zone == null) return;
    zone.noteFocus(widget.index);
    tvReveal(context, zone, widget.index);
  }

  static TraversalDirection? _direction(LogicalKeyboardKey key) =>
      switch (key) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        LogicalKeyboardKey.arrowRight => TraversalDirection.right,
        _ => null,
      };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final direction = _direction(key);
    if (direction != null) {
      if (event is! KeyUpEvent) {
        TvReveal.jump = event is KeyRepeatEvent;
        _zone?.move(widget.index, direction);
      }
      // Always used: an arrow that can't move does nothing (R3), and never
      // falls through to Flutter's geometric traversal (R1).
      return KeyEventResult.handled;
    }
    if (tvSelectKeys.contains(key)) {
      if (!widget.enabled) return KeyEventResult.handled;
      switch (event) {
        case KeyDownEvent():
          _pressed = true;
          _longFired = false;
          if (widget.onLongSelect != null) {
            _longTimer = Timer(TvFocusable.longPress, () {
              _longFired = true;
              widget.onLongSelect?.call();
            });
          }
        case KeyUpEvent():
          _longTimer?.cancel();
          // Only a press that started here: the key can come up on another
          // item after the first one opened something.
          if (_pressed && !_longFired) widget.onSelect?.call();
          _pressed = false;
        case KeyRepeatEvent():
          break;
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: Semantics(
        container: true,
        button: true,
        enabled: widget.enabled,
        focused: _focused,
        label: widget.label,
        onTap: widget.enabled ? widget.onSelect : null,
        child: ExcludeSemantics(child: widget.builder(context, _focused)),
      ),
    );
  }
}
