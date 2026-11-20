import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../app/navigation_args.dart';
import '../app/theme/marquee_colors.dart';
import '../core/storage/preferences.dart';
import '../data/models/catalog_models.dart';
import '../data/models/media_item.dart';
import '../data/models/playback_request.dart';
import 'player/tv_player_screen.dart';
import 'screens/browse/tv_genre_screen.dart';
import 'screens/details/tv_details_screen.dart';
import 'screens/person/tv_person_screen.dart';
import 'screens/browse/tv_list_screen.dart';
import 'screens/home/tv_home_screen.dart';
import 'screens/downloads/tv_downloads_screen.dart';
import 'screens/library/tv_library_screen.dart';
import 'screens/search/tv_search_screen.dart';
import 'screens/settings/tv_settings_screen.dart';
import 'screens/tv_welcome_screen.dart';
import 'tv_shell.dart';

/// The TV router (docs/TV.md §4.4): the phone's paths and arguments, its
/// own screens. First launch asks for the language; the tabs each keep their
/// back stack; the player pushes above the shell. Pages change without a
/// transition: instant is easiest to follow from the sofa, and cheapest on
/// slow TV chips.
final tvRouterProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier(ref.read(settingsProvider).hasChosenLanguage);
  ref
    ..listen(
      settingsProvider.select((s) => s.hasChosenLanguage),
      (_, chosen) => onboarded.value = chosen,
    )
    ..onDispose(onboarded.dispose);

  final router = GoRouter(
    initialLocation: '/home',
    // The screens decide where focus goes (docs/TV.md R2, R11); a route
    // change taking focus to its scope would lose it.
    requestFocus: false,
    refreshListenable: onboarded,
    redirect: (context, state) {
      final atWelcome = state.matchedLocation == '/welcome';
      if (!onboarded.value) return atWelcome ? null : '/welcome';
      return atWelcome ? '/home' : null;
    },
    routes: [
      _route('/welcome', (_) => const TvWelcomeScreen()),
      // Full screen, above the tabs (tvOpenPlayer). Without its request (a
      // restored location) it plays the ID alone.
      _route(
        '/watch/:id',
        (state) => TvPlayerScreen(
          request: state.extra is PlaybackRequest
              ? state.extra! as PlaybackRequest
              : PlaybackRequest(
                  item: MediaItem(id: state.pathParameters['id']!),
                ),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) => TvShell(
          shell: shell,
          // A tab's own screen, not a page pushed inside it.
          atRoot: state.uri.pathSegments.length <= 1,
        ),
        branches: [
          _branch('/home', const TvHomeScreen()),
          _branch('/search', const TvSearchScreen()),
          _branch('/library', const TvLibraryScreen()),
          _branch(
            '/downloads',
            const TvDownloadsScreen(),
            routes: [
              // One series' downloaded episodes.
              _route(
                'saved/:id',
                (state) =>
                    TvSavedSeriesScreen(titleId: state.pathParameters['id']!),
              ),
            ],
          ),
          _branch(
            '/settings',
            const TvSettingsScreen(),
            routes: [_route('licenses', (_) => const TvLicensesScreen())],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// A page with the app's background, shown without a transition.
GoRoute _route(
  String path,
  Widget Function(GoRouterState state) screen, {
  List<RouteBase> routes = const [],
  GoRouterRedirect? redirect,
}) => GoRoute(
  path: path,
  redirect: redirect,
  routes: routes,
  pageBuilder: (_, state) => NoTransitionPage(
    key: state.pageKey,
    child: Material(color: MarqueeColors.night, child: screen(state)),
  ),
);

StatefulShellBranch _branch(
  String path,
  Widget screen, {
  List<RouteBase> routes = const [],
}) => StatefulShellBranch(
  routes: [
    _route(path, (_) => screen, routes: [..._browse, ...routes]),
  ],
);

/// Pages any tab opens from its lists (tv_navigation.dart), inside that tab.
final _browse = <RouteBase>[
  _route(
    'title/:id',
    (state) => TvDetailsScreen(
      id: state.pathParameters['id']!,
      args: state.extra is TitleArgs ? state.extra! as TitleArgs : null,
    ),
  ),
  _route(
    'genre/:id',
    (state) => TvGenreScreen(
      categoryId: state.pathParameters['id']!,
      genre: state.extra is Category ? state.extra! as Category : null,
    ),
  ),
  _route(
    'person/:id',
    (state) => TvPersonScreen(
      id: state.pathParameters['id']!,
      args: state.extra is PersonArgs ? state.extra! as PersonArgs : null,
    ),
  ),
  _route(
    'list',
    // "See all" needs the list it was opened from; without it (a restored
    // location) go back to the tab.
    redirect: (_, state) => state.extra is MediaListArgs
        ? null
        : '/${state.uri.pathSegments.first}',
    (state) => TvListScreen(args: state.extra! as MediaListArgs),
  ),
];
