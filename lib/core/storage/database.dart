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

/// The app's database: watch history now; favorites and downloads in later
/// phases (PLAN.md §5).
@DriftDatabase(tables: [WatchHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'cinemakom'));

  @override
  int get schemaVersion => 1;
}
