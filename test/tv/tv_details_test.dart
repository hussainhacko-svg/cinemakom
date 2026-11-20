import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cinemakom/tv/tv_app.dart';
import 'package:cinemakom/tv/tv_router.dart';

import 'package:cinemakom/core/network/api_endpoints.dart';

import '../fixture.dart';
import '../helpers/app_harness.dart';
import '../helpers/fake_downloader.dart';
import '../repositories/fake_api_client.dart';
import 'reachability.dart';
import 'tv_driver.dart';

// Details, the episodes split and the download panels on TV (docs/TV.md
// TV-3), on fixture data. The series is the fixture's (id 4328) with its
// episodes made up from the fixture's own episode format.

final _exits = <String>[];

/// [perSeason] episodes in each of [seasons] seasons, numbered from 1.
List<Object?> _episodes(int seasons, int perSeason) {
  final model = (fixture('series_episodes')! as List).first as Map;
  return [
    for (var s = 1; s <= seasons; s++)
      for (var n = 1; n <= perSeason; n++)
        {
          ...model,
          'nb': '${s * 1000 + n}',
          'season': '$s',
          'episodeNummer': '$n',
        },
  ];
}

/// Lets the downloads' real file work finish, then settles (as the phone's
/// download tests do).
Future<void> _io(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Every quality is 2 GB; subtitles answer with a tiny SRT.
final _downloadRoutes = [
  FakeApiClient.path('size:', (ApiRequest r) => 2 * 1024 * 1024 * 1024),
  FakeApiClient.path('https://cnth2', '1\n00:00:01,000 --> 00:00:02,000\nHi\n'),
];

Future<TvDriver> _pumpDetails(
  WidgetTester tester, {
  String id = '4328',
  List<Object?>? episodes,
  FakeDownloader? downloader,
  int? freeSpace,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') _exits.add('exit');
      return null;
    },
  );
  _exits.clear();
  await tester.pumpWidget(const SizedBox());
  await pumpApp(
    tester,
    tv: true,
    downloader: downloader,
    freeSpace: freeSpace,
    api: fixtureApi([
      ..._downloadRoutes,
      if (episodes != null) FakeApiClient.path('videoSeason/', episodes),
    ]),
  );
  ProviderScope.containerOf(tester.element(find.byType(TvApp)))
      .read(tvRouterProvider)
      .push('/home/title/$id');
  await tester.pumpAndSettle();
  return TvDriver(tester);
}

