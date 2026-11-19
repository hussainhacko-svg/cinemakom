import 'dart:io';

import 'package:cinemakom/core/downloads/downloader.dart';
import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/playback_models.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:cinemakom/data/repositories/downloads_repository.dart';
import 'package:cinemakom/data/repositories/media_repository.dart';
import 'package:drift/native.dart';
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

class Env {
  Env({
    List<(bool Function(ApiRequest), Object? Function(ApiRequest))> routes =
        const [],
  }) : dir = Directory.systemTemp.createTempSync('dl-test') {
    api = fixtureApi([
      FakeApiClient.path('https://cnth2', srt),
      FakeApiClient.path('size:', (ApiRequest r) => 3000000000),
      ...routes,
    ]);
    downloader = FakeDownloader(root: dir.path);
    repo = DownloadsRepository(
      store: store,
      downloader: downloader,
      media: MediaRepository(api),
      api: api,
      root: () async => (baseDirectory: 'root', directory: dir.path),
      styledSubtitles: false,
      clock: () => DateTime(2026, 11, 19, 12, tick++),
    );
  }

  final Directory dir;
  late final FakeApiClient api;
  late final FakeDownloader downloader;
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
  tearDown(() => env.dir.deleteSync(recursive: true));

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
    expect(job.spot.directory, p.join(env.dir.path, 'Eve of Destruction'));
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
    expect(d.problem, DownloadProblem.unavailable);
    expect(env.downloader.resumed, hasLength(1));
  });

  test('a dropped connection fails; Try again resumes, or restarts', () async {
    await env.start();
    await env.repo.download(movie, source: await env.source('720p'));
    env.downloader.send(
      const DownloaderStatus('3119279', DownloaderState.failed),
    );
    await env.settle();
    expect((await env.store.get(movie.id))!.problem, DownloadProblem.network);

    await env.repo.resume(movie.id);
    expect(env.downloader.resumed, hasLength(1));
    expect((await env.store.get(movie.id))!.status, DownloadStatus.queued);

    // No partial file left: it starts over (same quality, fresh URL).
    env.downloader.canResume = false;
    await env.repo.resume(movie.id);
    expect(env.downloader.enqueued, hasLength(2));
    expect(
      env.downloader.enqueued.last.spot.fileName,
      'Eve of Destruction 720p.mp4',
    );
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

  test('after a restart: lost tasks fail, finished ones complete', () async {
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
    expect((await env.store.get('a'))!.status, DownloadStatus.failed);
    final b = (await env.store.get('b'))!;
    expect((b.status, b.totalBytes), (DownloadStatus.complete, 3));
  });

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
        status: DownloadStatus.failed,
        problem: DownloadProblem.noSpace,
        addedAt: DateTime(2026, 1, 1),
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
        (back.problem, back.duration, back.title.ar),
        (DownloadProblem.noSpace, const Duration(minutes: 44), 'س'),
      );
      await store.remove('e1');
      expect(await store.get('e1'), isNull);
      expect(await store.watchAll().first, hasLength(1));
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
