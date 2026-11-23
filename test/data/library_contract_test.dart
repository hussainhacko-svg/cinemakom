// One contract for both LibraryRepository implementations: the real one
// (drift, on an in-memory SQLite) and the in-memory one every widget test
// uses. If they ever behave differently, the widget tests stop telling the
// truth about the app.

import 'package:cinemakom/core/network/api_endpoints.dart' show VideoKind;
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/localized_text.dart';
import 'package:cinemakom/data/models/media_item.dart';
import 'package:cinemakom/data/models/watch_progress.dart';
import 'package:cinemakom/data/repositories/library_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _min = Duration(minutes: 1);

/// Whole seconds: the database keeps no milliseconds.
final _t0 = DateTime.utc(2026, 11, 20, 12);
DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

WatchProgress _movie(
  String id, {
  int minute = 0,
  Duration position = const Duration(minutes: 10),
  Duration duration = const Duration(minutes: 100),
  String title = 'Movie',
  bool? finished,
}) => WatchProgress(
  videoId: id,
  position: position,
  duration: duration,
  updatedAt: _at(minute),
  title: LocalizedText(en: title),
  kind: VideoKind.movies,
  finished: finished,
);

WatchProgress _episode(
  String id,
  String seriesId, {
  required int season,
  required int episode,
  int minute = 0,
  Duration position = const Duration(minutes: 5),
  Duration duration = const Duration(minutes: 22),
}) => WatchProgress(
  videoId: id,
  seriesId: seriesId,
  season: season,
  episode: episode,
  position: position,
  duration: duration,
  updatedAt: _at(minute),
  title: const LocalizedText(en: 'Series', ar: 'مسلسل'),
  posterUrl: 'https://img/series.jpg',
  kind: VideoKind.series,
);

