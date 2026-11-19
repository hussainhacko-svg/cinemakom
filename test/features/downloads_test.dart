import 'dart:io';

import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:cinemakom/features/downloads/downloads_screen.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../helpers/app_harness.dart';
import '../helpers/fake_downloader.dart';
import '../repositories/fake_api_client.dart';
import 'player/fake_engine.dart';

Future<void> _push(WidgetTester tester, String location) async {
  ProviderScope.containerOf(tester.element(find.byType(CinemakomApp)))
      .read(routerProvider)
      .push(location);
  await tester.pumpAndSettle();
}

/// Lets real file and timer work finish, then rebuilds.
Future<void> _io(WidgetTester tester) async {
  // Each file step finishes on the real event loop, then the next starts.
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openDownloads(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Downloads'),
    ),
  );
  await tester.pumpAndSettle();
}

final _dir = Directory.systemTemp.createTempSync('dl-ui').path;

Download _row(
  String id, {
  String titleId = '3119279',
  String title = 'Eve of Destruction',
  DownloadStatus status = DownloadStatus.complete,
  int? season,
  int? episode,
  int bytes = 2 * 1024 * 1024 * 1024,
  DownloadProblem? problem,
  String? dir,
}) => Download(
  videoId: id,
  titleId: titleId,
  title: LocalizedText(en: title),
  season: season,
  episode: episode,
  kind: season == null ? VideoKind.movies : VideoKind.series,
  quality: '1080p',
  baseDirectory: 'root',
  directory: dir ?? _dir,
  fileName: '$id.mp4',
  status: status,
  problem: problem,
  totalBytes: bytes,
  addedAt: DateTime(2026, 11, 19),
);

void main() {
  testWidgets('an empty Downloads tab says what goes there', (tester) async {
    await pumpApp(tester);
    await _openDownloads(tester);
    expect(find.text('DOWNLOADS'), findsOneWidget);
    expect(
      find.text(
        'Movies and episodes you download show up here, and play without '
        'a connection.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a movie: pick a quality with its size, then it queues', (
    tester,
  ) async {
    final downloader = FakeDownloader();
    final store = MemoryDownloadStore();
    await pumpApp(
      tester,
      downloads: store,
      downloader: downloader,
      api: fixtureApi([
        FakeApiClient.path('size:', (ApiRequest r) => 2 * 1024 * 1024 * 1024),
        FakeApiClient.path(
          'https://cnth2',
          '1\n00:00:01,000 --> 00:00:02,000\nHi\n',
        ),
      ]),
    );
    await _push(tester, '/home/title/3119279');
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Download quality'), findsOneWidget);
    expect(find.text('1080p · 2.0 GB'), findsOneWidget);
    await tester.tap(find.text('720p · 2.0 GB'));
    await tester.pumpAndSettle();
    await _io(tester);

    expect(downloader.enqueued.single.taskId, '3119279');
    expect(store.rows['3119279']!.quality, '720p');
    expect(find.text('Added to downloads'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('a series shows a download button per episode and the season', (
    tester,
  ) async {
    await pumpApp(tester);
    await _push(tester, '/home/title/4328');
    await tester.scrollUntilVisible(
      find.text('Download season'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byTooltip('Download episode'), findsWidgets);
    // A series has no movie Download pill.
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('Downloading and On this device, a series as one row', (
    tester,
  ) async {
    final downloader = FakeDownloader();
    final store = MemoryDownloadStore([
      _row(
        'run',
        title: 'Tenet',
        titleId: 'run',
        status: DownloadStatus.running,
      ),
      _row(
        'bad',
        title: 'Dune',
        titleId: 'bad',
        status: DownloadStatus.failed,
        problem: DownloadProblem.noSpace,
      ),
      _row('3119279'),
      _row('e1', titleId: '4328', title: 'Friends', season: 1, episode: 1),
      _row('e2', titleId: '4328', title: 'Friends', season: 1, episode: 2),
    ]);
    // The engine still runs it (else startup marks it lost).
    downloader.knownStates['run'] = DownloaderState.running;
    await pumpApp(tester, downloads: store, downloader: downloader);
    await _openDownloads(tester);

    expect(find.text('DOWNLOADING'), findsOneWidget);
    expect(find.text('ON THIS DEVICE'), findsOneWidget);
    expect(find.text('6.0 GB used by Cinemakom'), findsOneWidget);
    expect(find.text('Not enough space on this device'), findsOneWidget);
    expect(find.text('2 episodes · 4.0 GB'), findsOneWidget);
    expect(find.text('1080p · 2.0 GB'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(downloader.paused, ['run']);

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedSeriesScreen), findsOneWidget);
    expect(find.text('Season 1 · Episode 1'), findsOneWidget);
    expect(find.text('Season 1 · Episode 2'), findsOneWidget);
  });

  testWidgets('cancel asks first; a series row long-presses to delete all', (
    tester,
  ) async {
    final downloader = FakeDownloader();
    // Its own folder: deleting a series removes the series' folder.
    final own = Directory.systemTemp.createTempSync('dl-series').path;
    final store = MemoryDownloadStore([
      _row(
        'run',
        title: 'Tenet',
        titleId: 'run',
        status: DownloadStatus.running,
        dir: own,
      ),
      for (final e in [1, 2])
        _row(
          'e$e',
          titleId: '4328',
          title: 'Friends',
          season: 1,
          episode: e,
          dir: own,
        ),
    ]);
    downloader.knownStates['run'] = DownloaderState.running;
    await pumpApp(tester, downloads: store, downloader: downloader);
    await _openDownloads(tester);

    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pumpAndSettle();
    expect(
      find.text("Cancel this download? What's downloaded so far is lost."),
      findsOneWidget,
    );
    expect(downloader.canceled, isEmpty);
    await tester.tap(find.text('Cancel download').last);
    await tester.pumpAndSettle();
    expect(downloader.canceled, ['run']);

    await tester.longPress(find.text('Friends'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all episodes'));
    await _io(tester);
    expect(store.rows.keys, isNot(contains('e1')));
    expect(store.rows.keys, isNot(contains('e2')));
  });

  testWidgets('a downloaded movie plays from disk, with no stream request', (
    tester,
  ) async {
    final file = File(p.join(_dir, '3119279.mp4'))..writeAsBytesSync([0]);
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);
    final api = fixtureApi();
    final engine = FakeEngine();
    await pumpApp(
      tester,
      api: api,
      engine: engine,
      downloads: MemoryDownloadStore([_row('3119279')]),
    );
    await _openDownloads(tester);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    await _io(tester);
    expect(find.byType(PlayerScreen), findsOneWidget);
    expect(engine.opened.last.source.uri, Uri.file(file.path).toString());
    expect(
      api.requests.where((r) => r.path.startsWith('transcoddedFiles')),
      isEmpty,
    );
  });
}
