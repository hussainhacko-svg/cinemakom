import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/brand/cinemakom_mark.dart';
import '../../app/l10n/app_localizations.dart';
import '../../app/theme/marquee_colors.dart';
import '../../app/theme/marquee_text.dart';

/// Debug label used by TV screens (e.g. TvHomeScreen's Play button,
/// TvDetailsScreen's Play button) to mark the preferred landing focus target
/// when entering the screen.
const tvPrimaryFocusLabel = 'tvPrimaryContentFocus';

/// Standard horizontal gutter inside the TV content area (outside overscan).
const tvGutter = 32.0;

class _Destination {
  const _Destination(this.icon, this.label);

  final IconData icon;
  final String Function(AppLocalizations) label;
}

/// Same order as the router's branches.
final _destinations = [
  _Destination(Icons.home_outlined, (l) => l.navHome),
  _Destination(Icons.search, (l) => l.navSearch),
  _Destination(Icons.video_library_outlined, (l) => l.navLibrary),
  _Destination(Icons.download_outlined, (l) => l.navDownloads),
  _Destination(Icons.settings_outlined, (l) => l.navSettings),
];

/// Dedicated 10-foot Android TV navigation shell (docs/ANDROID_TV.md).
///
/// Keeps a crisp D-pad-first side rail (`TvNavRail`) beside the active tab,
/// applies overscan-safe padding, remembers the last focused widget per tab,
/// and handles Back-to-rail before exiting the app.
class TvShell extends StatefulWidget {
  const TvShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<TvShell> {
  final _railFocus = FocusNode(debugLabel: 'tvShellRail');
  final _contentFocus = FocusNode(debugLabel: 'tvShellContent');
  final _contentKey = GlobalKey(debugLabel: 'tvShellContentBox');
  late final List<FocusNode> _destNodes = List.generate(
    _destinations.length,
    (i) => FocusNode(debugLabel: 'tvNavDest_$i'),
  );

  /// Last focused content widget per branch so moving Left→Right across the
  /// TV rail returns focus right where the user left off.
  final Map<int, FocusNode> _lastContentFocus = {};

  bool _railHasFocus = false;
  int _focusedRailIndex = 0;
  GoRouterDelegate? _routerDelegate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegate = GoRouter.of(context).routerDelegate;
    if (delegate != _routerDelegate) {
      _routerDelegate?.removeListener(_onRouteChanged);
      _routerDelegate = delegate;
      _routerDelegate?.addListener(_onRouteChanged);
    }
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _routerDelegate?.removeListener(_onRouteChanged);
    _railFocus.dispose();
    _contentFocus.dispose();
    for (final node in _destNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Selects [index] and moves focus into that tab's content (or keeps focus
  /// on the rail item when the screen has no focusable content, e.g. empty
  /// Downloads).
  void _selectAndEnter(int index, {bool? initialLocation}) {
    final current = widget.navigationShell.currentIndex;
    final resetToRoot = initialLocation ?? (index == current);
    widget.navigationShell.goBranch(index, initialLocation: resetToRoot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entered = _focusContent(
        branchIndex: index,
        preferRestore: !resetToRoot,
      );
      if (!entered) _focusRail(index);
    });
  }

  void _moveFromRailToContent(int railIndex) {
    final current = widget.navigationShell.currentIndex;
    if (railIndex == current) {
      final entered = _focusContent(branchIndex: current, preferRestore: true);
      if (!entered) _focusRail(current);
    } else {
      _selectAndEnter(railIndex, initialLocation: false);
    }
  }

  void _focusRail(int index) {
    final safe = index.clamp(0, _destNodes.length - 1);
    final current = widget.navigationShell.currentIndex;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null &&
        _isActiveFocusable(primary) &&
        primary.ancestors.contains(_contentFocus)) {
      _lastContentFocus[current] = primary;
    }
    _destNodes[safe].requestFocus();
  }

  bool _isActiveFocusable(FocusNode node) {
    if (node is FocusScopeNode) return false;
    if (!node.canRequestFocus || node.skipTraversal) return false;
    final ctx = node.context;
    if (ctx == null || !ctx.mounted) return false;
    if (!TickerMode.valuesOf(ctx).enabled) return false;
    if (node.size.isEmpty) return false;
    return true;
  }

