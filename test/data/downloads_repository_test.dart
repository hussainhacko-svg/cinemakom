import 'dart:async';
import 'dart:io';

import 'package:cinemakom/core/downloads/connectivity_monitor.dart';
import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:cinemakom/data/repositories/downloads_janitor.dart';
import 'package:cinemakom/data/repositories/downloads_repository.dart';
import 'package:cinemakom/data/repositories/media_repository.dart';
import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/app_harness.dart' show fixtureApi;
import '../helpers/fake_downloader.dart';
import '../repositories/fake_api_client.dart';

const movie = MediaItem(
  id: '3119279',
  title: LocalizedText(en: 'Eve of Destruction', ar: 'حواء المدمرة'),
  posterUrl: 'https://img/p.jpg',
  kind: VideoKind.movies,
  year: 1991,
);

const series = MediaItem(
  id: '4328',
  title: LocalizedText(en: 'Friends'),
  kind: VideoKind.series,
);

Episode ep(String id, int season, int episode) =>
    Episode(id: id, season: season, episode: episode);

const srt = '1\n00:00:01,000 --> 00:00:02,000\nHello\n';

class FakeConnectivity implements ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();

  void setOnline(bool online) => _controller.add(online);

  void close() => _controller.close();

  @override
  Stream<bool> get onChanged => _controller.stream;
}

class Env {
  Env({
    List<(bool Function(ApiRequest), Object? Function(ApiRequest))> routes =
        const [],
    Duration rescheduleGrace = Duration.zero,
    Duration stallGuardDuration = const Duration(seconds: 60),
    Duration progressSaveInterval = const Duration(seconds: 2),
    Duration reconcileCooldown = const Duration(seconds: 5),
    Duration serverRetryBaseDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
    Duration Function()? elapsed,
    Duration userPauseGrace = const Duration(seconds: 3),
  }) : dir = Directory.systemTemp.createTempSync('dl-test') {
    api = fixtureApi([
      ...routes,
      FakeApiClient.path('https://cnth2', srt),
      FakeApiClient.path('size:', (ApiRequest r) => 3000000000),
    ]);
    downloader = FakeDownloader(root: dir.path);
    connectivity = FakeConnectivity();
    repo = DownloadsRepository(
      store: store,
      downloader: downloader,
      media: MediaRepository(api),
      api: api,
      root: () async => (baseDirectory: 'root', directory: dir.path),
      connectivity: connectivity,
      styledSubtitles: false,
      clock: clock ?? () => DateTime(2026, 11, 19, 12, tick++),
      elapsed: elapsed,
      userPauseGrace: userPauseGrace,
      reconnectRetryBaseDelay: const Duration(milliseconds: 10),
      rescheduleGrace: rescheduleGrace,
      stallGuardDuration: stallGuardDuration,
      progressSaveInterval: progressSaveInterval,
      reconcileCooldown: reconcileCooldown,
      serverRetryBaseDelay: serverRetryBaseDelay,
    );
  }

  final Directory dir;
  late final FakeApiClient api;
  late final FakeDownloader downloader;
  late final FakeConnectivity connectivity;
  final store = MemoryDownloadStore();
  late final DownloadsRepository repo;
  int tick = 0;

  Future<void> start() => repo.start(
    const DownloadNotices(
      running: 'Downloading',
      complete: 'Downloaded',
      failed: 'Stopped',
      paused: 'Paused',
    ),
  );

  /// Lets queued event handling run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  Future<VideoSource> source(String label) async =>
      (await repo.choices(movie.id))
          .firstWhere((c) => c.source.label == label)
          .source;
}