void main() {
  testWidgets('Details opens on Play; the split: seasons, episodes, and Down '
      'keeps the download column (§7.4)', (tester) async {
    final tv = await _pumpDetails(tester, episodes: _episodes(3, 8));
    expect(tv.focused, 'Play');
    await tv.down();
    expect(tv.focused, 'Season 1');
    await tv.down(); // moving onto a season shows its episodes
    expect(tv.focused, 'Season 2');
    await tv.right();
    // Row 0 is Download season; the episodes start at row 1.
    expect(tv.focusPath, '1/1/1:2');
    expect(tv.focused, startsWith('Episode 1'));
    await tv.up();
    expect(tv.focused, 'Download season 2');
    await tv.down();
    await tv.right();
    expect(tv.focused, 'Download episode, Episode 1');
    await tv.down();
    expect(tv.focused, 'Download episode, Episode 2');
    await tv.down();
    expect(tv.focused, 'Download episode, Episode 3');
    await tv.left();
    expect(tv.focused, startsWith('Episode 3'));
    await tv.left(); // back to the selected season
    expect(tv.focused, 'Season 2');
    await tv.right(); // the episodes column remembers
    expect(tv.focused, startsWith('Episode 3'));
  });

  testWidgets('Download episode 3 of season 2, pause, resume, cancel it, '
      'focus on the same button throughout', (tester) async {
    final downloader = FakeDownloader();
    final tv = await _pumpDetails(
      tester,
      episodes: _episodes(3, 8),
      downloader: downloader,
    );
    await tv.down();
    await tv.down();
    await tv.right();
    await tv.right();
    await tv.down();
    await tv.down();
    expect(tv.focused, 'Download episode, Episode 3');
    final button = tv.focusPath;

    await tv.ok(); // the quality panel, on the preferred quality
    expect(find.text('DOWNLOAD'), findsOneWidget);
    expect(tv.focused, '1080p, 2.0 GB');
    await tv.ok();
    await _io(tester);
    expect(downloader.enqueued.single.taskId, '2003');
    expect(tv.focusPath, button);
    expect(tv.focused, 'Episode 3, Waiting');

    await tv.ok(); // its menu: Pause
    await tv.ok();
    await _io(tester);
    expect(downloader.paused, ['2003']);
    expect(tv.focusPath, button);
    expect(tv.focused, 'Episode 3, Paused');

    await tv.ok(); // Resume
    expect(tv.focused, 'Resume');
    await tv.ok();
    await _io(tester);
    expect(downloader.resumed.single.$1, '2003');
    expect(tv.focusPath, button);

    await tv.ok();
    await tv.down();
    expect(tv.focused, 'Cancel download');
    await tv.ok(); // it asks first, on the safe answer
    expect(tv.focused, 'Keep downloading');
    await tv.down();
    await tv.ok();
    await _io(tester);
    expect(downloader.canceled, ['2003']);
    expect(tv.focusPath, button);
    expect(tv.focused, 'Download episode, Episode 3');
  });

  testWidgets('Download season, above the episodes, queues the season picked', (
    tester,
  ) async {
    final downloader = FakeDownloader();
    final tv = await _pumpDetails(
      tester,
      episodes: _episodes(3, 8),
      downloader: downloader,
    );
    await tv.down();
    await tv.down(); // Season 2
    await tv.right(); // its first episode
    await tv.up();
    expect(tv.focused, 'Download season 2');
    await tv.ok();
    await tv.ok();
    // Each episode is saved one after the other.
    for (var i = 0; i < 10 && downloader.enqueued.length < 8; i++) {
      await _io(tester);
    }
    expect(downloader.enqueued.map((j) => j.taskId), [
      for (var n = 1; n <= 8; n++) '${2000 + n}',
    ]);
    expect(tv.focused, 'Download season 2');
  });

  testWidgets('A quality that would not fit is shown but skipped; when none '
      'fits the TV says so', (tester) async {
    // 2 GB files: with 2.3 GB free, none leaves the 500 MB reserve.
    var tv = await _pumpDetails(
      tester,
      episodes: _episodes(1, 2),
      freeSpace: 2300 * 1024 * 1024,
    );
    await tv.down();
    await tv.right();
    await tv.right();
    await tv.ok();
    expect(
      find.text('Not enough space on this device\n2.2 GB free on this TV'),
      findsOneWidget,
    );
    expect(tv.focused, 'OK');
    await tv.ok();
    expect(tv.focused, 'Download episode, Episode 1');

    // With 3 GB free they fit.
    tv = await _pumpDetails(
      tester,
      episodes: _episodes(1, 2),
      freeSpace: 3 * 1024 * 1024 * 1024,
    );
    await tv.down();
    await tv.right();
    await tv.right();
    await tv.ok();
    expect(tv.focused, '1080p, 2.0 GB');
    expect(find.text('3.0 GB free on this TV'), findsOneWidget);
  });

  testWidgets('A long one-season show lists only its blocks of 50', (
    tester,
  ) async {
    final tv = await _pumpDetails(tester, episodes: _episodes(1, 120));
    await tv.down();
    expect(tv.focused, '1–50');
    await tv.down();
    expect(tv.focused, '51–100');
    await tv.right();
    expect(tv.focused, startsWith('Episode 51'));
    await tv.left();
    await tv.down();
    expect(tv.focused, '101–120');
  });

  testWidgets('Cast opens the person page; Back comes back to the person', (
    tester,
  ) async {
    final tv = await _pumpDetails(tester, episodes: _episodes(1, 4));
    await tv.down(); // seasons
    await tv.down(); // cast
    final person = tv.focused;
    expect(tv.focusPath, startsWith('1/2:'));
    await tv.ok();
    expect(tv.focusPath, '1/0:0');
    await tv.back();
    expect(tv.focused, person);
  });

  testWidgets('No traps on a series page', (tester) async {
    final reached = await expectNoTraps(
      tester,
      pumpScreen: () => _pumpDetails(tester, episodes: _episodes(2, 4)),
      leftScreen: () => _exits.isNotEmpty,
      backChecks: 10,
    );
    expect(reached, containsAll(['Play', 'Season 2']));
    expect(reached.where((l) => l.startsWith('Download season ')), isNotEmpty);
  });

  testWidgets('No traps on a movie page', (tester) async {
    final reached = await expectNoTraps(
      tester,
      pumpScreen: () => _pumpDetails(tester, id: '3119279'),
      leftScreen: () => _exits.isNotEmpty,
      backChecks: 8,
    );
    expect(reached, containsAll(['Play', 'Download']));
  });
}
