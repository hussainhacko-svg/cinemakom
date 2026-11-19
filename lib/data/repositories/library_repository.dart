import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_endpoints.dart' show VideoKind;
import '../../core/storage/database.dart';
import '../models/localized_text.dart';
import '../models/media_item.dart';
import '../models/watch_progress.dart';

/// The Library: watch history (what was watched and how far, PLAYER.md
/// §7.6), titles hidden from Continue watching, and favorites.
abstract interface class LibraryRepository {
  /// Saves or replaces the row for [progress.videoId].
  Future<void> save(WatchProgress progress);

  Future<WatchProgress?> progress(String videoId);

  Stream<WatchProgress?> watchProgress(String videoId);

  /// A series' episodes: episode ID → progress.
  Stream<Map<String, WatchProgress>> watchSeries(String seriesId);

  /// Continue watching: the newest row of each title, newest first (see
  /// [continueFrom]). A series whose newest episode is finished stays, so
  /// its next episode can be offered.
  Stream<List<WatchProgress>> watchContinue();

  /// Removes [titleId] (a movie or series) from Continue watching until it
  /// is watched again. Its history stays.
  Future<void> hideFromContinue(String titleId);

  /// Favorites, the last added first.
  Stream<List<MediaItem>> watchFavorites();

  Stream<bool> watchIsFavorite(String titleId);

  /// Saves [item]'s movie or series (by [MediaItem.seriesId]), or moves it
  /// to the front.
  Future<void> addFavorite(MediaItem item);

  Future<void> removeFavorite(String titleId);

  /// Every movie and series in the favorites or the history.
  Future<Set<String>> titleIds();

  /// Rewrites the stored titles, posters, years and genres with [fresh]
  /// metadata (from `getVideosByIds`). Missing fields keep their old value.
  Future<void> updateTitles(Iterable<MediaItem> fresh);
}

/// Continue watching from history [rows] (newest first): the newest row of
/// each movie or series, newest first. Finished movies drop out; a series
/// stays even when its newest episode is finished (its next episode is the
/// one to offer). A title in [hidden] is left out unless it was watched
/// after it was hidden.
List<WatchProgress> continueFrom(
  Iterable<WatchProgress> rows, {
  Map<String, DateTime> hidden = const {},
}) {
  bool shown(WatchProgress p) {
    final hiddenAt = hidden[p.titleId];
    return hiddenAt == null || hiddenAt.isBefore(p.updatedAt);
  }

  final seen = <String>{};
  return [
    for (final p in rows)
      if (seen.add(p.titleId) && (p.isSeries || !p.isFinished) && shown(p)) p,
  ];
}

