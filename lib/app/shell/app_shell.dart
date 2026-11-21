import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/repositories/downloads_repository.dart';
import '../brand/cinemakom_mark.dart';
import '../l10n/app_localizations.dart';
import '../theme/marquee_colors.dart';
import '../theme/marquee_text.dart';

/// Window widths where the navigation changes (DESIGN.md §5).
abstract final class Breakpoints {
  /// From here on, a rail replaces the bottom bar.
  static const rail = 600.0;

  /// From here on, the rail is extended, with the logo and side labels.
  static const extendedRail = 1200.0;
}

enum NavLayout { bar, rail, extendedRail }

NavLayout navLayoutFor(double width) => width >= Breakpoints.extendedRail
    ? NavLayout.extendedRail
    : width >= Breakpoints.rail
    ? NavLayout.rail
    : NavLayout.bar;

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

/// The five-tab frame around every main screen. Each tab keeps its own back
/// stack; tapping the active tab again returns it to its first screen.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _downloadsTab = 3;

  void _select(WidgetRef ref, int index) {
    if (index == _downloadsTab) {
      unawaited(ref.read(downloadsRepositoryProvider).reconcile());
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final layout = navLayoutFor(MediaQuery.sizeOf(context).width);
    final index = navigationShell.currentIndex;

    if (layout == NavLayout.bar) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.palette.boothRaised)),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _select(ref, i),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.icon), label: d.label(l10n)),
            ],
          ),
        ),
      );
    }

    final extended = layout == NavLayout.extendedRail;
    // The extended rail sets labels beside the icons, at button size.
    final sideLabel = MarqueeText.of(context).label;
    return Scaffold(
      body: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: BorderDirectional(
                end: BorderSide(color: context.palette.boothRaised),
              ),
            ),
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => _select(ref, i),
              extended: extended,
              minExtendedWidth: 232,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              selectedLabelTextStyle: extended
                  ? sideLabel.copyWith(color: context.palette.bulb)
                  : null,
              unselectedLabelTextStyle: extended
                  ? sideLabel
                        .copyWith(color: context.palette.dust)
                        .withWeight(FontWeight.w500)
                  : null,
              leading: Padding(
                padding: const EdgeInsetsDirectional.only(top: 12, bottom: 20),
                child: extended
                    ? const CinemakomLogo(markSize: 36)
                    : const CinemakomMark(size: 36),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label(l10n)),
                  ),
              ],
            ),
          ),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
