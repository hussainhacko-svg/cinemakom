import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/app/catalog_providers.dart';
import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/tv_router.dart';

import '../helpers/app_harness.dart';
import 'reachability.dart';
import 'tv_driver.dart';

// The TV genre page (docs/TV.md §7.2) on fixture data.

final _exits = <String>[];

Future<TvDriver> _pumpGenre(WidgetTester tester) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') _exits.add('exit');
      return null;
    },
  );
  _exits.clear();
  await tester.pumpWidget(const SizedBox());
  await pumpApp(tester, tv: true);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(TvApp)),
  );
  final genre = (await container.read(genresProvider.future)).first;
  container
      .read(tvRouterProvider)
      .push('/home/genre/${genre.id}', extra: genre);
  await tester.pumpAndSettle();
  return TvDriver(tester);
}

void main() {
  testWidgets('Focus starts on the first poster; Up reaches the filters, '
      'which open on their current value', (tester) async {
    final tv = await _pumpGenre(tester);
    expect(tv.focusPath, '1/1:0');
    await tv.up();
    expect(tv.focused, 'Sort: Recently added');
    await tv.ok();
    expect(tv.focused, 'Recently added');
    await tv.down();
    final picked = tv.focused;
    await tv.ok();
    expect(tv.focused, 'Sort: $picked');
    await tv.down();
    expect(tv.focusPath, '1/1:0');
    await tv.back(); // pops the page: focus back on Home where it was
    expect(tv.focused, 'Play');
  });

  testWidgets('No traps on a genre page', (tester) async {
    final reached = await expectNoTraps(
      tester,
      pumpScreen: () => _pumpGenre(tester),
      leftScreen: () => _exits.isNotEmpty,
      backChecks: 8,
    );
    expect(reached, contains('Sort: Recently added'));
  });
}
