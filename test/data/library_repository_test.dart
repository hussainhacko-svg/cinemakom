import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const min = Duration(minutes: 1);

WatchProgress row(
  String id, {
  String? series,
  int minutes = 10,
  int of = 100,
  int at = 0,
}) => WatchProgress(
  videoId: id,
  seriesId: series,
  season: series == null ? null : 1,
  episode: series == null ? null : 2,
  position: min * minutes,
  duration: min * of,
  updatedAt: DateTime(2026, 11, 19, 12, at),
  title: const LocalizedText(en: 'Title', ar: 'عنوان'),
  posterUrl: 'https://img/p.jpg',
  kind: series == null ? VideoKind.movies : VideoKind.series,
);

void main() {
  group('WatchProgress rules', () {
    test('finished at 95%, or with less than 2 minutes left', () {
      expect(row('a', minutes: 94).isFinished, isFalse);
      expect(row('a', minutes: 95).isFinished, isTrue);
      expect(row('a', minutes: 19, of: 20).isFinished, isTrue);
      expect(row('a', minutes: 17, of: 20).isFinished, isFalse);
    });

    test('resume after 30 s, not once finished', () {
      final start = WatchProgress(
        videoId: 'a',
        position: const Duration(seconds: 20),
        duration: min * 90,
        updatedAt: DateTime(2026),
        title: const LocalizedText(en: 'A'),
      );
      expect(start.resumeAt, isNull);
      expect(row('a', minutes: 14).resumeAt, min * 14);
      expect(row('a', minutes: 99).resumeAt, isNull);
      expect(row('a', minutes: 14).remaining, min * 86);
    });

    test('continue keeps the newest row per title, without finished '
        'movies', () {
      final rows = [
        row('e3', series: 's', at: 9),
        row('e2', series: 's', at: 8),
        row('m1', minutes: 99, at: 7),
        row('m2', at: 6),
        // A finished episode stays: its next episode is offered.
        row('t5', series: 't', minutes: 99, at: 5),
      ];
      expect(continueFrom(rows).map((p) => p.videoId), ['e3', 'm2', 't5']);
    });

    test('a hidden title comes back only when watched after hiding', () {
      final rows = [row('e3', series: 's', at: 9), row('m2', at: 6)];
      expect(
        continueFrom(
          rows,
          hidden: {'s': DateTime(2026, 11, 19, 12, 9)},
        ).map((p) => p.videoId),
        ['m2'],
      );
      expect(
        continueFrom(
          rows,
          hidden: {'s': DateTime(2026, 11, 19, 12, 8)},
        ).map((p) => p.videoId),
        ['e3', 'm2'],
      );
    });

    test('a favorite is its movie or series', () {
      const episode = MediaItem(
        id: 'e7',
        rootSeriesId: 's1',
        title: LocalizedText(en: 'Show'),
        hdPosterUrl: 'https://img/hd.jpg',
        categories: [
          LocalizedText(en: 'Drama'),
          LocalizedText(en: 'Crime'),
        ],
      );
      final f = favoriteOf(episode);
      expect(f.id, 's1');
      expect(f.kind, VideoKind.series);
      expect(f.posterUrl, 'https://img/hd.jpg');
      expect(f.categories.map((c) => c.en), ['Drama']);
    });
  });

  group('DriftLibraryRepository', () {
    late AppDatabase db;
    late DriftLibraryRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftLibraryRepository(db);
    });
    tearDown(() => db.close());

    test('saves, replaces and reads back every field', () async {
      await repo.save(row('e1', series: 's', minutes: 5));
      await repo.save(row('e1', series: 's', minutes: 14, at: 1));
      final p = (await repo.progress('e1'))!;
      expect(p.position, min * 14);
      expect(p.duration, min * 100);
      expect((p.seriesId, p.season, p.episode), ('s', 1, 2));
      expect((p.title.en, p.title.ar), ('Title', 'عنوان'));
      expect(p.kind, VideoKind.series);
      expect(p.isFinished, isFalse);
      expect(await repo.progress('nope'), isNull);
    });

    test('series and continue streams', () async {
      await repo.save(row('e1', series: 's', at: 1));
      await repo.save(row('e2', series: 's', at: 2));
      await repo.save(row('m', at: 3));
      expect((await repo.watchSeries('s').first).keys, {'e1', 'e2'});
      expect((await repo.watchContinue().first).map((p) => p.videoId), [
        'm',
        'e2',
      ]);
    });

    test('hiding a title, then watching it again', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      Future<void> watched(String id, String? series, DateTime at) => repo.save(
        WatchProgress(
          videoId: id,
          seriesId: series,
          position: min * 10,
          duration: min * 100,
          updatedAt: at,
          title: const LocalizedText(en: 'T'),
        ),
      );
      await watched('e1', 's', past);
      await watched('m', null, past);
      await repo.hideFromContinue('s');
      expect((await repo.watchContinue().first).map((p) => p.videoId), ['m']);
      // The history is kept.
      expect((await repo.watchSeries('s').first).keys, {'e1'});
      await watched('e2', 's', DateTime.now().add(const Duration(minutes: 1)));
      expect((await repo.watchContinue().first).map((p) => p.videoId), [
        'e2',
        'm',
      ]);
    });

    test('favorites: add, re-add to the front, remove', () async {
      const a = MediaItem(
        id: 'a',
        title: LocalizedText(en: 'A', ar: 'أ'),
        posterUrl: 'https://img/a.jpg',
        year: 2020,
        kind: VideoKind.movies,
        categories: [LocalizedText(en: 'Drama', ar: 'دراما')],
      );
      const b = MediaItem(id: 'b', kind: VideoKind.series);
      expect(await repo.watchIsFavorite('a').first, isFalse);
      await repo.addFavorite(a);
      await repo.addFavorite(b);
      expect((await repo.watchFavorites().first).map((f) => f.id), ['b', 'a']);
      await repo.addFavorite(a);
      final list = await repo.watchFavorites().first;
      expect(list.map((f) => f.id), ['a', 'b']);
      final saved = list.first;
      expect((saved.title.en, saved.title.ar), ('A', 'أ'));
      expect(
        (saved.posterUrl, saved.year, saved.kind),
        ('https://img/a.jpg', 2020, VideoKind.movies),
      );
      expect(saved.categories.single.ar, 'دراما');
      expect(await repo.watchIsFavorite('a').first, isTrue);
      await repo.removeFavorite('a');
      expect((await repo.watchFavorites().first).map((f) => f.id), ['b']);
    });

    test('titleIds and updateTitles cover favorites and history', () async {
      await repo.addFavorite(
        const MediaItem(
          id: 'f',
          title: LocalizedText(en: 'Old'),
        ),
      );
      await repo.save(row('e1', series: 's'));
      await repo.save(row('m'));
      expect(await repo.titleIds(), {'f', 's', 'm'});

      await repo.updateTitles(const [
        MediaItem(
          id: 'f',
          title: LocalizedText(en: 'New'),
          posterUrl: 'https://img/new.jpg',
        ),
        MediaItem(
          id: 's',
          title: LocalizedText(en: 'Series', ar: 'مسلسل'),
        ),
        // No poster in the answer: the stored one stays.
        MediaItem(
          id: 'm',
          title: LocalizedText(en: 'Movie'),
        ),
      ]);
      final f = (await repo.watchFavorites().first).single;
      expect((f.title.en, f.posterUrl), ('New', 'https://img/new.jpg'));
      final e1 = (await repo.progress('e1'))!;
      expect((e1.title.en, e1.title.ar), ('Series', 'مسلسل'));
      final m = (await repo.progress('m'))!;
      expect((m.title.en, m.posterUrl), ('Movie', 'https://img/p.jpg'));
      // Positions are untouched.
      expect(m.position, min * 10);
    });
  });

  test('a version 1 database gains the new tables', () async {
    // The Phase 4 schema, as installed apps have it.
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
            "INSERT INTO watch_history VALUES ('m', NULL, NULL, NULL, 60000, "
            "600000, 0, 1795000000, 'Kept', NULL, NULL, 'movies')",
          )
          ..execute('PRAGMA user_version = 1'),
      ),
    );
    addTearDown(db.close);
    final repo = DriftLibraryRepository(db);
    expect((await repo.progress('m'))!.title.en, 'Kept');
    await repo.addFavorite(const MediaItem(id: 'f'));
    await repo.hideFromContinue('m');
    expect(await repo.titleIds(), {'f', 'm'});
  });
}
