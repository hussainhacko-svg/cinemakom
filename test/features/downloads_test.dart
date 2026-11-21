import 'dart:io';

import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/preferences.dart';
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
  String? titleAr,
  DownloadStatus status = DownloadStatus.complete,
  int? season,
  int? episode,
  int bytes = 2 * 1024 * 1024 * 1024,
  int downloadedBytes = 0,
  bool pausedByUser = false,
  bool startedOver = false,
  DownloadProblem? problem,
  String? problemDetail,
  String? dir,
  bool createFile = true,
}) {
  final folder = dir ?? _dir;
  if (status == DownloadStatus.complete && createFile) {
    final f = File(p.join(folder, '$id.mp4'));
    if (!f.existsSync()) {
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(const [0]);
    }
  }
  return Download(
    videoId: id,
    titleId: titleId,
    title: LocalizedText(en: title, ar: titleAr),
    season: season,
    episode: episode,
    kind: season == null ? VideoKind.movies : VideoKind.series,
    quality: '1080p',
    baseDirectory: 'root',
    directory: folder,
    fileName: '$id.mp4',
    status: status,
    problem: problem,
    problemDetail: problemDetail,
    totalBytes: bytes,
    downloadedBytes: downloadedBytes,
    pausedByUser: pausedByUser,
    startedOver: startedOver,
    addedAt: DateTime(2026, 11, 19),
  );
}

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

  testWidgets(
    'paused, waiting and failed rows show saved bytes (never 1 MB of 27 GB) and Details',
    (tester) async {
      const gb = 1024 * 1024 * 1024;
      final downloader = FakeDownloader();
      final store = MemoryDownloadStore([
        _row(
          'p1',
          titleId: 'p1',
          title: 'The Odyssey',
          status: DownloadStatus.paused,
          pausedByUser: true,
          bytes: 27 * gb,
          downloadedBytes: (3.6 * gb).round(),
        ),
        _row(
          'w1',
          titleId: 'w1',
          title: 'Arrival',
          status: DownloadStatus.paused,
          pausedByUser: false,
          bytes: 4 * gb,
          downloadedBytes: 1 * gb,
        ),
        _row(
          'f1',
          titleId: 'f1',
          title: 'Dune',
          status: DownloadStatus.failed,
          problem: DownloadProblem.interrupted,
          problemDetail: 'Task timed out',
          bytes: 27 * gb,
          downloadedBytes: 0,
        ),
      ]);
      await pumpApp(tester, downloads: store, downloader: downloader);
      await _openDownloads(tester);

      expect(find.textContaining('Paused · 3.6 GB of 27 GB'), findsOneWidget);
      expect(
        find.textContaining('Waiting for connection · 1.0 GB of 4.0 GB'),
        findsOneWidget,
      );
      // 0 saved bytes must NEVER show "1 MB of 27 GB".
      expect(find.textContaining('1 MB'), findsNothing);
      expect(find.text('Stopped: interrupted'), findsOneWidget);

      // Long-press opens menu -> Details shows engine message & path.
      await tester.longPress(find.text('Dune'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Task timed out'), findsOneWidget);
      expect(find.textContaining('f1.mp4'), findsOneWidget);
    },
  );

  testWidgets('Arabic RTL Downloads rows show saved bytes and reasons', (
    tester,
  ) async {
    const gb = 1024 * 1024 * 1024;
    final downloader = FakeDownloader();
    final store = MemoryDownloadStore([
      _row(
        'p1',
        titleId: 'p1',
        title: 'The Odyssey',
        titleAr: 'الأوديسة',
        status: DownloadStatus.paused,
        pausedByUser: true,
        bytes: 27 * gb,
        downloadedBytes: (3.6 * gb).round(),
      ),
      _row(
        'f1',
        titleId: 'f1',
        title: 'Dune',
        titleAr: 'كثيب',
        status: DownloadStatus.failed,
        problem: DownloadProblem.server,
        bytes: 4 * gb,
        downloadedBytes: 2 * gb,
      ),
    ]);
    await pumpApp(
      tester,
      downloads: store,
      downloader: downloader,
      store: MemoryPreferenceStore({PreferenceKeys.language: 'ar'}),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('التنزيلات'),
      ),
    );
    await tester.pumpAndSettle();
    expect(directionAt(tester, find.text('الأوديسة')), TextDirection.rtl);
    expect(find.textContaining('متوقف مؤقتًا'), findsOneWidget);
    expect(find.textContaining('3.6 غ.ب من 27 غ.ب'), findsOneWidget);
    expect(find.textContaining('توقف: خطأ في الخادم'), findsOneWidget);
  });

  testWidgets(
    'storage line shows used and free space when free space is known',
    (tester) async {
      const gb = 1024 * 1024 * 1024;
      final store = MemoryDownloadStore([_row('3119279', bytes: 27 * gb)]);
      await pumpApp(tester, downloads: store, freeSpace: 120 * gb);
      await _openDownloads(tester);
      expect(find.text('Downloads use 27 GB · 120 GB free'), findsOneWidget);
    },
  );

  testWidgets(
    'missing finished file shows File removed with Download again and Remove',
    (tester) async {
      final goneDir = Directory.systemTemp.createTempSync('dl-gone').path;
      addTearDown(() => Directory(goneDir).deleteSync(recursive: true));
      final downloader = FakeDownloader();
      final store = MemoryDownloadStore([
        _row('3119279', dir: goneDir, createFile: false),
      ]);
      await pumpApp(tester, downloads: store, downloader: downloader);
      await _openDownloads(tester);

      expect(find.text('File removed'), findsOneWidget);
      await tester.tap(find.text('Eve of Destruction'));
      await tester.pumpAndSettle();
      expect(find.text('Download again'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
    },
  );

  testWidgets('tapping a download notification navigates to Downloads tab', (
    tester,
  ) async {
    final downloader = FakeDownloader();
    await pumpApp(tester, downloader: downloader);
    expect(find.text('DOWNLOADS'), findsNothing);

    downloader.tapNotification('3119279');
    await tester.pumpAndSettle();
    expect(find.text('DOWNLOADS'), findsOneWidget);
  });
}