void _contract(String name, LibraryRepository Function() make) {
  group(name, () {
    late LibraryRepository repo;
    setUp(() => repo = make());

    test('a saved row reads back field for field', () async {
      final e = _episode('e3', 's1', season: 2, episode: 3, minute: 7);
      await repo.save(e);
      final back = (await repo.progress('e3'))!;
      expect(back.videoId, 'e3');
      expect(back.seriesId, 's1');
      expect((back.season, back.episode), (2, 3));
      expect(back.position, e.position);
      expect(back.duration, e.duration);
      expect(back.updatedAt.isAtSameMomentAs(e.updatedAt), isTrue);
      expect(back.title, e.title);
      expect(back.posterUrl, e.posterUrl);
      expect(back.kind, VideoKind.series);
      expect(back.isFinished, isFalse);
      expect(await repo.progress('nope'), isNull);
    });

    test('saving the same video again replaces its row', () async {
      await repo.save(_movie('m', position: _min));
      await repo.save(_movie('m', position: _min * 40, minute: 1));
      expect((await repo.progress('m'))!.position, _min * 40);
      expect((await repo.watchContinue().first).length, 1);
    });

    test('"finished" is kept as it was saved', () async {
      // Near the end: finished by the rule.
      await repo.save(_movie('a', position: _min * 99));
      // Stored explicitly, against the rule.
      await repo.save(_movie('b', position: _min * 99, finished: false));
      expect((await repo.progress('a'))!.isFinished, isTrue);
      expect((await repo.progress('b'))!.isFinished, isFalse);
    });

    test('watchProgress follows one video', () async {
      expect(await repo.watchProgress('m').first, isNull);
      await repo.save(_movie('m'));
      expect((await repo.watchProgress('m').first)!.videoId, 'm');
    });

    test('watchSeries has that series\' episodes only', () async {
      await repo.save(_episode('e1', 's1', season: 1, episode: 1));
      await repo.save(_episode('e2', 's1', season: 1, episode: 2));
      await repo.save(_episode('x1', 's2', season: 1, episode: 1));
      await repo.save(_movie('m'));
      expect((await repo.watchSeries('s1').first).keys.toSet(), {'e1', 'e2'});
      expect(await repo.watchSeries('none').first, isEmpty);
    });

    group('Continue watching', () {
      test('the newest row of each title, newest first', () async {
        await repo.save(_episode('e1', 's1', season: 1, episode: 1, minute: 1));
        await repo.save(_movie('m', minute: 2));
        await repo.save(_episode('e2', 's1', season: 1, episode: 2, minute: 3));
        final rows = await repo.watchContinue().first;
        expect(rows.map((r) => r.videoId), ['e2', 'm']);
      });

      test('a finished movie leaves; a finished episode stays (its next '
          'one is offered)', () async {
        await repo.save(_movie('done', position: _min * 99, minute: 1));
        await repo.save(
          _episode(
            'e1',
            's1',
            season: 1,
            episode: 1,
            minute: 2,
            position: _min * 22,
          ),
        );
        final rows = await repo.watchContinue().first;
        expect(rows.map((r) => r.videoId), ['e1']);
        expect(rows.single.isFinished, isTrue);
      });

      test('an older unfinished episode doesn\'t bring back a series whose '
          'newest episode is the one shown', () async {
        await repo.save(_episode('e1', 's1', season: 1, episode: 1, minute: 5));
        await repo.save(_episode('e9', 's1', season: 1, episode: 9, minute: 1));
        final rows = await repo.watchContinue().first;
        expect(rows.map((r) => r.videoId), ['e1']);
      });

      test('a hidden title stays hidden until it is watched again', () async {
        await repo.save(_episode('e1', 's1', season: 1, episode: 1, minute: 1));
        await repo.save(_movie('m', minute: 2));
        await repo.hideFromContinue('s1');
        expect((await repo.watchContinue().first).map((r) => r.videoId), ['m']);
        // History stays.
        expect(await repo.progress('e1'), isNotNull);
        expect((await repo.watchSeries('s1').first).length, 1);

        // Watching another episode later brings the series back.
        final later = DateTime.now().toUtc().add(const Duration(hours: 1));
        await repo.save(
          WatchProgress(
            videoId: 'e2',
            seriesId: 's1',
            season: 1,
            episode: 2,
            position: _min,
            duration: _min * 22,
            updatedAt: DateTime.utc(
              later.year,
              later.month,
              later.day,
              later.hour,
              later.minute,
              later.second,
            ),
            title: const LocalizedText(en: 'Series'),
            kind: VideoKind.series,
          ),
        );
        expect((await repo.watchContinue().first).first.videoId, 'e2');
      });

      test('hiding while the clock is behind the newest row still hides it '
          'until a later watch', () async {
        final future = DateTime.now().toUtc().add(const Duration(days: 2));
        DateTime whole(DateTime d) =>
            DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
        await repo.save(
          WatchProgress(
            videoId: 'm',
            position: _min * 10,
            duration: _min * 100,
            updatedAt: whole(future),
            title: const LocalizedText(en: 'Movie'),
          ),
        );
        await repo.hideFromContinue('m');
        expect(await repo.watchContinue().first, isEmpty);
        await repo.save(
          WatchProgress(
            videoId: 'm',
            position: _min * 11,
            duration: _min * 100,
            updatedAt: whole(future.add(const Duration(minutes: 1))),
            title: const LocalizedText(en: 'Movie'),
          ),
        );
        expect((await repo.watchContinue().first).single.videoId, 'm');
      });

      test('hiding a title with no history is harmless', () async {
        await repo.hideFromContinue('ghost');
        await repo.save(_movie('m'));
        expect((await repo.watchContinue().first).single.videoId, 'm');
      });
    });

    group('favorites', () {
      test('an episode is saved as its series, with one genre', () async {
        await repo.addFavorite(
          const MediaItem(
            id: 'e5',
            rootSeriesId: 's1',
            title: LocalizedText(en: 'Series'),
            hdPosterUrl: 'https://img/hd.jpg',
            year: 1994,
            categories: [
              LocalizedText(en: 'Comedy', ar: 'كوميدي'),
              LocalizedText(en: 'Romance'),
            ],
          ),
        );
        final f = (await repo.watchFavorites().first).single;
        expect(f.id, 's1');
        expect(f.kind, VideoKind.series);
        expect(f.posterUrl, 'https://img/hd.jpg');
        expect(f.year, 1994);
        expect(f.categories, [const LocalizedText(en: 'Comedy', ar: 'كوميدي')]);
        expect(await repo.watchIsFavorite('s1').first, isTrue);
        expect(await repo.watchIsFavorite('e5').first, isFalse);
      });

      test(
        'the last added first; adding again moves it to the front',
        () async {
          for (final id in ['a', 'b', 'c']) {
            await repo.addFavorite(MediaItem(id: id));
          }
          expect((await repo.watchFavorites().first).map((f) => f.id), [
            'c',
            'b',
            'a',
          ]);
          await repo.addFavorite(const MediaItem(id: 'a'));
          expect((await repo.watchFavorites().first).map((f) => f.id), [
            'a',
            'c',
            'b',
          ]);
        },
      );

      test('remove, and removing twice', () async {
        await repo.addFavorite(const MediaItem(id: 'a'));
        await repo.removeFavorite('a');
        await repo.removeFavorite('a');
        expect(await repo.watchFavorites().first, isEmpty);
        expect(await repo.watchIsFavorite('a').first, isFalse);
      });
    });

    test('titleIds: favorites and history, by movie or series', () async {
      await repo.addFavorite(const MediaItem(id: 'f'));
      await repo.save(_episode('e1', 's1', season: 1, episode: 1));
      await repo.save(_episode('e2', 's1', season: 1, episode: 2));
      await repo.save(_movie('m'));
      expect(await repo.titleIds(), {'f', 's1', 'm'});
    });

    group('updateTitles', () {
      setUp(() async {
        await repo.addFavorite(
          const MediaItem(
            id: 's1',
            title: LocalizedText(en: 'Old', ar: 'قديم'),
            posterUrl: 'https://img/old.jpg',
            year: 1990,
            kind: VideoKind.series,
            categories: [LocalizedText(en: 'Drama', ar: 'دراما')],
          ),
        );
        await repo.save(_episode('e1', 's1', season: 1, episode: 1));
        await repo.save(_movie('m', title: 'Movie'));
      });

      test(
        'each title language on its own; missing fields keep their value',
        () async {
          await repo.updateTitles([
            const MediaItem(
              id: 's1',
              title: LocalizedText(en: 'New'),
            ),
          ]);
          final f = (await repo.watchFavorites().first).single;
          expect(f.title, const LocalizedText(en: 'New', ar: 'قديم'));
          expect(f.posterUrl, 'https://img/old.jpg');
          expect(f.year, 1990);
          expect(
            f.categories.single,
            const LocalizedText(en: 'Drama', ar: 'دراما'),
          );
          final e1 = (await repo.progress('e1'))!;
          expect(e1.title, const LocalizedText(en: 'New', ar: 'مسلسل'));
        },
      );

      test('a fresh genre replaces the old pair whole', () async {
        await repo.updateTitles([
          const MediaItem(
            id: 's1',
            categories: [LocalizedText(en: 'Comedy')],
          ),
        ]);
        final f = (await repo.watchFavorites().first).single;
        // Never "Comedy" with the Arabic of "Drama".
        expect(f.categories.single, const LocalizedText(en: 'Comedy'));
      });

      test('posters and years; history positions stay', () async {
        await repo.updateTitles([
          const MediaItem(
            id: 's1',
            hdPosterUrl: 'https://img/new-hd.jpg',
            year: 1994,
          ),
          const MediaItem(id: 'm', posterUrl: 'https://img/m.jpg'),
          const MediaItem(
            id: 'unknown',
            title: LocalizedText(en: 'X'),
          ),
        ]);
        final f = (await repo.watchFavorites().first).single;
        expect((f.posterUrl, f.year), ('https://img/new-hd.jpg', 1994));
        final e1 = (await repo.progress('e1'))!;
        expect(e1.posterUrl, 'https://img/new-hd.jpg');
        expect(e1.position, const Duration(minutes: 5));
        final m = (await repo.progress('m'))!;
        expect((m.title.en, m.posterUrl), ('Movie', 'https://img/m.jpg'));
        expect(await repo.titleIds(), {'s1', 'm'});
      });

      test('an episode record refreshes its series', () async {
        await repo.updateTitles([
          const MediaItem(
            id: 'e7',
            rootSeriesId: 's1',
            title: LocalizedText(ar: 'جديد'),
          ),
        ]);
        expect(
          (await repo.watchFavorites().first).single.title,
          const LocalizedText(en: 'Old', ar: 'جديد'),
        );
      });
    });
  });
}

void main() {
  _contract('drift', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return DriftLibraryRepository(db);
  });
  _contract('in memory', MemoryLibraryRepository.new);

  group('continueFrom', () {
    test('hidden at the same moment as the newest row: still hidden', () {
      final p = _movie('m', minute: 3);
      expect(continueFrom([p], hidden: {'m': p.updatedAt}), isEmpty);
      expect(continueFrom([p], hidden: {'m': p.updatedAt.subtract(_min)}), [p]);
    });

    test('a title that is hidden doesn\'t hide another', () {
      final a = _movie('a', minute: 2);
      final b = _movie('b', minute: 1);
      expect(continueFrom([a, b], hidden: {'a': _at(5)}), [b]);
    });
  });
}
