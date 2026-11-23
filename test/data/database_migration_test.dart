// Upgrades of installed databases. Every release installs over the last one
// (one signing key since 2026-11-23), so each older schema must reach the
// current one with its rows intact, and end up exactly like a fresh install.
//
// The CREATE TABLE statements are what drift made at each version, dumped
// from the commits that shipped them: schema 1 (1e313d5), 2 (16b028e) and
// 3 (615e734).

import 'dart:io';

import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/download.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/repositories/download_store.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _watchHistory =
    'CREATE TABLE "watch_history" ("video_id" TEXT NOT NULL, '
    '"series_id" TEXT NULL, "season" INTEGER NULL, "episode" INTEGER NULL, '
    '"position_ms" INTEGER NOT NULL, "duration_ms" INTEGER NOT NULL, '
    '"finished" INTEGER NOT NULL CHECK ("finished" IN (0, 1)), '
    '"updated_at" INTEGER NOT NULL, "title_en" TEXT NULL, '
    '"title_ar" TEXT NULL, "poster_url" TEXT NULL, "kind" TEXT NULL, '
    'PRIMARY KEY ("video_id"))';

const _favorites =
    'CREATE TABLE "favorites" ("title_id" TEXT NOT NULL, '
    '"title_en" TEXT NULL, "title_ar" TEXT NULL, "poster_url" TEXT NULL, '
    '"kind" TEXT NULL, "year" INTEGER NULL, "genre_en" TEXT NULL, '
    '"genre_ar" TEXT NULL, "added_at" INTEGER NOT NULL, '
    'PRIMARY KEY ("title_id"))';

const _continueHidden =
    'CREATE TABLE "continue_hidden" ("title_id" TEXT NOT NULL, '
    '"hidden_at" INTEGER NOT NULL, PRIMARY KEY ("title_id"))';

/// Schema 3's downloads table (Phase 6), before the reliability fields.
const _downloadsV3 =
    'CREATE TABLE "downloads" ("video_id" TEXT NOT NULL, '
    '"title_id" TEXT NOT NULL, "season" INTEGER NULL, '
    '"episode" INTEGER NULL, "episode_last" INTEGER NULL, '
    '"finale" INTEGER NOT NULL DEFAULT 0 CHECK ("finale" IN (0, 1)), '
    '"title_en" TEXT NULL, "title_ar" TEXT NULL, "poster_url" TEXT NULL, '
    '"kind" TEXT NULL, "year" INTEGER NULL, "duration_ms" INTEGER NULL, '
    '"quality" TEXT NOT NULL, "base_directory" TEXT NOT NULL, '
    '"directory" TEXT NOT NULL, "file_name" TEXT NOT NULL, '
    '"subtitles" TEXT NOT NULL DEFAULT \'[]\', "total_bytes" INTEGER NULL, '
    '"status" TEXT NOT NULL, "problem" TEXT NULL, '
    '"added_at" INTEGER NOT NULL, "completed_at" INTEGER NULL, '
    'PRIMARY KEY ("video_id"))';

/// 2026-11-19 12:00 UTC, in drift's format (seconds since the epoch).
const _t = 1795089600;

/// A database at [version], made with [statements].
AppDatabase _installed(int version, List<String> statements) => AppDatabase(
  NativeDatabase.memory(
    setup: (raw) {
      for (final s in statements) {
        raw.execute(s);
      }
      raw.execute('PRAGMA user_version = $version');
    },
  ),
);

/// Every table's columns as `name type notnull default pk`, for comparing
/// a migrated database with a fresh one.
Future<Map<String, List<String>>> _shape(AppDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final t in tables)
      t.read<String>('name'): [
        for (final c
            in await db
                .customSelect('PRAGMA table_info("${t.read<String>('name')}")')
                .get())
          '${c.read<String>('name')} ${c.read<String>('type')} '
              '${c.read<int>('notnull')} ${c.readNullable<String>('dflt_value')} '
              '${c.read<int>('pk')}',
      ]..sort(),
  };
}