/// The favorite form of [item]: its movie or series, with what a poster
/// card shows.
MediaItem favoriteOf(MediaItem item) => MediaItem(
  id: item.seriesId,
  title: item.title,
  posterUrl: item.posterUrl ?? item.hdPosterUrl,
  year: item.year,
  kind: item.kind ?? (item.rootSeriesId != null ? VideoKind.series : null),
  categories: item.categories.take(1).toList(),
);

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
  Stream<WatchProgress?> watchProgress(String videoId) =>
      _byId(videoId)
          .watchSingleOrNull()
          .map((r) => r == null ? null : _fromRow(r));

  @override
  Stream<Map<String, WatchProgress>> watchSeries(String seriesId) =>
      (_db.select(_db.watchHistory)..where((t) => t.seriesId.equals(seriesId)))
          .watch()
          .map((rows) => {for (final r in rows) r.videoId: _fromRow(r)});

  @override
  Stream<List<WatchProgress>> watchContinue() {
    final h = _db.watchHistory;
    final hidden = _db.continueHidden;
    final query = _db.select(h).join([
      leftOuterJoin(
        hidden,
        hidden.titleId.equalsExp(coalesce([h.seriesId, h.videoId])),
      ),
    ])..orderBy([OrderingTerm.desc(h.updatedAt)]);
    return query.watch().map((rows) {
      final hiddenAt = <String, DateTime>{};
      final progress = <WatchProgress>[];
      for (final r in rows) {
        final p = _fromRow(r.readTable(h));
        progress.add(p);
        if (r.readTableOrNull(hidden) case final x?) {
          hiddenAt[x.titleId] = x.hiddenAt;
        }
      }
      return continueFrom(progress, hidden: hiddenAt);
    });
  }

  @override
  Future<void> hideFromContinue(String titleId) async {
    // Hidden up to now, or up to the newest row if the clock went back, so
    // only a later watch brings the title back.
    final newest =
        await (_db.select(_db.watchHistory)
              ..where(
                (t) => t.seriesId.equals(titleId) | t.videoId.equals(titleId),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    final now = DateTime.now();
    final at = newest == null || newest.updatedAt.isBefore(now)
        ? now
        : newest.updatedAt;
    await _db
        .into(_db.continueHidden)
        .insertOnConflictUpdate(
          ContinueHiddenCompanion.insert(titleId: titleId, hiddenAt: at),
        );
  }

  static MediaItem _favoriteFromRow(FavoriteRow r) => MediaItem(
    id: r.titleId,
    title: LocalizedText(en: r.titleEn, ar: r.titleAr),
    posterUrl: r.posterUrl,
    year: r.year,
    kind: VideoKind.values.asNameMap()[r.kind],
    categories: [
      if (r.genreEn != null || r.genreAr != null)
        LocalizedText(en: r.genreEn, ar: r.genreAr),
    ],
  );

  @override
  Stream<List<MediaItem>> watchFavorites() =>
      (_db.select(_db.favorites)..orderBy([
            (t) => OrderingTerm.desc(t.addedAt),
            // Same second: the later insert first.
            (_) => OrderingTerm.desc(const CustomExpression<int>('rowid')),
          ]))
          .watch()
          .map((rows) => [for (final r in rows) _favoriteFromRow(r)]);

  @override
  Stream<bool> watchIsFavorite(String titleId) =>
      (_db.select(_db.favorites)..where((t) => t.titleId.equals(titleId)))
          .watchSingleOrNull()
          .map((r) => r != null);

  @override
  Future<void> addFavorite(MediaItem item) async {
    final f = favoriteOf(item);
    final genre = f.categories.firstOrNull;
    // Delete first, so a re-added title gets a new rowid (the tie-break).
    await _db.transaction(() async {
      await removeFavorite(f.id);
      await _db
          .into(_db.favorites)
          .insert(
            FavoritesCompanion.insert(
              titleId: f.id,
              titleEn: Value(f.title.en),
              titleAr: Value(f.title.ar),
              posterUrl: Value(f.posterUrl),
              kind: Value(f.kind?.name),
              year: Value(f.year),
              genreEn: Value(genre?.en),
              genreAr: Value(genre?.ar),
              addedAt: DateTime.now(),
            ),
          );
    });
  }

  @override
  Future<void> removeFavorite(String titleId) =>
      (_db.delete(_db.favorites)..where((t) => t.titleId.equals(titleId))).go();

  @override
  Future<Set<String>> titleIds() async {
    final favorites = await _db.select(_db.favorites).get();
    final history = await _db.select(_db.watchHistory).get();
    return {
      for (final f in favorites) f.titleId,
      for (final h in history) h.seriesId ?? h.videoId,
    };
  }

  @override
  Future<void> updateTitles(Iterable<MediaItem> fresh) =>
      _db.transaction(() async {
        for (final item in fresh) {
          final id = item.seriesId;
          Value<T> keep<T>(T? v) => v == null ? const Value.absent() : Value(v);
          final genre = item.categories.firstOrNull;
          final poster = item.posterUrl ?? item.hdPosterUrl;
          await (_db.update(
            _db.favorites,
          )..where((t) => t.titleId.equals(id))).write(
            FavoritesCompanion(
              titleEn: keep(item.title.en),
              titleAr: keep(item.title.ar),
              posterUrl: keep(poster),
              year: keep(item.year),
              genreEn: keep(genre?.en),
              genreAr: keep(genre?.ar),
            ),
          );
          await (_db.update(_db.watchHistory)..where(
                (t) =>
                    t.seriesId.equals(id) |
                    (t.seriesId.isNull() & t.videoId.equals(id)),
              ))
              .write(
                WatchHistoryCompanion(
                  titleEn: keep(item.title.en),
                  titleAr: keep(item.title.ar),
                  posterUrl: keep(poster),
                ),
              );
        }
      });
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

final favoritesProvider = StreamProvider.autoDispose<List<MediaItem>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFavorites(),
);

final isFavoriteProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, titleId) =>
      ref.watch(libraryRepositoryProvider).watchIsFavorite(titleId),
);

