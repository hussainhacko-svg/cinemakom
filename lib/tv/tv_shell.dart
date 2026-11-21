import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/repositories/downloads_repository.dart';
import 'focus/tv_nav.dart';
import 'focus/tv_scopes.dart';
import 'focus/tv_screen.dart';
import 'theme/tv_space.dart';
import 'widgets/tv_tab_bar.dart';

/// The tab shell (docs/TV.md §2, §6.4): the tab bar above each tab's own
/// back stack. Its focus group holds the tab bar (order 0) and the shown
/// tab's page (order 1), so Up from a page's first zone reaches the tabs.
///
/// The bar is only on a tab's own screen ([atRoot]; a pushed page has the
/// whole screen, as in the Genre design), and only while focus is on it or
/// on the page's first zone: further down it slides away and the page gets
/// the screen; Up or Back brings it back.
///
/// Back (R4) here: from a tab's page, to its tab (scrolling the page back to
/// the top); from the tab bar, to Home; from Home's tab, out of the app.
class TvShell extends ConsumerStatefulWidget {
  const TvShell({super.key, required this.shell, required this.atRoot});

  final StatefulNavigationShell shell;
  final bool atRoot;

  @override
  ConsumerState<TvShell> createState() => _TvShellState();
}

class _TvShellState extends ConsumerState<TvShell> {
  TvNavGroup? _group;
  bool _barShown = true;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  TvNavZone? get _tabs => _group?.children
      .whereType<TvNavZone>()
      .where((z) => z.order == 0)
      .firstOrNull;

  /// The shown tab's page: the active child group.
  TvNavGroup? get _page => _group?.children
      .whereType<TvNavGroup>()
      .where((g) => g.attached && g.canEnter)
      .firstOrNull;

  void _focusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus is! TvItemNode || focus.zone == null) return;
    final zone = focus.zone!;
    final shown = zone == _tabs || zone == _page?.firstZone;
    if (shown != _barShown && mounted) setState(() => _barShown = shown);
  }

  bool _back() {
    final focus = FocusManager.instance.primaryFocus;
    final onTabs = focus is TvItemNode && focus.zone == _tabs;
    if (!onTabs) {
      _page?.scrollToTop?.call();
      return _tabs?.enter() ?? false;
    }
    if (widget.shell.currentIndex != 0) {
      _go(0);
      return true;
    }
    return false; // Home's tab: leave the app.
  }

  void _go(int tab) {
    widget.shell.goBranch(tab);
    // The bar lands on the new current tab once it has rebuilt.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tabs?.enter());
  }

  @override
  Widget build(BuildContext context) {
    final showBar = widget.atRoot && _barShown;
    final still = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: TvScreen(
        onBack: _back,
        builder: (context, scroll) => Builder(
          builder: (context) {
            _group = TvGroupScope.maybeOf(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRect(
                  child: AnimatedAlign(
                    alignment: AlignmentDirectional.bottomStart,
                    heightFactor: showBar ? 1 : 0,
                    duration: still ? Duration.zero : TvFocusStyle.duration,
                    curve: TvFocusStyle.curve,
                    child: ExcludeFocus(
                      excluding: !widget.atRoot,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          TvSpace.safeH,
                          TvSpace.safeV,
                          TvSpace.safeH,
                          22,
                        ),
                        child: TvTabBar(
                          current: widget.shell.currentIndex,
                          onTab: (i) {
                            if (i == 3) {
                              unawaited(
                                ref
                                    .read(downloadsRepositoryProvider)
                                    .reconcile(),
                              );
                            }
                            widget.shell.goBranch(i);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: widget.shell),
              ],
            );
          },
        ),
      ),
    );
  }
}
