import 'package:flutter/foundation.dart' show ValueNotifier, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show Widget;

import '../core/storage/preferences.dart';
import '../data/models/catalog_models.dart';
import '../data/models/media_item.dart';
import '../data/models/playback_request.dart';
import '../features/browse/media_list_screen.dart';
import '../features/debug/debug_screen.dart';
import '../features/details/details_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/genre/genre_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/onboarding/language_screen.dart';
import '../features/player/player_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff/staff_screen.dart';
import 'navigation.dart';
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
  static const watch = '/watch';
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
      // Full screen, above the tabs (openPlayer). Without its request (a
      // restored location) it plays the ID alone.
      GoRoute(
        path: '${AppRoutes.watch}/:id',
        builder: (_, state) => PlayerScreen(
          request: state.extra is PlaybackRequest
              ? state.extra! as PlaybackRequest
              : PlaybackRequest(
                  item: MediaItem(id: state.pathParameters['id']!),
                ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          _branch(AppRoutes.home, const HomeScreen(), routes: _browse),
          _branch(AppRoutes.search, const SearchScreen(), routes: _browse),
          _branch(AppRoutes.library, const LibraryScreen(), routes: _browse),
          _branch(
            AppRoutes.downloads,
            const DownloadsScreen(),
            routes: [
              ..._browse,
              // One series' downloaded episodes.
              GoRoute(
                path: 'saved/:id',
                builder: (_, state) =>
                    SavedSeriesScreen(titleId: state.pathParameters['id']!),
              ),
            ],
          ),
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

/// Pages any tab can open from its lists (see navigation.dart): details,
/// a genre, a person, and "See all". They open inside that tab.
final _browse = <RouteBase>[
  GoRoute(
    path: 'title/:id',
    builder: (_, state) => DetailsScreen(
      id: state.pathParameters['id']!,
      args: state.extra is TitleArgs ? state.extra! as TitleArgs : null,
    ),
  ),
  GoRoute(
    path: 'genre/:id',
    builder: (_, state) => GenreScreen(
      categoryId: state.pathParameters['id']!,
      genre: state.extra is Category ? state.extra! as Category : null,
    ),
  ),
  GoRoute(
    path: 'person/:id',
    builder: (_, state) => StaffScreen(
      id: state.pathParameters['id']!,
      args: state.extra is PersonArgs ? state.extra! as PersonArgs : null,
    ),
  ),
  GoRoute(
    path: 'list',
    // "See all" needs the list it was opened from; without it (a restored
    // or typed location) go back to the tab.
    redirect: (_, state) => state.extra is MediaListArgs
        ? null
        : '/${state.uri.pathSegments.first}',
    builder: (_, state) => MediaListScreen(args: state.extra! as MediaListArgs),
  ),
];
