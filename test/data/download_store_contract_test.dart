// One contract for both DownloadStore implementations (drift and the
// in-memory one the widget and repository tests use), plus what only the
// database can get wrong: damaged rows.

import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 11, 20, 12);

Download _row(
  String id, {
  String titleId = 't',
  int? season,
  int? episode,
  int minute = 0,
  DownloadStatus status = DownloadStatus.queued,
}) => Download(
  videoId: id,
  titleId: titleId,
  title: const LocalizedText(en: 'Title'),
  season: season,
  episode: episode,
  quality: '720p',
  baseDirectory: 'root',
  directory: '/movies/Title',
  fileName: '$id.mp4',
  status: status,
  addedAt: _t0.add(Duration(minutes: minute)),
);

/// Every field set, none at its default.
final _full = Download(
  videoId: 'e7',
  titleId: 's1',
  title: const LocalizedText(en: 'Friends', ar: 'الأصدقاء'),
  season: 2,
  episode: 7,
  episodeLast: 8,
  finale: true,
  posterUrl: 'https://img/p.jpg',
  kind: VideoKind.series,
  year: 1994,
  duration: const Duration(minutes: 44),
  quality: '1080p',
  baseDirectory: 'root',
  directory: '/storage/emulated/0/Movies/Cinemakom/Friends (1994)',
  fileName: 'Friends S02E07-E08 1080p.mp4',
  subtitles: const [
    DownloadedSubtitle(
      language: 'ar',
      fileName: 'Friends S02E07-E08 1080p.ar.srt',
      format: 'srt',
    ),
    DownloadedSubtitle(
      language: 'ar',
      fileName: 'Friends S02E07-E08 1080p.ar.ass',
      format: 'ass',
    ),
  ],
  totalBytes: 3 * 1024 * 1024 * 1024 + 7,
  downloadedBytes: 2 * 1024 * 1024 * 1024,
  status: DownloadStatus.paused,
  pausedByUser: true,
  startedOver: true,
  problem: DownloadProblem.linkExpired,
  problemDetail: 'HTTP 403 "Forbidden"',
  addedAt: _t0,
  updatedAt: _t0.add(const Duration(minutes: 5)),
  completedAt: _t0.add(const Duration(minutes: 9)),
  contentUri: 'content://media/external/video/media/42',
);

void _expectSame(Download a, Download b) {
  expect(a.videoId, b.videoId);
  expect(a.titleId, b.titleId);
  expect(a.title, b.title);
  expect(
    (a.season, a.episode, a.episodeLast),
    (b.season, b.episode, b.episodeLast),
  );
  expect(a.finale, b.finale);
  expect((a.posterUrl, a.kind, a.year), (b.posterUrl, b.kind, b.year));
  expect(a.duration, b.duration);
  expect(a.quality, b.quality);
  expect(
    (a.baseDirectory, a.directory, a.fileName),
    (b.baseDirectory, b.directory, b.fileName),
  );
  expect(
    [for (final s in a.subtitles) s.toJson()],
    [for (final s in b.subtitles) s.toJson()],
  );
  expect((a.totalBytes, a.downloadedBytes), (b.totalBytes, b.downloadedBytes));
  expect(
    (a.status, a.pausedByUser, a.startedOver),
    (b.status, b.pausedByUser, b.startedOver),
  );
  expect((a.problem, a.problemDetail), (b.problem, b.problemDetail));
  bool same(DateTime? x, DateTime? y) =>
      x == null ? y == null : (y != null && x.isAtSameMomentAs(y));
  expect(same(a.addedAt, b.addedAt), isTrue, reason: 'addedAt');
  expect(same(a.updatedAt, b.updatedAt), isTrue, reason: 'updatedAt');
  expect(same(a.completedAt, b.completedAt), isTrue, reason: 'completedAt');
  expect(a.contentUri, b.contentUri);
}