void main() {
  late Env env;
  setUp(() => env = Env());
  tearDown(() {
    env.repo.dispose();
    env.connectivity.close();
    env.dir.deleteSync(recursive: true);
  });

  test('choices: every quality, highest first, with sizes', () async {
    final choices = await env.repo.choices(movie.id);
    expect(choices.map((c) => c.source.label), [
      '1080p',
      '720p',
      '480p',
      '360p',
      '240p',
    ]);
    expect(choices.first.bytes, 3000000000);
    // Always fresh URLs: past the API cache.
    expect(
      env.api.requests
          .where((r) => r.path.startsWith('transcoddedFiles'))
          .single
          .query,
      contains('_'),
    );
  });

  test('a movie: subtitles saved, the video queued with the headers', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('720p'), bytes: 5);
    final job = env.downloader.enqueued.single;
    expect(job.taskId, movie.id);
    expect(job.headers['Referer'], 'https://cinemana.shabakaty.com/');
    expect(
      job.spot.directory,
      p.join(env.dir.path, 'Eve of Destruction (1991)'),
    );
    expect(job.spot.fileName, 'Eve of Destruction 720p.mp4');

    final d = (await env.store.get(movie.id))!;
    expect(d.status, DownloadStatus.queued);
    expect((d.quality, d.totalBytes), ('720p', 5));
    expect(d.subtitles.map((s) => s.fileName), [
      'Eve of Destruction 720p.ar.srt',
      'Eve of Destruction 720p.en.srt',
    ]);
    expect(
      File(p.join(job.spot.directory, d.subtitles.first.fileName))
          .readAsStringSync(),
      srt,
    );
    // Asking again does nothing.
    await env.repo.download(movie, source: await env.source('720p'));
    expect(env.downloader.enqueued, hasLength(1));
  });

  test('an episode is named by season and episode', () async {
    await env.start();
    await env.repo.download(
      series,
      episode: ep('e1', 2, 5),
      source: const VideoSource(url: 'https://x', resolution: '1080p'),
    );
    final job = env.downloader.enqueued.single;
    expect(job.spot.fileName, 'Friends S02E05 1080p.mp4');
    expect(job.displayName, 'Friends · S02E05');
    final d = (await env.store.get('e1'))!;
    expect((d.titleId, d.season, d.episode), ('4328', 2, 5));
  });

  // A file only appears on disk when its download finishes, so the disk
  // alone can't tell that a queued download already took a name. Two
  // series with the same English title (a dubbed and a subtitled release),
  // or a season listing one episode twice, must not share a file: one
  // would overwrite the other, and deleting either would delete both.
  test('downloads on their way never share a file', () async {
    await env.start();
    const dubbed = MediaItem(
      id: '9001',
      title: LocalizedText(en: 'Friends'),
      kind: VideoKind.series,
    );
    const src = VideoSource(url: 'https://x', resolution: '1080p');
    await env.repo.download(series, episode: ep('e1', 1, 1), source: src);
    await env.repo.download(dubbed, episode: ep('d1', 1, 1), source: src);
    await env.repo.download(series, episode: ep('e1b', 1, 1), source: src);
    final paths = {
      for (final id in ['e1', 'd1', 'e1b'])
        await env.repo.filePath((await env.store.get(id))!),
    };
    expect(paths, hasLength(3));
    expect(env.downloader.enqueued.map((j) => j.spot.fileName), [
      'Friends S01E01 1080p.mp4',
      'Friends S01E01 1080p (2).mp4',
      'Friends S01E01 1080p (3).mp4',
    ]);
  });

  test(
    'progress, then complete: playable from disk with its subtitles',
    () async {
      await env.start();
      await env.repo.download(movie, source: await env.source('240p'));
      final job = env.downloader.enqueued.single;
      final progress = <Map<String, DownloadProgress>>[];
      final sub = env.repo.watchProgress().listen(progress.add);

      env.downloader.send(
        DownloaderProgress(
          movie.id,
          fraction: 0.5,
          expectedBytes: 2000,
          bytesPerSecond: 100,
        ),
      );
      await env.settle();
      expect((await env.store.get(movie.id))!.status, DownloadStatus.running);
      expect(progress.last[movie.id]!.fraction, 0.5);

      await env.downloader.finish(job, bytes: 1234);
      await env.settle();
      final d = (await env.store.get(movie.id))!;
      expect(d.status, DownloadStatus.complete);
      expect(d.totalBytes, 1234);
      expect(progress.last, isEmpty);

      final local = (await env.repo.playable(movie.id))!;
      expect(local.path, p.join(job.spot.directory, job.spot.fileName));
      expect(local.quality, '240p');
      expect(local.subtitles.map((s) => s.languageCode), ['ar', 'en']);
      expect(local.subtitles.first.url, startsWith('file://'));
      expect(await env.repo.usedBytes(), 1234);
      await sub.cancel();
    },
  );

  test('a refused URL is retried once with a fresh one, then fails', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('720p'));
    env.downloader.send(
      const DownloaderStatus('3119279', DownloaderState.failed, httpCode: 403),
    );
    await env.settle();
    expect(env.downloader.resumed.single.$1, movie.id);
    expect(env.downloader.resumed.single.$2, startsWith('https://'));

    env.downloader.send(
      const DownloaderStatus('3119279', DownloaderState.failed, httpCode: 403),
    );
    await env.settle();
    final d = (await env.store.get(movie.id))!;
    expect(d.status, DownloadStatus.failed);
    expect(d.problem, DownloadProblem.linkExpired);
    expect(env.downloader.resumed, hasLength(1));
  });

  test('a dropped connection fails; Try again resumes, or restarts', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('720p'));
    env.downloader.send(
      const DownloaderProgress('3119279', fraction: 0.4, expectedBytes: 1000),
    );
    await env.settle();
    env.downloader.send(
      const DownloaderStatus('3119279', DownloaderState.failed),
    );
    await env.settle();
    final failed = (await env.store.get(movie.id))!;
    expect(failed.problem, DownloadProblem.network);
    expect(failed.downloadedBytes, 400);

    await env.repo.resume(movie.id);
    expect(env.downloader.resumed, hasLength(1));
    final resumed = (await env.store.get(movie.id))!;
    expect(resumed.status, DownloadStatus.queued);
    expect(resumed.downloadedBytes, 400);
    expect(resumed.startedOver, isFalse);

    // No partial file left: cancels old task (rule 1), starts over with startedOver.
    // (It fails first: Resume does nothing to a download already going.)
    env.downloader.send(
      const DownloaderStatus('3119279', DownloaderState.failed),
    );
    await env.settle();
    env.downloader.resumeAllowed = false;
    await env.repo.resume(movie.id);
    expect(env.downloader.canceled, contains(movie.id));
    expect(env.downloader.enqueued, hasLength(2));
    expect(
      env.downloader.enqueued.last.spot.fileName,
      'Eve of Destruction 720p.mp4',
    );
    final restarted = (await env.store.get(movie.id))!;
    expect(restarted.downloadedBytes, 0);
    expect(restarted.startedOver, isTrue);
  });

  test('no space and file errors say so', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('720p'));
    env.downloader.send(
      const DownloaderStatus('3119279', DownloaderState.failed, noSpace: true),
    );
    await env.settle();
    expect((await env.store.get(movie.id))!.problem, DownloadProblem.noSpace);
  });

  test(
    'pause, then delete removes the files, the row and the folder',
    () async {
      await env.start();
      await env.repo.download(movie, source: await env.source('240p'));
      await env.repo.pause(movie.id);
      expect((await env.store.get(movie.id))!.status, DownloadStatus.paused);

      final job = env.downloader.enqueued.single;
      await env.downloader.finish(job);
      await env.settle();
      await env.repo.delete(movie.id);
      expect(await env.store.get(movie.id), isNull);
      expect(Directory(job.spot.directory).existsSync(), isFalse);
      expect(
        env.downloader.canceled,
        isEmpty,
        reason: 'a finished one has no task',
      );
    },
  );

  test('a missing file is not playable', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('240p'));
    final job = env.downloader.enqueued.single;
    await env.downloader.finish(job);
    await env.settle();
    File(p.join(job.spot.directory, job.spot.fileName)).deleteSync();
    expect(await env.repo.playable(movie.id), isNull);
  });

  test('a season: queues what is missing, in the closest quality', () async {
    await env.start();
    await env.repo.download(
      series,
      episode: ep('e1', 1, 1),
      source: const VideoSource(url: 'https://x', resolution: '720p'),
    );
    final queued = await env.repo.downloadEpisodes(series, [
      ep('e1', 1, 1),
      ep('e2', 1, 2),
      ep('e3', 1, 3),
    ], 1080);
    expect(queued, 2);
    expect(env.downloader.enqueued.map((j) => j.taskId), ['e1', 'e2', 'e3']);
    expect((await env.store.get('e2'))!.quality, '1080p');
    final eps = await env.repo.downloadedEpisodes('4328');
    expect(eps, isEmpty, reason: 'none finished yet');
  });

  test('after a restart: a lost task continues by itself, a finished one '
      'completes', () async {
    final base = Download(
      videoId: 'a',
      titleId: 'a',
      title: const LocalizedText(en: 'A'),
      quality: '720p',
      baseDirectory: 'root',
      directory: env.dir.path,
      fileName: 'a.mp4',
      status: DownloadStatus.running,
      addedAt: DateTime(2026),
    );
    await env.store.put(base);
    await env.store.put(
      Download(
        videoId: 'b',
        titleId: 'b',
        title: const LocalizedText(en: 'B'),
        quality: '720p',
        baseDirectory: 'root',
        directory: env.dir.path,
        fileName: 'b.mp4',
        status: DownloadStatus.running,
        addedAt: DateTime(2026),
      ),
    );
    File(p.join(env.dir.path, 'b.mp4')).writeAsBytesSync([1, 2, 3]);
    env.downloader.knownStates['b'] = DownloaderState.complete;
    await env.start();
    await env.settle();
    // Interrupted (unknown to the engine), then continued from its partial
    // file (docs/DOWNLOADS.md §5.5), once its fresh link is in.
    expect((await env.store.get('a'))!.status, DownloadStatus.queued);
    expect(env.downloader.resumed.map((r) => r.$1), ['a']);
    final b = (await env.store.get('b'))!;
    expect((b.status, b.totalBytes), (DownloadStatus.complete, 3));
  });

  // Finished while the app wasn't listening, with no size on record: the
  // check after a restart can't tell it from a copy cut short, so it's
  // "interrupted". The cleanup must keep it, and the automatic continue,
  // with a fresh link in hand, asks the real size and finishes it.
  group('a file of unknown size at its place after a restart', () {
    Future<Download> lostRow(int onDisk, {required int realSize}) async {
      env.repo.dispose();
      env.connectivity.close();
      env.dir.deleteSync(recursive: true);
      env = Env(routes: [FakeApiClient.path('size:', realSize)]);
      final row = Download(
        videoId: movie.id,
        titleId: movie.id,
        title: movie.title,
        quality: '720p',
        baseDirectory: 'root',
        directory: env.dir.path,
        fileName: 'm.mp4',
        status: DownloadStatus.running,
        addedAt: DateTime(2026),
      );
      await env.store.put(row);
      File(p.join(env.dir.path, 'm.mp4'))
          .writeAsBytesSync(List.filled(onDisk, 1));
      return row;
    }

    test('the whole file: kept, and finished without downloading', () async {
      await lostRow(1000, realSize: 1000);
      await env.start();
      await env.settle();
      final d = (await env.store.get(movie.id))!;
      expect((d.status, d.totalBytes), (DownloadStatus.complete, 1000));
      expect(File(p.join(env.dir.path, 'm.mp4')).lengthSync(), 1000);
      expect(env.downloader.resumed, isEmpty);
      expect(env.downloader.enqueued, isEmpty);
      expect(await env.repo.playable(movie.id), isNotNull);
    });

    test('a copy cut short: continues, now knowing its size', () async {
      await lostRow(400, realSize: 1000);
      await env.start();
      await env.settle();
      final d = (await env.store.get(movie.id))!;
      expect((d.status, d.totalBytes), (DownloadStatus.queued, 1000));
      expect(env.downloader.resumed.map((r) => r.$1), [movie.id]);
    });

    test('the size still unknown: kept, and continued', () async {
      await lostRow(400, realSize: 0);
      await env.start();
      await env.settle();
      expect(File(p.join(env.dir.path, 'm.mp4')).existsSync(), isTrue);
      expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
    });
  });

  // Each run of the engine that isn't a resume (its own retries after a
  // dropped connection) reports 0% before a byte arrives. That is no
  // measure of what's saved: the partial file is still there. Taken as one,
  // the row showed 0% and an automatic restart thought nothing was lost.
  test(
    'the engine\'s 0% at the start of a retry keeps the saved bytes',
    () async {
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      final seen = <double>[];
      final sub = env.repo.watchProgress().listen((m) {
        if (m[movie.id] case final p?) seen.add(p.fraction);
      });
      addTearDown(sub.cancel);
      env.downloader.send(
        const DownloaderProgress('3119279', fraction: 0.4, expectedBytes: 1000),
      );
      await env.settle();
      expect((await env.store.get(movie.id))!.downloadedBytes, 400);

      // The connection drops; the engine tries again.
      for (final e in [
        const DownloaderStatus('3119279', DownloaderState.queued),
        const DownloaderStatus('3119279', DownloaderState.running),
        const DownloaderProgress('3119279', fraction: 0, expectedBytes: 1000),
        const DownloaderStatus('3119279', DownloaderState.queued),
      ]) {
        env.downloader.send(e);
        await env.settle();
        expect(
          (await env.store.get(movie.id))!.downloadedBytes,
          400,
          reason: '$e',
        );
      }
      expect(seen, isNot(contains(0.0)));
      expect(await env.repo.usedBytes(), 400);

      // Real progress counts again, lower too (the engine started over).
      env.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.45,
          expectedBytes: 1000,
        ),
      );
      await env.settle();
      expect((await env.store.get(movie.id))!.downloadedBytes, 450);
    },
  );

  test('events are handled in order', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('240p'));
    final job = env.downloader.enqueued.single;
    // A late progress event must not undo "complete".
    await env.downloader.finish(job);
    env.downloader.send(const DownloaderProgress('3119279', fraction: 0.9));
    await env.settle();
    expect((await env.store.get(movie.id))!.status, DownloadStatus.complete);
  });

  group('D2 state machine & saved progress', () {
    test('time-limit paused without user pause keeps running and keeps saved bytes', () async {
      await env.start();
      await env.repo.download(
        movie,
        source: await env.source('720p'),
        bytes: 10000,
      );
      env.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.36,
          expectedBytes: 10000,
        ),
      );
      await env.settle();
      expect((await env.store.get(movie.id))!.downloadedBytes, 3600);

      // Engine emits time-limit paused on its own (user did NOT press Pause).
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.paused),
      );
      await env.settle();
      final afterTimeout = (await env.store.get(movie.id))!;
      expect(afterTimeout.status, DownloadStatus.running);
      expect(afterTimeout.pausedByUser, isFalse);
      expect(afterTimeout.downloadedBytes, 3600);

      // Next run arrives with progress -> stays running, advances bytes.
      env.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.45,
          expectedBytes: 10000,
        ),
      );
      await env.settle();
      final next = (await env.store.get(movie.id))!;
      expect(next.status, DownloadStatus.running);
      expect(next.downloadedBytes, 4500);
    });

    test(
      'progress after user pause is ignored; after Resume it runs again',
      () async {
        await env.start();
        await env.repo.download(
          movie,
          source: await env.source('720p'),
          bytes: 10000,
        );
        env.downloader.send(
          const DownloaderProgress(
            '3119279',
            fraction: 0.25,
            expectedBytes: 10000,
          ),
        );
        await env.settle();

        await env.repo.pause(movie.id);
        final paused = (await env.store.get(movie.id))!;
        expect(paused.status, DownloadStatus.paused);
        expect(paused.pausedByUser, isTrue);
        expect(paused.downloadedBytes, 2500);

        // Trailing progress from the stopping engine must be ignored.
        env.downloader.send(
          const DownloaderProgress(
            '3119279',
            fraction: 0.30,
            expectedBytes: 10000,
          ),
        );
        env.downloader.send(
          const DownloaderStatus('3119279', DownloaderState.running),
        );
        await env.settle();
        expect((await env.store.get(movie.id))!.status, DownloadStatus.paused);
        expect((await env.store.get(movie.id))!.pausedByUser, isTrue);

        // Resume clears pausedByUser; next progress moves to running.
        await env.repo.resume(movie.id);
        env.downloader.send(
          const DownloaderProgress(
            '3119279',
            fraction: 0.31,
            expectedBytes: 10000,
          ),
        );
        await env.settle();
        final resumed = (await env.store.get(movie.id))!;
        expect(resumed.status, DownloadStatus.running);
        expect(resumed.pausedByUser, isFalse);
        expect(resumed.downloadedBytes, 3100);
      },
    );

    test(
      'late paused arriving after running of the next run stays running',
      () async {
        await env.start();
        await env.repo.download(
          movie,
          source: await env.source('720p'),
          bytes: 10000,
        );
        env.downloader.send(
          const DownloaderStatus('3119279', DownloaderState.running),
        );
        env.downloader.send(
          const DownloaderProgress(
            '3119279',
            fraction: 0.5,
            expectedBytes: 10000,
          ),
        );
        // Late timeout-paused from previous run arrives after running/progress.
        env.downloader.send(
          const DownloaderStatus('3119279', DownloaderState.paused),
        );
        await env.settle();
        final d = (await env.store.get(movie.id))!;
        expect(d.status, DownloadStatus.running);
        expect(d.downloadedBytes, 5000);
      },
    );

    for (final (engine, status, problem) in [
      // The notification's Pause: the engine keeps the task paused.
      (DownloaderState.paused, DownloadStatus.paused, null),
      // The engine lost the task.
      (null, DownloadStatus.failed, DownloadProblem.interrupted),
    ]) {
      test('a pause the app did not ask for, engine then '
          '${engine?.name ?? "unknown"}: ${status.name} after the guard', () {
        fakeAsync((async) {
          final e = Env(
            routes: [
              FakeApiClient.path(
                'translationFiles/',
                const <String, Object?>{},
              ),
            ],
            clock: () => async.getClock(DateTime(2026, 11, 21, 12)).now(),
            elapsed: () => async.elapsed,
            stallGuardDuration: const Duration(seconds: 8),
          );
          addTearDown(() {
            e.repo.dispose();
            e.dir.deleteSync(recursive: true);
          });
          e.start();
          async.flushMicrotasks();
          e.repo.download(
            movie,
            source: const VideoSource(
              url: 'https://x/v.mp4',
              resolution: '720p',
            ),
            bytes: 10000,
          );
          async.flushMicrotasks();
          e.downloader.send(
            const DownloaderProgress(
              '3119279',
              fraction: 0.4,
              expectedBytes: 10000,
            ),
          );
          async.flushMicrotasks();

          e.downloader.knownStates[movie.id] = DownloaderState.paused;
          e.downloader.send(
            const DownloaderStatus('3119279', DownloaderState.paused),
          );
          async.flushMicrotasks();
          if (engine == null) e.downloader.knownStates.remove(movie.id);

          // Rule 4: still "downloading" while the next run may follow.
          async.elapse(const Duration(seconds: 7));
          Download? row;
          e.store.get(movie.id).then((v) => row = v);
          async.flushMicrotasks();
          expect(row!.status, DownloadStatus.running);

          async.elapse(const Duration(seconds: 2));
          e.store.get(movie.id).then((v) => row = v);
          async.flushMicrotasks();
          expect(row!.status, status);
          expect(row!.problem, problem);
          expect(row!.pausedByUser, engine != null);
          expect(row!.downloadedBytes, 4000);
        });
      });
    }

    test(
      'at 99% with no complete event, the guard fetches it from the engine',
      () async {
        final e = Env(
          routes: [
            FakeApiClient.path('translationFiles/', const <String, Object?>{}),
          ],
          stallGuardDuration: const Duration(milliseconds: 30),
        );
        addTearDown(() {
          e.repo.dispose();
          e.dir.deleteSync(recursive: true);
        });
        await e.start();
        await e.repo.download(
          movie,
          source: const VideoSource(url: 'https://x/v.mp4', resolution: '720p'),
          bytes: 10000,
        );
        e.downloader.knownStates[movie.id] = DownloaderState.running;
        e.downloader.send(
          const DownloaderProgress(
            '3119279',
            fraction: 0.995,
            expectedBytes: 10000,
          ),
        );
        final syncs = e.downloader.syncCalls;

        // Still moving the file: the guard asks the engine, and keeps asking.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(e.downloader.syncCalls, greaterThan(syncs + 1));
        expect((await e.store.get(movie.id))!.status, DownloadStatus.running);

        // Done, but its event never came: the next check finishes it.
        e.downloader.knownStates[movie.id] = DownloaderState.complete;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect((await e.store.get(movie.id))!.status, DownloadStatus.complete);
      },
    );

    test(
      'pause while in holding queue cancels engine task and Resume enqueues it',
      () async {
        await env.start();
        await env.repo.download(
          movie,
          source: await env.source('720p'),
          bytes: 5000,
        );
        // Holding-queue tasks return false from pause().
        env.downloader.pauseReturns = false;
        await env.repo.pause(movie.id);

        final paused = (await env.store.get(movie.id))!;
        expect(paused.status, DownloadStatus.paused);
        expect(paused.pausedByUser, isTrue);
        expect(env.downloader.canceled, contains(movie.id));

        // Resume has no partial file -> enqueues fresh without startedOver.
        env.downloader.resumeAllowed = false;
        await env.repo.resume(movie.id);
        expect(env.downloader.enqueued, hasLength(2));
        final resumed = (await env.store.get(movie.id))!;
        expect(resumed.status, DownloadStatus.queued);
        expect(resumed.pausedByUser, isFalse);
        expect(resumed.startedOver, isFalse);
      },
    );

    test('failure reasons and auto-actions match §5.5 table', () async {
      await env.start();

      // 404 -> unavailable immediately (no auto-retry).
      await env.repo.download(movie, source: await env.source('720p'));
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          httpCode: 404,
          detail: 'HTTP 404 Not Found',
        ),
      );
      await env.settle();
      var d = (await env.store.get(movie.id))!;
      expect(d.problem, DownloadProblem.unavailable);
      expect(d.problemDetail, 'HTTP 404 Not Found');
      expect(env.downloader.resumed, isEmpty);

      // fileError -> storage.
      await env.repo.resume(movie.id);
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          fileError: true,
          detail: 'Permission denied',
        ),
      );
      await env.settle();
      d = (await env.store.get(movie.id))!;
      expect(d.problem, DownloadProblem.storage);
      expect(d.problemDetail, 'Permission denied');

      // timedOut -> retries once automatically, second time fails interrupted.
      await env.repo.resume(movie.id);
      final resumedBefore = env.downloader.resumed.length;
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          timedOut: true,
          detail: 'Task timed out',
        ),
      );
      await env.settle();
      expect(env.downloader.resumed.length, resumedBefore + 1);
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          timedOut: true,
          detail: 'Task timed out',
        ),
      );
      await env.settle();
      d = (await env.store.get(movie.id))!;
      expect(d.problem, DownloadProblem.interrupted);

      // HTTP 416 / resumeError -> cancels and restarts from 0 with startedOver;
      // next progress clears startedOver.
      await env.repo.resume(movie.id);
      env.downloader.send(
        const DownloaderProgress('3119279', fraction: 0.5, expectedBytes: 2000),
      );
      await env.settle();
      final enqBefore = env.downloader.enqueued.length;
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          httpCode: 416,
          resumeError: true,
        ),
      );
      await env.settle();
      expect(env.downloader.enqueued.length, enqBefore + 1);
      d = (await env.store.get(movie.id))!;
      expect(d.status, DownloadStatus.queued);
      expect(d.downloadedBytes, 0);
      expect(d.startedOver, isTrue);

      env.downloader.send(
        const DownloaderProgress('3119279', fraction: 0.1, expectedBytes: 2000),
      );
      await env.settle();
      d = (await env.store.get(movie.id))!;
      expect(d.startedOver, isFalse);
      expect(d.downloadedBytes, 200);
    });

    test('HTTP 5xx retries 3 times with backoff, then fails server', () {
      fakeAsync((async) {
        final e = Env(
          routes: [
            FakeApiClient.path('translationFiles/', const <String, Object?>{}),
          ],
          clock: () => async.getClock(DateTime(2026, 11, 21, 12)).now(),
          serverRetryBaseDelay: const Duration(seconds: 2),
        );
        addTearDown(() {
          e.repo.dispose();
          e.dir.deleteSync(recursive: true);
        });
        e.start();
        e.repo.download(
          movie,
          source: const VideoSource(url: 'https://x/v.mp4', resolution: '720p'),
        );
        async.flushMicrotasks();

        // Attempts 1 (2s), 2 (4s), 3 (8s).
        for (final wait in [2, 4, 8]) {
          e.downloader.send(
            const DownloaderStatus(
              '3119279',
              DownloaderState.failed,
              httpCode: 503,
            ),
          );
          async.flushMicrotasks();
          async.elapse(Duration(seconds: wait));
        }
        expect(e.downloader.resumed, hasLength(3));

        // 4th 5xx fails with server.
        e.downloader.send(
          const DownloaderStatus(
            '3119279',
            DownloaderState.failed,
            httpCode: 503,
            detail: 'Service Unavailable',
          ),
        );
        async.flushMicrotasks();
        Download? row;
        e.store.get(movie.id).then((v) => row = v);
        async.flushMicrotasks();
        expect(row!.status, DownloadStatus.failed);
        expect(row!.problem, DownloadProblem.server);
        expect(row!.problemDetail, 'Service Unavailable');
      });
    });

    test(
      'reconcile waits for reschedule grace before failing unknown tasks',
      () {
        fakeAsync((async) {
          final e = Env(
            clock: () => async.getClock(DateTime(2026, 11, 21, 12)).now(),
            rescheduleGrace: const Duration(seconds: 6),
          );
          addTearDown(() {
            e.repo.dispose();
            e.dir.deleteSync(recursive: true);
          });
          e.store.put(
            Download(
              videoId: 'lost',
              titleId: 'lost',
              title: const LocalizedText(en: 'Lost'),
              quality: '720p',
              baseDirectory: 'root',
              directory: e.dir.path,
              fileName: 'lost.mp4',
              status: DownloadStatus.running,
              totalBytes: 10000,
              downloadedBytes: 3000,
              addedAt: DateTime(2026, 11, 21, 11),
            ),
          );
          e.downloader.resumeAllowed = false;
          e.start();
          async.flushMicrotasks();

          // Still inside grace window at t=5s -> stays running.
          async.elapse(const Duration(seconds: 5));
          Download? row;
          e.store.get('lost').then((v) => row = v);
          async.flushMicrotasks();
          expect(row!.status, DownloadStatus.running);

          // After grace window (t=6s) -> interrupted + startedOver, bytes kept.
          async.elapse(const Duration(seconds: 2));
          e.store.get('lost').then((v) => row = v);
          async.flushMicrotasks();
          expect(row!.status, DownloadStatus.failed);
          expect(row!.problem, DownloadProblem.interrupted);
          expect(row!.startedOver, isTrue);
          expect(row!.downloadedBytes, 3000);
        });
      },
    );

    test('saved bytes survive pause, failure, restart on new repository, and reconcile', () async {
      await env.start();
      await env.repo.download(
        movie,
        source: await env.source('720p'),
        bytes: 27000000000,
      );
      env.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.2,
          expectedBytes: 27000000000,
        ),
      );
      await env.settle();
      await env.repo.pause(movie.id);

      // Simulate app restart with a fresh repository on the same store.
      final repo2 = DownloadsRepository(
        store: env.store,
        downloader: env.downloader,
        media: MediaRepository(env.api),
        api: env.api,
        root: () async => (baseDirectory: 'root', directory: env.dir.path),
        styledSubtitles: false,
        rescheduleGrace: Duration.zero,
      );
      addTearDown(repo2.dispose);
      await repo2.start(
        const DownloadNotices(
          running: 'Downloading',
          complete: 'Downloaded',
          failed: 'Stopped',
          paused: 'Paused',
        ),
      );

      final row = (await env.store.get(movie.id))!;
      expect(row.status, DownloadStatus.paused);
      expect(row.pausedByUser, isTrue);
      expect(row.downloadedBytes, 5400000000);
      expect(row.savedFraction, closeTo(0.2, 0.001));
    });
  });

  group('D3 retry, connectivity & D4 janitor', () {
    test('no network pauses active tasks as waiting; network back auto-resumes only those', () async {
      await env.start();
      await env.repo.download(
        series,
        episode: ep('e1', 1, 1),
        source: const VideoSource(url: 'https://x/1', resolution: '720p'),
        bytes: 10000,
      );
      await env.repo.download(
        series,
        episode: ep('e2', 1, 2),
        source: const VideoSource(url: 'https://x/2', resolution: '720p'),
        bytes: 10000,
      );
      env.downloader.send(
        const DownloaderProgress('e1', fraction: 0.4, expectedBytes: 10000),
      );
      env.downloader.send(
        const DownloaderProgress('e2', fraction: 0.2, expectedBytes: 10000),
      );
      await env.settle();

      // User explicitly pauses e2; e1 stays running.
      await env.repo.pause('e2');
      expect((await env.store.get('e2'))!.pausedByUser, isTrue);

      // Connectivity drops -> e1 pauses with pausedByUser=false; e2 stays user-paused.
      env.connectivity.setOnline(false);
      await env.settle();

      final e1Offline = (await env.store.get('e1'))!;
      final e2Offline = (await env.store.get('e2'))!;
      expect(e1Offline.status, DownloadStatus.paused);
      expect(e1Offline.pausedByUser, isFalse);
      expect(e1Offline.isWaitingForConnection, isTrue);
      expect(e1Offline.downloadedBytes, 4000);
      expect(e2Offline.status, DownloadStatus.paused);
      expect(e2Offline.pausedByUser, isTrue);

      // Connectivity returns -> e1 auto-resumes with fresh URL; e2 stays paused!
      env.connectivity.setOnline(true);
      await env.settle();

      expect(env.downloader.resumed.map((r) => r.$1), ['e1']);
      expect((await env.store.get('e1'))!.status, DownloadStatus.queued);
      expect((await env.store.get('e2'))!.status, DownloadStatus.paused);
      expect((await env.store.get('e2'))!.pausedByUser, isTrue);
    });

    test('quality gone on Retry asks instead of switching silently; switchTo starts over', () async {
      await env.start();
      await env.store.put(
        Download(
          videoId: movie.id,
          titleId: movie.id,
          title: movie.title,
          quality: '2160p', // Fixture streams_movie only has 1080p..240p.
          baseDirectory: 'root',
          directory: env.dir.path,
          fileName: 'm.mp4',
          status: DownloadStatus.failed,
          problem: DownloadProblem.network,
          totalBytes: 10000,
          downloadedBytes: 3000,
          addedAt: DateTime(2026, 11, 21),
        ),
      );

      final outcome = await env.repo.resume(movie.id);
      expect(outcome, isA<ResumeQualityGone>());
      final gone = outcome as ResumeQualityGone;
      expect(gone.previousQuality, '2160p');
      expect(gone.fallback.label, '1080p');
      // Row was NOT mutated and nothing was cancelled or enqueued yet!
      expect(env.downloader.canceled, isEmpty);
      expect(env.downloader.enqueued, isEmpty);
      expect((await env.store.get(movie.id))!.quality, '2160p');

      // User confirms switching to fallback quality.
      final confirmed = await env.repo.resume(
        movie.id,
        switchTo: gone.fallback,
      );
      expect(confirmed, isA<ResumeStarted>());
      expect((confirmed as ResumeStarted).startedOver, isTrue);
      expect(env.downloader.canceled, contains(movie.id));
      expect(env.downloader.enqueued, hasLength(1));
      final row = (await env.store.get(movie.id))!;
      expect(row.quality, '1080p');
      expect(row.downloadedBytes, 0);
      expect(row.startedOver, isTrue);
    });

    test(
      'Rule 1: re-downloading a failed title cancels old task first',
      () async {
        await env.start();
        await env.repo.download(movie, source: await env.source('720p'));
        env.downloader.send(
          const DownloaderStatus(
            '3119279',
            DownloaderState.failed,
            httpCode: 404,
          ),
        );
        await env.settle();
        expect((await env.store.get(movie.id))!.status, DownloadStatus.failed);

        await env.repo.download(movie, source: await env.source('1080p'));
        expect(env.downloader.canceled, contains(movie.id));
        expect(env.downloader.enqueued, hasLength(2));
        expect((await env.store.get(movie.id))!.quality, '1080p');
      },
    );

    test('janitor sweeps stray temp files on delete and final failure', () async {
      final tempDir = Directory(p.join(env.dir.path, 'tmp'))..createSync();
      env.downloader.tempDirectories.add(tempDir.path);
      final stray = File(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}old'),
      )..writeAsBytesSync(List.filled(512, 1));

      await env.start();
      // No active downloads -> startup reconcile sweeps the stray immediately.
      expect(stray.existsSync(), isFalse);

      // Failed non-resumable download also triggers sweep.
      await env.repo.download(movie, source: await env.source('720p'));
      env.downloader.resumeAllowed = false;
      final failedTemp = File(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}fail'),
      )..writeAsBytesSync(List.filled(256, 2));
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          noSpace: true,
        ),
      );
      await env.settle();
      expect(failedTemp.existsSync(), isFalse);
    });
  });

  group('D5 outside changes & D6 notifications', () {
    test(
      'reconcile detects missing finished file; redownload queues again',
      () async {
        await env.start();
        await env.repo.download(movie, source: await env.source('240p'));
        final job = env.downloader.enqueued.single;
        await env.downloader.finish(job, bytes: 100);
        await env.settle();

        final missingHistory = <Set<String>>[];
        final sub = env.repo.watchMissing().listen(missingHistory.add);
        addTearDown(sub.cancel);
        await env.settle();
        expect(missingHistory.last, isEmpty);

        // User deletes the finished video outside the app.
        File(p.join(job.spot.directory, job.spot.fileName)).deleteSync();
        await env.repo.reconcile(force: true);
        await env.settle();
        expect(missingHistory.last, contains(movie.id));
        expect(await env.repo.playable(movie.id), isNull);

        // Download again clears missing and enqueues fresh in same quality.
        final outcome = await env.repo.redownload(movie.id);
        expect(outcome, isA<ResumeStarted>());
        await env.settle();
        expect(missingHistory.last, isEmpty);
        expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
      },
    );

    test('enqueued job carries per-task notification texts', () async {
      await env.repo.start(
        DownloadNotices(
          running: 'Downloading',
          complete: 'Downloaded',
          failed: 'Download stopped',
          paused: 'Paused',
          formatSize: (b) => '${b ~/ (1024 * 1024 * 1024)} GB',
          downloadedSize: (s) => 'Downloaded · $s',
        ),
      );
      await env.repo.download(
        movie,
        source: await env.source('1080p'),
        bytes: 3 * 1024 * 1024 * 1024,
      );
      final notice = env.downloader.enqueued.single.notice!;
      expect(notice.runningTitle, 'Eve of Destruction');
      expect(notice.runningBody, contains('1080p'));
      expect(notice.runningBody, contains('3 GB'));
      expect(notice.runningBody, contains('{progress}'));
      expect(notice.runningBody, contains('{networkSpeed}'));
      expect(notice.pausedBody, 'Paused · {progress}');
      expect(notice.completeBody, contains('3 GB'));
    });

    test('completing episode 1 while episode 2 already wrote to disk and episode 3 is queued never deadlocks or deletes ep2', () async {
      await env.start();
      await env.repo.download(
        series,
        episode: ep('e1', 1, 1),
        source: const VideoSource(url: 'https://x/1', resolution: '720p'),
        bytes: 1000,
      );
      await env.repo.download(
        series,
        episode: ep('e2', 1, 2),
        source: const VideoSource(url: 'https://x/2', resolution: '720p'),
        bytes: 1000,
      );
      await env.repo.download(
        series,
        episode: ep('e3', 1, 3),
        source: const VideoSource(url: 'https://x/3', resolution: '720p'),
        bytes: 1000,
      );

      final job1 = env.downloader.enqueued[0];
      final job2 = env.downloader.enqueued[1];
      // Native engine already wrote ep2.mp4 to disk right before ep1's complete
      // event triggers janitor sweep (race condition regression test).
      final ep2Path = await env.downloader.pathOf(job2.spot);
      File(ep2Path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(1000, 0));

      await env.downloader.finish(job1, bytes: 1000);
      await env.settle();
      // Janitor must NOT have deleted ep2's finished file!
      expect(File(ep2Path).existsSync(), isTrue);

      await env.downloader.finish(job2, bytes: 1000);
      await env.settle();
      await env.repo.reconcile(force: true);

      expect((await env.store.get('e1'))!.status, DownloadStatus.complete);
      expect((await env.store.get('e2'))!.status, DownloadStatus.complete);
      expect((await env.store.get('e3'))!.status, DownloadStatus.queued);
      expect(await env.repo.playable('e2'), isNotNull);
    });
  });

  group('PR #4 review fixes', () {
    const v720 = VideoSource(url: 'https://x/v.mp4', resolution: '720p');

    Future<Env> running(Env e, {String id = '3119279'}) async {
      await e.start();
      await e.repo.download(movie, source: v720, bytes: 10000);
      e.downloader.send(
        DownloaderProgress(id, fraction: 0.4, expectedBytes: 10000),
      );
      await e.settle();
      return e;
    }

    Env fresh({
      List<(bool Function(ApiRequest), Object? Function(ApiRequest))> routes =
          const [],
      Duration userPauseGrace = Duration.zero,
    }) {
      final e = Env(routes: routes, userPauseGrace: userPauseGrace);
      addTearDown(() {
        e.repo.dispose();
        e.connectivity.close();
        e.dir.deleteSync(recursive: true);
      });
      return e;
    }

    test('critical 4: the notification\'s Resume after an in-app pause runs '
        'again; a late event from before the stop does not', () async {
      final e = await running(fresh());
      await e.repo.pause(movie.id);
      var row = (await e.store.get(movie.id))!;
      expect(
        (row.status, row.pausedByUser, row.downloadedBytes),
        (DownloadStatus.paused, true, 4000),
      );

      // Not past the saved bytes: from before the stop.
      e.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.4,
          expectedBytes: 10000,
        ),
      );
      await e.settle();
      expect((await e.store.get(movie.id))!.status, DownloadStatus.paused);

      e.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.running),
      );
      await e.settle();
      row = (await e.store.get(movie.id))!;
      expect((row.status, row.pausedByUser), (DownloadStatus.running, false));

      e.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.5,
          expectedBytes: 10000,
        ),
      );
      await e.settle();
      expect((await e.store.get(movie.id))!.downloadedBytes, 5000);
    });

    test('critical 4: progress past the saved bytes resumes a user-paused '
        'row without a running event', () async {
      final e = await running(fresh());
      await e.repo.pause(movie.id);
      e.downloader.send(
        const DownloaderProgress(
          '3119279',
          fraction: 0.6,
          expectedBytes: 10000,
        ),
      );
      await e.settle();
      final row = (await e.store.get(movie.id))!;
      expect((row.status, row.downloadedBytes), (DownloadStatus.running, 6000));
    });

    test('moments after an in-app pause, the engine\'s last events are '
        'ignored', () async {
      final e = await running(
        fresh(userPauseGrace: const Duration(minutes: 1)),
      );
      await e.repo.pause(movie.id);
      e.downloader
        ..send(const DownloaderStatus('3119279', DownloaderState.running))
        ..send(
          const DownloaderProgress(
            '3119279',
            fraction: 0.7,
            expectedBytes: 10000,
          ),
        );
      await e.settle();
      // A reconcile while the engine catches up doesn't undo it either.
      e.downloader.knownStates[movie.id] = DownloaderState.running;
      await e.repo.reconcile(force: true);
      await e.settle();
      final row = (await e.store.get(movie.id))!;
      expect(
        (row.status, row.pausedByUser, row.downloadedBytes),
        (DownloadStatus.paused, true, 4000),
      );
    });

    test('critical 4: reconcile follows the engine for a paused row resumed '
        'outside the app', () async {
      final e = await running(fresh());
      await e.repo.pause(movie.id);
      e.downloader.knownStates[movie.id] = DownloaderState.running;
      await e.repo.reconcile(force: true);
      final row = (await e.store.get(movie.id))!;
      expect((row.status, row.pausedByUser), (DownloadStatus.running, false));
    });

    test('critical 4: the notification\'s Cancel removes the download and '
        'its subtitles', () async {
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      final job = env.downloader.enqueued.single;
      final subs = (await env.store.get(movie.id))!.subtitles;
      expect(subs, isNotEmpty);
      env.downloader.knownStates.remove(movie.id);
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.canceled),
      );
      await env.settle();
      expect(await env.store.get(movie.id), isNull);
      for (final s in subs) {
        expect(
          File(p.join(job.spot.directory, s.fileName)).existsSync(),
          isFalse,
        );
      }
    });

    test('the app\'s own cancels never remove the row', () async {
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      // Pausing in the holding queue cancels the engine task.
      env.downloader.pauseReturns = false;
      await env.repo.pause(movie.id);
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.canceled),
      );
      await env.settle();
      expect((await env.store.get(movie.id))!.status, DownloadStatus.paused);

      // A canceled while the engine still has the task (a new attempt).
      await env.store.put(
        (await env.store.get(movie.id))!
            .copyWith(status: DownloadStatus.queued),
      );
      env.downloader.knownStates[movie.id] = DownloaderState.queued;
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.canceled),
      );
      await env.settle();
      expect(await env.store.get(movie.id), isNotNull);
    });

    test('critical 3: "Waiting for connection" survives a reconcile with the '
        'engine paused, then resumes when the network is back', () async {
      final e = await running(fresh());
      e.connectivity.setOnline(false);
      await e.settle();
      expect((await e.store.get(movie.id))!.isWaitingForConnection, isTrue);
      expect(e.downloader.knownStates[movie.id], DownloaderState.paused);

      await e.repo.reconcile(force: true);
      await e.settle();
      expect((await e.store.get(movie.id))!.isWaitingForConnection, isTrue);

      e.connectivity.setOnline(true);
      await e.settle();
      expect(e.downloader.resumed.map((r) => r.$1), [movie.id]);
      // The resume carries the per-task notification again.
      expect(
        e.downloader.resumeNotices[movie.id]?.runningBody,
        contains('720p'),
      );
      expect((await e.store.get(movie.id))!.status, DownloadStatus.queued);
    });

    test('high 5: offline leaves queued downloads to the engine, and a running '
        'one it could not pause as it is', () async {
      await env.start();
      await env.repo.download(
        series,
        episode: ep('e1', 1, 1),
        source: v720,
        bytes: 10000,
      );
      await env.repo.download(
        series,
        episode: ep('e2', 1, 2),
        source: v720,
        bytes: 10000,
      );
      env.downloader.send(
        const DownloaderProgress('e2', fraction: 0.3, expectedBytes: 10000),
      );
      await env.settle();
      env.downloader.pauseable['e2'] = false;

      env.connectivity.setOnline(false);
      await env.settle();
      expect((await env.store.get('e1'))!.status, DownloadStatus.queued);
      expect((await env.store.get('e2'))!.status, DownloadStatus.running);
      expect(env.downloader.canceled, isEmpty);
    });

    test('high 5: network back but no fresh URL yet: stays waiting and asks '
        'again', () async {
      var down = false;
      final e = fresh(
        routes: [
          (
            (ApiRequest r) => down && r.path.startsWith('transcoddedFiles'),
            (ApiRequest r) => offline,
          ),
        ],
      );
      await running(e);
      e.connectivity.setOnline(false);
      await e.settle();
      down = true;
      e.connectivity.setOnline(true);
      await e.settle();
      final row = (await e.store.get(movie.id))!;
      expect(row.isWaitingForConnection, isTrue);
      expect(row.problem, isNull);

      down = false;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await e.settle();
      expect(e.downloader.resumed.map((r) => r.$1), [movie.id]);
      expect((await e.store.get(movie.id))!.status, DownloadStatus.queued);
    });

    test('high 6: a season\'s episodes each carry their size', () async {
      await env.start();
      await env.repo.downloadEpisodes(series, [
        ep('e1', 1, 1),
        ep('e2', 1, 2),
      ], 720);
      for (final id in ['e1', 'e2']) {
        expect((await env.store.get(id))!.totalBytes, 3000000000);
      }
    });

    test('high 7: reconcile never completes a file of unknown size', () async {
      await env.start();
      Download row(String id, int? total) => Download(
        videoId: id,
        titleId: id,
        title: const LocalizedText(en: 'X'),
        quality: '720p',
        baseDirectory: 'root',
        directory: env.dir.path,
        fileName: '$id.mp4',
        status: DownloadStatus.running,
        totalBytes: total,
        addedAt: DateTime(2026, 11, 22),
      );
      for (final id in ['unknown', 'exact']) {
        File(p.join(env.dir.path, '$id.mp4'))
            .writeAsBytesSync(List.filled(100, 1));
      }
      await env.store.put(row('unknown', null));
      await env.store.put(row('exact', 100));
      await env.repo.reconcile(force: true);
      expect(
        (await env.store.get('unknown'))!.status,
        isNot(DownloadStatus.complete),
      );
      expect((await env.store.get('exact'))!.status, DownloadStatus.complete);
    });

    test(
      'high 8: Download again asks when the quality is gone and keeps the '
      'row; the pick renames the file and subtitles and takes the new size',
      () async {
        await env.start();
        final dir = p.join(env.dir.path, 'Eve of Destruction (1991)');
        final sub = File(p.join(dir, 'Eve 2160p.ar.srt'))
          ..createSync(recursive: true)
          ..writeAsStringSync(srt);
        final done = Download(
          videoId: movie.id,
          titleId: movie.id,
          title: movie.title,
          quality: '2160p',
          baseDirectory: 'root',
          directory: dir,
          fileName: 'Eve 2160p.mp4',
          subtitles: const [
            DownloadedSubtitle(
              language: 'ar',
              fileName: 'Eve 2160p.ar.srt',
              format: 'srt',
            ),
          ],
          status: DownloadStatus.complete,
          totalBytes: 9,
          downloadedBytes: 9,
          addedAt: DateTime(2026, 11, 21),
        );
        await env.store.put(done);

        final outcome = await env.repo.redownload(movie.id);
        expect(outcome, isA<ResumeQualityGone>());
        expect(
          (await env.store.get(movie.id))!.status,
          DownloadStatus.complete,
        );
        expect(env.downloader.enqueued, isEmpty);

        final started = await env.repo.redownload(
          movie.id,
          switchTo: (outcome as ResumeQualityGone).fallback,
        );
        expect(started, isA<ResumeStarted>());
        expect((started as ResumeStarted).startedOver, isFalse);
        final row = (await env.store.get(movie.id))!;
        expect(row.status, DownloadStatus.queued);
        expect(row.quality, '1080p');
        expect(row.fileName, 'Eve 1080p.mp4');
        expect(row.totalBytes, 3000000000);
        expect(row.startedOver, isFalse);
        expect(row.subtitles.single.fileName, 'Eve 1080p.ar.srt');
        expect(sub.existsSync(), isFalse);
        expect(File(p.join(dir, 'Eve 1080p.ar.srt')).existsSync(), isTrue);
        expect(env.downloader.enqueued.single.spot.fileName, 'Eve 1080p.mp4');
      },
    );

    test(
      'high 8: Download again saves removed subtitles again at once',
      () async {
        await env.start();
        await env.repo.download(movie, source: await env.source('240p'));
        final job = env.downloader.enqueued.single;
        await env.downloader.finish(job, bytes: 100);
        await env.settle();
        final d = (await env.store.get(movie.id))!;
        for (final name in [
          d.fileName,
          for (final s in d.subtitles) s.fileName,
        ]) {
          File(p.join(job.spot.directory, name)).deleteSync();
        }
        await env.repo.reconcile(force: true);

        await env.repo.redownload(movie.id);
        final row = (await env.store.get(movie.id))!;
        expect(row.status, DownloadStatus.queued);
        expect(row.startedOver, isFalse);
        for (final s in row.subtitles) {
          expect(
            File(p.join(job.spot.directory, s.fileName)).existsSync(),
            isTrue,
          );
        }
      },
    );

    test('high 8: a Retry that must start over removes the old temp file '
        'before enqueueing', () async {
      final tempDir = Directory(p.join(env.dir.path, 'tmp'))..createSync();
      env.downloader.tempDirectories.add(tempDir.path);
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      final stale = File(
        p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}old'),
      )..writeAsBytesSync(List.filled(64, 1));
      env.downloader.resumeAllowed = false;
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          connectionError: true,
        ),
      );
      await env.settle();
      // (The failed row has no resume data: the sweep after the failure
      // already removed it; a new one appears as the engine retries.)
      stale.writeAsBytesSync(List.filled(64, 1));
      await env.repo.resume(movie.id);
      expect(stale.existsSync(), isFalse);
      expect(env.downloader.enqueued, hasLength(2));
    });

    test('Android 7-9: a download asks for shared storage first', () async {
      await env.start();
      await env.repo.download(movie, source: v720);
      expect(env.downloader.storageAsks, 1);
    });
  });

  group('slow connections and huge files', () {
    const v720 = VideoSource(url: 'https://x/v.mp4', resolution: '720p');

    test('a passing failure continues by itself later, from its partial '
        'file; one that cannot pass does not', () {
      fakeAsync((async) {
        final e = Env(
          routes: [
            FakeApiClient.path('translationFiles/', const <String, Object?>{}),
          ],
          clock: () => async.getClock(DateTime(2026, 11, 22, 12)).now(),
          elapsed: () => async.elapsed,
        );
        addTearDown(() {
          e.repo.dispose();
          e.dir.deleteSync(recursive: true);
        });
        e.start();
        async.flushMicrotasks();
        e.repo.download(movie, source: v720, bytes: 10000);
        e.repo.download(
          series,
          episode: ep('e1', 1, 1),
          source: v720,
          bytes: 10000,
        );
        async.flushMicrotasks();
        e.downloader
          ..send(
            const DownloaderProgress(
              '3119279',
              fraction: 0.5,
              expectedBytes: 10000,
            ),
          )
          ..send(
            const DownloaderStatus(
              '3119279',
              DownloaderState.failed,
              connectionError: true,
            ),
          )
          ..send(
            const DownloaderStatus('e1', DownloaderState.failed, noSpace: true),
          );
        async.flushMicrotasks();
        Download? row;
        e.store.get(movie.id).then((v) => row = v);
        async.flushMicrotasks();
        expect(row!.status, DownloadStatus.failed);

        async.elapse(const Duration(minutes: 2, seconds: 1));
        e.store.get(movie.id).then((v) => row = v);
        async.flushMicrotasks();
        expect(e.downloader.resumed.map((r) => r.$1), [movie.id]);
        expect(row!.status, DownloadStatus.queued);
        expect(row!.downloadedBytes, 5000);

        async.elapse(const Duration(hours: 1));
        e.store.get('e1').then((v) => row = v);
        async.flushMicrotasks();
        expect(row!.status, DownloadStatus.failed);
        expect(e.downloader.resumed.map((r) => r.$1), [movie.id]);
      });
    });

    test('the app coming to the front continues failed downloads that can '
        'continue; one that could only start over waits for Retry', () async {
      await env.start();
      await env.repo.download(movie, source: v720, bytes: 10000);
      await env.repo.download(
        series,
        episode: ep('e1', 1, 1),
        source: v720,
        bytes: 10000,
      );
      for (final id in ['3119279', 'e1']) {
        env.downloader.send(
          DownloaderProgress(id, fraction: 0.3, expectedBytes: 10000),
        );
      }
      await env.settle();
      env.downloader.resumable['e1'] = false;
      for (final id in ['3119279', 'e1']) {
        env.downloader.knownStates[id] = DownloaderState.failed;
        env.downloader.send(
          DownloaderStatus(id, DownloaderState.failed, connectionError: true),
        );
      }
      await env.settle();

      await env.repo.reconcile(force: true);
      await env.settle();
      expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
      final e1 = (await env.store.get('e1'))!;
      expect((e1.status, e1.downloadedBytes), (DownloadStatus.failed, 3000));
      expect(env.downloader.resumed.map((r) => r.$1), [movie.id]);
    });

    test(
      'the network coming back continues downloads that failed on it',
      () async {
        await env.start();
        await env.repo.download(movie, source: v720, bytes: 10000);
        env.downloader.send(
          const DownloaderStatus(
            '3119279',
            DownloaderState.failed,
            connectionError: true,
          ),
        );
        await env.settle();
        env.connectivity.setOnline(false);
        await env.settle();
        expect((await env.store.get(movie.id))!.status, DownloadStatus.failed);
        env.connectivity.setOnline(true);
        await env.settle();
        expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
      },
    );

    test('a job carries its quality, so the engine can refresh its URL in '
        'the same one', () async {
      await env.start();
      await env.repo.download(movie, source: v720);
      expect(env.downloader.enqueued.single.quality, '720p');
    });

    test(
      'the sweep protects the partial file the engine can continue from',
      () async {
        final tempDir = Directory(p.join(env.dir.path, 'tmp'))..createSync();
        env.downloader.tempDirectories.add(tempDir.path);
        await env.start();
        await env.repo.download(movie, source: v720);
        final kept = File(
          p.join(tempDir.path, '${DownloadsJanitor.tempFilePrefix}kept'),
        )..writeAsBytesSync(List.filled(64, 1));
        env.downloader
          ..resumeAllowed = false
          ..protectedFiles[movie.id] = kept.path;
        env.downloader.send(
          const DownloaderStatus(
            '3119279',
            DownloaderState.failed,
            noSpace: true,
          ),
        );
        await env.settle();
        expect(kept.existsSync(), isTrue);

        // Once the download is gone, so is its protection.
        env.downloader.protectedFiles.clear();
        await env.repo.delete(movie.id);
        expect(kept.existsSync(), isFalse);
      },
    );
  });

  // Engine events and the user's controls wait their turn in one queue. A
  // slow network or a permission dialog must never be what they wait on:
  // on a weak connection Pause and Delete would hang for minutes.
  group('the network never holds up the queue', () {
    late Completer<void> net;
    var hang = false;

    /// [env] with every request matching [what] held until [net] completes.
    void hangOn(bool Function(ApiRequest) what) {
      env.repo.dispose();
      env.connectivity.close();
      env.dir.deleteSync(recursive: true);
      net = Completer<void>();
      hang = false;
      env = Env(
        routes: [
          (
            (r) => hang && what(r) && !r.path.startsWith('size:'),
            (r) async {
              await net.future;
              // Then answered as usual.
              hang = false;
              return fixtureApi().fetch(r);
            },
          ),
          FakeApiClient.path('size:', (ApiRequest r) async {
            if (hang && what(r)) await net.future;
            return 3000000000;
          }),
        ],
      );
    }

    /// The episode `e1`, running at 40%.
    Future<void> runningEpisode() async {
      await env.repo.download(
        series,
        episode: ep('e1', 1, 1),
        source: const VideoSource(url: 'https://x', resolution: '1080p'),
      );
      env.downloader.send(
        const DownloaderProgress('e1', fraction: 0.4, expectedBytes: 1000),
      );
      await env.settle();
      expect((await env.store.get('e1'))!.status, DownloadStatus.running);
    }

    /// Pauses `e1` and checks that it happened at once.
    Future<void> pauseIsPrompt() async {
      await env.repo.pause('e1').timeout(const Duration(seconds: 2));
      final e1 = (await env.store.get('e1'))!;
      expect(e1.status, DownloadStatus.paused);
      expect(e1.downloadedBytes, 400);
    }

    test('a Resume waiting for a fresh link', () async {
      hangOn((r) => r.path.startsWith('transcoddedFiles/id/3119279'));
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.failed),
      );
      await env.settle();
      await runningEpisode();

      hang = true;
      final resuming = env.repo.resume(movie.id);
      await env.settle();
      await pauseIsPrompt();
      expect((await env.store.get(movie.id))!.status, DownloadStatus.failed);

      net.complete();
      expect(await resuming, isA<ResumeStarted>());
      expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
      expect(env.downloader.resumed.single.$1, movie.id);
    });

    test('a new download fetching its subtitles: the video starts first, '
        'the subtitles join it', () async {
      hangOn((r) => r.path.startsWith('translationFiles/id/3119279'));
      await env.start();
      await runningEpisode();
      final source = await env.source('720p');

      hang = true;
      final adding = env.repo.download(movie, source: source);
      await env.settle();
      await pauseIsPrompt();
      expect(env.downloader.enqueued.map((j) => j.taskId), contains(movie.id));

      net.complete();
      await adding;
      final d = (await env.store.get(movie.id))!;
      expect(d.subtitles.map((s) => s.language), ['ar', 'en']);
      final dir = p.dirname(await env.repo.filePath(d));
      for (final s in d.subtitles) {
        expect(File(p.join(dir, s.fileName)).existsSync(), isTrue);
      }
    });

    test('subtitles that arrive after their download was deleted are '
        'deleted too, with the folder they made', () async {
      hangOn((r) => r.path.startsWith('translationFiles/id/3119279'));
      await env.start();
      final source = await env.source('720p');
      hang = true;
      final adding = env.repo.download(movie, source: source);
      await env.settle();
      final d = (await env.store.get(movie.id))!;
      final dir = p.dirname(await env.repo.filePath(d));
      await env.repo.delete(movie.id).timeout(const Duration(seconds: 2));

      net.complete();
      await adding;
      expect(await env.store.get(movie.id), isNull);
      expect(Directory(dir).existsSync(), isFalse, reason: 'nothing left');
    });

    test('a quality switch waiting for the new size', () async {
      hangOn((r) => r.path.startsWith('size:'));
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.failed),
      );
      await env.settle();
      await runningEpisode();
      final to = await env.source('480p');

      hang = true;
      final switching = env.repo.resume(movie.id, switchTo: to);
      await env.settle();
      await pauseIsPrompt();

      net.complete();
      expect(await switching, isA<ResumeStarted>());
      final d = (await env.store.get(movie.id))!;
      expect((d.quality, d.totalBytes), ('480p', 3000000000));
    });

    test('the notification permission dialog', () async {
      hangOn((_) => false);
      await env.start();
      await runningEpisode();
      final source = await env.source('720p');

      final dialog = env.downloader.notifyDialog = Completer<void>();
      final adding = env.repo.download(movie, source: source);
      await env.settle();
      await pauseIsPrompt();

      dialog.complete();
      await adding;
      expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
    });

    test('a re-download of a removed file waiting for a fresh link', () async {
      hangOn((r) => r.path.startsWith('transcoddedFiles/id/3119279'));
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      await env.downloader.finish(env.downloader.enqueued.last);
      await env.settle();
      final done = (await env.store.get(movie.id))!;
      expect(done.status, DownloadStatus.complete);
      File(await env.repo.filePath(done)).deleteSync();
      await runningEpisode();

      hang = true;
      final again = env.repo.redownload(movie.id);
      await env.settle();
      await pauseIsPrompt();

      net.complete();
      expect(await again, isA<ResumeStarted>());
      expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);
    });

    test('two Resumes at once start the download once', () async {
      hangOn((r) => r.path.startsWith('transcoddedFiles/id/3119279'));
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      env.downloader.send(
        const DownloaderStatus('3119279', DownloaderState.failed),
      );
      await env.settle();

      hang = true;
      final first = env.repo.resume(movie.id);
      final second = env.repo.resume(movie.id);
      await env.settle();
      net.complete();
      expect(await first, isA<ResumeStarted>());
      expect(await second, isA<ResumeStarted>());
      expect(env.downloader.resumed, hasLength(1));
    });

    test('a Pause while an automatic retry fetches its link wins', () async {
      hangOn((r) => r.path.startsWith('transcoddedFiles/id/3119279'));
      await env.start();
      await env.repo.download(movie, source: await env.source('720p'));
      env.downloader.send(
        const DownloaderProgress('3119279', fraction: 0.5, expectedBytes: 1000),
      );
      await env.settle();

      hang = true;
      // An expired link: retried by itself with a fresh one.
      env.downloader.send(
        const DownloaderStatus(
          '3119279',
          DownloaderState.failed,
          httpCode: 403,
        ),
      );
      await env.settle();
      await env.repo.pause(movie.id).timeout(const Duration(seconds: 2));

      net.complete();
      await env.settle();
      await env.settle();
      final d = (await env.store.get(movie.id))!;
      expect((d.status, d.pausedByUser), (DownloadStatus.paused, true));
      expect(env.downloader.resumed, isEmpty);
    });
  });

  group('DriftDownloadStore', () {
    test('reads back every field, newest first', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftDownloadStore(db);
      final d = Download(
        videoId: 'e1',
        titleId: 's',
        title: const LocalizedText(en: 'S', ar: 'س'),
        season: 1,
        episode: 7,
        episodeLast: 8,
        finale: true,
        posterUrl: 'https://img',
        kind: VideoKind.series,
        year: 2020,
        duration: const Duration(minutes: 44),
        quality: '1080p',
        baseDirectory: 'root',
        directory: '/x',
        fileName: 'f.mp4',
        subtitles: const [
          DownloadedSubtitle(
            language: 'ar',
            fileName: 'f.ar.srt',
            format: 'srt',
          ),
        ],
        totalBytes: 99,
        downloadedBytes: 42,
        status: DownloadStatus.failed,
        pausedByUser: true,
        startedOver: true,
        problem: DownloadProblem.noSpace,
        problemDetail: 'ENOSPC: no space left',
        addedAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
        contentUri: 'content://media/external/video/media/99',
      );
      await store.put(d);
      await store.put(
        Download(
          videoId: 'm',
          titleId: 'm',
          title: const LocalizedText(en: 'M'),
          quality: '720p',
          baseDirectory: 'root',
          directory: '/x',
          fileName: 'm.mp4',
          status: DownloadStatus.complete,
          addedAt: DateTime(2026, 2, 1),
        ),
      );
      expect((await store.all()).map((d) => d.videoId), ['m', 'e1']);
      final back = (await store.get('e1'))!;
      expect(back.asEpisode!.numbering.numbers, [7, 8]);
      expect(back.asEpisode!.numbering.isFinale, isTrue);
      expect(back.subtitles.single.fileName, 'f.ar.srt');
      expect(
        (
          back.problem,
          back.problemDetail,
          back.downloadedBytes,
          back.pausedByUser,
          back.startedOver,
          back.updatedAt,
          back.contentUri,
          back.duration,
          back.title.ar,
        ),
        (
          DownloadProblem.noSpace,
          'ENOSPC: no space left',
          42,
          true,
          true,
          DateTime(2026, 1, 2),
          'content://media/external/video/media/99',
          const Duration(minutes: 44),
          'س',
        ),
      );
      await store.remove('e1');
      expect(await store.get('e1'), isNull);
      expect(await store.watchAll().first, hasLength(1));
    });

    test('a version 3 database gains schema 4 download columns', () async {
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) => raw
            ..execute(
              'CREATE TABLE watch_history (video_id TEXT NOT NULL, '
              'series_id TEXT, season INTEGER, episode INTEGER, '
              'position_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL, '
              'finished INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
              'title_en TEXT, title_ar TEXT, poster_url TEXT, kind TEXT, '
              'PRIMARY KEY (video_id))',
            )
            ..execute(
              'CREATE TABLE favorites (title_id TEXT NOT NULL, title_en TEXT, '
              'title_ar TEXT, poster_url TEXT, kind TEXT, year INTEGER, '
              'genre_en TEXT, genre_ar TEXT, added_at INTEGER NOT NULL, '
              'PRIMARY KEY (title_id))',
            )
            ..execute(
              'CREATE TABLE continue_hidden (title_id TEXT NOT NULL, '
              'hidden_at INTEGER NOT NULL, PRIMARY KEY (title_id))',
            )
            ..execute(
              'CREATE TABLE downloads (video_id TEXT NOT NULL, '
              'title_id TEXT NOT NULL, season INTEGER, episode INTEGER, '
              'episode_last INTEGER, finale INTEGER NOT NULL DEFAULT 0, '
              'title_en TEXT, title_ar TEXT, poster_url TEXT, kind TEXT, '
              'year INTEGER, duration_ms INTEGER, quality TEXT NOT NULL, '
              'base_directory TEXT NOT NULL, directory TEXT NOT NULL, '
              'file_name TEXT NOT NULL, subtitles TEXT NOT NULL DEFAULT \'[]\', '
              'total_bytes INTEGER, status TEXT NOT NULL, problem TEXT, '
              'added_at INTEGER NOT NULL, completed_at INTEGER, '
              'PRIMARY KEY (video_id))',
            )
            ..execute(
              "INSERT INTO downloads (video_id, title_id, title_en, quality, "
              "base_directory, directory, file_name, total_bytes, status, "
              "added_at) VALUES ('v1', 'v1', 'Old', '1080p', 'root', '/x', "
              "'old.mp4', 1000, 'paused', 1700000000)",
            )
            ..execute('PRAGMA user_version = 3'),
        ),
      );
      addTearDown(db.close);
      final rows = await DriftDownloadStore(db).all();
      expect(rows, hasLength(1));
      expect(rows.single.downloadedBytes, 0);
      expect(rows.single.pausedByUser, isFalse);
      expect(rows.single.startedOver, isFalse);
      expect(rows.single.problemDetail, isNull);
    });

    test('a version 2 database gains the downloads table', () async {
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) => raw
            ..execute(
              'CREATE TABLE watch_history (video_id TEXT NOT NULL, '
              'series_id TEXT, season INTEGER, episode INTEGER, '
              'position_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL, '
              'finished INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
              'title_en TEXT, title_ar TEXT, poster_url TEXT, kind TEXT, '
              'PRIMARY KEY (video_id))',
            )
            ..execute(
              'CREATE TABLE favorites (title_id TEXT NOT NULL, title_en TEXT, '
              'title_ar TEXT, poster_url TEXT, kind TEXT, year INTEGER, '
              'genre_en TEXT, genre_ar TEXT, added_at INTEGER NOT NULL, '
              'PRIMARY KEY (title_id))',
            )
            ..execute(
              'CREATE TABLE continue_hidden (title_id TEXT NOT NULL, '
              'hidden_at INTEGER NOT NULL, PRIMARY KEY (title_id))',
            )
            ..execute('PRAGMA user_version = 2'),
        ),
      );
      addTearDown(db.close);
      expect(await DriftDownloadStore(db).all(), isEmpty);
    });
  });
}
