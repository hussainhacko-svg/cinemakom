import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/app/navigation_args.dart';
import 'package:cinemakom/app/catalog_providers.dart';
import 'package:cinemakom/data/paging/media_sources.dart';
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/tv_router.dart';
import 'package:cinemakom/tv/widgets/tv_paged_grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cinemakom/core/network/api_endpoints.dart';

import '../fixture.dart';
import '../helpers/app_harness.dart';
import '../repositories/fake_api_client.dart';
import 'reachability.dart';
import 'tv_driver.dart';

// The TV app's shell and Home on fixture data (docs/TV.md TV-2).

final _exits = <String>[];

Future<TvDriver> _pumpTv(WidgetTester tester) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') _exits.add('exit');
      return null;
    },
  );
  _exits.clear();
  // A fresh app each time (pumping it again would keep its state).
  await tester.pumpWidget(const SizedBox());
  await pumpApp(tester, tv: true);
  return TvDriver(tester);
}

void main() {
  testWidgets('Home opens on Play (R11)', (tester) async {
    final tv = await _pumpTv(tester);
    expect(tv.focused, 'Play');
  });

  testWidgets('Up reaches the tabs; moving onto a tab switches to it', (
    tester,
  ) async {
    final tv = await _pumpTv(tester);
    await tv.up();
    expect(tv.focused, 'Home');
    await tv.right();
    expect(tv.focused, 'Search');
    await tv.down(); // the Search tab has nothing to focus yet
    expect(tv.focused, 'Search');
    await tv.left();
    await tv.down();
    expect(tv.focused, 'Play');
  });

  testWidgets('The Back ladder: content → its tab → Home → exit (R4)', (
    tester,
  ) async {
    final tv = await _pumpTv(tester);
    await tv.down();
    await tv.down();
    await tv.right();
    final deep = tv.focused;
    expect(deep, isNot('Play'));
    await tv.back();
    expect(tv.focused, 'Home');
    await tv.right();
    await tv.right();
    expect(tv.focused, 'Library');
    await tv.back();
    expect(tv.focused, 'Home');
    expect(_exits, isEmpty);
    await tv.back();
    expect(_exits, ['exit']);
  });

  testWidgets('Home → See all → Back: focus where it was (R2)', (tester) async {
    final tv = await _pumpTv(tester);
    await tv.down();
    // Along the first row to its See all card.
    await tv.press(LogicalKeyboardKey.arrowRight, times: 40);
    expect(tv.focused, 'See all');
    final row = tv.focusPath;
    await tv.ok();
    expect(tv.focused, isNot('See all'));
    expect(tv.focused, isNot(startsWith('not a TV item')));
    await tv.back();
    expect(tv.focused, 'See all');
    expect(tv.focusPath, row);
  });

  testWidgets("The remote's Back (Android's system Back) climbs one rung at "
      'a time: See all → Home → its tab → exit', (tester) async {
    final tv = await _pumpTv(tester);
    await tv.down();
    await tv.press(LogicalKeyboardKey.arrowRight, times: 40);
    await tv.ok();
    expect(tv.focused, isNot('See all'));
    Future<void> systemBack() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    await systemBack();
    expect(tv.focused, 'See all');
    expect(_exits, isEmpty);
    await systemBack();
    expect(tv.focused, 'Home');
    expect(_exits, isEmpty);
    await systemBack();
    expect(_exits, ['exit']);
  });

  testWidgets('See all: a lower row scrolls into view with its titles', (
    tester,
  ) async {
    // A genre page of 18 titles (three rows): the fixture's 6, three times
    // with new IDs.
    final page = fixture('videos_by_category')! as Map<String, Object?>;
    final items = page['info']! as List<Object?>;
    final long = {
      ...page,
      'info': [
        for (var k = 0; k < 3; k++)
          for (final i in items)
            {...i! as Map<String, Object?>, 'nb': '9$k${(i as Map)['nb']}'},
      ],
    };
    await tester.pumpWidget(const SizedBox());
    await pumpApp(
      tester,
      tv: true,
      api: fixtureApi([
        FakeApiClient.path(
          'videosByCategory',
          (ApiRequest r) =>
              requestedPage(r) == 0 ? long : {...page, 'info': []},
        ),
      ]),
    );
    final tv = TvDriver(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TvApp)),
    );
    final genre = (await container.read(genresProvider.future)).first;
    container
        .read(tvRouterProvider)
        .push(
          '/home/list',
          extra: MediaListArgs(
            title: 'A genre',
            source: GenreSource(categoryId: genre.id),
          ),
        );
    await tester.pumpAndSettle();
    expect(tv.focusPath, '1/0:0');
    await tv.down();
    expect(tv.focusPath, '1/0:$tvGridColumns');
    final node = FocusManager.instance.primaryFocus!;
    final box = node.context!.findRenderObject()! as RenderBox;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    // The whole card, title and meta included, sits above the bottom of
    // the safe area.
    expect(bottom, lessThanOrEqualTo(540 - 27 + 0.5));
  });

  testWidgets('No traps on Home: every control reached, Back always leaves', (
    tester,
  ) async {
    final reached = await expectNoTraps(
      tester,
      pumpScreen: () => _pumpTv(tester),
      leftScreen: () => _exits.isNotEmpty,
      backChecks: 12,
    );
    expect(reached, containsAll(['Play', 'Home', 'Settings', 'See all']));
  });
}
