import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_endpoints.dart' show VideoKind;
import '../../core/storage/database.dart';
import '../models/localized_text.dart';
import '../models/watch_progress.dart';

/// Watch history: what was watched and how far (PLAYER.md §7.6). Phase 5
/// adds favorites.
abstract interface class LibraryRepository {
  /// Saves or replaces the row for [progress.videoId].
  Future<void> save(WatchProgress progress);

  Future<WatchProgress?> progress(String videoId);

  Stream<WatchProgress?> watchProgress(String videoId);

  /// A series' episodes: episode ID → progress.
  Stream<Map<String, WatchProgress>> watchSeries(String seriesId);

  /// Continue watching: the latest movie or episode of each title, newest
  /// first, without finished ones.
  Stream<List<WatchProgress>> watchContinue();
}

/// The newest row of each movie or series, newest first, unfinished only.
/// [rows] must be newest first.
List<WatchProgress> continueFrom(Iterable<WatchProgress> rows) {
  final seen = <String>{};
  return [
    for (final p in rows)
      if (seen.add(p.seriesId ?? p.videoId) && !p.isFinished) p,
  ];
}

class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this._db);

  final AppDatabase _db;

  static WatchProgress _fromRow(WatchHistoryData r) => WatchProgress(
    videoId: r.videoId,
    seriesId: r.seriesId,
    season: r.season,
    episode: r.episode,
    position: Duration(milliseconds: r.positionMs),
    duration: Duration(milliseconds: r.durationMs),
    finished: r.finished,
    updatedAt: r.updatedAt,
    title: LocalizedText(en: r.titleEn, ar: r.titleAr),
    posterUrl: r.posterUrl,
    kind: VideoKind.values.asNameMap()[r.kind],
  );

  @override
  Future<void> save(WatchProgress p) => _db
      .into(_db.watchHistory)
      .insertOnConflictUpdate(
        WatchHistoryCompanion.insert(
          videoId: p.videoId,
          seriesId: Value(p.seriesId),
          season: Value(p.season),
          episode: Value(p.episode),
          positionMs: p.position.inMilliseconds,
          durationMs: p.duration.inMilliseconds,
          finished: p.isFinished,
          updatedAt: p.updatedAt,
          titleEn: Value(p.title.en),
          titleAr: Value(p.title.ar),
          posterUrl: Value(p.posterUrl),
          kind: Value(p.kind?.name),
        ),
      );

  SimpleSelectStatement<$WatchHistoryTable, WatchHistoryData> _byId(
    String id,
  ) => _db.select(_db.watchHistory)..where((t) => t.videoId.equals(id));

  @override
  Future<WatchProgress?> progress(String videoId) async {
    final row = await _byId(videoId).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Stream<WatchProgress?> watchProgress(String videoId) => _byId(
    videoId,
  ).watchSingleOrNull().map((r) => r == null ? null : _fromRow(r));

  @override
  Stream<Map<String, WatchProgress>> watchSeries(String seriesId) =>
      (_db.select(_db.watchHistory)
            ..where((t) => t.seriesId.equals(seriesId)))
          .watch()
          .map((rows) => {for (final r in rows) r.videoId: _fromRow(r)});

  @override
  Stream<List<WatchProgress>> watchContinue() =>
      (_db.select(_db.watchHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch()
          .map((rows) => continueFrom(rows.map(_fromRow)));
}

/// The database, opened once. Tests replace [libraryRepositoryProvider]
/// instead.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => DriftLibraryRepository(ref.watch(appDatabaseProvider)),
);

final watchProgressProvider = StreamProvider.autoDispose
    .family<WatchProgress?, String>(
      (ref, videoId) =>
          ref.watch(libraryRepositoryProvider).watchProgress(videoId),
    );

final seriesProgressProvider = StreamProvider.autoDispose
    .family<Map<String, WatchProgress>, String>(
      (ref, seriesId) =>
          ref.watch(libraryRepositoryProvider).watchSeries(seriesId),
    );

final continueWatchingProvider =
    StreamProvider.autoDispose<List<WatchProgress>>(
      (ref) => ref.watch(libraryRepositoryProvider).watchContinue(),
    );

/// In-memory [LibraryRepository] for tests. Streams emit the current value
/// on listen and after every save.
class MemoryLibraryRepository implements LibraryRepository {
  MemoryLibraryRepository([Iterable<WatchProgress> rows = const []])
    : rows = {for (final r in rows) r.videoId: r};

  final Map<String, WatchProgress> rows;
  final _changes = StreamController<void>.broadcast();

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  List<WatchProgress> get _newestFirst =>
      rows.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> save(WatchProgress progress) async {
    rows[progress.videoId] = progress;
    _changes.add(null);
  }

  @override
  Future<WatchProgress?> progress(String videoId) async => rows[videoId];

  @override
  Stream<WatchProgress?> watchProgress(String videoId) =>
      _watch(() => rows[videoId]);

  @override
  Stream<Map<String, WatchProgress>> watchSeries(String seriesId) => _watch(
    () => {
      for (final p in rows.values)
        if (p.seriesId == seriesId) p.videoId: p,
    },
  );

  @override
  Stream<List<WatchProgress>> watchContinue() =>
      _watch(() => continueFrom(_newestFirst));
}
