import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tv_space.dart';
import 'tv_back.dart';
import 'tv_nav.dart';
import 'tv_scopes.dart';

/// A TV page: its zones in order, top to bottom (docs/TV.md §5.2). It
/// - gives focus to its initial zone when it opens, and back to where it was
///   when it's shown again, or once its content loads (R2, R11);
/// - scrolls so the focused zone sits at [keylineTop] (R10), when [builder]
///   gives [scroll] to the page's scroll view;
/// - handles Back (R4): a pushed page (or a panel) pops; at the root of a
///   navigator, [onBack] decides (the tab bar, TV-2), else the app exits.
///
/// Inside another screen's group (a tab's content under the tab bar) its
/// zones continue that group: Up from its first zone reaches the tab bar.
class TvScreen extends StatefulWidget {
  const TvScreen({
    super.key,
    required this.builder,
    this.order = 0,
    this.onBack,
    this.keylineTop = TvSpace.pageKeyline,
  });

  final Widget Function(BuildContext context, ScrollController scroll) builder;

  /// Its place in an outer screen's group, if any.
  final int order;

  /// Back at the root of a navigator; true when used.
  final bool Function()? onBack;

  final double keylineTop;

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> implements TvPage {
  @override
  final scroll = ScrollController();
  late final _root = TvNavGroup()
    ..activeCheck = (() => _active)
    ..onContentAdded = _scheduleFocus;
  TvNavGroup? _parent;
  bool _active = true;
  bool _focusScheduled = false;

  @override
  double get keylineTop => widget.keylineTop;

  @override
  TvNavZone? get firstZone => _root.firstZone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depends on the route: rebuilt when it's current again after a pop.
    _active =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    final parent = TvGroupScope.maybeOf(context);
    if (parent != _parent || !_root.attached) {
      _parent?.remove(_root);
      _parent = parent;
      _root.order = widget.order;
      if (parent != null) {
        parent.add(_root);
      } else {
        _root.rootAttached = true;
      }
    }
    _scheduleFocus();
  }

  @override
  void dispose() {
    _parent?.remove(_root);
    _root.rootAttached = false;
    scroll.dispose();
    super.dispose();
  }

  /// After the frame, takes focus if nothing useful has it (R11): where it
  /// was on this page (R2), else the initial zone, else the first.
  void _scheduleFocus() {
    if (_focusScheduled) return;
    _focusScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted || !_active || !tvFocusIsLost()) return;
      if (_root.remembered == null && (_root.initialZone?.enter() ?? false)) {
        return;
      }
      _root.enter();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  bool _back() {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
      return true;
    }
    return widget.onBack?.call() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    _root.rtl = Directionality.of(context) == TextDirection.rtl;
    return TvPageScope(
      page: this,
      child: TvGroupScope(
        group: _root,
        child: TvBack(onBack: _back, child: widget.builder(context, scroll)),
      ),
    );
  }
}
