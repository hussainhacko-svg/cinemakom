// Downloads end to end (PLAN.md Phase 6): the real background_downloader,
// the live CDN and the real player. A short episode at 240p (about 40 MB):
// download, pause, resume with a fresh URL, finish, play from disk, delete.
//
//   fvm flutter test integration_test/downloads_test.dart -d linux
//
// The database is in memory and files go to a temporary folder, so the
// owner's real downloads and history are untouched.
import 'dart:io';

import 'package:cinemakom/app/app.dart';
import 'package:cinemakom/app/router.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/core/storage/preferences.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/models/playback_request.dart';
import 'package:cinemakom/data/repositories/downloads_repository.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:cinemakom/features/player/player_controller.dart';
import 'package:cinemakom/features/player/player_screen.dart';
import 'package:cinemakom/features/player/player_state.dart';
import 'package:cinemakom/main.dart' show noRetry;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:path/path.dart' as p;

/// Friends, Season 1 Episode 1 (the series' own record).
const friends = MediaItem(
  id: '4328',
  title: LocalizedText(en: 'Friends'),
  kind: VideoKind.series,
);
final pilot = Episode(id: '4328', season: 1, episode: 1);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();

  /// Re-reads the download row (set by the test).
  Future<void> Function()? refresh;

  Future<void> until(
    WidgetTester tester,
    String what,
    bool Function() done, {
    int seconds = 30,
  }) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $what');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await refresh?.call();
    }
  }

  testWidgets('download, pause, resume, play offline, delete', (tester) async {
    final dir = Directory.systemTemp.createTempSync('cinemakom-dl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: noRetry,
        overrides: [
          preferenceStoreProvider.overrideWith(
            (ref) => MemoryPreferenceStore({PreferenceKeys.language: 'en'}),
          ),
          appDatabaseProvider.overrideWithValue(db),
          libraryRepositoryProvider.overrideWithValue(
            MemoryLibraryRepository(),
          ),
          downloadRootProvider.overrideWithValue(
            () async => (baseDirectory: 'root', directory: dir.path),
          ),
        ],
        child: const CinemakomApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CinemakomApp)),
    );
    final repo = container.read(downloadsRepositoryProvider);
    // Polled on the real event loop: drift's watch streams don't run in the
    // test's zone.
    Download? row;
    var fraction = 0.0;
    final progress = repo.watchProgress().listen(
      (m) => fraction = m[pilot.id]?.fraction ?? fraction,
    );
    addTearDown(progress.cancel);
    refresh = () async {
      row = await tester.runAsync<Download?>(() => repo.get(pilot.id));
    };
    await until(
      tester,
      'startup',
      () => find.text('Home').evaluate().isNotEmpty,
    );

    // Sizes from the CDN, then the lowest quality.
    final choices = (await tester.runAsync(() => repo.choices(pilot.id)))!;
    debugPrint(
      'choices: ${[for (final c in choices) '${c.source.label} ${c.bytes}']}',
    );
    expect(choices.every((c) => (c.bytes ?? 0) > 1000000), isTrue);
    final low = choices.last;
    await tester.runAsync(
      () => repo.download(
        friends,
        episode: pilot,
        source: low.source,
        bytes: low.bytes,
      ),
    );
    await until(tester, 'the row', () => row != null);
    expect(row?.subtitles.map((s) => s.language), containsAll(['ar', 'en']));

    await until(tester, 'progress', () => fraction > 0.1, seconds: 60);
    await tester.runAsync(() => repo.pause(pilot.id));
    await until(tester, 'paused', () => row?.status == DownloadStatus.paused);
    final pausedAt = fraction;
    final savedAtPause = row!.downloadedBytes;
    debugPrint('paused at $pausedAt ($savedAtPause bytes saved)');
    expect(savedAtPause, greaterThan(0));

    fraction = -1;
    await tester.runAsync(() => repo.resume(pilot.id));
    // It continues from the partial file: progress never starts over.
    await until(tester, 'progress after resuming', () => fraction >= 0);
    expect(fraction, greaterThanOrEqualTo(pausedAt * 0.95));
    await until(
      tester,
      'complete (at $fraction, ${row?.status})',
      () => row?.status == DownloadStatus.complete,
      seconds: 300,
    );
    final file = File(p.join(row!.directory, row!.fileName));
    expect(file.lengthSync(), low.bytes);
    for (final s in row!.subtitles) {
      expect(File(p.join(row!.directory, s.fileName)).existsSync(), isTrue);
    }

    // Plays from disk.
    container
        .read(routerProvider)
        .push(
          '/watch/${pilot.id}',
          extra: PlaybackRequest(item: friends, episode: pilot),
        );
    await until(
      tester,
      'the player',
      () => find.byType(PlayerScreen).evaluate().isNotEmpty,
    );
    final request = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    final controller = container.read(
      playerControllerProvider(request.request).notifier,
    );
    await until(
      tester,
      'offline playback',
      () =>
          controller.state.phase == PlayerPhase.ready &&
          controller.position.value > const Duration(seconds: 3),
    );
    expect(controller.state.quality!.url, startsWith('file://'));
    expect(controller.state.subtitles, isNotEmpty);
    container.read(routerProvider).pop();
    await until(
      tester,
      'leaving the player',
      () => find.byType(PlayerScreen).evaluate().isEmpty,
    );

    // Deleting the finished file outside the app marks it missing (§9).
    var missing = <String>{};
    final missingSub = repo.watchMissing().listen((m) => missing = m);
    addTearDown(missingSub.cancel);
    file.deleteSync();
    await tester.runAsync(() => repo.reconcile(force: true));
    await until(tester, 'missing detected', () => missing.contains(pilot.id));
    expect(await tester.runAsync(() => repo.playable(pilot.id)), isNull);

    await tester.runAsync(() => repo.delete(pilot.id));
    await until(tester, 'the row gone', () => row == null);

    // Deleting during a download leaves no `.partial` temp files behind (§9).
    await tester.runAsync(
      () => repo.download(
        friends,
        episode: pilot,
        source: low.source,
        bytes: low.bytes,
      ),
    );
    fraction = 0;
    await until(
      tester,
      'second download running',
      () => fraction > 0.05,
      seconds: 60,
    );
    await tester.runAsync(() => repo.delete(pilot.id));
    await until(tester, 'second row gone', () => row == null);
    final partialDir = Directory(p.join(dir.path, '.partial'));
    final strays = partialDir.existsSync()
        ? partialDir
              .listSync()
              .whereType<File>()
              .where(
                (f) => p
                    .basename(f.path)
                    .startsWith('com.bbflight.background_downloader'),
              )
              .toList()
        : const <File>[];
    expect(strays, isEmpty);

    // Two downloads with one name at once (a dubbed and a subtitled release
    // of one series): each gets its own file, and deleting one keeps the
    // other. A file only appears when it finishes, so only the rows can
    // tell the names apart.
    const twin = MediaItem(
      id: 'twin-4328',
      title: LocalizedText(en: 'Friends'),
      kind: VideoKind.series,
    );
    final twinPilot = Episode(id: 'twin-4328', season: 1, episode: 1);
    Download? twinRow;
    Future<void> both() async {
      row = await tester.runAsync<Download?>(() => repo.get(pilot.id));
      twinRow = await tester.runAsync<Download?>(() => repo.get(twinPilot.id));
    }

    refresh = both;
    for (final (item, episode) in [(friends, pilot), (twin, twinPilot)]) {
      await tester.runAsync(
        () => repo.download(
          item,
          episode: episode,
          source: low.source,
          bytes: low.bytes,
        ),
      );
    }
    await until(
      tester,
      'both complete (${row?.status}, ${twinRow?.status})',
      () =>
          row?.status == DownloadStatus.complete &&
          twinRow?.status == DownloadStatus.complete,
      seconds: 300,
    );
    final one = File(p.join(row!.directory, row!.fileName));
    final other = File(p.join(twinRow!.directory, twinRow!.fileName));
    debugPrint('twins: ${one.path} and ${other.path}');
    expect(one.path, isNot(other.path));
    expect(one.lengthSync(), low.bytes);
    expect(other.lengthSync(), low.bytes);
    await tester.runAsync(() => repo.delete(twinPilot.id));
    await until(tester, 'the twin gone', () => twinRow == null);
    expect(other.existsSync(), isFalse);
    expect(one.lengthSync(), low.bytes, reason: 'the other file stays');
    await tester.runAsync(() => repo.delete(pilot.id));
    await until(tester, 'the pilot gone', () => row == null);

    // The connection dies for good part way: the engine retries on its
    // own, each run reporting 0% first. The saved bytes must hold. Then
    // Pause and Retry: a fresh link fetched outside the queue, and the
    // download finishes with the real engine.
    refresh = () async {
      row = await tester.runAsync<Download?>(() => repo.get(pilot.id));
    };
    await tester.runAsync(
      () => repo.download(
        friends,
        episode: pilot,
        source: low.source,
        bytes: low.bytes,
      ),
    );
    fraction = 0;
    await until(tester, 'progress', () => fraction > 0.1, seconds: 60);
    await tester.runAsync(() => repo.pause(pilot.id));
    await until(tester, 'paused', () => row?.status == DownloadStatus.paused);
    final saved = row!.downloadedBytes;
    final refused = Uri.parse(low.source.url)
        .replace(scheme: 'https', host: '127.0.0.1', port: 1)
        .toString();
    final engine = container.read(downloaderProvider);
    await tester.runAsync(() => engine.resume(pilot.id, refused));
    // The engine's first retries come 2 s and 4 s apart.
    final watchUntil = DateTime.now().add(const Duration(seconds: 8));
    var lowest = saved;
    while (DateTime.now().isBefore(watchUntil)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await refresh!();
      if (row!.downloadedBytes < lowest) lowest = row!.downloadedBytes;
    }
    debugPrint('while retrying: ${row?.status}, lowest $lowest of $saved');
    expect(lowest, saved, reason: 'the saved bytes held');

    await tester.runAsync(() => repo.pause(pilot.id));
    await until(tester, 'paused again', () {
      return row?.status == DownloadStatus.paused;
    });
    final outcome = await tester.runAsync(() => repo.resume(pilot.id));
    debugPrint('Retry: $outcome');
    expect(outcome, isA<ResumeStarted>());
    await until(
      tester,
      'complete after Retry (${row?.status})',
      () => row?.status == DownloadStatus.complete,
      seconds: 300,
    );
    expect(File(p.join(row!.directory, row!.fileName)).lengthSync(), low.bytes);
    await tester.runAsync(() => repo.delete(pilot.id));
    await until(tester, 'cleaned up', () => row == null);
  });
}
