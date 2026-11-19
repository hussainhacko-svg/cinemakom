import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show Widget;

import '../core/storage/preferences.dart';
import '../features/debug/debug_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/onboarding/language_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import 'shell/app_shell.dart';

/// App locations. Screens navigate with these, never with literal strings.
abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const home = '/home';
  static const search = '/search';
  static const library = '/library';
  static const downloads = '/downloads';
  static const settings = '/settings';
  static const debug = '/settings/debug';
}

/// The router. Created once; it re-runs its redirect when the first-launch
/// language choice changes, but never rebuilds (that would reset every tab).
final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier(ref.read(settingsProvider).hasChosenLanguage);
  ref
    ..listen(
      settingsProvider.select((s) => s.hasChosenLanguage),
      (_, chosen) => onboarded.value = chosen,
    )
    ..onDispose(onboarded.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final atWelcome = state.matchedLocation == AppRoutes.welcome;
      if (!onboarded.value) return atWelcome ? null : AppRoutes.welcome;
      return atWelcome ? AppRoutes.home : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const LanguageScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(AppRoutes.home, const HomeScreen()),
          _branch(AppRoutes.search, const SearchScreen()),
          _branch(AppRoutes.library, const LibraryScreen()),
          _branch(AppRoutes.downloads, const DownloadsScreen()),
          _branch(
            AppRoutes.settings,
            const SettingsScreen(),
            routes: [
              // Developer-only API check, compiled out of release builds.
              if (kDebugMode)
                GoRoute(path: 'debug', builder: (_, _) => const DebugScreen()),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(
  String path,
  Widget screen, {
  List<RouteBase> routes = const [],
}) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (_, _) => screen, routes: routes)],
);
