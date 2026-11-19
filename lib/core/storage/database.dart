import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// How far each movie or episode was watched (PLAYER.md §7.6). Display
/// metadata only; never stream URLs.
class WatchHistory extends Table {
  /// The movie or episode.
  TextColumn get videoId => text()();

  /// The series (its first episode's ID); null for movies.
  TextColumn get seriesId => text().nullable()();
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  IntColumn get positionMs => integer()();
  IntColumn get durationMs => integer()();
  BoolColumn get finished => boolean()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get titleEn => text().nullable()();
  TextColumn get titleAr => text().nullable()();
  TextColumn get posterUrl => text().nullable()();

  /// `VideoKind.name`.
  TextColumn get kind => text().nullable()();

  @override
  Set<Column> get primaryKey => {videoId};
}

/// Saved titles (the Library's Favorites), with what a poster card shows.
/// The display fields are refreshed from the API (`getVideosByIds`).
@DataClassName('FavoriteRow')
class Favorites extends Table {
  /// The movie, or the series (its first episode's ID).
  TextColumn get titleId => text()();
  TextColumn get titleEn => text().nullable()();
  TextColumn get titleAr => text().nullable()();
  TextColumn get posterUrl => text().nullable()();

  /// `VideoKind.name`.
  TextColumn get kind => text().nullable()();
  IntColumn get year => integer().nullable()();

  /// The first genre, for the card's caption.
  TextColumn get genreEn => text().nullable()();
  TextColumn get genreAr => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {titleId};
}

/// Titles removed from Continue watching. A title stays hidden until it is
/// watched again (a history row newer than [hiddenAt]); its history is kept.
@DataClassName('HiddenContinueRow')
class ContinueHidden extends Table {
  /// The movie, or the series.
  TextColumn get titleId => text()();
  DateTimeColumn get hiddenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {titleId};
}

/// The app's database: watch history, favorites, and titles hidden from
/// Continue watching. Downloads come in Phase 6 (PLAN.md §5).
@DriftDatabase(tables: [WatchHistory, Favorites, ContinueHidden])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'cinemakom'));

  /// 1: watch history (Phase 4). 2: favorites and hidden Continue titles.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(favorites);
        await m.createTable(continueHidden);
      }
    },
  );
}
