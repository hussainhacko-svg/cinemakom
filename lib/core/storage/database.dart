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

/// A downloaded (or downloading) movie or episode (PLAN.md Phase 6). The
/// file's place is stored the way background_downloader names it: a base
/// directory, a folder in it, and a file name, so app sandboxes that move
/// between launches (iOS) still resolve. Live progress isn't stored; the
/// downloader reports it.
@DataClassName('DownloadRow')
class Downloads extends Table {
  /// The movie or episode; also the downloader's task ID.
  TextColumn get videoId => text()();

  /// The movie, or the series (its first episode's ID).
  TextColumn get titleId => text()();
  IntColumn get season => integer().nullable()();

  /// The server's `episodeNummer`, and the last number of a double episode.
  IntColumn get episode => integer().nullable()();
  IntColumn get episodeLast => integer().nullable()();
  BoolColumn get finale => boolean().withDefault(const Constant(false))();
  TextColumn get titleEn => text().nullable()();
  TextColumn get titleAr => text().nullable()();
  TextColumn get posterUrl => text().nullable()();

  /// `VideoKind.name`.
  TextColumn get kind => text().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();

  /// The stream's resolution, e.g. "1080p".
  TextColumn get quality => text()();

  /// background_downloader's `BaseDirectory.name`, the folder and the file.
  TextColumn get baseDirectory => text()();
  TextColumn get directory => text()();
  TextColumn get fileName => text()();

  /// The subtitle files beside the video, as JSON:
  /// `[{"lang": "ar", "file": "….ar.srt", "format": "srt"}]`.
  TextColumn get subtitles => text().withDefault(const Constant('[]'))();
  IntColumn get totalBytes => integer().nullable()();

  /// `DownloadStatus.name`.
  TextColumn get status => text()();

  /// Why it failed (`DownloadProblem.name`), when it did.
  TextColumn get problem => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {videoId};
}

/// The app's database: watch history, favorites, titles hidden from
/// Continue watching, and downloads.
@DriftDatabase(tables: [WatchHistory, Favorites, ContinueHidden, Downloads])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'cinemakom'));

  /// 1: watch history (Phase 4). 2: favorites and hidden Continue titles.
  /// 3: downloads.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(favorites);
        await m.createTable(continueHidden);
      }
      if (from < 3) await m.createTable(downloads);
    },
  );
}