  bool _isAttachedAndActive(FocusNode node) =>
      _contentFocus.descendants.contains(node) && _isActiveFocusable(node);

  bool _focusContent({required int branchIndex, required bool preferRestore}) {
    if (preferRestore) {
      final saved = _lastContentFocus[branchIndex];
      if (saved != null && _isAttachedAndActive(saved)) {
        saved.requestFocus();
        return true;
      }
    }

    final active = _contentFocus.descendants
        .where(_isActiveFocusable)
        .toList();
    if (active.isEmpty) return false;

    for (final node in active) {
      if (node.debugLabel == tvPrimaryFocusLabel) {
        node.requestFocus();
        return true;
      }
    }
    active.first.requestFocus();
    return true;
  }

  KeyEventResult _onContentKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final towardRailKey = isRtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    final towardRailDir = isRtl
        ? TraversalDirection.right
        : TraversalDirection.left;

    if (key == towardRailKey) {
      final primary = FocusManager.instance.primaryFocus;
      // Never steal horizontal arrows while actively typing in a TextField.
      if (primary?.context?.widget is EditableText) {
        return KeyEventResult.ignored;
      }
      if (primary == null) {
        _focusRail(widget.navigationShell.currentIndex);
        return KeyEventResult.handled;
      }

      final oldRect = primary.rect;
      final primaryCtx = primary.context;
      final oldScrollable = primaryCtx != null
          ? Scrollable.maybeOf(primaryCtx, axis: Axis.horizontal)
          : null;
      final atStartEdge = _isAtContentStartEdge(oldRect, isRtl: isRtl);

      final moved = primary.focusInDirection(towardRailDir);
      if (!moved) {
        _focusRail(widget.navigationShell.currentIndex);
        return KeyEventResult.handled;
      }

      // Guard against directional traversal jumping out-of-band to another row
      // when the user is already at the start edge of the screen.
      final next = FocusManager.instance.primaryFocus;
      if (atStartEdge && next != null && next != primary) {
        final nextCtx = next.context;
        final sameScrollable =
            oldScrollable != null &&
            nextCtx != null &&
            Scrollable.maybeOf(nextCtx, axis: Axis.horizontal) == oldScrollable;
        final inBand =
            next.rect.top < oldRect.bottom && next.rect.bottom > oldRect.top;
        if (!sameScrollable && !inBand) {
          final current = widget.navigationShell.currentIndex;
          if (_isActiveFocusable(primary)) {
            _lastContentFocus[current] = primary;
          }
          _destNodes[current.clamp(0, _destNodes.length - 1)].requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) &&
        !GoRouter.of(context).canPop()) {
      _focusRail(widget.navigationShell.currentIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isAtContentStartEdge(Rect rect, {required bool isRtl}) {
    final renderBox =
        _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return false;
    final topLeft = renderBox.localToGlobal(Offset.zero);
    final contentRect = topLeft & renderBox.size;
    const slop = 16.0;
    return isRtl
        ? rect.right >= contentRect.right - tvGutter - slop
        : rect.left <= contentRect.left + tvGutter + slop;
  }

  void _handleRailBack() {
    final index = widget.navigationShell.currentIndex;
    if (index != 0) {
      widget.navigationShell.goBranch(0);
      _focusRail(0);
    } else if (_focusedRailIndex != 0) {
      _focusRail(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = widget.navigationShell.currentIndex;
    final canPopBranch = GoRouter.of(context).canPop();
    final atHomeRail = _railHasFocus && index == 0 && _focusedRailIndex == 0;

    final rail = Focus(
      focusNode: _railFocus,
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: (hasFocus) {
        if (_railHasFocus != hasFocus) {
          setState(() => _railHasFocus = hasFocus);
        }
      },
      child: TvNavRail(
        selectedIndex: index,
        focusNodes: _destNodes,
        destinations: [
          for (final d in _destinations) (d.icon, d.label(l10n)),
        ],
        onFocusedIndexChanged: (i) {
          if (_focusedRailIndex != i) {
            setState(() => _focusedRailIndex = i);
          }
        },
        onSelect: _selectAndEnter,
        onMoveToContent: _moveFromRailToContent,
        onBack: canPopBranch || atHomeRail ? null : _handleRailBack,
      ),
    );

    final content = Expanded(
      child: KeyedSubtree(
        key: _contentKey,
        child: Focus(
          focusNode: _contentFocus,
          skipTraversal: true,
          canRequestFocus: false,
          onKeyEvent: _onContentKey,
          child: widget.navigationShell,
        ),
      ),
    );

    // Overscan safety padding on TVs (docs/ANDROID_TV.md).
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(children: [rail, content]),
    );

    return PopScope(
      canPop: canPopBranch || atHomeRail,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_railHasFocus) {
          _focusRail(index);
        } else {
          _handleRailBack();
        }
      },
      child: Scaffold(body: body),
    );
  }
}

/// D-pad-first side navigation rail for Android TV.
class TvNavRail extends StatelessWidget {
  const TvNavRail({
    super.key,
    required this.selectedIndex,
    required this.focusNodes,
    required this.destinations,
    required this.onFocusedIndexChanged,
    required this.onSelect,
    required this.onMoveToContent,
    this.onBack,
  });

  final int selectedIndex;
  final List<FocusNode> focusNodes;
  final List<(IconData, String)> destinations;
  final ValueChanged<int> onFocusedIndexChanged;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onMoveToContent;
  final VoidCallback? onBack;

  static const width = 92.0;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final towardContentKey = isRtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    final awayFromContentKey = isRtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: MarqueeColors.navBar,
        border: BorderDirectional(
          end: BorderSide(color: MarqueeColors.boothRaised),
        ),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsetsDirectional.only(top: 12, bottom: 16),
            child: CinemakomMark(size: 36),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < destinations.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _TvNavRailItem(
                      icon: destinations[i].$1,
                      label: destinations[i].$2,
                      selected: i == selectedIndex,
                      focusNode: focusNodes[i],
                      onFocusGained: () => onFocusedIndexChanged(i),
                      onTap: () => onSelect(i),
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent &&
                            event is! KeyRepeatEvent) {
                          return KeyEventResult.ignored;
                        }
                        final key = event.logicalKey;
                        if (key == LogicalKeyboardKey.arrowUp) {
                          if (i > 0) focusNodes[i - 1].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (key == LogicalKeyboardKey.arrowDown) {
                          if (i < focusNodes.length - 1) {
                            focusNodes[i + 1].requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                        if (key == towardContentKey) {
                          onMoveToContent(i);
                          return KeyEventResult.handled;
                        }
                        if (key == awayFromContentKey) {
                          return KeyEventResult.handled;
                        }
                        if (event is KeyDownEvent &&
                            (key == LogicalKeyboardKey.goBack ||
                                key == LogicalKeyboardKey.escape) &&
                            onBack != null) {
                          onBack!();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvNavRailItem extends StatefulWidget {
  const _TvNavRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onFocusGained,
    required this.onTap,
    required this.onKeyEvent,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onFocusGained;
  final VoidCallback onTap;
  final FocusOnKeyEventCallback onKeyEvent;

  @override
  State<_TvNavRailItem> createState() => _TvNavRailItemState();
}

class _TvNavRailItemState extends State<_TvNavRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final text = MarqueeText.of(context);
    final selected = widget.selected;
    final focused = _focused;

    final fgColor = selected
        ? MarqueeColors.bulb
        : focused
        ? MarqueeColors.cream
        : MarqueeColors.dust;
    final labelStyle = (selected || focused)
        ? text.navLabel.copyWith(color: fgColor).withWeight(FontWeight.w600)
        : text.navLabel.copyWith(color: fgColor);

    return Semantics(
      selected: selected,
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: widget.onKeyEvent,
        child: Material(
          color: focused ? MarqueeColors.boothRaised : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(MarqueeRadius.card),
            side: focused
                ? const BorderSide(color: MarqueeColors.bulb, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: widget.focusNode,
            onTap: widget.onTap,
            onFocusChange: (f) {
              setState(() => _focused = f);
              if (f) widget.onFocusGained();
            },
            focusColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected && !focused
                            ? MarqueeColors.boothRaised
                            : Colors.transparent,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(16),
                        ),
                      ),
                      child: SizedBox(
                        width: 56,
                        height: 30,
                        child: Center(
                          child: Icon(widget.icon, color: fgColor, size: 22),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
