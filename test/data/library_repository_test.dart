import 'package:cinemakom/core/network/api_endpoints.dart';
import 'package:cinemakom/core/storage/database.dart';
import 'package:cinemakom/data/models/localized_text.dart';
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

    test('continue keeps the newest row per title, unfinished only', () {
      final rows = [
        row('e3', series: 's', at: 9),
        row('e2', series: 's', at: 8),
        row('m1', minutes: 99, at: 7),
        row('m2', at: 6),
      ];
      expect(continueFrom(rows).map((p) => p.videoId), ['e3', 'm2']);
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
      expect(
        (await repo.watchContinue().first).map((p) => p.videoId),
        ['m', 'e2'],
      );
    });
  });
}