void main() {
  late Map<String, List<String>> fresh;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    fresh = await _shape(db);
    await db.close();
  });

  test('a fresh install has the four tables at schema 4', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 4);
    expect(fresh.keys, [
      'continue_hidden',
      'downloads',
      'favorites',
      'watch_history',
    ]);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 4);
  });

  for (final (version, statements) in [
    (1, [_watchHistory]),
    (2, [_watchHistory, _favorites, _continueHidden]),
    (3, [_watchHistory, _favorites, _continueHidden, _downloadsV3]),
  ]) {
    test(
      'schema $version upgrades to exactly what a fresh install has',
      () async {
        final db = _installed(version, statements);
        addTearDown(db.close);
        expect(await _shape(db), fresh);
        final v = await db.customSelect('PRAGMA user_version').getSingle();
        expect(v.read<int>('user_version'), 4);
      },
    );
  }

  test('schema 2: history, favorites and hidden titles survive', () async {
    final db = _installed(2, [
      _watchHistory,
      _favorites,
      _continueHidden,
      "INSERT INTO watch_history VALUES ('e2', 's1', 1, 2, 60000, 1320000, 0, "
          "$_t, 'Friends', 'الأصدقاء', 'https://img/p.jpg', 'series')",
      "INSERT INTO favorites VALUES ('s1', 'Friends', NULL, NULL, 'series', "
          "1994, 'Comedy', 'كوميدي', $_t)",
      "INSERT INTO continue_hidden VALUES ('m9', $_t)",
    ]);
    addTearDown(db.close);
    final repo = DriftLibraryRepository(db);

    final e2 = (await repo.progress('e2'))!;
    expect(e2.seriesId, 's1');
    expect((e2.season, e2.episode), (1, 2));
    expect(e2.position, const Duration(minutes: 1));
    expect((e2.title.en, e2.title.ar), ('Friends', 'الأصدقاء'));
    expect(e2.kind, VideoKind.series);
    expect(e2.updatedAt.toUtc(), DateTime.utc(2026, 11, 19, 12));

    final f = (await repo.watchFavorites().first).single;
    expect((f.id, f.year, f.kind), ('s1', 1994, VideoKind.series));
    expect(f.categories.single.ar, 'كوميدي');
    expect(await repo.titleIds(), {'s1'});

    // The new downloads table works.
    final store = DriftDownloadStore(db);
    expect(await store.all(), isEmpty);
  });

  test('schema 3: a Phase 6 download keeps everything and gains the '
      'reliability fields at their defaults', () async {
    final db = _installed(3, [
      _watchHistory,
      _favorites,
      _continueHidden,
      _downloadsV3,
      "INSERT INTO downloads VALUES ('e7', 's1', 1, 7, 8, 1, 'Friends', NULL, "
          "'https://img/p.jpg', 'series', 1994, 1320000, '720p', 'root', "
          "'/movies/Friends (1994)', 'Friends S01E07-E08 720p.mp4', "
          "'[{\"lang\":\"ar\",\"file\":\"Friends S01E07-E08 720p.ar.srt\","
          "\"format\":\"srt\"}]', 300000000, 'complete', NULL, $_t, $_t)",
      "INSERT INTO downloads VALUES ('m1', 'm1', NULL, NULL, NULL, 0, "
          "'Dune', NULL, NULL, 'movies', 2021, NULL, '1080p', 'root', "
          "'/movies/Dune (2021)', 'Dune 1080p.mp4', '[]', NULL, 'failed', "
          "'network', $_t, NULL)",
    ]);
    addTearDown(db.close);
    final store = DriftDownloadStore(db);

    final e7 = (await store.get('e7'))!;
    expect(e7.status, DownloadStatus.complete);
    expect((e7.season, e7.episode, e7.episodeLast, e7.finale), (1, 7, 8, true));
    expect(e7.numbering.numbers, [7, 8]);
    expect(e7.subtitles.single.fileName, 'Friends S01E07-E08 720p.ar.srt');
    expect(e7.totalBytes, 300000000);
    expect(e7.duration, const Duration(minutes: 22));
    expect(e7.completedAt!.toUtc(), DateTime.utc(2026, 11, 19, 12));
    // New in schema 4.
    expect(e7.downloadedBytes, 0);
    expect(e7.pausedByUser, isFalse);
    expect(e7.startedOver, isFalse);
    expect(e7.problemDetail, isNull);
    expect(e7.updatedAt, isNull);
    expect(e7.contentUri, isNull);

    final m1 = (await store.get('m1'))!;
    expect(m1.status, DownloadStatus.failed);
    expect(m1.problem, DownloadProblem.network);
    expect(m1.totalBytes, isNull);

    // And the rows can be written again with the new fields.
    await store.put(
      m1.copyWith(
        downloadedBytes: 1234,
        pausedByUser: true,
        updatedAt: DateTime.utc(2026, 11, 20),
        contentUri: 'content://media/1',
      ),
    );
    final again = (await store.get('m1'))!;
    expect((again.downloadedBytes, again.pausedByUser), (1234, true));
    expect(again.contentUri, 'content://media/1');
  });

  test('an upgrade runs once: reopening the upgraded file changes nothing', () async {
    // A real file, as on a device, so the second open sees the first.
    final dir = Directory.systemTemp.createTempSync('db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'cinemakom.sqlite'));
    final first = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          if (raw.userVersion != 0) return;
          for (final s in [_watchHistory, _favorites, _continueHidden]) {
            raw.execute(s);
          }
          raw
            ..execute(
              "INSERT INTO watch_history VALUES ('m', NULL, NULL, NULL, 1, 2, "
              "0, $_t, 'Kept', NULL, NULL, 'movies')",
            )
            ..userVersion = 2;
        },
      ),
    );
    await DriftLibraryRepository(first).addFavorite(const MediaItem(id: 'f'));
    final shape = await _shape(first);
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    expect(await _shape(second), shape);
    expect(shape, fresh);
    final repo = DriftLibraryRepository(second);
    expect((await repo.progress('m'))!.title.en, 'Kept');
    expect(await repo.titleIds(), {'f', 'm'});
  });
}