/// In-memory [LibraryRepository] for tests. Streams emit the current value
/// on listen and after every save.
class MemoryLibraryRepository implements LibraryRepository {
  MemoryLibraryRepository([
    Iterable<WatchProgress> rows = const [],
    Iterable<MediaItem> favorites = const [],
  ]) : rows = {for (final r in rows) r.videoId: r},
       favorites = {for (final f in favorites.map(favoriteOf)) f.id: f};

  final Map<String, WatchProgress> rows;

  /// Oldest added first.
  final Map<String, MediaItem> favorites;
  final Map<String, DateTime> hidden = {};
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
      _watch(() => continueFrom(_newestFirst, hidden: hidden));

  @override
  Future<void> hideFromContinue(String titleId) async {
    final newest = _newestFirst
        .where((p) => p.titleId == titleId)
        .firstOrNull
        ?.updatedAt;
    final now = DateTime.now();
    hidden[titleId] = newest != null && newest.isAfter(now) ? newest : now;
    _changes.add(null);
  }

  @override
  Stream<List<MediaItem>> watchFavorites() =>
      _watch(() => favorites.values.toList().reversed.toList());

  @override
  Stream<bool> watchIsFavorite(String titleId) =>
      _watch(() => favorites.containsKey(titleId));

  @override
  Future<void> addFavorite(MediaItem item) async {
    final f = favoriteOf(item);
    favorites
      ..remove(f.id)
      ..[f.id] = f;
    _changes.add(null);
  }

  @override
  Future<void> removeFavorite(String titleId) async {
    favorites.remove(titleId);
    _changes.add(null);
  }

  @override
  Future<Set<String>> titleIds() async => {
    ...favorites.keys,
    for (final p in rows.values) p.titleId,
  };

  /// What [updateTitles] was given, for tests.
  final updated = <MediaItem>[];

  @override
  Future<void> updateTitles(Iterable<MediaItem> fresh) async {
    updated.addAll(fresh);
    for (final item in fresh) {
      for (final p in rows.values.toList()) {
        if (p.titleId != item.seriesId) continue;
        rows[p.videoId] = WatchProgress(
          videoId: p.videoId,
          seriesId: p.seriesId,
          season: p.season,
          episode: p.episode,
          position: p.position,
          duration: p.duration,
          updatedAt: p.updatedAt,
          title: item.title.isEmpty ? p.title : item.title,
          posterUrl: item.posterUrl ?? item.hdPosterUrl ?? p.posterUrl,
          kind: p.kind,
          finished: p.finished,
        );
      }
      final old = favorites[item.seriesId];
      if (old != null) {
        favorites[old.id] = MediaItem(
          id: old.id,
          title: item.title.isEmpty ? old.title : item.title,
          posterUrl: item.posterUrl ?? item.hdPosterUrl ?? old.posterUrl,
          year: item.year ?? old.year,
          kind: old.kind,
          categories: item.categories.isEmpty
              ? old.categories
              : item.categories.take(1).toList(),
        );
      }
    }
    _changes.add(null);
  }
}