void _contract(String name, DownloadStore Function() make) {
  group(name, () {
    late DownloadStore store;
    setUp(() => store = make());

    test('every field reads back as written', () async {
      await store.put(_full);
      _expectSame((await store.get('e7'))!, _full);
      _expectSame((await store.all()).single, _full);
    });

    test('a minimal row reads back with its defaults', () async {
      await store.put(_row('m'));
      final m = (await store.get('m'))!;
      expect(m.subtitles, isEmpty);
      expect((m.totalBytes, m.downloadedBytes), (null, 0));
      expect((m.pausedByUser, m.startedOver, m.finale), (false, false, false));
      expect((m.problem, m.problemDetail, m.contentUri), (null, null, null));
      expect((m.updatedAt, m.completedAt), (null, null));
    });

    test('put replaces; clearing a field sticks', () async {
      await store.put(_full);
      await store.put(
        _full.copyWith(
          status: DownloadStatus.running,
          clearProblem: true,
          clearTotalBytes: true,
          clearContentUri: true,
          pausedByUser: false,
        ),
      );
      final d = (await store.get('e7'))!;
      expect(d.status, DownloadStatus.running);
      expect((d.problem, d.problemDetail), (null, null));
      expect((d.totalBytes, d.contentUri), (null, null));
      expect(d.pausedByUser, isFalse);
      expect((await store.all()).length, 1);
    });

    test('remove, twice, and get of a missing row', () async {
      await store.put(_row('a'));
      await store.remove('a');
      await store.remove('a');
      expect(await store.get('a'), isNull);
      expect(await store.all(), isEmpty);
    });

    test('newest first; a season added at once in episode order', () async {
      await store.put(_row('old', minute: 0));
      // Download season: every episode in the same second.
      await store.put(_row('e3', season: 1, episode: 3, minute: 5));
      await store.put(_row('e1', season: 1, episode: 1, minute: 5));
      await store.put(_row('s2e1', season: 2, episode: 1, minute: 5));
      await store.put(_row('e2', season: 1, episode: 2, minute: 5));
      await store.put(_row('new', minute: 9));
      expect((await store.all()).map((d) => d.videoId), [
        'new',
        'e1',
        'e2',
        'e3',
        's2e1',
        'old',
      ]);
    });

    test('watchAll emits the current rows, then every change', () async {
      expect(await store.watchAll().first, isEmpty);
      await store.put(_row('a'));
      expect((await store.watchAll().first).single.videoId, 'a');
      await store.put(_row('a', status: DownloadStatus.complete));
      expect(
        (await store.watchAll().first).single.status,
        DownloadStatus.complete,
      );
    });
  });
}

void main() {
  _contract('drift', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return DriftDownloadStore(db);
  });
  _contract('in memory', MemoryDownloadStore.new);

  group('drift: damaged rows', () {
    late AppDatabase db;
    late DriftDownloadStore store;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftDownloadStore(db);
    });
    tearDown(() => db.close());

    Future<void> setColumn(String column, Object? value) => db.customStatement(
      'UPDATE downloads SET $column = ? WHERE video_id = ?',
      [value, 'e7'],
    );

    test(
      'an unknown status reads as failed (so "Try again" can fix it)',
      () async {
        await store.put(_full);
        await setColumn('status', 'exploded');
        expect((await store.get('e7'))!.status, DownloadStatus.failed);
      },
    );

    test('an unknown problem or kind reads as none', () async {
      await store.put(_full);
      await setColumn('problem', 'gremlins');
      await setColumn('kind', 'opera');
      final d = (await store.get('e7'))!;
      expect(d.problem, isNull);
      expect(d.kind, isNull);
      // The episode still knows it's a series.
      expect(d.item.kind, VideoKind.series);
    });

    for (final (what, json) in [
      ('not JSON', '{oops'),
      ('not a list', '{"lang":"ar"}'),
      ('the wrong types', '[{"lang":1,"file":null,"format":"srt"}, 7, null]'),
      ('empty', ''),
    ]) {
      test('subtitles that are $what read as none, never a crash', () async {
        await store.put(_full);
        await setColumn('subtitles', json);
        final d = (await store.get('e7'))!;
        expect(d.subtitles, isEmpty);
        expect(d.videoId, 'e7');
      });
    }

    test('good subtitle entries survive a bad neighbour', () async {
      await store.put(_full);
      await setColumn(
        'subtitles',
        '[{"lang":"en","file":"a.en.srt","format":"srt"},{"lang":2}]',
      );
      expect((await store.get('e7'))!.subtitles.single.fileName, 'a.en.srt');
    });

    test('Arabic, quotes and very large sizes are stored exactly', () async {
      final d = _full.copyWith(
        fileName: 'عنوان "طويل" S01E01 1080p.mp4',
        totalBytes: 1 << 40,
        downloadedBytes: (1 << 40) - 1,
        problemDetail: "it's 'quoted'; DROP TABLE downloads; --",
      );
      await store.put(d);
      _expectSame((await store.get('e7'))!, d);
      final count = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM downloads WHERE video_id = ?',
            variables: [Variable.withString('e7')],
          )
          .getSingle();
      expect(count.read<int>('n'), 1);
    });
  });
}
