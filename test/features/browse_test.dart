import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/app/widgets/media_image.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/features/details/details_screen.dart';
import 'package:cinemakom/features/genre/genre_screen.dart';
import 'package:cinemakom/features/home/home_providers.dart';
import 'package:cinemakom/features/home/widgets/home_hero.dart';
import 'package:cinemakom/features/search/search_screen.dart';
import 'package:cinemakom/features/staff/staff_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../data/paged_media_test.dart' show rawItems;
import '../fixture.dart';
import '../helpers/app_harness.dart';
import '../repositories/fake_api_client.dart';

/// Pushes [location] on the current tab, as a list would.
Future<void> push(WidgetTester tester, String location) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push(location);
  await tester.pumpAndSettle();
}

void main() {
  group('home', () {
    testWidgets('shows the hero and the rows', (tester) async {
      await pumpApp(tester);
      // The first banner, uppercased as a Latin hero title.
      expect(find.text('TENET'), findsOneWidget);
      expect(find.text('NOW SHOWING'), findsWidgets);
      // Scroll the lazily built rows into view.
      await tester.scrollUntilVisible(
        find.text('LATEST MOVIES'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('LATEST MOVIES'), findsOneWidget);
    });

    testWidgets('the hero shows at most heroBannerCap banners', (tester) async {
      // The live API sends 85; here 18 distinct ones.
      final one = (fixture('banners')! as List).cast<Map<String, Object?>>();
      final many = [
        for (var copy = 0; copy < 3; copy++)
          for (final b in one) {...b, 'nb': '${b['nb']}$copy'},
      ];
      expect(many, hasLength(18));
      await pumpApp(
        tester,
        api: fixtureApi([FakeApiClient.path('banner/', many)]),
      );
      final banners = ProviderScope.containerOf(
        tester.element(find.byType(HomeHero)),
      ).read(bannersProvider).value!;
      expect(banners, hasLength(heroBannerCap));
      expect(heroBannerCap, 10);
    });

    testWidgets('the hero moves on by itself, but not under a finger', (
      tester,
    ) async {
      await pumpApp(tester);
      const next = 'THE LORD OF THE RINGS: THE RINGS OF POWER';
      // Every banner's text is laid out; only the current one is opaque.
      double shown(String title) => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text(title),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      final hero = find.byType(HomeHero);
      final height = tester.getSize(hero).height;
      expect(shown('TENET'), 1);

      final finger = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await tester.pump(const Duration(seconds: 11));
      expect(shown('TENET'), 1);
      // Cancelled, so it isn't a tap (that opens the title).
      await finger.cancel();

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(shown(next), 1);
      expect(shown('TENET'), 0);
      // A longer title doesn't move the page below.
      expect(tester.getSize(hero).height, height);
    });

    testWidgets('the hero loops forward from the last banner to the first', (
      tester,
    ) async {
      await pumpApp(tester);
      double shown(String title) => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text(title),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      // The fixture has 6 banners: five advances reach the last, the sixth
      // comes back round to the first.
      final start = tester.getTopLeft(find.byType(PageView));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
      }
      expect(shown('TENET'), 1);
      // Forward, not a rewind: the pages only ever moved one way.
      final page = tester
          .widget<PageView>(find.byType(PageView))
          .controller!
          .page!;
      expect(page, greaterThan(10000));
      expect(tester.getTopLeft(find.byType(PageView)), start);
    });

    testWidgets('a failing section offers a retry', (tester) async {
      var bannersFail = true;
      await pumpApp(
        tester,
        api: fixtureApi([
          FakeApiClient.path(
            'banner/',
            (ApiRequest _) => bannersFail ? offline : const [],
          ),
        ]),
      );
      expect(
        find.text('No connection. Check your internet and try again.'),
        findsOneWidget,
      );
      bannersFail = false;
      await tester.tap(find.text('Try again').first);
      await tester.pumpAndSettle();
      expect(
        find.text('No connection. Check your internet and try again.'),
        findsNothing,
      );
    });

    testWidgets('a poster opens details inside the tab', (tester) async {
      await pumpApp(tester);
      // The hero's artwork opens the details (its Play opens the player).
      await tester.tap(find.byType(MediaImage).first);
      await tester.pumpAndSettle();
      expect(find.byType(DetailsScreen), findsOneWidget);
      // The bottom bar stays, and back returns to Home.
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailsScreen), findsNothing);
      expect(find.text('TENET'), findsOneWidget);
    });
  });

  group('details', () {
    testWidgets('a series lists its episodes by number', (tester) async {
      await pumpApp(tester);
      await push(tester, '/home/title/4328');
      expect(find.text('FRIENDS'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('EPISODES'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining(RegExp(r'^Episodes? \d')), findsWidgets);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('a movie shows its synopsis and genres', (tester) async {
      await pumpApp(tester);
      await push(tester, '/home/title/3119279');
      expect(find.text('EVE OF DESTRUCTION'), findsOneWidget);
      expect(find.byType(Wrap), findsWidgets);
    });
  });

  group('person', () {
    testWidgets('a cast member opens their page with their titles', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, '/home/title/3119279');
      await tester.scrollUntilVisible(
        find.bySemanticsLabel('Gregory Hines, Actor'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // Clear of the bottom bar.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Gregory Hines, Actor'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffScreen), findsOneWidget);
      expect(find.text('GREGORY HINES'), findsOneWidget);
      expect(find.text('Actor · 2 titles'), findsOneWidget);
      expect(find.text('History of the World: Part I'), findsOneWidget);
      // Inside the tab: the bar stays, and back returns to the title.
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffScreen), findsNothing);
      expect(find.text('EVE OF DESTRUCTION'), findsOneWidget);
    });

    testWidgets('an unknown person says so', (tester) async {
      await pumpApp(
        tester,
        api: fixtureApi([FakeApiClient.path('staff/actorID/', const [])]),
      );
      await push(tester, '/home/person/1');
      expect(find.text("This person's page isn't available."), findsOneWidget);
    });
  });

  group('genre', () {
    testWidgets('scrolling loads the next pages until a short one', (
      tester,
    ) async {
      final api = fixtureApi([
        FakeApiClient.path('videosByCategory', (ApiRequest r) {
          final offset = int.parse('${r.query['offset']}');
          return {
            'info': rawItems(offset, offset < 60 ? 30 : 5),
            'offset': offset + 30,
          };
        }),
      ]);
      await pumpApp(tester, api: api);
      await push(tester, '/home/genre/1');
      expect(find.byType(GenreScreen), findsOneWidget);
      expect(find.text('Title 1'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Title 65'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      final offsets = [
        for (final r in api.requests)
          if (r.path == 'videosByCategory') r.query['offset'],
      ];
      expect(offsets, containsAllInOrder([0, 30, 60]));
      expect(offsets.where((o) => o == 90), isEmpty);
    });

    testWidgets('kind and sort change the request', (tester) async {
      final api = fixtureApi();
      await pumpApp(tester, api: api);
      await push(tester, '/home/genre/1');
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recently added'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A to Z'));
      await tester.pumpAndSettle();
      final last = api.requests.lastWhere(
        (r) => r.path.startsWith('videosByCategory'),
      );
      expect(last.query['videoKind'], VideoKind.series.code);
      expect(last.query['orderby'], SortOrder.titleAscending.code);
    });
  });

  group('search', () {
    testWidgets('shows genres before typing and results after', (tester) async {
      final api = fixtureApi();
      await pumpApp(tester, api: api);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(find.text('BROWSE GENRES'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'batman');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        api.requests.where((r) => r.path.contains('video_title_search')),
        isEmpty,
        reason: 'debounced',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('TITLES'), findsOneWidget);
      expect(find.text('The Batman'), findsOneWidget);
    });

    testWidgets('the kind chips filter the results', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'batman');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Batman: The Animated Series'), findsOneWidget);

      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();
      expect(find.text('Batman: The Animated Series'), findsNothing);
    });

    testWidgets('a search with no results says so', (tester) async {
      await pumpApp(
        tester,
        api: fixtureApi([
          FakeApiClient.path('video/V/2/', const []),
          FakeApiClient.path('AdvancedSearch', const []),
        ]),
      );
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Nothing found for “zzzz”'), findsOneWidget);
    });
  });
}
